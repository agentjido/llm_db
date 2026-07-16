defmodule LLMDB.ReloadIdempotencyTest do
  use ExUnit.Case, async: false

  alias LLMDB.{Engine, Loader, Snapshot, Store}
  alias LLMDB.Sources.Config, as: ConfigSource

  setup do
    original_config = Application.get_all_env(:llm_db)
    Store.clear!()

    snapshot_path = write_snapshot!("base")

    on_exit(fn ->
      File.rm(snapshot_path)
      Store.clear!()

      Application.get_all_env(:llm_db)
      |> Keyword.keys()
      |> Enum.each(&Application.delete_env(:llm_db, &1))

      Application.put_all_env(llm_db: original_config)
    end)

    %{snapshot_path: snapshot_path}
  end

  test "reload publishes changed custom provider and model metadata", %{snapshot_path: path} do
    {:ok, first} = LLMDB.load(load_opts(path, custom("Provider A", "Model A")))
    first_epoch = LLMDB.epoch()

    assert {:ok, provider} = LLMDB.provider(:digest_custom)
    assert provider.name == "Provider A"
    assert {:ok, model} = LLMDB.model(:digest_custom, "same-id")
    assert model.name == "Model A"

    {:ok, second} = LLMDB.load(load_opts(path, custom("Provider B", "Model B")))

    assert LLMDB.epoch() > first_epoch
    assert first.meta.digest != second.meta.digest
    assert {:ok, provider} = LLMDB.provider(:digest_custom)
    assert provider.name == "Provider B"
    assert {:ok, model} = LLMDB.model(:digest_custom, "same-id")
    assert model.name == "Model B"
  end

  test "equivalent custom maps with different construction order remain a no-op", %{
    snapshot_path: path
  } do
    model_a = Map.new(name: "Same Model", capabilities: %{chat: true})
    model_b = Map.new(capabilities: %{chat: true}, name: "Same Model")

    custom_a = %{digest_custom: [name: "Same Provider", models: %{"same-id" => model_a}]}
    custom_b = %{digest_custom: [models: %{"same-id" => model_b}, name: "Same Provider"]}

    {:ok, first} = LLMDB.load(load_opts(path, custom_a))
    first_epoch = LLMDB.epoch()
    {:ok, second} = LLMDB.load(load_opts(path, custom_b))

    assert second == first
    assert LLMDB.epoch() == first_epoch
  end

  test "equivalent accepted filter forms remain a no-op", %{snapshot_path: path} do
    atom_key_opts = Keyword.put(load_opts(path), :allow, %{digest_base: ["base-*"]})
    string_key_opts = Keyword.put(load_opts(path), :allow, %{"digest_base" => ["base-*"]})

    {:ok, first} = LLMDB.load(atom_key_opts)
    first_epoch = LLMDB.epoch()
    {:ok, second} = LLMDB.load(string_key_opts)

    assert second == first
    assert LLMDB.epoch() == first_epoch
  end

  test "changing the effective filter publishes the new catalog", %{snapshot_path: path} do
    {:ok, first} = LLMDB.load(load_opts(path))
    first_epoch = LLMDB.epoch()

    filtered_opts = Keyword.put(load_opts(path), :allow, %{digest_base: ["base-*"]})
    {:ok, second} = LLMDB.load(filtered_opts)

    assert second.meta.digest != first.meta.digest
    assert LLMDB.epoch() > first_epoch
    assert Map.keys(second.models) == [:digest_base]
    assert {:ok, _model} = LLMDB.model(:digest_base, "base-model")
    assert {:error, :not_found} = LLMDB.model(:digest_other, "other-model")
  end

  test "changing provider preference publishes new selection order", %{snapshot_path: path} do
    first_opts = Keyword.put(load_opts(path), :prefer, [:digest_base, :digest_other])
    {:ok, first} = LLMDB.load(first_opts)
    first_epoch = LLMDB.epoch()
    assert [{:digest_base, "base-model"} | _] = LLMDB.candidates(require: [chat: true])

    second_opts = Keyword.put(load_opts(path), :prefer, [:digest_other, :digest_base])
    {:ok, second} = LLMDB.load(second_opts)

    assert second.meta.digest != first.meta.digest
    assert LLMDB.epoch() > first_epoch
    assert [{:digest_other, "other-model"} | _] = LLMDB.candidates(require: [chat: true])
  end

  test "a new source snapshot identity invalidates an equivalent catalog" do
    first_path = write_snapshot!("source-a")
    second_path = write_snapshot!("source-b")

    on_exit(fn ->
      File.rm(first_path)
      File.rm(second_path)
    end)

    {:ok, first} = LLMDB.load(load_opts(first_path))
    first_epoch = LLMDB.epoch()
    {:ok, second} = LLMDB.load(load_opts(second_path))

    assert first.meta.source_snapshot_id != second.meta.source_snapshot_id
    assert first.meta.digest != second.meta.digest
    assert LLMDB.epoch() > first_epoch
    assert first.providers == second.providers
    assert first.base_models == second.base_models
  end

  test "equivalent loads have one deterministic fingerprint across processes", %{
    snapshot_path: path
  } do
    opts =
      path
      |> load_opts(custom("Stable Provider", "Stable Model"))
      |> Keyword.put(:allow, %{
        digest_base: ["base-*"],
        digest_other: ["other-*"]
      })

    digests =
      1..4
      |> Enum.map(fn _ -> Task.async(fn -> Loader.load(opts) end) end)
      |> Task.await_many()
      |> Enum.map(fn {:ok, snapshot} -> snapshot.meta.digest end)

    assert [digest] = Enum.uniq(digests)
    assert digest =~ ~r/^[a-f0-9]{64}$/

    {:ok, _snapshot} = LLMDB.load(opts)
    epoch = LLMDB.epoch()

    1..4
    |> Enum.map(fn _ -> Task.async(fn -> LLMDB.load(opts) end) end)
    |> Task.await_many()
    |> Enum.each(fn {:ok, snapshot} -> assert snapshot.meta.digest == digest end)

    assert LLMDB.epoch() == epoch
  end

  defp load_opts(path, custom \\ %{}) do
    [
      snapshot_source: {:file, path},
      allow: :all,
      deny: %{},
      prefer: [],
      custom: custom
    ]
  end

  defp custom(provider_name, model_name) do
    %{
      digest_custom: [
        name: provider_name,
        models: %{
          "same-id" => %{
            name: model_name,
            capabilities: %{chat: true}
          }
        }
      ]
    }
  end

  defp write_snapshot!(nonce) do
    {:ok, engine_snapshot} =
      Engine.run(
        sources: [
          {ConfigSource,
           %{
             overrides: %{
               digest_base: %{
                 name: "Digest Base",
                 models: [
                   %{
                     id: "base-model",
                     provider: :digest_base,
                     capabilities: %{chat: true}
                   }
                 ]
               },
               digest_other: %{
                 name: "Digest Other",
                 models: [
                   %{
                     id: "other-model",
                     provider: :digest_other,
                     capabilities: %{chat: true}
                   }
                 ]
               }
             }
           }}
        ]
      )

    document =
      engine_snapshot
      |> Map.put(:generated_at, "2026-07-16T00:00:00Z")
      |> Snapshot.from_engine_snapshot()
      |> Map.delete("snapshot_id")
      |> Map.put("test_revision_nonce", nonce)
      |> then(fn snapshot -> Map.put(snapshot, "snapshot_id", Snapshot.snapshot_id(snapshot)) end)

    path =
      Path.join(
        System.tmp_dir!(),
        "llm-db-reload-#{nonce}-#{System.unique_integer([:positive])}.json"
      )

    Snapshot.write!(path, document)
    path
  end
end
