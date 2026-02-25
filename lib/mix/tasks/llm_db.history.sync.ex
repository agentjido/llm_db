defmodule Mix.Tasks.LlmDb.History.Sync do
  use Mix.Task
  @dialyzer {:nowarn_function, run: 1}

  @shortdoc "Incrementally syncs model history into priv/llm_db/history"

  @moduledoc """
  Incrementally syncs model history from committed provider snapshots.

  This task reads `priv/llm_db/history/meta.json` when present and appends only
  events for commits after `to_commit`. If history does not exist yet, it
  performs an initial full backfill into the output directory.

  ## Usage

      mix llm_db.history.sync
      mix llm_db.history.sync --to HEAD
      mix llm_db.history.sync --output-dir priv/llm_db/history

  ## Options

  - `--to` - End commit SHA/ref (default: `HEAD`)
  - `--output-dir` - Directory for generated history files (default: `priv/llm_db/history`)
  """

  @impl Mix.Task
  def run(args) do
    ensure_llm_db_project!()

    {opts, _, invalid} =
      OptionParser.parse(args,
        strict: [
          to: :string,
          output_dir: :string
        ]
      )

    if invalid != [] do
      Mix.raise("Invalid options: #{inspect(invalid)}")
    end

    runtime_opts =
      []
      |> maybe_put(:to, opts[:to])
      |> maybe_put(:output_dir, opts[:output_dir])

    Mix.shell().info("Syncing model history from git...")

    case LLMDB.History.Backfill.sync(runtime_opts) do
      {:ok, summary} ->
        Mix.shell().info("✓ History sync complete")
        Mix.shell().info("  commits scanned:   #{summary.commits_scanned}")
        Mix.shell().info("  commits processed: #{summary.commits_processed}")
        Mix.shell().info("  snapshots written: #{summary.snapshots_written}")
        Mix.shell().info("  events written:    #{summary.events_written}")
        Mix.shell().info("  output dir:        #{summary.output_dir}")
        Mix.shell().info("  from commit:       #{summary.from_commit}")
        Mix.shell().info("  to commit:         #{summary.to_commit}")

      {:error, reason} ->
        Mix.raise("History sync failed: #{inspect(reason)}")
    end
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp ensure_llm_db_project! do
    app = Mix.Project.config()[:app]

    if app != :llm_db do
      Mix.raise("""
      mix llm_db.history.sync can only be run inside the llm_db project itself.
      """)
    end
  end
end
