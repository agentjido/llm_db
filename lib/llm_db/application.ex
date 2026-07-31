defmodule LLMDB.Application do
  @moduledoc """
  OTP application callback for LLMDB.

  Loads the packaged catalog before the consumer application starts. Public
  queries retain lazy initialization as a fallback for runtimes that do not
  start the `:llm_db` application.
  """

  use Application

  @impl true
  def start(_type, _args) do
    with :ok <- load_catalog() do
      Supervisor.start_link([], strategy: :one_for_one, name: LLMDB.Supervisor)
    end
  end

  defp load_catalog do
    if Application.get_env(:llm_db, :skip_packaged_load, false) do
      :ok
    else
      case LLMDB.load() do
        {:ok, _catalog} -> :ok
        {:error, reason} -> {:error, reason}
      end
    end
  end
end
