defmodule LLMDB.HistoryTest do
  use ExUnit.Case, async: false

  alias LLMDB.History

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

  test "available?/0 is false when history files are missing" do
    dir = temp_history_dir()
    File.rm_rf!(dir)

    Application.put_env(:llm_db, :history_dir, dir)
    clear_history_cache()

    refute History.available?()
    assert {:error, :history_unavailable} = History.meta()
  end

  test "timeline/2 follows lineage_key and returns deterministic ordering" do
    dir = temp_history_dir()
    write_meta(dir)

    events = [
      %{
        "schema_version" => 1,
        "event_id" => "c:2",
        "snapshot_id" => "c",
        "source_commit" => "c",
        "captured_at" => "2026-01-03T00:00:00Z",
        "type" => "changed",
        "model_key" => "openai:gpt-4.1",
        "lineage_key" => "openai:gpt-4o",
        "provider" => "openai",
        "model_id" => "gpt-4.1",
        "changes" => [
          %{
            "path" => "limits.context",
            "op" => "replace",
            "before" => 128_000,
            "after" => 256_000
          }
        ]
      },
      %{
        "schema_version" => 1,
        "event_id" => "a:1",
        "snapshot_id" => "a",
        "source_commit" => "a",
        "captured_at" => "2026-01-01T00:00:00Z",
        "type" => "introduced",
        "model_key" => "openai:gpt-4o",
        "lineage_key" => "openai:gpt-4o",
        "provider" => "openai",
        "model_id" => "gpt-4o",
        "changes" => []
      },
      %{
        "schema_version" => 1,
        "event_id" => "b:1",
        "snapshot_id" => "b",
        "source_commit" => "b",
        "captured_at" => "2026-01-02T00:00:00Z",
        "type" => "introduced",
        "model_key" => "openai:gpt-4.1",
        "lineage_key" => "openai:gpt-4o",
        "provider" => "openai",
        "model_id" => "gpt-4.1",
        "changes" => []
      }
    ]

    write_events(dir, "2026", events)

    Application.put_env(:llm_db, :history_dir, dir)
    clear_history_cache()

    assert {:ok, timeline} = History.timeline(:openai, "gpt-4.1")
    assert Enum.map(timeline, & &1["event_id"]) == ["a:1", "b:1", "c:2"]

    assert {:ok, old_timeline} = History.timeline("openai", "gpt-4o")
    assert Enum.map(old_timeline, & &1["event_id"]) == ["a:1", "b:1", "c:2"]

    assert {:ok, []} = History.timeline(:openai, "does-not-exist")
  end

  test "recent/1 caps at 500 and sorts newest first" do
    dir = temp_history_dir()
    write_meta(dir)

    events =
      Enum.map(1..510, fn i ->
        id = String.pad_leading(Integer.to_string(i), 4, "0")

        %{
          "schema_version" => 1,
          "event_id" => "e#{id}",
          "snapshot_id" => "s#{id}",
          "source_commit" => "s#{id}",
          "captured_at" => "2026-01-01T00:00:00Z",
          "type" => "changed",
          "model_key" => "openai:gpt-4o",
          "lineage_key" => "openai:gpt-4o",
          "provider" => "openai",
          "model_id" => "gpt-4o",
          "changes" => []
        }
      end)

    write_events(dir, "2026", events)

    Application.put_env(:llm_db, :history_dir, dir)
    clear_history_cache()

    assert {:ok, recent} = History.recent(600)
    assert length(recent) == 500
    assert hd(recent)["event_id"] == "e0510"
    assert List.last(recent)["event_id"] == "e0011"

    assert {:error, :invalid_limit} = History.recent(0)
  end

  defp write_meta(dir) do
    File.mkdir_p!(Path.join(dir, "events"))

    meta = %{
      "commits_scanned" => 3,
      "commits_processed" => 3,
      "snapshots_written" => 3,
      "events_written" => 3,
      "output_dir" => dir,
      "from_commit" => "a",
      "to_commit" => "c",
      "generated_at" => "2026-02-25T00:00:00Z",
      "source_repo" => "git@github.com:agentjido/llm_db.git"
    }

    File.write!(Path.join(dir, "meta.json"), Jason.encode!(meta, pretty: true))
  end

  defp write_events(dir, year, events) do
    path = Path.join([dir, "events", "#{year}.ndjson"])

    lines =
      events
      |> Enum.map(&Jason.encode!/1)
      |> Enum.map_join("\n", & &1)

    File.write!(path, lines <> "\n")
  end

  defp temp_history_dir do
    path =
      Path.join(System.tmp_dir!(), "llm_db_history_test_#{System.unique_integer([:positive])}")

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
