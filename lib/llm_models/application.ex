defmodule LLMModels.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    LLMModels.load()

    children = [
      # Starts a worker by calling: LLMModels.Worker.start_link(arg)
      # {LLMModels.Worker, arg}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: LLMModels.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
