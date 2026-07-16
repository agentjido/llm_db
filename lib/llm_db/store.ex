defmodule LLMDB.Store do
  @moduledoc """
  Manages persistent_term storage for LLM model snapshots with atomic swaps.

  Uses `:persistent_term` for fast, concurrent reads with atomic updates tracked by monotonic epochs.

  This module is a compatibility facade over the internal catalog boundary.
  Consumers should use `LLMDB` query and load functions. Raw store access has
  no backwards-compatibility guarantee and can be removed no earlier than the
  next major release.
  """

  alias LLMDB.{Catalog, Model, Provider}

  @doc """
  Reads the full store from persistent_term.

  ## Returns

  Map with `:snapshot`, `:epoch`, and `:opts` keys, or `nil` if not set.
  """
  @spec get() :: map() | nil
  defdelegate get(), to: Catalog

  @doc """
  Returns the snapshot portion from the store.

  ## Returns

  The snapshot map or `nil` if not set.
  """
  @spec snapshot() :: map() | nil
  defdelegate snapshot(), to: Catalog

  @doc """
  Returns the current epoch from the store.

  ## Returns

  Non-negative integer representing the current epoch, or `0` if not set.
  """
  @spec epoch() :: non_neg_integer()
  defdelegate epoch(), to: Catalog

  @doc """
  Returns the last load options from the store.

  ## Returns

  Keyword list of options used in the last load, or `[]` if not set.
  """
  @spec last_opts() :: keyword()
  defdelegate last_opts(), to: Catalog

  @doc """
  Atomically swaps the store with new snapshot and options.

  Creates a new epoch using a monotonic unique integer and stores the complete state.

  ## Parameters

  - `snapshot` - The snapshot map to store
  - `opts` - Keyword list of options to store

  ## Returns

  `:ok`
  """
  @spec put!(map(), keyword()) :: :ok
  defdelegate put!(snapshot, opts), to: Catalog

  @doc """
  Clears the persistent_term store.

  Primarily used for testing cleanup.

  ## Returns

  `:ok`
  """
  @spec clear!() :: :ok
  defdelegate clear!(), to: Catalog

  # Query functions

  @doc """
  Returns all providers from the snapshot.

  ## Returns

  List of Provider structs, or empty list if no snapshot.
  """
  @spec providers() :: [LLMDB.Provider.t()]
  def providers do
    Catalog.providers()
    |> Enum.map(fn
      %Provider{} = provider -> provider
      provider -> Provider.new!(provider)
    end)
  end

  @doc """
  Returns a specific provider by ID.

  ## Parameters

  - `provider_id` - Provider atom

  ## Returns

  - `{:ok, provider}` - Provider found
  - `{:error, :not_found}` - Provider not found
  """
  @spec provider(atom()) :: {:ok, LLMDB.Provider.t()} | {:error, :not_found}
  def provider(provider_id) when is_atom(provider_id) do
    case Catalog.provider(provider_id) do
      {:ok, %Provider{} = provider} -> {:ok, provider}
      {:ok, provider} -> {:ok, Provider.new!(provider)}
      {:error, :not_found} = error -> error
    end
  end

  @doc """
  Returns all models for a specific provider.

  Includes models from aliased providers. For example, calling `models(:google_vertex)`
  will return models from both `:google_vertex` AND `:google_vertex_anthropic` since
  `google_vertex_anthropic` has `alias_of: :google_vertex`.

  ## Parameters

  - `provider_id` - Provider atom

  ## Returns

  List of Model structs for the provider and its aliases, or empty list if provider not found.
  """
  @spec models(atom()) :: [LLMDB.Model.t()]
  def models(provider_id) when is_atom(provider_id) do
    Catalog.models(provider_id)
    |> Enum.map(fn
      %Model{} = model -> model
      model -> Model.new!(model)
    end)
  end

  @doc """
  Returns a specific model by provider and ID.

  Resolves both model aliases and provider aliases. For example, looking up
  `model(:google_vertex, "claude-haiku-4-5@20251001")` will find the model
  even if it's stored under `:google_vertex_anthropic` provider (via alias_of).

  ## Parameters

  - `provider_id` - Provider atom
  - `model_id` - Model ID string (can be an alias)

  ## Returns

  - `{:ok, model}` - Model found
  - `{:error, :not_found}` - Model not found
  """
  @spec model(atom(), String.t()) :: {:ok, LLMDB.Model.t()} | {:error, :not_found}
  def model(provider_id, model_id) when is_atom(provider_id) and is_binary(model_id) do
    case Catalog.model(provider_id, model_id) do
      {:ok, %Model{} = model} -> {:ok, model}
      {:ok, model} -> Model.new(model)
      {:error, :not_found} = error -> error
    end
  end
end
