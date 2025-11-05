defmodule LLMModels.Store do
  @moduledoc """
  Manages persistent_term storage for LLM model snapshots with atomic swaps.

  Uses `:persistent_term` for fast, concurrent reads with atomic updates tracked by monotonic epochs.
  """

  @store_key :llm_models_store

  @doc """
  Reads the full store from persistent_term.

  ## Returns

  Map with `:snapshot`, `:epoch`, and `:opts` keys, or `nil` if not set.
  """
  @spec get() :: map() | nil
  def get do
    :persistent_term.get(@store_key, nil)
  end

  @doc """
  Returns the snapshot portion from the store.

  ## Returns

  The snapshot map or `nil` if not set.
  """
  @spec snapshot() :: map() | nil
  def snapshot do
    case get() do
      %{snapshot: snapshot} -> snapshot
      _ -> nil
    end
  end

  @doc """
  Returns the current epoch from the store.

  ## Returns

  Non-negative integer representing the current epoch, or `0` if not set.
  """
  @spec epoch() :: non_neg_integer()
  def epoch do
    case get() do
      %{epoch: epoch} -> epoch
      _ -> 0
    end
  end

  @doc """
  Returns the last load options from the store.

  ## Returns

  Keyword list of options used in the last load, or `[]` if not set.
  """
  @spec last_opts() :: keyword()
  def last_opts do
    case get() do
      %{opts: opts} -> opts
      _ -> []
    end
  end

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
  def put!(snapshot, opts) do
    epoch = :erlang.unique_integer([:monotonic, :positive])
    store = %{snapshot: snapshot, epoch: epoch, opts: opts}
    :persistent_term.put(@store_key, store)
    :ok
  end

  @doc """
  Clears the persistent_term store.

  Primarily used for testing cleanup.

  ## Returns

  `:ok`
  """
  @spec clear!() :: :ok
  def clear! do
    :persistent_term.erase(@store_key)
    :ok
  end
end
