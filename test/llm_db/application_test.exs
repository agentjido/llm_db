defmodule LLMDB.ApplicationTest do
  use ExUnit.Case, async: false

  describe "start/2" do
    test "returns a supervisor compatible with release_handler" do
      master = :application_controller.get_master(:llm_db)
      {root, _} = :application_master.get_child(master)

      assert :supervisor.get_callback_module(root) == Supervisor.Default
      assert {:status, ^root, _, _} = :sys.get_status(root, 5000)
      assert Process.whereis(LLMDB.Supervisor) == root
    end
  end

  describe "load_dotenv configuration" do
    test "load_dotenv defaults to true" do
      original = Application.get_env(:llm_db, :load_dotenv)

      try do
        Application.delete_env(:llm_db, :load_dotenv)
        assert Application.get_env(:llm_db, :load_dotenv, true) == true
      after
        if original do
          Application.put_env(:llm_db, :load_dotenv, original)
        end
      end
    end

    test "load_dotenv can be set to false" do
      original = Application.get_env(:llm_db, :load_dotenv)

      try do
        Application.put_env(:llm_db, :load_dotenv, false)
        assert Application.get_env(:llm_db, :load_dotenv, true) == false
      after
        if original do
          Application.put_env(:llm_db, :load_dotenv, original)
        else
          Application.delete_env(:llm_db, :load_dotenv)
        end
      end
    end
  end
end
