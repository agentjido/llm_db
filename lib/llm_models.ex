defmodule LLMModels do
  @moduledoc """
  Fast, persistent_term-backed LLM model metadata catalog with explicit refresh controls.

  Provides a simple, capability-aware API for querying LLM model metadata.
  All queries are backed by `:persistent_term` for O(1), lock-free access.

  ## Lifecycle

  - `load/1` - Build catalog from sources and publish to persistent_term
  - `reload/0` - Re-run load with last-known options

  ## Providers

  - `provider/0` - Get all providers as Provider structs
  - `provider/1` - Get a specific provider by ID

  ## Models

  - `model/0` - Get all models as Model structs
  - `model/1` - Parse "provider:model" spec and get model
  - `model/2` - Get a specific model by provider and ID
  - `models/1` - Get all models for a provider

  ## Selection and Policy

  - `select/1` - Select a model matching capability requirements
  - `allowed?/1` - Check if a model passes allow/deny filters

  ## Examples

      # Get all providers
      providers = LLMModels.provider()

      # Get a specific provider
      {:ok, provider} = LLMModels.provider(:openai)

      # Get all models for a provider
      models = LLMModels.models(:openai)

      # Get a specific model
      {:ok, model} = LLMModels.model(:openai, "gpt-4o-mini")

      # Parse spec and get model
      {:ok, model} = LLMModels.model("openai:gpt-4o-mini")

      # Access capabilities from model
      {:ok, model} = LLMModels.model(:openai, "gpt-4o-mini")
      model.capabilities.tools.enabled
      #=> true

      # Select a model matching requirements
      {:ok, {:openai, "gpt-4o-mini"}} = LLMModels.select(
        require: [chat: true, tools: true, json_native: true],
        prefer: [:openai, :anthropic]
      )

      # Check if a model is allowed
      true = LLMModels.allowed?({:openai, "gpt-4o-mini"})
  """

  alias LLMModels.{Engine, Store, Spec, Provider, Model}

  @type provider :: atom()
  @type model_id :: String.t()
  @type model_spec :: {provider(), model_id()} | String.t()

  # Lifecycle functions

  @doc """
  Loads the model catalog from all sources and publishes to persistent_term.

  Runs the ETL pipeline to ingest, normalize, validate, merge, enrich, filter,
  and index model metadata from packaged snapshot, config overrides, and
  behaviour overrides.

  ## Options

  - `:config` - Config map override (optional)

  ## Returns

  - `{:ok, snapshot}` - Success with the generated snapshot
  - `{:error, term}` - Error from engine or validation

  ## Examples

      {:ok, snapshot} = LLMModels.load()
      {:ok, snapshot} = LLMModels.load(config: custom_config)
  """
  @spec load(keyword()) :: {:ok, map()} | {:error, term()}
  def load(opts \\ []) do
    with {:ok, snapshot} <- Engine.run(opts) do
      Store.put!(snapshot, opts)
      {:ok, snapshot}
    end
  end

  @doc """
  Reloads the catalog using the last-known options.

  Retrieves the options from the last successful `load/1` call and
  re-runs the ETL pipeline with those options.

  ## Returns

  - `:ok` - Success
  - `{:error, term}` - Error from engine or validation

  ## Examples

      :ok = LLMModels.reload()
  """
  @spec reload() :: :ok | {:error, term()}
  def reload do
    last_opts = Store.last_opts()

    case load(last_opts) do
      {:ok, _snapshot} -> :ok
      {:error, reason} -> {:error, reason}
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

  # Lookup and listing functions

  @doc """
  Gets provider(s) from the catalog.

  ## Arity 0 - Returns all providers

  Returns list of all Provider structs, sorted by ID.

  ## Examples

      providers = LLMModels.provider()
      #=> [%LLMModels.Provider{id: :anthropic, ...}, ...]

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

      {:ok, provider} = LLMModels.provider(:openai)
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

      models = LLMModels.model()
      #=> [%LLMModels.Model{}, ...]

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

      {:ok, model} = LLMModels.model("openai:gpt-4o-mini")
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

  Returns list of Model structs for the specified provider.

  ## Parameters

  - `provider` - Provider atom (e.g., `:openai`)

  ## Returns

  List of Model structs for the provider.

  ## Examples

      models = LLMModels.models(:openai)
      #=> [%LLMModels.Model{id: "gpt-4o", ...}, ...]
  """
  @spec models(provider()) :: [Model.t()]
  def models(provider) when is_atom(provider) do
    case snapshot() do
      nil ->
        []

      %{models: models_by_provider} ->
        models_by_provider
        |> Map.get(provider, [])
        |> Enum.map(&Model.new!/1)

      _ ->
        []
    end
  end

  @doc """
  Gets a specific model by provider and model ID.

  Handles alias resolution automatically.

  ## Parameters

  - `provider` - Provider atom
  - `model_id` - Model identifier string

  ## Returns

  - `{:ok, model}` - Model struct
  - `{:error, :not_found}` - Model not found

  ## Examples

      {:ok, model} = LLMModels.model(:openai, "gpt-4o-mini")
      {:ok, model} = LLMModels.model(:openai, "gpt-4-mini")  # alias
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

  - `spec` - Either `{provider, model_id}` tuple or `"provider:model"` string

  ## Returns

  Boolean indicating if the model is allowed.

  ## Examples

      true = LLMModels.allowed?({:openai, "gpt-4o-mini"})
      false = LLMModels.allowed?({:openai, "gpt-5-pro"})  # if denied
  """
  @spec allowed?(model_spec()) :: boolean()
  def allowed?(spec)

  def allowed?({provider, model_id}) when is_atom(provider) and is_binary(model_id) do
    case snapshot() do
      nil ->
        false

      %{filters: %{allow: allow, deny: deny}} ->
        deny_patterns = Map.get(deny, provider, [])
        denied? = matches_patterns?(model_id, deny_patterns)

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
                allow_patterns == [] or matches_patterns?(model_id, allow_patterns)
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

      {:ok, {provider, model_id}} = LLMModels.select(
        require: [chat: true, tools: true],
        prefer: [:openai, :anthropic]
      )

      {:ok, {provider, model_id}} = LLMModels.select(
        require: [json_native: true],
        forbid: [streaming_tool_calls: true],
        scope: :openai
      )
  """
  @spec select(keyword()) :: {:ok, {provider(), model_id()}} | {:error, :no_match}
  def select(opts \\ []) do
    require_kw = Keyword.get(opts, :require, [])
    forbid_kw = Keyword.get(opts, :forbid, [])
    prefer = Keyword.get(opts, :prefer, [])
    scope = Keyword.get(opts, :scope, :all)

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

  # Backward-compatibility wrappers (old API)

  @doc """
  Returns list of provider atoms.

  **Deprecated:** Use `provider/0` for Provider structs.

  ## Examples

      providers = LLMModels.list_providers()
      #=> [:openai, :anthropic, ...]
  """
  @spec list_providers() :: [provider()]
  def list_providers do
    provider() |> Enum.map(& &1.id)
  end

  @doc """
  Gets a provider by ID.

  **Deprecated:** Use `provider/1`.

  ## Examples

      {:ok, provider} = LLMModels.get_provider(:openai)
      :error = LLMModels.get_provider(:nonexistent)
  """
  @spec get_provider(provider()) :: {:ok, Provider.t()} | :error
  def get_provider(id) when is_atom(id), do: provider(id)

  @doc """
  Lists models for a provider.

  **Deprecated:** Use `models/1` for Model structs.

  ## Examples

      models = LLMModels.list_models(:openai)
      #=> [%LLMModels.Model{id: "gpt-4o", ...}, ...]
  """
  @spec list_models(provider()) :: [Model.t()]
  def list_models(provider) when is_atom(provider) do
    models(provider)
  end

  @doc """
  Lists models for a provider with optional capability filtering.

  **Deprecated:** Use `models/1` with `Enum.filter` or `select/1`.

  ## Options

  - `:require` - Keyword list of required capabilities (e.g., `[tools: true, json_native: true]`)
  - `:forbid` - Keyword list of forbidden capabilities

  ## Examples

      models = LLMModels.list_models(:openai, require: [chat: true, tools: true])
      #=> [%LLMModels.Model{id: "gpt-4o", ...}, ...]
  """
  @spec list_models(provider(), keyword()) :: [Model.t()]
  def list_models(provider, opts) when is_atom(provider) and is_list(opts) do
    require_kw = Keyword.get(opts, :require, [])
    forbid_kw = Keyword.get(opts, :forbid, [])

    models(provider)
    |> Enum.filter(&matches_require?(&1, require_kw))
    |> Enum.reject(&matches_forbid?(&1, forbid_kw))
  end

  @doc """
  Gets a model by provider and ID.

  **Deprecated:** Use `model/2`.

  ## Examples

      {:ok, model} = LLMModels.get_model(:openai, "gpt-4o-mini")
      :error = LLMModels.get_model(:openai, "nonexistent")
  """
  @spec get_model(provider(), model_id()) :: {:ok, Model.t()} | :error
  def get_model(provider, model_id) when is_atom(provider) and is_binary(model_id) do
    case model(provider, model_id) do
      {:ok, m} -> {:ok, m}
      {:error, :not_found} -> :error
    end
  end

  @doc """
  Gets capabilities for a model spec.

  Returns capabilities map or nil if model not found.

  ## Parameters

  - `spec` - Either `{provider, model_id}` tuple or `"provider:model"` string

  ## Examples

      caps = LLMModels.capabilities({:openai, "gpt-4o-mini"})
      #=> %{chat: true, tools: %{enabled: true, ...}, ...}

      caps = LLMModels.capabilities("openai:gpt-4o-mini")
      #=> %{chat: true, tools: %{enabled: true, ...}, ...}

      nil = LLMModels.capabilities({:openai, "nonexistent"})
  """
  @spec capabilities({provider(), model_id()} | String.t()) :: map() | nil
  def capabilities({provider, model_id}) when is_atom(provider) and is_binary(model_id) do
    case model(provider, model_id) do
      {:ok, m} -> Map.get(m, :capabilities)
      _ -> nil
    end
  end

  def capabilities(spec) when is_binary(spec) do
    with {:ok, {p, id}} <- Spec.parse_spec(spec) do
      capabilities({p, id})
    else
      _ -> nil
    end
  end

  # Spec parsing (internal use only)

  @doc false
  @spec parse_provider(atom() | binary()) ::
          {:ok, provider()} | {:error, :unknown_provider | :bad_provider}
  defdelegate parse_provider(input), to: Spec

  @doc false
  @spec parse_spec(String.t()) ::
          {:ok, {provider(), model_id()}}
          | {:error, :invalid_format | :unknown_provider | :bad_provider}
  defdelegate parse_spec(spec), to: Spec

  @doc false
  @spec resolve(model_spec(), keyword()) ::
          {:ok, {provider(), model_id(), map()}} | {:error, term()}
  defdelegate resolve(input, opts \\ []), to: Spec

  # Private helpers

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
end
