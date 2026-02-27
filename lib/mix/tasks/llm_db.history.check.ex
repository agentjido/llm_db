defmodule Mix.Tasks.LlmDb.History.Check do
  use Mix.Task

  @shortdoc "Checks whether generated history is up to date with git metadata commits"

  @moduledoc """
  Checks whether `priv/llm_db/history` is current with provider metadata history.

  Intended for CI drift detection after metadata changes.

  ## Usage

      mix llm_db.history.check
      mix llm_db.history.check --to HEAD
      mix llm_db.history.check --allow-missing
      mix llm_db.history.check --output-dir priv/llm_db/history

  ## Options

  - `--to` - End commit SHA/ref to compare against (default: `HEAD`)
  - `--allow-missing` - Treat missing history output as success (default: `false`)
  - `--output-dir` - History directory (default: `priv/llm_db/history`)
  """

  @impl Mix.Task
  def run(args) do
    ensure_llm_db_project!()

    {opts, _, invalid} =
      OptionParser.parse(args,
        strict: [
          to: :string,
          allow_missing: :boolean,
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

    allow_missing? = opts[:allow_missing] == true

    case LLMDB.History.Backfill.check(runtime_opts) do
      {:ok, :up_to_date} ->
        Mix.shell().info("✓ History is up to date")

      {:ok, :history_unavailable} when allow_missing? ->
        Mix.shell().info("✓ History output unavailable (allowed)")

      {:ok, :history_unavailable} ->
        Mix.raise(
          "History check failed: history output is unavailable. Run mix llm_db.history.sync"
        )

      {:ok, {:outdated, %{new_commits: count, latest_commit: latest}}} ->
        Mix.raise(
          "History check failed: #{count} metadata commit(s) pending. Latest pending commit: #{latest}. Run mix llm_db.history.sync"
        )

      {:error, reason} ->
        Mix.raise("History check failed: #{inspect(reason)}")
    end
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp ensure_llm_db_project! do
    app = Mix.Project.config()[:app]

    if app != :llm_db do
      Mix.raise("""
      mix llm_db.history.check can only be run inside the llm_db project itself.
      """)
    end
  end
end
