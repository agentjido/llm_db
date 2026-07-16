defmodule LLMDB.SnapshotTest do
  use ExUnit.Case, async: true

  alias LLMDB.{Model, Provider, Snapshot}

  import ExUnit.CaptureLog

  test "encodes nested maps as deterministic compact JSON with sorted keys" do
    encoded = Snapshot.encode(%{"b" => %{"d" => 1, "c" => 2}, "a" => 1})

    assert encoded == ~s({"a":1,"b":{"c":2,"d":1}})
    refute String.contains?(encoded, "\n")
  end

  test "serializing the same document twice is byte-identical" do
    document = snapshot_document()
    rebuilt = document |> Enum.reverse() |> Map.new()

    assert document == rebuilt
    assert Snapshot.encode(document) == Snapshot.encode(rebuilt)
  end

  test "omits empty runtime migration fields from snapshot output" do
    provider =
      Provider.new!(%{
        id: :test_provider,
        name: "Test Provider"
      })

    model =
      Model.new!(%{
        id: "test-model",
        provider: :test_provider
      })

    snapshot =
      Snapshot.from_engine_snapshot(%{
        version: 2,
        generated_at: "2026-03-26T00:00:00Z",
        providers: %{
          test_provider: Map.put(provider, :models, %{"test-model" => model})
        }
      })

    provider_json = snapshot["providers"]["test_provider"]
    model_json = provider_json["models"]["test-model"]

    refute Map.has_key?(provider_json, "runtime")
    refute Map.has_key?(provider_json, "catalog_only")
    refute Map.has_key?(model_json, "doc_url")
    refute Map.has_key?(model_json, "execution")
    refute Map.has_key?(model_json, "catalog_only")
  end

  test "includes populated runtime metadata fields in snapshot output" do
    provider =
      Provider.new!(%{
        id: :test_provider,
        name: "Test Provider",
        runtime: %{
          base_url: "https://api.example.test/v1",
          auth: %{type: :bearer, env: ["TEST_API_KEY"]}
        }
      })

    model =
      Model.new!(%{
        id: "test-model",
        provider: :test_provider,
        execution: %{
          text: %{supported: true, family: :openai_chat_compatible, path: "/chat/completions"}
        }
      })

    snapshot =
      Snapshot.from_engine_snapshot(%{
        version: 2,
        generated_at: "2026-03-26T00:00:00Z",
        providers: %{
          test_provider:
            provider
            |> Map.put(:catalog_only, true)
            |> Map.put(:models, %{"test-model" => Map.put(model, :catalog_only, true)})
        }
      })

    provider_json = snapshot["providers"]["test_provider"]
    model_json = provider_json["models"]["test-model"]

    assert provider_json["catalog_only"] == true
    assert provider_json["runtime"]["base_url"] == "https://api.example.test/v1"
    assert provider_json["runtime"]["auth"]["type"] == "bearer"
    assert model_json["catalog_only"] == true
    assert model_json["execution"]["text"]["family"] == "openai_chat_compatible"
    assert model_json["execution"]["text"]["path"] == "/chat/completions"
  end

  test "strict integrity rejects mismatched snapshot content" do
    snapshot = snapshot_document()
    mismatched = put_in(snapshot, ["providers", "test_provider", "name"], "Changed")

    assert {:error, {:snapshot_id_mismatch, details}} =
             mismatched
             |> Jason.encode!()
             |> Snapshot.decode()

    assert details[:expected] == snapshot["snapshot_id"]
    assert details[:computed] != details[:expected]
  end

  test "warn and off integrity policies preserve validation" do
    snapshot = snapshot_document()
    mismatched = put_in(snapshot, ["providers", "test_provider", "name"], "Changed")
    encoded = Jason.encode!(mismatched)

    log =
      capture_log(fn ->
        assert {:ok, ^mismatched} = Snapshot.decode(encoded, integrity_policy: :warn)
      end)

    assert log =~ "checksum check failed"
    assert log =~ "do not authenticate publishers"
    assert {:ok, ^mismatched} = Snapshot.decode(encoded, integrity_policy: :off)

    malformed = Map.put(mismatched, "providers", [])

    assert {:error, :invalid_snapshot_format} =
             malformed
             |> Jason.encode!()
             |> Snapshot.decode(integrity_policy: :warn)
  end

  test "embedded documents and JSON content use the same preparation contract" do
    snapshot = snapshot_document()

    assert {:ok, prepared} = Snapshot.prepare(snapshot)
    assert {:ok, decoded} = snapshot |> Jason.encode!() |> Snapshot.decode()
    assert prepared == decoded
  end

  test "rejects unsupported schema versions after checksum verification" do
    snapshot =
      snapshot_document()
      |> Map.put("schema_version", Snapshot.schema_version() + 1)
      |> then(fn document -> Map.put(document, "snapshot_id", Snapshot.snapshot_id(document)) end)

    assert {:error, {:unsupported_schema_version, 2}} = Snapshot.prepare(snapshot)
  end

  defp snapshot_document do
    Snapshot.from_engine_snapshot(%{
      version: 2,
      generated_at: "2026-03-26T00:00:00Z",
      providers: %{
        test_provider: %{
          id: :test_provider,
          name: "Test Provider",
          models: %{}
        }
      }
    })
  end
end
