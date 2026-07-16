defmodule LLMDB.ToolingBoundaryTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

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

  test "legacy history backfill APIs identify the maintained replacement and removal window" do
    deprecations = LLMDB.History.Backfill.__info__(:deprecated)

    for arity <- [0, 1] do
      assert {{:run, ^arity}, message} = List.keyfind(deprecations, {:run, arity}, 0)
      assert message =~ "mix llm_db.history.migrate_git --publish"
      assert message =~ "v2027.0.0"
    end

    for arity <- [0, 1] do
      assert {{:sync, ^arity}, message} = List.keyfind(deprecations, {:sync, arity}, 0)
      assert message =~ "mix llm_db.history.rebuild --publish"
      assert message =~ "v2027.0.0"
    end

    assert {{:run, 1}, task_message} =
             List.keyfind(Mix.Tasks.LlmDb.History.Backfill.__info__(:deprecated), {:run, 1}, 0)

    assert task_message =~ "mix llm_db.history.migrate_git --publish"
    assert task_message =~ "mix llm_db.history.rebuild --publish"
    assert task_message =~ "v2027.0.0"

    assert {:shortdoc, [shortdoc]} =
             List.keyfind(
               Mix.Tasks.LlmDb.History.Backfill.module_info(:attributes),
               :shortdoc,
               0
             )

    assert shortdoc =~ "Deprecated"
  end

  test "legacy history backfill task emits actionable migration guidance" do
    warning =
      capture_io(:stderr, fn ->
        assert_raise Mix.Error, ~r/Invalid options/, fn ->
          apply(Mix.Tasks.LlmDb.History.Backfill, :run, [["--invalid"]])
        end
      end)

    assert warning =~ "mix llm_db.history.backfill is deprecated"
    assert warning =~ "mix llm_db.history.migrate_git --publish"
    assert warning =~ "mix llm_db.history.rebuild --publish"
    assert warning =~ "v2027.0.0"
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
