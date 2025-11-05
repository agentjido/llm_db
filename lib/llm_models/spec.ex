defmodule LLMModels.Spec do
  @moduledoc """
  Canonical "provider:model" spec parsing and resolution.

  This module provides functions to parse and resolve model specifications in various formats,
  including "provider:model" strings, tuples, and bare model IDs with provider scope.
  """

  alias LLMModels.{Normalize, Store}
  alias LLMModels.Schema.Model

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

      iex> LLMModels.Spec.parse_provider(:openai)
      {:ok, :openai}

      iex> LLMModels.Spec.parse_provider("google-vertex")
      {:ok, :google_vertex}

      iex> LLMModels.Spec.parse_provider("nonexistent")
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

      iex> LLMModels.Spec.parse_spec("openai:gpt-4")
      {:ok, {:openai, "gpt-4"}}

      iex> LLMModels.Spec.parse_spec("google-vertex:gemini-pro")
      {:ok, {:google_vertex, "gemini-pro"}}

      iex> LLMModels.Spec.parse_spec("gpt-4")
      {:error, :invalid_format}
  """
  @spec parse_spec(String.t()) ::
          {:ok, {atom(), String.t()}}
          | {:error, :invalid_format | :unknown_provider | :bad_provider}
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

      iex> LLMModels.Spec.resolve("openai:gpt-4")
      {:ok, {:openai, "gpt-4", %LLMModels.Schema.Model{}}}

      iex> LLMModels.Spec.resolve({:openai, "gpt-4"})
      {:ok, {:openai, "gpt-4", %LLMModels.Schema.Model{}}}

      iex> LLMModels.Spec.resolve("gpt-4", scope: :openai)
      {:ok, {:openai, "gpt-4", %LLMModels.Schema.Model{}}}

      iex> LLMModels.Spec.resolve("gpt-4")
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

  defp resolve_model(provider, model_id) do
    case Store.snapshot() do
      nil ->
        {:error, :not_found}

      snapshot ->
        key = {provider, model_id}

        canonical_id = Map.get(snapshot.aliases_by_key, key, model_id)
        canonical_key = {provider, canonical_id}

        case Map.get(snapshot.models_by_key, canonical_key) do
          nil -> {:error, :not_found}
          model -> {:ok, {provider, canonical_id, model}}
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
      key = {provider, model_id}

      canonical_id = Map.get(snapshot.aliases_by_key, key, model_id)
      canonical_key = {provider, canonical_id}

      case Map.get(snapshot.models_by_key, canonical_key) do
        nil -> []
        model -> [{provider, canonical_id, model}]
      end
    end)
  end
end
