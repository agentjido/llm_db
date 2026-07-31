defmodule LLMDB.ColdStartTest do
  use ExUnit.Case, async: false

  test "a fresh VM loads known provider atoms and prepares the catalog before lookup" do
    ebin_paths =
      Mix.Project.build_path()
      |> Path.join("lib/*/ebin")
      |> Path.wildcard()

    assert ebin_paths != [], "test build has no ebin paths"

    script = """
    {:ok, provider} = LLMDB.Normalize.normalize_provider_id("openai")

    if Atom.to_string(provider) != "openai" do
      raise "provider registry returned the wrong provider"
    end

    {:ok, _started} = Application.ensure_all_started(:llm_db)

    if is_nil(LLMDB.snapshot()) do
      raise "catalog was not loaded during application startup"
    end

    startup_epoch = LLMDB.epoch()
    [model | _models] = LLMDB.models(provider)
    spec = Atom.to_string(provider) <> ":" <> model.id
    {:ok, _model} = LLMDB.model(spec)

    if LLMDB.epoch() != startup_epoch do
      raise "first lookup reloaded the catalog"
    end

    IO.puts("cold-start-ok")
    """

    args = Enum.flat_map(ebin_paths, &["-pa", &1]) ++ ["-e", script]
    elixir = System.find_executable("elixir") || flunk("elixir executable was not found")

    {output, status} =
      System.cmd(elixir, args,
        cd: File.cwd!(),
        stderr_to_stdout: true
      )

    assert status == 0, output
    assert output =~ "cold-start-ok"
  end
end
