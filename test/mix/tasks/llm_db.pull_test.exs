defmodule Mix.Tasks.LlmDb.PullTest do
  use ExUnit.Case, async: false

  @dotenv_path Path.expand(".env")
  @runtime_path Path.expand("config/runtime.exs")

  test "load_runtime_config_and_dotenv honors load_dotenv from runtime config" do
    original_dotenv = dotenv_file()
    original_runtime = runtime_file()
    original_env = System.get_env("LLMDB_DOTENV_TEST_KEY")
    original_load_dotenv = Application.get_env(:llm_db, :load_dotenv, :unset)

    try do
      File.write!(@dotenv_path, "LLMDB_DOTENV_TEST_KEY=from_dotenv\n")
      File.write!(@runtime_path, "import Config\nconfig :llm_db, :load_dotenv, false\n")

      Application.delete_env(:llm_db, :load_dotenv)
      System.delete_env("LLMDB_DOTENV_TEST_KEY")
      Mix.Task.reenable("app.config")

      Mix.Tasks.LlmDb.Pull.load_runtime_config_and_dotenv()

      assert Application.get_env(:llm_db, :load_dotenv) == false
      assert System.get_env("LLMDB_DOTENV_TEST_KEY") == nil
    after
      restore_dotenv_file(original_dotenv)
      restore_runtime_file(original_runtime)
      restore_application_env(original_load_dotenv)
      restore_system_env("LLMDB_DOTENV_TEST_KEY", original_env)
    end
  end

  defp dotenv_file do
    case File.read(@dotenv_path) do
      {:ok, contents} -> {:ok, contents}
      {:error, :enoent} -> :missing
    end
  end

  defp runtime_file do
    case File.read(@runtime_path) do
      {:ok, contents} -> {:ok, contents}
      {:error, :enoent} -> :missing
    end
  end

  defp restore_dotenv_file({:ok, contents}), do: File.write!(@dotenv_path, contents)
  defp restore_dotenv_file(:missing), do: File.rm(@dotenv_path)

  defp restore_runtime_file({:ok, contents}), do: File.write!(@runtime_path, contents)
  defp restore_runtime_file(:missing), do: File.rm(@runtime_path)

  defp restore_application_env(:unset), do: Application.delete_env(:llm_db, :load_dotenv)
  defp restore_application_env(value), do: Application.put_env(:llm_db, :load_dotenv, value)

  defp restore_system_env(key, nil), do: System.delete_env(key)
  defp restore_system_env(key, value), do: System.put_env(key, value)
end
