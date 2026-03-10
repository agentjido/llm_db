defmodule LLMDB.History.BackfillTest do
  use ExUnit.Case, async: false

  alias LLMDB.History.Backfill

  describe "diff_models/2" do
    test "emits introduced, removed, and changed events deterministically" do
      previous = %{
        "openai:gpt-4o" => %{
          "id" => "gpt-4o",
          "provider" => "openai",
          "limits" => %{"context" => 128_000}
        },
        "openai:gpt-3.5-turbo" => %{"id" => "gpt-3.5-turbo", "provider" => "openai"}
      }

      current = %{
        "openai:gpt-4o" => %{
          "id" => "gpt-4o",
          "provider" => "openai",
          "limits" => %{"context" => 256_000}
        },
        "anthropic:claude-sonnet-4" => %{"id" => "claude-sonnet-4", "provider" => "anthropic"}
      }

      events = Backfill.diff_models(previous, current)

      assert [
               %{type: "introduced", model_key: "anthropic:claude-sonnet-4", changes: []},
               %{type: "removed", model_key: "openai:gpt-3.5-turbo", changes: []},
               %{
                 type: "changed",
                 model_key: "openai:gpt-4o",
                 changes: [
                   %{
                     path: "limits.context",
                     op: "replace",
                     before: 128_000,
                     after: 256_000
                   }
                 ]
               }
             ] = events
    end

    test "does not emit a changed event for reordered aliases" do
      previous = %{
        "openai:gpt-4o" => %{
          "id" => "gpt-4o",
          "provider" => "openai",
          "aliases" => ["gpt-4o-latest", "chatgpt-4o-latest"]
        }
      }

      current = %{
        "openai:gpt-4o" => %{
          "id" => "gpt-4o",
          "provider" => "openai",
          "aliases" => ["chatgpt-4o-latest", "gpt-4o-latest"]
        }
      }

      # Simulate post-normalization data used by the backfill engine.
      previous_normalized = %{
        "openai:gpt-4o" => %{
          "id" => "gpt-4o",
          "provider" => "openai",
          "aliases" => Enum.sort(previous["openai:gpt-4o"]["aliases"])
        }
      }

      current_normalized = %{
        "openai:gpt-4o" => %{
          "id" => "gpt-4o",
          "provider" => "openai",
          "aliases" => Enum.sort(current["openai:gpt-4o"]["aliases"])
        }
      }

      assert Backfill.diff_models(previous_normalized, current_normalized) == []
    end
  end

  describe "sync/1" do
    test "bootstraps on empty output directory and is idempotent" do
      output_dir = temp_output_dir()
      first_commit = first_metadata_commit()

      on_exit(fn -> File.rm_rf!(output_dir) end)

      assert {:ok, first} = Backfill.sync(output_dir: output_dir, to: first_commit)
      assert first.from_commit == first_commit
      assert first.to_commit == first_commit
      assert first.commits_processed == 1
      assert first.snapshots_written == 1

      assert File.exists?(Path.join(output_dir, "meta.json"))
      assert File.exists?(Path.join(output_dir, "snapshots.ndjson"))

      assert {:ok, second} = Backfill.sync(output_dir: output_dir, to: first_commit)
      assert second.from_commit == first_commit
      assert second.to_commit == first_commit
      assert second.commits_processed == first.commits_processed
      assert second.events_written == first.events_written
    end

    test "repairs rewritten anchors without duplicating history when the snapshot digest matches a reachable commit" do
      output_dir = temp_output_dir()
      latest_commit = latest_metadata_commit()

      on_exit(fn -> File.rm_rf!(output_dir) end)

      assert {:ok, _summary} = Backfill.sync(output_dir: output_dir, to: latest_commit)

      snapshot_count = snapshot_line_count(output_dir)
      event_count = event_line_count(output_dir)

      overwrite_meta_to_commit(output_dir, String.duplicate("0", 40))

      assert {:ok, repaired} = Backfill.sync(output_dir: output_dir, to: latest_commit)
      assert repaired.to_commit == latest_commit
      assert read_meta_file(output_dir)["to_commit"] == latest_commit
      assert snapshot_line_count(output_dir) == snapshot_count
      assert event_line_count(output_dir) == event_count
    end

    test "processes pending commits after re-anchoring to a reachable metadata snapshot" do
      output_dir = temp_output_dir()
      previous_commit = previous_metadata_commit()
      latest_commit = latest_metadata_commit()

      on_exit(fn -> File.rm_rf!(output_dir) end)

      assert {:ok, _summary} = Backfill.sync(output_dir: output_dir, to: previous_commit)

      snapshot_count = snapshot_line_count(output_dir)
      event_count = event_line_count(output_dir)

      overwrite_meta_to_commit(output_dir, String.duplicate("0", 40))

      assert {:ok, repaired} = Backfill.sync(output_dir: output_dir, to: latest_commit)
      assert repaired.to_commit == latest_commit
      assert read_meta_file(output_dir)["to_commit"] == latest_commit
      assert snapshot_line_count(output_dir) == snapshot_count + 1
      assert event_line_count(output_dir) > event_count
    end
  end

  describe "check/1" do
    test "treats missing to_commit as up to date when the snapshot digest matches reachable history" do
      output_dir = temp_output_dir()
      latest_commit = latest_metadata_commit()

      on_exit(fn -> File.rm_rf!(output_dir) end)

      assert {:ok, _summary} = Backfill.sync(output_dir: output_dir, to: latest_commit)

      overwrite_meta_to_commit(output_dir, nil)

      assert {:ok, :up_to_date} = Backfill.check(output_dir: output_dir, to: latest_commit)
    end

    test "treats rewritten anchors as up to date when the snapshot digest matches reachable history" do
      output_dir = temp_output_dir()
      latest_commit = latest_metadata_commit()

      on_exit(fn -> File.rm_rf!(output_dir) end)

      assert {:ok, _summary} = Backfill.sync(output_dir: output_dir, to: latest_commit)

      overwrite_meta_to_commit(output_dir, String.duplicate("0", 40))

      assert {:ok, :up_to_date} = Backfill.check(output_dir: output_dir, to: latest_commit)
    end

    test "reports pending commits from the resolved reachable anchor" do
      output_dir = temp_output_dir()
      previous_commit = previous_metadata_commit()
      latest_commit = latest_metadata_commit()

      on_exit(fn -> File.rm_rf!(output_dir) end)

      assert {:ok, _summary} = Backfill.sync(output_dir: output_dir, to: previous_commit)

      overwrite_meta_to_commit(output_dir, String.duplicate("0", 40))

      assert {:ok, {:outdated, %{new_commits: 1, latest_commit: ^latest_commit}}} =
               Backfill.check(output_dir: output_dir, to: latest_commit)
    end

    test "returns backfill guidance when an unreachable anchor cannot be re-anchored" do
      output_dir = temp_output_dir()
      first_commit = first_metadata_commit()

      on_exit(fn -> File.rm_rf!(output_dir) end)

      assert {:ok, _summary} = Backfill.sync(output_dir: output_dir, to: first_commit)

      overwrite_meta_to_commit(output_dir, String.duplicate("0", 40))
      overwrite_last_snapshot_digest(output_dir, String.duplicate("f", 64))

      assert {:error, message} = Backfill.check(output_dir: output_dir, to: first_commit)
      assert message =~ "cannot be re-anchored"
      assert message =~ "backfill --force"
    end
  end

  defp temp_output_dir do
    path =
      Path.join(
        System.tmp_dir!(),
        "llm_db_history_sync_test_#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(path)
    File.mkdir_p!(path)
    path
  end

  defp first_metadata_commit do
    metadata_commits()
    |> List.first()
  end

  defp previous_metadata_commit do
    metadata_commits()
    |> Enum.take(-2)
    |> List.first()
  end

  defp latest_metadata_commit do
    metadata_commits()
    |> List.last()
  end

  defp metadata_commits do
    {output, 0} =
      System.cmd("git", [
        "rev-list",
        "--reverse",
        "--topo-order",
        "HEAD",
        "--",
        "priv/llm_db/providers",
        "priv/llm_db/manifest.json"
      ])

    output
    |> String.split("\n", trim: true)
  end

  defp write_meta(output_dir, meta) do
    path = Path.join(output_dir, "meta.json")
    File.write!(path, Jason.encode!(meta))
  end

  defp overwrite_meta_to_commit(output_dir, to_commit) do
    output_dir
    |> read_meta_file()
    |> Map.put("to_commit", to_commit)
    |> then(&write_meta(output_dir, &1))
  end

  defp read_meta_file(output_dir) do
    output_dir
    |> Path.join("meta.json")
    |> File.read!()
    |> Jason.decode!()
  end

  defp overwrite_last_snapshot_digest(output_dir, digest) do
    path = Path.join(output_dir, "snapshots.ndjson")

    updated =
      path
      |> File.read!()
      |> String.split("\n", trim: true)
      |> List.update_at(-1, fn line ->
        line
        |> Jason.decode!()
        |> Map.put("digest", digest)
        |> Jason.encode!()
      end)
      |> Enum.join("\n")
      |> Kernel.<>("\n")

    File.write!(path, updated)
  end

  defp snapshot_line_count(output_dir) do
    output_dir
    |> Path.join("snapshots.ndjson")
    |> File.read!()
    |> String.split("\n", trim: true)
    |> length()
  end

  defp event_line_count(output_dir) do
    output_dir
    |> Path.join("events/*.ndjson")
    |> Path.wildcard()
    |> Enum.reduce(0, fn path, acc ->
      count =
        path
        |> File.read!()
        |> String.split("\n", trim: true)
        |> length()

      acc + count
    end)
  end
end
