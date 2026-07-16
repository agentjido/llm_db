defmodule LLMDB.PackageManifestTest do
  use ExUnit.Case, async: true

  @expected_files ~w(
    config
    guides
    lib
    priv/llm_db/snapshot.json
    mix.exs
    LICENSE
    README.md
    CHANGELOG.md
  )

  test "the Hex manifest keeps runtime/tooling assets and excludes repository-only files" do
    package_files = Mix.Project.config() |> Keyword.fetch!(:package) |> Keyword.fetch!(:files)

    assert package_files == @expected_files
    refute "AGENTS.md" in package_files
    refute "usage-rules.md" in package_files
    refute ".formatter.exs" in package_files
  end
end
