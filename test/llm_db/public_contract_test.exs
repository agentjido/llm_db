defmodule LLMDB.PublicContractTest do
  use ExUnit.Case, async: false

  alias LLMDB.{Model, Provider, Snapshot, Store}

  @model_fields [
    :aliases,
    :base_url,
    :capabilities,
    :catalog_only,
    :cost,
    :deprecated,
    :doc_url,
    :execution,
    :extra,
    :family,
    :id,
    :knowledge,
    :last_updated,
    :lifecycle,
    :limits,
    :modalities,
    :model,
    :name,
    :pricing,
    :provider,
    :provider_model_id,
    :release_date,
    :retired,
    :tags
  ]

  @provider_fields [
    :alias_of,
    :base_url,
    :catalog_only,
    :config_schema,
    :doc,
    :env,
    :exclude_models,
    :extra,
    :id,
    :name,
    :pricing_defaults,
    :runtime
  ]

  setup do
    Store.clear!()

    provider = Provider.new!(%{id: :contract_provider, name: "Contract Provider"})

    model =
      Model.new!(%{
        id: "contract-model",
        provider: :contract_provider,
        name: "Contract Model",
        capabilities: %{chat: true}
      })

    snapshot = %{
      providers_by_id: %{contract_provider: provider},
      models_by_key: %{{:contract_provider, "contract-model"} => model},
      aliases_by_key: %{},
      providers: [provider],
      models: %{contract_provider: [model]},
      base_models: [model],
      filters: %{allow: :all, deny: %{}},
      prefer: [:contract_provider],
      meta: %{digest: "public-contract"}
    }

    Store.put!(snapshot, [])
    on_exit(&Store.clear!/0)

    %{model: model, provider: provider}
  end

  test "the public facade preserves primary return and error shapes", %{
    model: model,
    provider: provider
  } do
    assert [^provider] = LLMDB.providers()
    assert {:ok, ^provider} = LLMDB.provider(:contract_provider)
    assert {:error, :not_found} = LLMDB.provider(:missing_provider)

    assert [^model] = LLMDB.models()
    assert [^model] = LLMDB.models(:contract_provider)
    assert [] = LLMDB.models(:missing_provider)
    assert {:ok, ^model} = LLMDB.model(:contract_provider, "contract-model")
    assert {:ok, ^model} = LLMDB.model("contract_provider:contract-model")
    assert {:error, :not_found} = LLMDB.model(:contract_provider, "missing-model")

    assert {:ok, {:contract_provider, "contract-model"}} = LLMDB.select(require: [chat: true])
    assert {:error, :no_match} = LLMDB.select(require: [embeddings: true])
    assert [{:contract_provider, "contract-model"}] = LLMDB.candidates(require: [chat: true])
    assert [] = LLMDB.candidates(require: [embeddings: true])

    assert LLMDB.allowed?({:contract_provider, "contract-model"})
    refute LLMDB.allowed?({:contract_provider, "missing-model"})
    assert %{chat: true} = LLMDB.capabilities({:contract_provider, "contract-model"})
    assert nil == LLMDB.capabilities({:contract_provider, "missing-model"})
  end

  test "required public struct and model JSON fields remain present", %{
    model: model,
    provider: provider
  } do
    assert_required_fields(Map.from_struct(model), @model_fields)
    assert_required_fields(Map.from_struct(provider), @provider_fields)

    json =
      model
      |> Jason.encode!()
      |> Jason.decode!()

    assert_required_fields(json, Enum.map(@model_fields, &Atom.to_string/1))
  end

  test "the current snapshot artifact round-trips through the supported reader" do
    document =
      Snapshot.from_engine_snapshot(%{
        version: 2,
        generated_at: "2026-07-16T00:00:00Z",
        providers: %{
          contract_provider: %{
            id: :contract_provider,
            name: "Contract Provider",
            models: %{}
          }
        }
      })

    assert document["schema_version"] == Snapshot.schema_version()
    assert {:ok, ^document} = document |> Snapshot.encode() |> Snapshot.decode()
  end

  test "documented maintainer task names remain registered" do
    tasks = [
      {"llm_db.pull", Mix.Tasks.LlmDb.Pull},
      {"llm_db.build", Mix.Tasks.LlmDb.Build},
      {"llm_db.snapshot.fetch", Mix.Tasks.LlmDb.Snapshot.Fetch},
      {"llm_db.snapshot.publish", Mix.Tasks.LlmDb.Snapshot.Publish},
      {"llm_db.history.backfill", Mix.Tasks.LlmDb.History.Backfill},
      {"llm_db.history.migrate_git", Mix.Tasks.LlmDb.History.MigrateGit},
      {"llm_db.history.rebuild", Mix.Tasks.LlmDb.History.Rebuild},
      {"llm_db.history.sync", Mix.Tasks.LlmDb.History.Sync},
      {"llm_db.history.check", Mix.Tasks.LlmDb.History.Check},
      {"llm_db.version", Mix.Tasks.LlmDb.Version}
    ]

    Enum.each(tasks, fn {name, module} ->
      assert Mix.Task.get(name) == module
      assert function_exported?(module, :run, 1)
    end)
  end

  defp assert_required_fields(actual, required) do
    missing = MapSet.difference(MapSet.new(required), MapSet.new(Map.keys(actual)))

    assert MapSet.size(missing) == 0,
           "missing required public fields: #{inspect(MapSet.to_list(missing))}"
  end
end
