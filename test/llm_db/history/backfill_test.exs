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
  end

  defp temp_output_dir do
    path =
      Path.join(
        System.tmp_dir!(),
        "llm_db_history_sync_test_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(path)
    path
  end

  defp first_metadata_commit do
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
    |> List.first()
  end
end
