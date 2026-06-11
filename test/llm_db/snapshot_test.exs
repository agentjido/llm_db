defmodule LLMDB.SnapshotTest do
  use ExUnit.Case, async: true

  alias LLMDB.{Model, Provider, Snapshot}

  test "encodes nested maps with stable sorted key order" do
    encoded = Snapshot.encode(%{"b" => %{"d" => 1, "c" => 2}, "a" => 1})

    assert [
             "{",
             "  \"a\": 1,",
             "  \"b\": {",
             "    \"c\": 2,",
             "    \"d\": 1",
             "  }",
             "}"
           ] = String.split(encoded, "\n", trim: true)
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
end
