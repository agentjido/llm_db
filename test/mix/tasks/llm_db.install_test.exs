defmodule Mix.Tasks.LlmDb.InstallTest do
  use ExUnit.Case, async: true
  import Igniter.Test

  test "installer posts correct notice" do
    test_project()
    |> Igniter.compose_task("llm_db.install", [])
    |> assert_has_notice("""
    LLM DB installed successfully !

    Next steps:
    https://hexdocs.pm/llm_db/readme.html#quick-start

    """)
  end
end
