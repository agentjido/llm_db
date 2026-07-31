defmodule LLMDB.ColdStartTest do
  use ExUnit.Case, async: false

  test "a fresh VM loads known provider atoms and prepares the catalog before lookup" do
    ebin_paths = Path.wildcard(Path.expand("_build/test/lib/*/ebin"))

    script = """
    {:ok, provider} = LLMDB.Normalize.normalize_provider_id("azure")

    if Atom.to_string(provider) != "azure" do
      raise "provider registry returned the wrong provider"
    end

    {:ok, _started} = Application.ensure_all_started(:llm_db)

    if is_nil(LLMDB.Store.snapshot()) do
      raise "catalog was not loaded during application startup"
    end

    startup_epoch = LLMDB.epoch()
    {:ok, _model} = LLMDB.model("azure:gpt-5.4")

    if LLMDB.epoch() != startup_epoch do
      raise "first lookup reloaded the catalog"
    end

    IO.puts("cold-start-ok")
    """

    args = Enum.flat_map(ebin_paths, &["-pa", &1]) ++ ["-e", script]

    {output, status} =
      System.cmd(System.find_executable("elixir"), args,
        cd: File.cwd!(),
        stderr_to_stdout: true
      )

    assert status == 0, output
    assert output =~ "cold-start-ok"
  end
end
