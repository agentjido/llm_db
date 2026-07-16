defmodule LLMDB.ToolingBoundaryTest do
  use ExUnit.Case, async: true

  @project_root Path.expand("../..", __DIR__)
  @boundary_guide Path.join(@project_root, "guides/runtime-and-maintainer-boundaries.md")

  @supported_tasks %{
    "llm_db.build" => Mix.Tasks.LlmDb.Build,
    "llm_db.history.backfill" => Mix.Tasks.LlmDb.History.Backfill,
    "llm_db.history.check" => Mix.Tasks.LlmDb.History.Check,
    "llm_db.history.migrate_git" => Mix.Tasks.LlmDb.History.MigrateGit,
    "llm_db.history.rebuild" => Mix.Tasks.LlmDb.History.Rebuild,
    "llm_db.history.sync" => Mix.Tasks.LlmDb.History.Sync,
    "llm_db.install" => Mix.Tasks.LlmDb.Install,
    "llm_db.models" => Mix.Tasks.LlmDb.Models,
    "llm_db.pull" => Mix.Tasks.LlmDb.Pull,
    "llm_db.snapshot.build" => Mix.Tasks.LlmDb.Snapshot.Build,
    "llm_db.snapshot.fetch" => Mix.Tasks.LlmDb.Snapshot.Fetch,
    "llm_db.snapshot.publish" => Mix.Tasks.LlmDb.Snapshot.Publish,
    "llm_db.version" => Mix.Tasks.LlmDb.Version
  }

  test "every supported Mix task name remains registered and callable" do
    Enum.each(@supported_tasks, fn {task_name, module} ->
      assert Code.ensure_loaded?(module)
      assert Mix.Task.get(task_name) == module
      assert function_exported?(module, :run, 1)
    end)
  end

  test "dotenv compatibility calls identify their task replacement" do
    deprecations = LLMDB.Dotenv.__info__(:deprecated)

    assert {{:load!, 0}, message} = List.keyfind(deprecations, {:load!, 0}, 0)
    assert message =~ "mix llm_db.pull"
    assert {{:load!, 1}, ^message} = List.keyfind(deprecations, {:load!, 1}, 0)
  end

  test "the boundary guide inventories every shipped module and direct dependency" do
    guide = File.read!(@boundary_guide)

    modules =
      @project_root
      |> Path.join("lib/**/*.ex")
      |> Path.wildcard()
      |> Enum.flat_map(fn path ->
        ~r/^\s*defmodule\s+([A-Za-z0-9_.]+)/m
        |> Regex.scan(File.read!(path), capture: :all_but_first)
        |> List.flatten()
      end)
      |> Enum.uniq()

    dependencies =
      Mix.Project.config()
      |> Keyword.fetch!(:deps)
      |> Enum.map(fn
        {name, _requirement} -> name
        {name, _requirement, _opts} -> name
      end)
      |> Enum.map(&Atom.to_string/1)

    assert Enum.reject(modules, &String.contains?(guide, &1)) == []
    assert Enum.reject(dependencies, &String.contains?(guide, "`#{&1}`")) == []
  end
end
