defmodule LLMDB.Application do
  @moduledoc """
  Deprecated compatibility shim for callers that invoked `start/2` directly.

  `:llm_db` no longer registers an OTP application callback or starts library
  processes. The catalog initializes lazily on the first public query, or
  explicitly through `LLMDB.load/1`.

  This module remains for one minor release so a direct caller can still start
  the former empty supervisor. Remove direct calls and rely on the query API or
  `LLMDB.load/1` instead.
  """

  use Application

  @impl true
  @deprecated "llm_db initializes lazily; call LLMDB.load/1 only when explicit loading is needed"
  def start(_type, _args) do
    Supervisor.start_link([], strategy: :one_for_one, name: LLMDB.Supervisor)
  end
end
