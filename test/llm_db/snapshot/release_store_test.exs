defmodule LLMDB.Snapshot.ReleaseStoreTest do
  use ExUnit.Case, async: false

  alias LLMDB.Snapshot.ReleaseStore

  test "creates snapshot and history releases atomically with assets" do
    tmp_dir = tmp_dir("release_store_create")
    bin_dir = Path.join(tmp_dir, "bin")
    assets_dir = Path.join(tmp_dir, "assets")
    log_path = Path.join(tmp_dir, "gh.log")
    script_path = Path.join(bin_dir, "gh")
    original_path = System.get_env("PATH")

    {snapshot_path, snapshot_meta_path, history_archive_path, history_meta_path} =
      write_assets!(assets_dir)

    File.mkdir_p!(bin_dir)

    File.write!(
      script_path,
      gh_script(log_path)
    )

    File.chmod!(script_path, 0o755)
    System.put_env("PATH", "#{bin_dir}:#{original_path}")
    System.put_env("GH_SCENARIO", "missing")

    on_exit(fn ->
      System.put_env("PATH", original_path)
      System.delete_env("GH_SCENARIO")
    end)

    assert :ok =
             ReleaseStore.ensure_snapshot_release(
               snapshot_path,
               snapshot_meta_path,
               "abc"
             )

    assert :ok =
             ReleaseStore.publish_history_release(
               [history_archive_path, history_meta_path],
               "abc"
             )

    log = File.read!(log_path)
    assert log =~ "release view snapshot-abc"
    assert log =~ "release create snapshot-abc #{snapshot_path} #{snapshot_meta_path}"
    assert log =~ "release view history-abc"
    assert log =~ "release create history-abc #{history_archive_path} #{history_meta_path}"
    refute log =~ "release upload"
  end

  test "reuses complete immutable releases without mutating them" do
    tmp_dir = tmp_dir("release_store_reuse")
    bin_dir = Path.join(tmp_dir, "bin")
    assets_dir = Path.join(tmp_dir, "assets")
    log_path = Path.join(tmp_dir, "gh.log")
    script_path = Path.join(bin_dir, "gh")
    original_path = System.get_env("PATH")

    {snapshot_path, snapshot_meta_path, _history_archive_path, _history_meta_path} =
      write_assets!(assets_dir)

    File.mkdir_p!(bin_dir)

    File.write!(
      script_path,
      gh_script(log_path)
    )

    File.chmod!(script_path, 0o755)
    System.put_env("PATH", "#{bin_dir}:#{original_path}")
    System.put_env("GH_SCENARIO", "complete_immutable")

    on_exit(fn ->
      System.put_env("PATH", original_path)
      System.delete_env("GH_SCENARIO")
    end)

    assert :ok =
             ReleaseStore.ensure_snapshot_release(
               snapshot_path,
               snapshot_meta_path,
               "abc"
             )

    log = File.read!(log_path)
    assert log =~ "release view snapshot-abc"
    refute log =~ "release create snapshot-abc"
    refute log =~ "release delete snapshot-abc"
    refute log =~ "release upload snapshot-abc"
  end

  test "repairs immutable releases that were published without assets" do
    tmp_dir = tmp_dir("release_store_repair")
    bin_dir = Path.join(tmp_dir, "bin")
    assets_dir = Path.join(tmp_dir, "assets")
    log_path = Path.join(tmp_dir, "gh.log")
    script_path = Path.join(bin_dir, "gh")
    original_path = System.get_env("PATH")

    {snapshot_path, snapshot_meta_path, _history_archive_path, _history_meta_path} =
      write_assets!(assets_dir)

    File.mkdir_p!(bin_dir)

    File.write!(
      script_path,
      gh_script(log_path)
    )

    File.chmod!(script_path, 0o755)
    System.put_env("PATH", "#{bin_dir}:#{original_path}")
    System.put_env("GH_SCENARIO", "immutable_missing_assets")

    on_exit(fn ->
      System.put_env("PATH", original_path)
      System.delete_env("GH_SCENARIO")
    end)

    assert :ok =
             ReleaseStore.ensure_snapshot_release(
               snapshot_path,
               snapshot_meta_path,
               "abc"
             )

    log = File.read!(log_path)
    assert log =~ "release view snapshot-abc"
    assert log =~ "release delete snapshot-abc"
    assert log =~ "release create snapshot-abc #{snapshot_path} #{snapshot_meta_path}"
    refute log =~ "release upload snapshot-abc"
  end

  defp write_assets!(assets_dir) do
    File.mkdir_p!(assets_dir)

    snapshot_path = Path.join(assets_dir, "snapshot.json")
    snapshot_meta_path = Path.join(assets_dir, "snapshot-meta.json")
    history_archive_path = Path.join(assets_dir, "history.tar.gz")
    history_meta_path = Path.join(assets_dir, "history-meta.json")

    File.write!(snapshot_path, ~s({"snapshot_id":"abc"}))
    File.write!(snapshot_meta_path, ~s({"snapshot_id":"abc"}))
    File.write!(history_archive_path, "archive")
    File.write!(history_meta_path, ~s({"to_snapshot_id":"abc"}))

    {snapshot_path, snapshot_meta_path, history_archive_path, history_meta_path}
  end

  defp gh_script(log_path) do
    """
    #!/bin/sh
    set -eu
    printf '%s\\n' "$*" >> "#{log_path}"

    scenario="${GH_SCENARIO:-missing}"

    if [ "$1" = "release" ] && [ "$2" = "view" ]; then
      tag="$3"

      if [ "$scenario" = "missing" ]; then
        echo "release not found" >&2
        exit 1
      fi

      if [ "$scenario" = "complete_immutable" ]; then
        if [ "$tag" = "snapshot-abc" ]; then
          echo '{"tagName":"snapshot-abc","isImmutable":true,"assets":[{"name":"snapshot.json"},{"name":"snapshot-meta.json"}]}'
          exit 0
        fi

        if [ "$tag" = "history-abc" ]; then
          echo '{"tagName":"history-abc","isImmutable":true,"assets":[{"name":"history.tar.gz"},{"name":"history-meta.json"}]}'
          exit 0
        fi
      fi

      if [ "$scenario" = "immutable_missing_assets" ]; then
        echo '{"tagName":"'"$tag"'","isImmutable":true,"assets":[]}'
        exit 0
      fi
    fi

    if [ "$1" = "release" ] && [ "$2" = "delete" ]; then
      echo "deleted"
      exit 0
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
  end

  defp tmp_dir(prefix) do
    path = Path.join(System.tmp_dir!(), "#{prefix}_#{System.unique_integer([:positive])}")
    File.mkdir_p!(path)
    path
  end
end
