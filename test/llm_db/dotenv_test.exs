defmodule LLMDB.DotenvTest do
  use ExUnit.Case, async: false

  setup do
    original_load_dotenv = Application.get_env(:llm_db, :load_dotenv, :unset)
    original_existing = System.get_env("LLMDB_DOTENV_EXISTING")
    original_loaded = System.get_env("LLMDB_DOTENV_LOADED")

    on_exit(fn ->
      restore_application_env(original_load_dotenv)
      restore_system_env("LLMDB_DOTENV_EXISTING", original_existing)
      restore_system_env("LLMDB_DOTENV_LOADED", original_loaded)
    end)

    :ok
  end

  test "loads missing env vars without overwriting existing ones" do
    env_path =
      write_temp_env("""
      LLMDB_DOTENV_EXISTING=from_dotenv
      LLMDB_DOTENV_LOADED=from_dotenv
      """)

    try do
      Application.put_env(:llm_db, :load_dotenv, true)
      System.put_env("LLMDB_DOTENV_EXISTING", "from_shell")
      System.delete_env("LLMDB_DOTENV_LOADED")

      LLMDB.Dotenv.load!(path: env_path)

      assert System.get_env("LLMDB_DOTENV_EXISTING") == "from_shell"
      assert System.get_env("LLMDB_DOTENV_LOADED") == "from_dotenv"
    after
      File.rm(env_path)
    end
  end

  test "raises when .env contents are malformed" do
    env_path = write_temp_env("BROKEN=${\n")

    try do
      Application.put_env(:llm_db, :load_dotenv, true)

      assert_raise RuntimeError, ~r/There was error with file/, fn ->
        LLMDB.Dotenv.load!(path: env_path)
      end
    after
      File.rm(env_path)
    end
  end

  defp write_temp_env(contents) do
    path = Path.join(System.tmp_dir!(), "llm_db-dotenv-#{System.unique_integer([:positive])}.env")
    File.write!(path, contents)
    path
  end

  defp restore_application_env(:unset), do: Application.delete_env(:llm_db, :load_dotenv)
  defp restore_application_env(value), do: Application.put_env(:llm_db, :load_dotenv, value)

  defp restore_system_env(key, nil), do: System.delete_env(key)
  defp restore_system_env(key, value), do: System.put_env(key, value)
end
