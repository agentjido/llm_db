defmodule LLMDB.History.RebuilderTest do
  use ExUnit.Case, async: false

  alias LLMDB.{History, History.Rebuilder, Snapshot}

  setup do
    previous_history_dir = Application.get_env(:llm_db, :history_dir)

    on_exit(fn ->
      clear_history_cache()

      if previous_history_dir == nil do
        Application.delete_env(:llm_db, :history_dir)
      else
        Application.put_env(:llm_db, :history_dir, previous_history_dir)
      end
    end)

    :ok
  end

  test "rebuilds snapshot-based history that preserves lineage timelines" do
    history_dir = temp_dir("llm_db_history_rebuilder")
    snapshots_dir = temp_dir("llm_db_snapshot_rebuilder")

    snapshot_a =
      snapshot(%{
        "openai" => %{
          "id" => "openai",
          "models" => %{
            "gpt-4o" => %{
              "id" => "gpt-4o",
              "provider" => "openai",
              "aliases" => ["gpt-4o-latest"]
            }
          }
        }
      })

    snapshot_b =
      snapshot(%{
        "openai" => %{
          "id" => "openai",
          "models" => %{
            "gpt-4.1" => %{
              "id" => "gpt-4.1",
              "provider" => "openai",
              "aliases" => ["gpt-4o", "gpt-4o-latest"]
            }
          }
        }
      })

    write_snapshot(snapshots_dir, snapshot_a)
    write_snapshot(snapshots_dir, snapshot_b)

    observations = [
      %{
        "snapshot_id" => snapshot_a["snapshot_id"],
        "captured_at" => "2026-01-01T00:00:00Z"
      },
      %{
        "snapshot_id" => snapshot_b["snapshot_id"],
        "captured_at" => "2026-01-02T00:00:00Z",
        "parent_snapshot_id" => snapshot_a["snapshot_id"]
      }
    ]

    assert {:ok, summary} =
             Rebuilder.rebuild(
               observations: observations,
               output_dir: history_dir,
               source: "test",
               snapshot_loader: fn snapshot_id ->
                 Snapshot.read(
                   Path.join([snapshots_dir, snapshot_id, Snapshot.snapshot_filename()])
                 )
               end
             )

    assert summary.from_snapshot_id == snapshot_a["snapshot_id"]
    assert summary.to_snapshot_id == snapshot_b["snapshot_id"]
    assert summary.snapshots_written == 2
    assert summary.events_written == 3

    Application.put_env(:llm_db, :history_dir, history_dir)
    clear_history_cache()

    assert {:ok, timeline} = History.timeline(:openai, "gpt-4.1")
    assert Enum.map(timeline, & &1["type"]) == ["introduced", "introduced", "removed"]

    assert Enum.map(timeline, & &1["lineage_key"]) == [
             "openai:gpt-4o",
             "openai:gpt-4o",
             "openai:gpt-4o"
           ]
  end

  defp snapshot(providers) do
    document = %{
      "schema_version" => Snapshot.schema_version(),
      "version" => 2,
      "generated_at" => "2026-01-01T00:00:00Z",
      "providers" => providers
    }

    Map.put(document, "snapshot_id", Snapshot.snapshot_id(document))
  end

  defp write_snapshot(base_dir, snapshot) do
    path = Path.join([base_dir, snapshot["snapshot_id"], Snapshot.snapshot_filename()])
    Snapshot.write!(path, snapshot)
  end

  defp temp_dir(prefix) do
    path = Path.join(System.tmp_dir!(), "#{prefix}_#{System.unique_integer([:positive])}")
    File.rm_rf!(path)
    File.mkdir_p!(path)
    path
  end

  defp clear_history_cache do
    case :ets.whereis(:llm_db_history) do
      :undefined -> :ok
      tid -> :ets.delete(tid)
    end
  end
end
