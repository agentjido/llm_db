defmodule LLMDB.LoadError do
  @moduledoc """
  Raised when lazy catalog initialization fails on the first public query.

  Call `LLMDB.load/1` explicitly when the caller needs to handle the same
  failure as an `{:error, reason}` tuple.
  """

  defexception [:reason]

  @impl true
  def message(%__MODULE__{reason: reason}) do
    "could not initialize the llm_db catalog: #{inspect(reason)}"
  end
end
