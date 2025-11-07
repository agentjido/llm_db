defmodule LLMDb do
  @moduledoc """
  Fast, persistent_term-backed LLM model metadata catalog with explicit refresh controls.

  Provides a simple, capability-aware API for querying LLM model metadata.
  All queries are backed by `:persistent_term` for O(1), lock-free access.

  ## Providers

  - `providers/0` - Get all providers as list of Provider structs
  - `provider/1` - Get a specific provider by ID

  ## Models

  - `models/0` - Get all models as list of Model structs
  - `models/1` - Get all models for a provider
  - `model/1` - Parse "provider:model" spec and get model
  - `model/2` - Get a specific model by provider and ID

  ## Selection and Policy

  - `select/1` - Select first model matching capability requirements
  - `candidates/1` - Get all models matching capability requirements
  - `allowed?/1` - Check if a model passes allow/deny filters
  - `capabilities/1` - Get capabilities map for a model

  ## Utilities

  - `parse/1` - Parse a model spec string into {provider, model_id} tuple

  ## Examples

      # Get all providers
      providers = LLMDb.provider()

      # Get a specific provider
      {:ok, provider} = LLMDb.provider(:openai)

      # Get all models for a provider
      models = LLMDb.models(:openai)

      # Get a specific model
      {:ok, model} = LLMDb.model(:openai, "gpt-4o-mini")

      # Parse spec and get model
      {:ok, model} = LLMDb.model("openai:gpt-4o-mini")

      # Access capabilities from model
      {:ok, model} = LLMDb.model(:openai, "gpt-4o-mini")
      model.capabilities.tools.enabled
      #=> true

      # Select a model matching requirements
      {:ok, {:openai, "gpt-4o-mini"}} = LLMDb.select(
        require: [chat: true, tools: true, json_native: true],
        prefer: [:openai, :anthropic]
      )

      # Check if a model is allowed
      true = LLMDb.allowed?({:openai, "gpt-4o-mini"})
  """

  alias LLMDb.{Engine, Model, Packaged, Provider, Runtime, Spec, Store}

  @type provider :: atom()
  @type model_id :: String.t()
  @type model_spec :: {provider(), model_id()} | String.t() | Model.t()

  # Lifecycle functions

  @doc """
  Loads or reloads the LLM model catalog.

  This function loads the packaged snapshot and applies any runtime overrides
  from configuration or the provided options. The catalog is automatically loaded
  on application startup, but this function can be used to manually reload it
  with different options.

  ## Options

  - `:filter` - Runtime filter configuration (see Runtime Filters guide)
    - `:allow` - Allow patterns (e.g., `%{providers: [:openai, :anthropic]}`)
    - `:deny` - Deny patterns (e.g., `%{capabilities: [:vision]}`)
  - Any other options are passed through to the storage layer

  ## Returns

  - `{:ok, snapshot}` - Successfully loaded the catalog
  - `{:error, :no_snapshot}` - No packaged snapshot available
  - `{:error, term}` - Other loading errors

  ## Examples

      # Load with default configuration
      {:ok, _snapshot} = LLMDb.load()

      # Load with custom filters
      LLMDb.load(filter: %{
        allow: %{providers: [:openai, :anthropic]},
        deny: %{capabilities: [:vision]}
      })
  """
  @spec load(keyword()) :: {:ok, map()} | {:error, term()}
  def load(opts \\ []) do
    with {:ok, snapshot} <- load_packaged_snapshot(),
         {:ok, updated_snapshot} <- apply_runtime_overrides(snapshot, opts) do
      Store.put!(updated_snapshot, opts)
      {:ok, updated_snapshot}
    end
  end

  @doc """
  Loads an empty catalog with no providers or models.

  This is used as a fallback when no packaged snapshot is available,
  allowing the application to start successfully. The catalog can
  later be populated via `load/1` once a snapshot is available.

  ## Examples

      LLMDb.load_empty()
      #=> {:ok, %{providers: [], models: %{}, ...}}
  """
  @spec load_empty(keyword()) :: {:ok, map()}
  def load_empty(opts \\ []) do
    {:ok, snapshot} = build_runtime_snapshot([], [])
    Store.put!(snapshot, opts)
    {:ok, snapshot}
  end

  defp load_packaged_snapshot do
    case Packaged.snapshot() do
      nil ->
        {:error, :no_snapshot}

      %{version: 2, providers: nested_providers} = _snapshot ->
        # V2 snapshot with nested providers - need to flatten and build indexes
        {providers, models} = flatten_nested_providers(nested_providers)
        build_runtime_snapshot(providers, models)

      %{providers: providers, models: models} when is_list(providers) and is_list(models) ->
        # V1 snapshot - raw flat lists that need to be indexed
        build_runtime_snapshot(providers, models)

      snapshot when is_map(snapshot) ->
        # Unknown format - try to use as-is
        {:ok, snapshot}
    end
  end

  defp flatten_nested_providers(nested_providers) when is_map(nested_providers) do
    {providers, all_models} =
      Enum.reduce(nested_providers, {[], []}, fn {_provider_id, provider_data},
                                                 {acc_providers, acc_models} ->
        # Extract provider without models key
        provider = Map.delete(provider_data, :models)

        # Get provider ID as string for models
        provider_id_str =
          case provider_data[:id] do
            a when is_atom(a) -> Atom.to_string(a)
            s when is_binary(s) -> s
          end

        # Extract models and ensure they have provider field
        models =
          case Map.get(provider_data, :models) do
            models when is_map(models) ->
              Enum.map(models, fn {_model_id, model_data} ->
                Map.put_new(model_data, :provider, provider_id_str)
              end)

            _ ->
              []
          end

        {[provider | acc_providers], models ++ acc_models}
      end)

    {Enum.reverse(providers), Enum.reverse(all_models)}
  end

  defp build_runtime_snapshot(providers, models) do
    # Build indexes from raw providers/models data
    # This is a lightweight operation that doesn't run the full ETL pipeline
    alias LLMDb.{Config, Index}

    require Logger

    config = Config.get()

    # Convert provider IDs from strings to atoms (JSON stores as strings)
    normalized_providers = normalize_raw_providers(providers)
    base_models = normalize_raw_models(models)

    # Compile default filters with known provider validation
    provider_ids = Enum.map(normalized_providers, & &1.id)

    {filters, unknown: unknown_providers} =
      Config.compile_filters(config.allow, config.deny, provider_ids)

    # Warn on unknown providers in filters
    if unknown_providers != [] do
      provider_ids_set = MapSet.new(provider_ids)

      Logger.warning(
        "llm_db: unknown provider(s) in filter: #{inspect(unknown_providers)}. " <>
          "Known providers: #{inspect(MapSet.to_list(provider_ids_set))}. " <>
          "Check spelling or remove unknown providers from configuration."
      )
    end

    # Apply filters to models
    filtered_models = Engine.apply_filters(base_models, filters)

    # Fail fast if filters eliminate all models
    if filters.allow != :all and filtered_models == [] do
      {:error,
       "llm_db: filters eliminated all models. Check :llm_db filter configuration. " <>
         "allow: #{summarize_filter(config.allow)}, deny: #{summarize_filter(config.deny)}. " <>
         "Use allow: :all to widen filters or remove deny patterns."}
    else
      # Build indexes at load time
      indexes = Index.build(normalized_providers, filtered_models)

      # Build full snapshot with indexes and base_models for runtime filter updates
      snapshot = %{
        providers_by_id: indexes.providers_by_id,
        models_by_key: indexes.models_by_key,
        aliases_by_key: indexes.aliases_by_key,
        providers: normalized_providers,
        models: indexes.models_by_provider,
        base_models: base_models,
        filters: filters,
        prefer: config.prefer,
        meta: %{
          epoch: nil,
          generated_at: DateTime.utc_now() |> DateTime.to_iso8601()
        }
      }

      {:ok, snapshot}
    end
  end

  defp normalize_raw_providers(providers) when is_list(providers) do
    Enum.map(providers, fn provider ->
      case provider do
        %{id: id} when is_binary(id) ->
          # Convert string ID to atom
          # Safe: In production, atoms are pre-generated by mix llm_db.pull
          # In tests, we create atoms on-the-fly (acceptable in test environment)
          Map.put(provider, :id, String.to_atom(id))

        _ ->
          provider
      end
    end)
  end

  defp normalize_raw_models(models) when is_list(models) do
    Enum.map(models, fn model ->
      model
      |> normalize_model_provider()
      |> normalize_model_modalities()
    end)
  end

  defp normalize_model_provider(%{provider: provider} = model) when is_binary(provider) do
    Map.put(model, :provider, String.to_atom(provider))
  end

  defp normalize_model_provider(model), do: model

  defp normalize_model_modalities(%{modalities: modalities} = model) when is_map(modalities) do
    normalized_modalities =
      modalities
      |> Map.update(:input, [], &convert_modality_list/1)
      |> Map.update(:output, [], &convert_modality_list/1)

    Map.put(model, :modalities, normalized_modalities)
  end

  defp normalize_model_modalities(model), do: model

  defp convert_modality_list(list) when is_list(list) do
    Enum.map(list, fn
      str when is_binary(str) -> String.to_atom(str)
      atom when is_atom(atom) -> atom
    end)
  end

  defp convert_modality_list(other), do: other

  defp apply_runtime_overrides(snapshot, opts) do
    case Keyword.get(opts, :runtime_overrides) do
      nil -> {:ok, snapshot}
      overrides -> Runtime.apply(snapshot, overrides)
    end
  end

  @doc false
  @spec snapshot() :: map() | nil
  def snapshot do
    Store.snapshot()
  end

  @doc false
  @spec epoch() :: non_neg_integer()
  def epoch do
    Store.epoch()
  end

  # Listing functions

  @doc """
  Gets all providers from the catalog.

  Returns list of all Provider structs, sorted by ID.

  ## Examples

      providers = LLMDb.providers()
      #=> [%LLMDb.Provider{id: :anthropic, ...}, ...]

  """
  @spec providers() :: [Provider.t()]
  def providers do
    provider()
  end

  @doc """
  Gets all models from the catalog.

  Returns all models as Model structs across all providers.

  ## Examples

      models = LLMDb.models()
      #=> [%LLMDb.Model{}, ...]

  """
  @spec models() :: [Model.t()]
  def models do
    model()
  end

  @doc """
  Gets all models for a specific provider.

  ## Parameters

  - `provider` - Provider atom (e.g., `:openai`, `:anthropic`)

  ## Returns

  List of Model structs for the provider, or empty list if provider not found.

  ## Examples

      models = LLMDb.models(:openai)
      #=> [%LLMDb.Model{id: "gpt-4o", ...}, ...]

  """
  @spec models(provider()) :: [Model.t()]
  def models(provider_id) when is_atom(provider_id) do
    case snapshot() do
      nil ->
        []

      %{models: models_by_provider} ->
        models_by_provider
        |> Map.get(provider_id, [])
        |> Enum.map(&Model.new!/1)

      _ ->
        []
    end
  end

  # Lookup functions

  @doc """
  Gets provider(s) from the catalog.

  ## Arity 0 - Returns all providers

  Returns list of all Provider structs, sorted by ID.

  ## Examples

      providers = LLMDb.provider()
      #=> [%LLMDb.Provider{id: :anthropic, ...}, ...]

  """
  @spec provider() :: [Provider.t()]
  def provider do
    case snapshot() do
      nil ->
        []

      %{providers_by_id: providers_map} ->
        providers_map
        |> Map.values()
        |> Enum.map(&Provider.new!/1)
        |> Enum.sort_by(& &1.id)

      _ ->
        []
    end
  end

  @doc """
  Gets a specific provider by ID.

  ## Parameters

  - `id` - Provider atom (e.g., `:openai`, `:anthropic`)

  ## Returns

  - `{:ok, provider}` - Provider struct
  - `:error` - Provider not found

  ## Examples

      {:ok, provider} = LLMDb.provider(:openai)
      provider.name
      #=> "OpenAI"
  """
  @spec provider(provider()) :: {:ok, Provider.t()} | :error
  def provider(id) when is_atom(id) do
    case snapshot() do
      nil ->
        :error

      %{providers_by_id: providers} ->
        case Map.fetch(providers, id) do
          {:ok, provider_map} -> {:ok, Provider.new!(provider_map)}
          :error -> :error
        end

      _ ->
        :error
    end
  end

  @doc """
  Gets model(s) from the catalog.

  ## Arity 0 - Returns all models

  Returns all models as Model structs across all providers.

  ## Examples

      models = LLMDb.model()
      #=> [%LLMDb.Model{}, ...]

  """
  @spec model() :: [Model.t()]
  def model do
    case snapshot() do
      nil ->
        []

      %{models: models_by_provider} ->
        models_by_provider
        |> Map.values()
        |> List.flatten()
        |> Enum.map(&Model.new!/1)

      _ ->
        []
    end
  end

  @doc """
  Gets a specific model by parsing a spec string.

  Parses "provider:model" spec and returns the Model struct.

  ## Parameters

  - `spec` - Model specification string (e.g., `"openai:gpt-4o-mini"`)

  ## Returns

  - `{:ok, model}` when spec is successfully parsed
  - `{:error, reason}` when spec parsing fails

  ## Examples

      {:ok, model} = LLMDb.model("openai:gpt-4o-mini")
      model.id
      #=> "gpt-4o-mini"
  """
  @spec model(String.t()) :: {:ok, Model.t()} | {:error, atom()}
  def model(spec) when is_binary(spec) do
    case parse_spec(spec) do
      {:ok, {provider, model_id}} -> model(provider, model_id)
      {:error, _} = error -> error
    end
  end

  @doc """
  Gets all models for a specific provider.

  @doc \"""
  Gets a specific model by provider and model ID.

  Handles alias resolution automatically.

  ## Parameters

  - `provider` - Provider atom
  - `model_id` - Model identifier string

  ## Returns

  - `{:ok, model}` - Model struct
  - `{:error, :not_found}` - Model not found

  ## Examples

      {:ok, model} = LLMDb.model(:openai, "gpt-4o-mini")
      {:ok, model} = LLMDb.model(:openai, "gpt-4-mini")  # alias
  """
  @spec model(provider(), model_id()) :: {:ok, Model.t()} | {:error, :not_found}
  def model(provider, model_id) when is_atom(provider) and is_binary(model_id) do
    case snapshot() do
      nil ->
        {:error, :not_found}

      snapshot when is_map(snapshot) ->
        key = {provider, model_id}

        canonical_id = Map.get(snapshot.aliases_by_key, key, model_id)
        canonical_key = {provider, canonical_id}

        case Map.fetch(snapshot.models_by_key, canonical_key) do
          {:ok, model_map} -> {:ok, Model.new!(model_map)}
          :error -> {:error, :not_found}
        end
    end
  end

  @doc """
  Checks if a model specification passes allow/deny filters.

  Deny patterns always win over allow patterns.

  ## Parameters

  - `spec` - Either `{provider, model_id}` tuple, `"provider:model"` string, or `%Model{}` struct

  ## Returns

  Boolean indicating if the model is allowed.

  ## Examples

      true = LLMDb.allowed?({:openai, "gpt-4o-mini"})
      false = LLMDb.allowed?({:openai, "gpt-5-pro"})  # if denied
      
      {:ok, model} = LLMDb.model("openai:gpt-4o-mini")
      true = LLMDb.allowed?(model)
  """
  @spec allowed?(model_spec()) :: boolean()
  def allowed?(spec)

  def allowed?(%Model{provider: provider, id: id}) do
    allowed?({provider, id})
  end

  def allowed?({provider, model_id}) when is_atom(provider) and is_binary(model_id) do
    case snapshot() do
      nil ->
        false

      %{filters: %{allow: allow, deny: deny}, aliases_by_key: aliases} ->
        # Resolve aliases to canonical model ID
        canonical_id = Map.get(aliases, {provider, model_id}, model_id)

        deny_patterns = Map.get(deny, provider, [])
        denied? = matches_patterns?(canonical_id, deny_patterns)

        if denied? do
          false
        else
          case allow do
            :all ->
              true

            allow_map when is_map(allow_map) ->
              allow_patterns = Map.get(allow_map, provider, [])

              if map_size(allow_map) > 0 and allow_patterns == [] do
                false
              else
                allow_patterns == [] or matches_patterns?(canonical_id, allow_patterns)
              end
          end
        end

      _ ->
        false
    end
  end

  def allowed?(spec) when is_binary(spec) do
    case Spec.parse_spec(spec) do
      {:ok, {provider, model_id}} -> allowed?({provider, model_id})
      _ -> false
    end
  end

  # Selection

  @doc """
  Selects the first allowed model matching capability requirements.

  Iterates through providers in preference order (or all providers) and
  returns the first model matching the capability filters.

  ## Options

  - `:require` - Keyword list of required capabilities (e.g., `[tools: true, json_native: true]`)
  - `:forbid` - Keyword list of forbidden capabilities
  - `:prefer` - List of provider atoms in preference order (e.g., `[:openai, :anthropic]`)
  - `:scope` - Either `:all` (default) or a specific provider atom

  ## Returns

  - `{:ok, {provider, model_id}}` - First matching model
  - `{:error, :no_match}` - No model matches the criteria

  ## Examples

      {:ok, {provider, model_id}} = LLMDb.select(
        require: [chat: true, tools: true],
        prefer: [:openai, :anthropic]
      )

      {:ok, {provider, model_id}} = LLMDb.select(
        require: [json_native: true],
        forbid: [streaming_tool_calls: true],
        scope: :openai
      )
  """
  @spec select(keyword()) :: {:ok, {provider(), model_id()}} | {:error, :no_match}
  def select(opts \\ []) do
    require_kw = Keyword.get(opts, :require, [])
    forbid_kw = Keyword.get(opts, :forbid, [])
    scope = Keyword.get(opts, :scope, :all)

    # Use snapshot.prefer as default if :prefer not explicitly provided
    prefer =
      case Keyword.fetch(opts, :prefer) do
        :error ->
          case snapshot() do
            %{prefer: p} when is_list(p) -> p
            _ -> []
          end

        {:ok, p} ->
          p
      end

    providers =
      case scope do
        :all ->
          all_providers = provider() |> Enum.map(& &1.id)

          if prefer != [] do
            prefer ++ (all_providers -- prefer)
          else
            all_providers
          end

        provider when is_atom(provider) ->
          [provider]
      end

    find_first_match(providers, require_kw, forbid_kw)
  end

  @doc """
  Gets all allowed models matching capability requirements.

  Returns all models that match the capability filters in preference order.
  Similar to `select/1` but returns all matches instead of just the first.

  ## Options

  - `:require` - Keyword list of required capabilities (e.g., `[tools: true, json_native: true]`)
  - `:forbid` - Keyword list of forbidden capabilities
  - `:prefer` - List of provider atoms in preference order (e.g., `[:openai, :anthropic]`)
  - `:scope` - Either `:all` (default) or a specific provider atom

  ## Returns

  List of `{provider, model_id}` tuples matching the criteria, in preference order.

  ## Examples

      # Get all models with chat and tools
      candidates = LLMDb.candidates(
        require: [chat: true, tools: true],
        prefer: [:openai, :anthropic]
      )
      #=> [{:openai, "gpt-4o"}, {:openai, "gpt-4o-mini"}, {:anthropic, "claude-3-5-sonnet-20241022"}, ...]

      # Get all OpenAI models with JSON support
      candidates = LLMDb.candidates(
        require: [json_native: true],
        scope: :openai
      )
      #=> [{:openai, "gpt-4o"}, {:openai, "gpt-4o-mini"}, ...]
  """
  @spec candidates(keyword()) :: [{provider(), model_id()}]
  def candidates(opts \\ []) do
    require_kw = Keyword.get(opts, :require, [])
    forbid_kw = Keyword.get(opts, :forbid, [])
    scope = Keyword.get(opts, :scope, :all)

    # Use snapshot.prefer as default if :prefer not explicitly provided
    prefer =
      case Keyword.fetch(opts, :prefer) do
        :error ->
          case snapshot() do
            %{prefer: p} when is_list(p) -> p
            _ -> []
          end

        {:ok, p} ->
          p
      end

    providers =
      case scope do
        :all ->
          all_providers = provider() |> Enum.map(& &1.id)

          if prefer != [] do
            prefer ++ (all_providers -- prefer)
          else
            all_providers
          end

        provider when is_atom(provider) ->
          [provider]
      end

    find_all_matches(providers, require_kw, forbid_kw)
  end

  @doc """
  Gets capabilities for a model spec.

  Returns capabilities map or nil if model not found.

  ## Parameters

  - `spec` - Either `{provider, model_id}` tuple, `"provider:model"` string, or `%Model{}` struct

  ## Examples

      caps = LLMDb.capabilities({:openai, "gpt-4o-mini"})
      #=> %{chat: true, tools: %{enabled: true, ...}, ...}

      caps = LLMDb.capabilities("openai:gpt-4o-mini")
      #=> %{chat: true, tools: %{enabled: true, ...}, ...}

      {:ok, model} = LLMDb.model("openai:gpt-4o-mini")
      caps = LLMDb.capabilities(model)
      #=> %{chat: true, tools: %{enabled: true, ...}, ...}

      nil = LLMDb.capabilities({:openai, "nonexistent"})
  """
  @spec capabilities(model_spec()) :: map() | nil
  def capabilities(%Model{capabilities: caps}) do
    caps
  end

  def capabilities({provider, model_id}) when is_atom(provider) and is_binary(model_id) do
    case model(provider, model_id) do
      {:ok, m} -> Map.get(m, :capabilities)
      _ -> nil
    end
  end

  def capabilities(spec) when is_binary(spec) do
    case Spec.parse_spec(spec) do
      {:ok, {p, id}} -> capabilities({p, id})
      _ -> nil
    end
  end

  # Utilities

  @doc """
  Parses a model spec string into a {provider, model_id} tuple.

  Accepts either "provider:model" format or a {provider, model_id} tuple.

  ## Parameters

  - `spec` - Either a string like `"openai:gpt-4o-mini"` or tuple like `{:openai, "gpt-4o-mini"}`

  ## Returns

  - `{:ok, {provider, model_id}}` - Successfully parsed spec
  - `{:error, term}` - Invalid spec format

  ## Examples

      {:ok, {:openai, "gpt-4o-mini"}} = LLMDb.parse("openai:gpt-4o-mini")
      {:ok, {:anthropic, "claude-3-5-sonnet-20241022"}} = LLMDb.parse("anthropic:claude-3-5-sonnet-20241022")
      {:ok, {:openai, "gpt-4o"}} = LLMDb.parse({:openai, "gpt-4o"})
      {:error, _} = LLMDb.parse("invalid")
  """
  @spec parse(String.t() | {provider(), model_id()}) ::
          {:ok, {provider(), model_id()}} | {:error, term()}
  def parse(spec), do: Spec.parse_spec(spec)

  # Private helpers

  defp parse_spec(spec), do: Spec.parse_spec(spec)

  defp matches_require?(_model, []), do: true

  defp matches_require?(model, require_kw) do
    caps = Map.get(model, :capabilities) || %{}

    Enum.all?(require_kw, fn {key, value} ->
      check_capability(caps, key, value)
    end)
  end

  defp matches_forbid?(_model, []), do: false

  defp matches_forbid?(model, forbid_kw) do
    caps = Map.get(model, :capabilities) || %{}

    Enum.any?(forbid_kw, fn {key, value} ->
      check_capability(caps, key, value)
    end)
  end

  defp check_capability(caps, key, expected_value) do
    case key do
      :chat -> Map.get(caps, :chat) == expected_value
      :embeddings -> Map.get(caps, :embeddings) == expected_value
      :reasoning -> get_in(caps, [:reasoning, :enabled]) == expected_value
      :tools -> get_in(caps, [:tools, :enabled]) == expected_value
      :tools_streaming -> get_in(caps, [:tools, :streaming]) == expected_value
      :tools_strict -> get_in(caps, [:tools, :strict]) == expected_value
      :tools_parallel -> get_in(caps, [:tools, :parallel]) == expected_value
      :json_native -> get_in(caps, [:json, :native]) == expected_value
      :json_schema -> get_in(caps, [:json, :schema]) == expected_value
      :json_strict -> get_in(caps, [:json, :strict]) == expected_value
      :streaming_text -> get_in(caps, [:streaming, :text]) == expected_value
      :streaming_tool_calls -> get_in(caps, [:streaming, :tool_calls]) == expected_value
      _ -> false
    end
  end

  defp matches_patterns?(_model_id, []), do: false

  defp matches_patterns?(model_id, patterns) when is_binary(model_id) do
    Enum.any?(patterns, fn
      %Regex{} = pattern -> Regex.match?(pattern, model_id)
      pattern when is_binary(pattern) -> model_id == pattern
    end)
  end

  defp find_first_match([], _require_kw, _forbid_kw), do: {:error, :no_match}

  defp find_first_match([provider | rest], require_kw, forbid_kw) do
    models_list =
      models(provider)
      |> Enum.filter(&matches_require?(&1, require_kw))
      |> Enum.reject(&matches_forbid?(&1, forbid_kw))
      |> Enum.filter(&allowed?({provider, &1.id}))

    case models_list do
      [] -> find_first_match(rest, require_kw, forbid_kw)
      [model | _] -> {:ok, {provider, model.id}}
    end
  end

  defp find_all_matches(providers, require_kw, forbid_kw) do
    Enum.flat_map(providers, fn provider ->
      models(provider)
      |> Enum.filter(&matches_require?(&1, require_kw))
      |> Enum.reject(&matches_forbid?(&1, forbid_kw))
      |> Enum.filter(&allowed?({provider, &1.id}))
      |> Enum.map(&{provider, &1.id})
    end)
  end

  defp summarize_filter(:all), do: ":all"

  defp summarize_filter(filter) when is_map(filter) and map_size(filter) == 0 do
    "%{}"
  end

  defp summarize_filter(filter) when is_map(filter) do
    # Summarize large filter maps to avoid huge error messages
    keys = Map.keys(filter) |> Enum.take(5)

    if map_size(filter) > 5 do
      "#{inspect(keys)} ... (#{map_size(filter)} providers total)"
    else
      inspect(filter)
    end
  end

  defp summarize_filter(other), do: inspect(other)
end
