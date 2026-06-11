defmodule LLMDB.LoaderCompatibilityTest do
  use ExUnit.Case, async: true

  alias LLMDB.{Loader, Snapshot}

  test "loads old v2 snapshots with legacy cost and reasoning token budgets" do
    snapshot_path = legacy_snapshot_path()

    on_exit(fn ->
      File.rm_rf!(snapshot_path)
    end)

    assert {:ok, loaded} =
             Loader.load(
               snapshot_source: {:file, snapshot_path},
               allow: :all,
               deny: %{},
               prefer: [],
               custom: %{}
             )

    [model] = loaded.models.test_provider_alpha
    components = Map.new(model.pricing.components, &{&1.id, &1})

    assert model.id == "legacy-model"
    assert model.provider == :test_provider_alpha
    assert model.limits.context == 128_000
    assert model.limits.output == 4_096
    refute Map.has_key?(model.limits, :input)
    assert model.capabilities.reasoning.enabled == true
    assert model.capabilities.reasoning.token_budget == 4_096
    assert model.cost.input == 1.0
    assert model.cost.output == 2.0
    assert components["token.input"].rate == 1.0
    assert components["token.output"].rate == 2.0
  end

  defp legacy_snapshot_path do
    snapshot_path =
      Path.join(
        System.tmp_dir!(),
        "llm_db-legacy-snapshot-#{System.unique_integer([:positive])}.json"
      )

    snapshot =
      %{
        "schema_version" => 1,
        "version" => 2,
        "generated_at" => "2026-01-01T00:00:00Z",
        "providers" => %{
          "test_provider_alpha" => %{
            "id" => "test_provider_alpha",
            "name" => "Test Provider Alpha",
            "models" => %{
              "legacy-model" => %{
                "id" => "legacy-model",
                "provider" => "test_provider_alpha",
                "limits" => %{
                  "context" => 128_000,
                  "output" => 4_096
                },
                "cost" => %{
                  "input" => 1.0,
                  "output" => 2.0
                },
                "capabilities" => %{
                  "reasoning" => %{
                    "enabled" => true,
                    "token_budget" => 4_096
                  }
                }
              }
            }
          }
        }
      }
      |> then(fn snapshot -> Map.put(snapshot, "snapshot_id", Snapshot.snapshot_id(snapshot)) end)

    Snapshot.write!(snapshot_path, snapshot)
    snapshot_path
  end
end
