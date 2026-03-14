defmodule LLMDB.Snapshot.ReleaseStoreTest do
  use ExUnit.Case, async: false

  alias LLMDB.Snapshot.ReleaseStore

  test "treats gh release create and upload stdout as success" do
    tmp_dir = tmp_dir("release_store")
    bin_dir = Path.join(tmp_dir, "bin")
    assets_dir = Path.join(tmp_dir, "assets")
    log_path = Path.join(tmp_dir, "gh.log")
    script_path = Path.join(bin_dir, "gh")
    original_path = System.get_env("PATH")

    File.mkdir_p!(bin_dir)
    File.mkdir_p!(assets_dir)
    File.write!(Path.join(assets_dir, "snapshot.json"), ~s({"snapshot_id":"abc"}))
    File.write!(Path.join(assets_dir, "snapshot-meta.json"), ~s({"snapshot_id":"abc"}))
    File.write!(Path.join(assets_dir, "latest.json"), ~s({"snapshot_id":"abc"}))
    File.write!(Path.join(assets_dir, "snapshot-index.json"), ~s({"snapshots":[]}))

    File.write!(
      script_path,
      """
      #!/bin/sh
      set -eu
      printf '%s\\n' "$*" >> "#{log_path}"

      if [ "$1" = "release" ] && [ "$2" = "view" ]; then
        echo "release not found" >&2
        exit 1
      fi

      if [ "$1" = "release" ] && [ "$2" = "create" ]; then
        echo "https://github.com/agentjido/llm_db/releases/tag/$3"
        exit 0
      fi

      if [ "$1" = "release" ] && [ "$2" = "upload" ]; then
        echo "uploaded"
        exit 0
      fi

      echo "unexpected command: $*" >&2
      exit 1
      """
    )

    File.chmod!(script_path, 0o755)
    System.put_env("PATH", "#{bin_dir}:#{original_path}")

    on_exit(fn ->
      System.put_env("PATH", original_path)
    end)

    assert :ok =
             ReleaseStore.ensure_snapshot_release(
               Path.join(assets_dir, "snapshot.json"),
               Path.join(assets_dir, "snapshot-meta.json"),
               "abc"
             )

    assert :ok =
             ReleaseStore.publish_catalog_index([
               Path.join(assets_dir, "latest.json"),
               Path.join(assets_dir, "snapshot-index.json")
             ])

    log = File.read!(log_path)
    assert log =~ "release view snapshot-abc"
    assert log =~ "release create snapshot-abc"
    assert log =~ "release upload snapshot-abc"
    assert log =~ "release create catalog-index"
    assert log =~ "release upload catalog-index"
  end

  defp tmp_dir(prefix) do
    path = Path.join(System.tmp_dir!(), "#{prefix}_#{System.unique_integer([:positive])}")
    File.mkdir_p!(path)
    path
  end
end
