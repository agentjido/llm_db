defmodule LLMDb.Spec do
  @moduledoc """
  Canonical "provider:model" spec parsing and resolution.

  This module provides functions to parse and resolve model specifications in various formats,
  including "provider:model" strings, tuples, and bare model IDs with provider scope.

  ## Amazon Bedrock Inference Profiles

  For Amazon Bedrock models, inference profile IDs with region prefixes (us., eu., ap., ca., global.)
  are supported. The region prefix is stripped for catalog lookup but preserved in the returned
  model ID. For example:

      iex> LLMDb.Spec.resolve("bedrock:us.anthropic.claude-opus-4-1-20250805-v1:0")
      {:ok, {:bedrock, "us.anthropic.claude-opus-4-1-20250805-v1:0", %LLMDb.Schema.Model{}}}

  The lookup uses "anthropic.claude-opus-4-1-20250805-v1:0" to find metadata, but the returned
  model ID retains the "us." prefix for API routing purposes.
  """

  alias LLMDb.{Normalize, Store}
  alias LLMDb.Schema.Model

  # Valid Bedrock inference profile region prefixes
  @bedrock_prefixes ~w(us. eu. ap. ca. global.)

  @doc """
  Parses and validates a provider identifier.

  Accepts atom or binary input, normalizes to atom, and verifies the provider
  exists in the current catalog.

  ## Parameters

  - `input` - Provider identifier as atom or binary

  ## Returns

  - `{:ok, atom}` - Normalized provider atom if valid and exists in catalog
  - `{:error, :unknown_provider}` - Provider not found in catalog
  - `{:error, :bad_provider}` - Invalid provider format

  ## Examples

      iex> LLMDb.Spec.parse_provider(:openai)
      {:ok, :openai}

      iex> LLMDb.Spec.parse_provider("google-vertex")
      {:ok, :google_vertex}

      iex> LLMDb.Spec.parse_provider("nonexistent")
      {:error, :unknown_provider}
  """
  @spec parse_provider(atom() | binary()) ::
          {:ok, atom()} | {:error, :unknown_provider | :bad_provider}
  def parse_provider(input) do
    with {:ok, provider_atom} <- Normalize.normalize_provider_id(input),
         {:ok, _} <- verify_provider_exists(provider_atom) do
      {:ok, provider_atom}
    else
      {:error, :bad_provider} -> {:error, :bad_provider}
      {:error, :unknown_provider} -> {:error, :unknown_provider}
    end
  end

  @doc """
  Parses a "provider:model" specification string.

  Splits the spec at the first ":" and validates the provider exists in the catalog.
  Model IDs may contain ":" characters, so only the first ":" is used as delimiter.

  ## Parameters

  - `spec` - String in "provider:model" format

  ## Returns

  - `{:ok, {provider_atom, model_id}}` - Parsed and normalized spec
  - `{:error, :invalid_format}` - No ":" found in spec
  - `{:error, :unknown_provider}` - Provider not found in catalog
  - `{:error, :bad_provider}` - Invalid provider format

  ## Examples

      iex> LLMDb.Spec.parse_spec("openai:gpt-4")
      {:ok, {:openai, "gpt-4"}}

      iex> LLMDb.Spec.parse_spec("google-vertex:gemini-pro")
      {:ok, {:google_vertex, "gemini-pro"}}

      iex> LLMDb.Spec.parse_spec("gpt-4")
      {:error, :invalid_format}
  """
  @spec parse_spec(String.t() | {atom(), String.t()}) ::
          {:ok, {atom(), String.t()}}
          | {:error, :invalid_format | :unknown_provider | :bad_provider}
  def parse_spec({provider, model_id}) when is_atom(provider) and is_binary(model_id) do
    {:ok, {provider, model_id}}
  end

  def parse_spec(spec) when is_binary(spec) do
    case String.split(spec, ":", parts: 2) do
      [provider_str, model_id] ->
        with {:ok, provider_atom} <- parse_provider(provider_str) do
          {:ok, {provider_atom, String.trim(model_id)}}
        end

      _ ->
        {:error, :invalid_format}
    end
  end

  @doc """
  Resolves a model specification to a canonical model record.

  Accepts multiple input formats:
  - "provider:model" string
  - {provider, model_id} tuple
  - Bare "model" string with opts[:scope] = provider_atom

  Handles alias resolution and validates the model exists in the catalog.

  ## Parameters

  - `input` - Model specification in one of the supported formats
  - `opts` - Keyword list with optional `:scope` for bare model resolution

  ## Returns

  - `{:ok, {provider, canonical_id, Model.t()}}` - Resolved model
  - `{:error, :not_found}` - Model doesn't exist
  - `{:error, :ambiguous}` - Bare model ID exists under multiple providers without scope
  - `{:error, :invalid_format}` - Malformed input
  - `{:error, term}` - Other parsing errors

  ## Examples

      iex> LLMDb.Spec.resolve("openai:gpt-4")
      {:ok, {:openai, "gpt-4", %LLMDb.Schema.Model{}}}

      iex> LLMDb.Spec.resolve({:openai, "gpt-4"})
      {:ok, {:openai, "gpt-4", %LLMDb.Schema.Model{}}}

      iex> LLMDb.Spec.resolve("gpt-4", scope: :openai)
      {:ok, {:openai, "gpt-4", %LLMDb.Schema.Model{}}}

      iex> LLMDb.Spec.resolve("gpt-4")
      {:error, :ambiguous}
  """
  @spec resolve(String.t() | {atom(), String.t()}, keyword()) ::
          {:ok, {atom(), String.t(), Model.t()}} | {:error, term()}
  def resolve(input, opts \\ [])

  def resolve(spec, opts) when is_binary(spec) do
    case String.contains?(spec, ":") do
      true ->
        with {:ok, {provider, model_id}} <- parse_spec(spec) do
          resolve_model(provider, model_id)
        end

      false ->
        case Keyword.get(opts, :scope) do
          nil -> resolve_bare_model(spec)
          scope -> resolve_model(scope, spec)
        end
    end
  end

  def resolve({provider, model_id}, _opts) when is_atom(provider) and is_binary(model_id) do
    resolve_model(provider, model_id)
  end

  def resolve(_, _), do: {:error, :invalid_format}

  # Private helpers

  defp verify_provider_exists(provider_atom) do
    case Store.snapshot() do
      %{providers_by_id: providers} when is_map(providers) ->
        if Map.has_key?(providers, provider_atom) do
          {:ok, provider_atom}
        else
          {:error, :unknown_provider}
        end

      _ ->
        {:error, :unknown_provider}
    end
  end

  # For Bedrock inference profiles, splits model_id into {base_id, prefix} where
  # base_id is used for catalog lookup and prefix is preserved for the returned ID.
  # For other providers or non-prefixed Bedrock IDs, returns {model_id, nil}.
  defp lookup_id_and_prefix(provider, model_id) do
    if provider == :bedrock do
      case Enum.find_value(@bedrock_prefixes, fn prefix ->
             if String.starts_with?(model_id, prefix),
               do: {prefix, String.replace_prefix(model_id, prefix, "")}
           end) do
        nil -> {model_id, nil}
        {prefix, base_id} -> {base_id, prefix}
      end
    else
      {model_id, nil}
    end
  end

  defp resolve_model(provider, model_id) do
    case Store.snapshot() do
      nil ->
        {:error, :not_found}

      snapshot ->
        {lookup_id, prefix} = lookup_id_and_prefix(provider, model_id)

        key = {provider, lookup_id}
        canonical_base_id = Map.get(snapshot.aliases_by_key, key, lookup_id)
        canonical_key = {provider, canonical_base_id}

        case Map.get(snapshot.models_by_key, canonical_key) do
          nil ->
            {:error, :not_found}

          model ->
            returned_id =
              case prefix do
                nil -> canonical_base_id
                p -> p <> canonical_base_id
              end

            {:ok, {provider, returned_id, model}}
        end
    end
  end

  defp resolve_bare_model(model_id) do
    case Store.snapshot() do
      nil ->
        {:error, :not_found}

      snapshot ->
        matches = find_all_matches(snapshot, model_id)

        case matches do
          [] -> {:error, :not_found}
          [{provider, canonical_id, model}] -> {:ok, {provider, canonical_id, model}}
          [_ | _] -> {:error, :ambiguous}
        end
    end
  end

  defp find_all_matches(snapshot, model_id) do
    providers = Map.keys(snapshot.providers_by_id)

    Enum.flat_map(providers, fn provider ->
      {lookup_id, prefix} = lookup_id_and_prefix(provider, model_id)

      key = {provider, lookup_id}
      canonical_base_id = Map.get(snapshot.aliases_by_key, key, lookup_id)
      canonical_key = {provider, canonical_base_id}

      case Map.get(snapshot.models_by_key, canonical_key) do
        nil ->
          []

        model ->
          returned_id =
            case prefix do
              nil -> canonical_base_id
              p -> p <> canonical_base_id
            end

          [{provider, returned_id, model}]
      end
    end)
  end
end
