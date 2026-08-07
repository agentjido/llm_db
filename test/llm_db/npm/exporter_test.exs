defmodule LLMDB.NPM.ExporterTest do
  use ExUnit.Case, async: true

  alias LLMDB.NPM.Exporter

  test "exports provider shards that retain canonical snapshot identity" do
    output_dir =
      Path.join(
        System.tmp_dir!(),
        "llm-db-npm-exporter-#{System.unique_integer([:positive])}"
      )

    on_exit(fn -> File.rm_rf!(output_dir) end)

    manifest = Exporter.export!(output_dir)
    openai = output_dir |> Path.join("providers/openai.json") |> File.read!() |> Jason.decode!()

    assert manifest["snapshot_id"] ==
             "priv/llm_db/snapshot.json"
             |> File.read!()
             |> Jason.decode!()
             |> Map.fetch!("snapshot_id")

    assert manifest["provider_count"] == map_size(manifest["providers"])
    assert manifest["model_count"] > 1_000
    assert manifest["providers"]["openai"]["model_count"] == map_size(openai["models"])
    assert openai["id"] == "openai"
    assert openai["models"]["gpt-5.4"]["provider"] == "openai"
  end

  test "rejects unsafe output directories" do
    assert_raise ArgumentError, fn -> Exporter.export!(Path.expand(".")) end
  end

  test "does not replace a populated directory that it does not own" do
    output_dir =
      Path.join(
        System.tmp_dir!(),
        "llm-db-npm-exporter-unowned-#{System.unique_integer([:positive])}"
      )

    important_path = Path.join(output_dir, "important.txt")
    File.mkdir_p!(output_dir)
    File.write!(important_path, "keep")
    on_exit(fn -> File.rm_rf!(output_dir) end)

    assert_raise ArgumentError, ~r/without an ownership marker/, fn ->
      Exporter.export!(output_dir)
    end

    assert File.read!(important_path) == "keep"
  end
end
