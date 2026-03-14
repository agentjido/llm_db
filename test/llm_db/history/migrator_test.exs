defmodule LLMDB.History.MigratorTest do
  use ExUnit.Case, async: false

  alias LLMDB.History.Migrator

  test "migrates a reachable git range into snapshot-based history artifacts" do
    [first_commit, second_commit | _rest] = metadata_commits()
    output_dir = temp_dir("llm_db_history_migrator")
    snapshots_dir = temp_dir("llm_db_snapshot_migrator")

    on_exit(fn ->
      File.rm_rf!(output_dir)
      File.rm_rf!(snapshots_dir)
    end)

    assert {:ok, summary} =
             Migrator.run(
               from: first_commit,
               to: second_commit,
               output_dir: output_dir,
               snapshots_dir: snapshots_dir
             )

    assert summary.commits_scanned == 2
    assert summary.snapshots_written >= 1
    assert summary.unique_snapshots_written >= 1
    assert is_binary(summary.from_snapshot_id)
    assert is_binary(summary.to_snapshot_id)
    assert File.exists?(Path.join(output_dir, "meta.json"))
    assert File.exists?(Path.join(output_dir, "snapshots.ndjson"))
    assert File.exists?(Path.join(output_dir, "snapshot-index.json"))
    assert File.exists?(Path.join(output_dir, "latest.json"))

    snapshot_index = read_json(Path.join(output_dir, "snapshot-index.json"))

    assert [%{"snapshot_id" => snapshot_id, "source_commit" => ^first_commit} | _] =
             snapshot_index["snapshots"]

    assert File.exists?(Path.join([snapshots_dir, snapshot_id, "snapshot.json"]))
    assert File.exists?(Path.join([snapshots_dir, snapshot_id, "snapshot-meta.json"]))
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
    |> Enum.map(&String.trim/1)
  end

  defp read_json(path) do
    path
    |> File.read!()
    |> Jason.decode!()
  end

  defp temp_dir(prefix) do
    path = Path.join(System.tmp_dir!(), "#{prefix}_#{System.unique_integer([:positive])}")
    File.rm_rf!(path)
    File.mkdir_p!(path)
    path
  end
end
