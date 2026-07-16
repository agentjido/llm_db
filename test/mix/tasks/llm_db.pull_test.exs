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

  test "load_runtime_config_and_dotenv honors task-scoped override configuration" do
    original_dotenv = dotenv_file()
    original_runtime = runtime_file()
    original_env = System.get_env("LLMDB_DOTENV_TEST_KEY")
    original_load_dotenv = Application.get_env(:llm_db, :load_dotenv, :unset)
    original_override = Application.get_env(:llm_db, :dotenv_override, :unset)

    try do
      File.write!(@dotenv_path, "LLMDB_DOTENV_TEST_KEY=from_dotenv\n")

      File.write!(
        @runtime_path,
        "import Config\nconfig :llm_db, load_dotenv: true, dotenv_override: false\n"
      )

      Application.delete_env(:llm_db, :load_dotenv)
      Application.delete_env(:llm_db, :dotenv_override)
      System.put_env("LLMDB_DOTENV_TEST_KEY", "from_shell")
      Mix.Task.reenable("app.config")

      Mix.Tasks.LlmDb.Pull.load_runtime_config_and_dotenv()

      assert Application.get_env(:llm_db, :load_dotenv) == true
      assert Application.get_env(:llm_db, :dotenv_override) == false
      assert System.get_env("LLMDB_DOTENV_TEST_KEY") == "from_shell"
    after
      restore_dotenv_file(original_dotenv)
      restore_runtime_file(original_runtime)
      restore_application_env(:load_dotenv, original_load_dotenv)
      restore_application_env(:dotenv_override, original_override)
      restore_system_env("LLMDB_DOTENV_TEST_KEY", original_env)
    end
  end

  test "load_runtime_config_and_dotenv defaults to repository credentials winning" do
    original_dotenv = dotenv_file()
    original_runtime = runtime_file()
    original_env = System.get_env("LLMDB_DOTENV_TEST_KEY")
    original_load_dotenv = Application.get_env(:llm_db, :load_dotenv, :unset)
    original_override = Application.get_env(:llm_db, :dotenv_override, :unset)

    try do
      File.write!(@dotenv_path, "LLMDB_DOTENV_TEST_KEY=from_dotenv\n")
      File.write!(@runtime_path, "import Config\nconfig :llm_db, load_dotenv: true\n")

      Application.delete_env(:llm_db, :load_dotenv)
      Application.delete_env(:llm_db, :dotenv_override)
      System.put_env("LLMDB_DOTENV_TEST_KEY", "from_shell")
      Mix.Task.reenable("app.config")

      Mix.Tasks.LlmDb.Pull.load_runtime_config_and_dotenv()

      assert System.get_env("LLMDB_DOTENV_TEST_KEY") == "from_dotenv"
    after
      restore_dotenv_file(original_dotenv)
      restore_runtime_file(original_runtime)
      restore_application_env(:load_dotenv, original_load_dotenv)
      restore_application_env(:dotenv_override, original_override)
      restore_system_env("LLMDB_DOTENV_TEST_KEY", original_env)
    end
  end

  test "ensure_no_failed_sources! accepts skips and successful pulls" do
    results = [
      {LLMDB.Sources.Google, {:ok, "priv/llm_db/remote/google.json"}},
      {LLMDB.Sources.OpenAI, {:error, :no_api_key}},
      {LLMDB.Sources.Local, :no_callback},
      {LLMDB.Sources.OpenRouter, :not_modified}
    ]

    assert :ok = Mix.Tasks.LlmDb.Pull.ensure_no_failed_sources!(results)
  end

  test "ensure_no_failed_sources! raises on real pull failures" do
    results = [
      {LLMDB.Sources.Google, {:error, {:http_status, 400}}},
      {LLMDB.Sources.OpenAI, {:error, :no_api_key}}
    ]

    assert_raise Mix.Error,
                 ~r/Source pull failed for 1 source\(s\): LLMDB.Sources.Google \(HTTP 400\)/,
                 fn ->
                   Mix.Tasks.LlmDb.Pull.ensure_no_failed_sources!(results)
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

  defp restore_application_env(value), do: restore_application_env(:load_dotenv, value)

  defp restore_application_env(key, :unset), do: Application.delete_env(:llm_db, key)
  defp restore_application_env(key, value), do: Application.put_env(:llm_db, key, value)

  defp restore_system_env(key, nil), do: System.delete_env(key)
  defp restore_system_env(key, value), do: System.put_env(key, value)
end
