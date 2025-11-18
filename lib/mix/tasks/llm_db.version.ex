defmodule Mix.Tasks.LlmDb.Version do
  @moduledoc """
  Updates the version in mix.exs to the current date (YYYY.MM.DD format).

  ## Usage

      mix llm_db.version
  """

  use Mix.Task

  @shortdoc "Update version to current date"

  @impl Mix.Task
  def run(_args) do
    version = Calendar.strftime(Date.utc_today(), "%Y.%-m.%-d")
    mix_exs_path = "mix.exs"

    content = File.read!(mix_exs_path)
    updated = Regex.replace(~r/@version ".*"/, content, "@version \"#{version}\"")

    File.write!(mix_exs_path, updated)
    Mix.shell().info("Updated version to #{version}")
  end
end
