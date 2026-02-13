defmodule Mix.Tasks.LlmDb.Build do
  use Mix.Task

  @shortdoc "Build snapshot.json from sources using the ETL pipeline (--check to verify)"

  @moduledoc """
  Builds snapshot.json from configured sources using the Engine ETL pipeline.

  Runs the complete ETL pipeline (Ingest → Normalize → Validate → Merge →
  Enrich → Filter → Index) on configured sources to generate a fresh
  snapshot.json file.

  ## Usage

      mix llm_db.build
      mix llm_db.build --check

  ## Options

    * `--check` — Instead of writing files, verify that the generated artifacts
      match what is already on disk. Exits with a non-zero status if any files
      are missing, unexpected, or out of date. Useful in CI to ensure
      contributors ran `mix llm_db.build` after editing TOML sources.

  ## Configuration

  Configure sources in your application config:

      config :llm_db,
        sources: [
          {LLMDB.Sources.Packaged, %{}},
          {LLMDB.Sources.ModelsDev, %{url: "https://models.dev/api.json"}},
          {LLMDB.Sources.JSONFile, %{paths: ["priv/custom.json"]}}
        ],
        allow: :all,
        deny: %{},
        prefer: [:openai, :anthropic]
  """

  @manifest_path "priv/llm_db/manifest.json"
  @providers_dir "priv/llm_db/providers"

  @impl Mix.Task
  def run(args) do
    ensure_llm_db_project!()

    {opts, _, _} = OptionParser.parse(args, strict: [check: :boolean])

    Mix.Task.run("app.start")

    Mix.shell().info("Building snapshot from configured sources...\n")

    {:ok, snapshot} = build_snapshot()

    if opts[:check] do
      check_snapshot(snapshot)
    else
      save_snapshot(snapshot)
      print_summary(snapshot)
    end
  end

  defp build_snapshot do
    config = LLMDB.Config.get()
    sources = LLMDB.Config.sources!()

    if sources == [] do
      Mix.shell().info("Warning: No sources configured - snapshot will be empty\n")
    end

    LLMDB.Engine.run(
      sources: sources,
      allow: config.allow,
      deny: config.deny,
      prefer: config.prefer
    )
  end

  defp render_manifest(snapshot) do
    provider_ids =
      snapshot.providers
      |> Map.keys()
      |> Enum.map(&Atom.to_string/1)
      |> Enum.sort()

    manifest = %{
      "version" => snapshot.version,
      "generated_at" => snapshot.generated_at,
      "providers" => provider_ids
    }

    Jason.encode!(manifest, pretty: true)
  end

  defp render_provider(provider_data) do
    provider_data
    |> map_with_string_keys()
    |> Jason.encode!(pretty: true)
  end

  defp save_snapshot(snapshot) do
    # Create providers directory
    File.mkdir_p!(@providers_dir)

    # Write each provider to its own file
    provider_ids =
      snapshot.providers
      |> Enum.map(fn {provider_id, provider_data} ->
        path = Path.join(@providers_dir, "#{provider_id}.json")
        File.write!(path, render_provider(provider_data))
        Atom.to_string(provider_id)
      end)
      |> Enum.sort()

    # Remove stale provider files no longer in the build
    expected_filenames = MapSet.new(provider_ids, &"#{&1}.json")

    case File.ls(@providers_dir) do
      {:ok, entries} ->
        entries
        |> Enum.filter(&String.ends_with?(&1, ".json"))
        |> Enum.reject(&MapSet.member?(expected_filenames, &1))
        |> Enum.each(fn filename ->
          path = Path.join(@providers_dir, filename)
          File.rm!(path)
          Mix.shell().info("✓ Removed stale #{path}")
        end)

      {:error, _} ->
        :ok
    end

    # Write manifest
    File.mkdir_p!(Path.dirname(@manifest_path))
    File.write!(@manifest_path, render_manifest(snapshot))

    Mix.shell().info("✓ Manifest written to #{@manifest_path} (v#{snapshot.version})")
    Mix.shell().info("✓ #{length(provider_ids)} provider files written to #{@providers_dir}/")

    # Generate ValidProviders module from normalized snapshot data
    generate_valid_providers(snapshot)
  end

  defp check_snapshot(snapshot) do
    mismatches = []

    # Check manifest (compare only version and providers list, not generated_at)
    expected_providers_list =
      snapshot.providers
      |> Map.keys()
      |> Enum.map(&Atom.to_string/1)
      |> Enum.sort()

    mismatches =
      case File.read(@manifest_path) do
        {:ok, on_disk} ->
          on_disk_manifest = Jason.decode!(on_disk)

          providers_match =
            Map.get(on_disk_manifest, "providers", []) == expected_providers_list

          version_match =
            Map.get(on_disk_manifest, "version") == snapshot.version

          if providers_match and version_match,
            do: mismatches,
            else: [{:mismatch, @manifest_path} | mismatches]

        {:error, _} ->
          [{:missing, @manifest_path} | mismatches]
      end

    # Check each expected provider file
    expected_providers =
      snapshot.providers
      |> Enum.map(fn {provider_id, provider_data} ->
        filename = "#{provider_id}.json"
        {filename, render_provider(provider_data)}
      end)
      |> Map.new()

    mismatches =
      Enum.reduce(expected_providers, mismatches, fn {filename, expected_json}, acc ->
        path = Path.join(@providers_dir, filename)

        case File.read(path) do
          {:ok, on_disk} ->
            if on_disk != expected_json,
              do: [{:mismatch, path} | acc],
              else: acc

          {:error, _} ->
            [{:missing, path} | acc]
        end
      end)

    # Check for unexpected files in providers/
    expected_filenames = Map.keys(expected_providers) |> MapSet.new()

    mismatches =
      case File.ls(@providers_dir) do
        {:ok, entries} ->
          entries
          |> Enum.filter(&String.ends_with?(&1, ".json"))
          |> Enum.reject(&MapSet.member?(expected_filenames, &1))
          |> Enum.reduce(mismatches, fn filename, acc ->
            [{:unexpected, Path.join(@providers_dir, filename)} | acc]
          end)

        {:error, _} ->
          mismatches
      end

    if mismatches == [] do
      Mix.shell().info("✓ All generated artifacts are up to date.")
    else
      files_list =
        mismatches
        |> Enum.sort_by(fn {_kind, path} -> path end)
        |> Enum.map_join("\n", fn
          {:mismatch, path} -> "  - #{path} (content mismatch)"
          {:missing, path} -> "  - #{path} (missing)"
          {:unexpected, path} -> "  - #{path} (unexpected)"
        end)

      Mix.raise("""
      Generated provider artifacts are out of date or were manually edited.

      Mismatched files:
      #{files_list}

      To fix this:
        1. Edit TOML source files under priv/llm_db/local/<provider>/
        2. Run: mix llm_db.build
        3. Commit the regenerated files

      Do NOT edit priv/llm_db/providers/*.json directly — these files are
      generated by `mix llm_db.build` and will be overwritten.
      """)
    end
  end

  defp print_summary(snapshot) do
    provider_count = map_size(snapshot.providers)

    model_count =
      snapshot.providers
      |> Map.values()
      |> Enum.map(fn provider -> map_size(provider.models) end)
      |> Enum.sum()

    Mix.shell().info("")
    Mix.shell().info("Summary:")
    Mix.shell().info("  Providers: #{provider_count}")
    Mix.shell().info("  Models: #{model_count}")
  end

  defp map_with_string_keys(map) when is_map(map) do
    # Convert struct to plain map first
    plain_map =
      if Map.has_key?(map, :__struct__) do
        Map.from_struct(map)
      else
        map
      end

    # Convert to sorted keyword list for deterministic JSON output
    plain_map
    |> Enum.map(fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), map_with_string_keys(v)}
      {k, v} -> {to_string(k), map_with_string_keys(v)}
    end)
    |> Enum.sort_by(fn {k, _v} -> k end)
    |> Jason.OrderedObject.new()
  end

  defp map_with_string_keys(list) when is_list(list) do
    Enum.map(list, &map_with_string_keys/1)
  end

  defp map_with_string_keys(value), do: value

  # Generate ValidProviders module from normalized snapshot data
  defp generate_valid_providers(snapshot) do
    # Extract provider atoms from nested providers map
    provider_atoms =
      snapshot.providers
      |> Map.keys()
      |> Enum.sort()
      |> Enum.uniq()

    write_valid_providers_module(provider_atoms)
    Mix.shell().info("✓ Generated valid_providers.ex with #{length(provider_atoms)} providers")
  end

  # Write the ValidProviders module to disk
  defp write_valid_providers_module(provider_atoms) do
    module_code = """
    defmodule LLMDB.Generated.ValidProviders do
      @moduledoc \"\"\"
      Auto-generated module containing all valid provider atoms.

      This module is generated by `mix llm_db.build` to prevent atom leaking.
      By pre-generating all provider atoms at build time, we ensure that runtime
      code can only use existing atoms via `String.to_existing_atom/1`.

      DO NOT EDIT THIS FILE MANUALLY - it will be overwritten.
      \"\"\"

      @providers #{inspect(provider_atoms, limit: :infinity)}

      @doc \"\"\"
      Returns the list of all valid provider atoms.
      \"\"\"
      @spec list() :: [atom()]
      def list, do: @providers

      @doc \"\"\"
      Checks if the given atom is a valid provider.
      \"\"\"
      @spec member?(atom()) :: boolean()
      def member?(atom), do: atom in @providers
    end
    """

    module_path = "lib/llm_db/generated/valid_providers.ex"
    File.mkdir_p!(Path.dirname(module_path))
    formatted = Code.format_string!(module_code) |> IO.iodata_to_binary()
    # Ensure file ends with newline (Elixir convention)
    content = if String.ends_with?(formatted, "\n"), do: formatted, else: formatted <> "\n"
    File.write!(module_path, content)
  end

  defp ensure_llm_db_project! do
    app = Mix.Project.config()[:app]

    if app != :llm_db do
      Mix.raise("""
      mix llm_db.build can only be run inside the llm_db project itself.

      This task generates lib/llm_db/generated/valid_providers.ex. Running it from
      a downstream application would create a duplicate LLMDB.Generated.ValidProviders
      module that conflicts with the one shipped in the :llm_db Hex package.

      If you need to regenerate the snapshot (maintainers only):

          cd path/to/llm_db
          mix llm_db.build

      For downstream applications, use the data and modules shipped with :llm_db.
      """)
    end
  end
end
