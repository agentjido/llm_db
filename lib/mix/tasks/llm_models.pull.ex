defmodule Mix.Tasks.LLMModels.Pull do
  use Mix.Task

  @shortdoc "Pull latest model metadata and regenerate snapshot"

  @moduledoc """
  Fetches the latest model metadata from models.dev, syncs it locally,
  and regenerates the packaged snapshot with valid providers module.

  ## Usage

      mix llm_models.pull [--url URL]

  ## Options

    * `--url` - Source URL (default: https://models.dev/api.json)

  ## Examples

      mix llm_models.pull
      mix llm_models.pull --url https://custom-source.com/models.json
  """

  @default_url "https://models.dev/api.json"
  @upstream_path "priv/llm_models/upstream.json"
  @snapshot_path "priv/llm_models/snapshot.json"

  @impl Mix.Task
  def run(args) do
    {opts, _remaining, _invalid} =
      OptionParser.parse(args, strict: [url: :string])

    url = Keyword.get(opts, :url, @default_url)

    Mix.shell().info("Fetching model metadata from #{url}...")

    case download(url) do
      {:ok, body} ->
        save_file(@upstream_path, body)
        save_manifest(@upstream_path, url, body)
        Mix.shell().info("✓ Pulled metadata to #{@upstream_path}")

        activate_snapshot()

      {:error, reason} ->
        Mix.raise("Failed to download from #{url}: #{inspect(reason)}")
    end
  end

  defp download(url) do
    case System.cmd("curl", ["-sS", "-L", url], stderr_to_stdout: true) do
      {body, 0} ->
        {:ok, body}

      {error, _} ->
        {:error, "curl failed: #{error}"}
    end
  end

  defp save_file(path, content) do
    path
    |> Path.dirname()
    |> File.mkdir_p!()

    File.write!(path, content)
  end

  defp save_manifest(json_path, url, content) do
    manifest_path = String.replace_suffix(json_path, ".json", ".manifest.json")

    sha256 = :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)

    manifest = %{
      source_url: url,
      downloaded_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      sha256: sha256,
      size_bytes: byte_size(content)
    }

    manifest_json = Jason.encode!(manifest, pretty: true)
    File.write!(manifest_path, manifest_json)

    Mix.shell().info("  Downloaded #{byte_size(content)} bytes")
    Mix.shell().info("  SHA256: #{sha256}")
  end

  defp activate_snapshot do
    Mix.shell().info("\nActivating snapshot...")

    upstream_data = read_upstream(@upstream_path)
    write_temp_snapshot(upstream_data)
    config = build_config()

    case LLMModels.Engine.run(config) do
      {:ok, snapshot} ->
        save_final_snapshot(snapshot)
        generate_valid_providers_module(snapshot)
        print_summary(snapshot)

      {:error, :empty_catalog} ->
        Mix.raise("Activation failed: resulting catalog is empty")

      {:error, reason} ->
        Mix.raise("Activation failed: #{inspect(reason)}")
    end
  end

  defp read_upstream(path) do
    case File.read(path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, data} -> data
          {:error, reason} -> Mix.raise("Failed to parse JSON: #{inspect(reason)}")
        end

      {:error, reason} ->
        Mix.raise("Failed to read #{path}: #{inspect(reason)}")
    end
  end

  defp write_temp_snapshot(upstream_data) do
    temp_path = LLMModels.Packaged.path()

    temp_path
    |> Path.dirname()
    |> File.mkdir_p!()

    {providers, all_models} = transform_upstream_data(upstream_data)

    providers = atomize_keys(providers)
    models = atomize_keys(all_models)

    temp_data = %{providers: providers, models: models}

    json = Jason.encode!(temp_data)
    File.write!(temp_path, json)
  end

  defp transform_upstream_data(data) do
    providers =
      data
      |> Enum.reject(fn {_key, value} -> not is_map(value) end)
      |> Enum.map(fn {_key, provider} ->
        provider
        |> Map.drop(["models"])
        |> Map.take(["id", "env", "npm", "api", "name", "doc"])
      end)

    all_models =
      data
      |> Enum.reject(fn {_key, value} -> not is_map(value) end)
      |> Enum.flat_map(fn {_key, provider} ->
        models = Map.get(provider, "models", %{})

        models
        |> Enum.map(fn {_model_key, model} ->
          Map.put(model, "provider", provider["id"])
        end)
      end)

    {providers, all_models}
  end

  defp build_config do
    app_config = Application.get_all_env(:llm_models)
    overrides_from_app = Keyword.get(app_config, :overrides, %{})

    overrides = %{
      providers: normalize_overrides(Map.get(overrides_from_app, :providers, [])),
      models: normalize_overrides(Map.get(overrides_from_app, :models, [])),
      exclude: Map.get(overrides_from_app, :exclude, %{})
    }

    [
      config: %{
        compile_embed: false,
        overrides: overrides,
        overrides_module: nil,
        allow: Keyword.get(app_config, :allow, :all),
        deny: Keyword.get(app_config, :deny, %{}),
        prefer: Keyword.get(app_config, :prefer, [])
      }
    ]
  end

  defp normalize_overrides(list) when is_list(list), do: list
  defp normalize_overrides(_), do: []

  defp atomize_keys(list) when is_list(list) do
    Enum.map(list, &atomize_keys/1)
  end

  defp atomize_keys(map) when is_map(map) do
    Map.new(map, fn {k, v} ->
      key = if is_binary(k), do: String.to_atom(k), else: k

      value =
        if key == :provider and is_binary(v) do
          case LLMModels.Normalize.normalize_provider_id(v, unsafe: true) do
            {:ok, atom} -> atom
            _ -> atomize_keys(v)
          end
        else
          atomize_keys(v)
        end

      {key, value}
    end)
  end

  defp atomize_keys(value), do: value

  defp save_final_snapshot(snapshot) do
    @snapshot_path
    |> Path.dirname()
    |> File.mkdir_p!()

    output_data = %{
      providers: snapshot.providers,
      models: Map.values(snapshot.models) |> List.flatten()
    }

    json = Jason.encode!(output_data, pretty: true)
    File.write!(@snapshot_path, json)

    Mix.shell().info("✓ Snapshot written to #{@snapshot_path}")
  end

  defp generate_valid_providers_module(snapshot) do
    provider_atoms =
      snapshot.providers
      |> Enum.map(& &1.id)
      |> Enum.sort()
      |> Enum.uniq()

    module_code = """
    defmodule LLMModels.Generated.ValidProviders do
      @moduledoc \"\"\"
      Auto-generated module containing all valid provider atoms.

      This module is generated by `mix llm_models.pull` to prevent atom leaking.
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

    module_path = "lib/llm_models/generated/valid_providers.ex"
    formatted = Code.format_string!(module_code)
    File.write!(module_path, formatted)

    provider_count = length(provider_atoms)
    Mix.shell().info("✓ Generated valid_providers.ex with #{provider_count} provider atoms")
  end

  defp print_summary(snapshot) do
    provider_count = length(snapshot.providers)
    model_count = Map.values(snapshot.models) |> Enum.map(&length/1) |> Enum.sum()

    Mix.shell().info("")
    Mix.shell().info("Summary:")
    Mix.shell().info("  Providers: #{provider_count}")
    Mix.shell().info("  Models: #{model_count}")
  end
end
