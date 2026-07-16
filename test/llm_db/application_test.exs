defmodule LLMDB.ApplicationTest do
  use ExUnit.Case, async: false

  @dotenv_path Path.expand(".env")

  describe "start/2" do
    test "returns a supervisor compatible with release_handler" do
      master = :application_controller.get_master(:llm_db)
      {root, _} = :application_master.get_child(master)

      assert :supervisor.get_callback_module(root) == Supervisor.Default
      assert {:status, ^root, _, _} = :sys.get_status(root, 5000)
      assert Process.whereis(LLMDB.Supervisor) == root
    end
  end

  describe "runtime environment boundary" do
    test "application startup does not load the repository dotenv file" do
      key = "LLMDB_RUNTIME_MUST_NOT_LOAD_DOTENV"
      original_dotenv = dotenv_file()
      original_env = System.get_env(key)

      try do
        File.write!(@dotenv_path, "#{key}=from_dotenv\n")
        System.delete_env(key)

        assert {:error, {:already_started, _pid}} = LLMDB.Application.start(:normal, [])
        assert System.get_env(key) == nil
      after
        restore_dotenv_file(original_dotenv)
        restore_system_env(key, original_env)
      end
    end

    test "catalog loading and queries do not load the repository dotenv file" do
      key = "LLMDB_RUNTIME_LOAD_MUST_NOT_LOAD_DOTENV"
      original_dotenv = dotenv_file()
      original_env = System.get_env(key)

      try do
        File.write!(@dotenv_path, "#{key}=from_dotenv\n")
        System.delete_env(key)

        assert {:ok, _snapshot} = LLMDB.load()
        assert is_list(LLMDB.providers())
        assert System.get_env(key) == nil
      after
        restore_dotenv_file(original_dotenv)
        restore_system_env(key, original_env)
      end
    end
  end

  defp dotenv_file do
    case File.read(@dotenv_path) do
      {:ok, contents} -> {:ok, contents}
      {:error, :enoent} -> :missing
    end
  end

  defp restore_dotenv_file({:ok, contents}), do: File.write!(@dotenv_path, contents)
  defp restore_dotenv_file(:missing), do: File.rm(@dotenv_path)

  defp restore_system_env(key, nil), do: System.delete_env(key)
  defp restore_system_env(key, value), do: System.put_env(key, value)
end
