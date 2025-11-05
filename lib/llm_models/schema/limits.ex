defmodule LLMModels.Schema.Limits do
  @moduledoc """
  Zoi schema for LLM model token limits.

  Defines context window and output token limits for models.
  """

  @schema Zoi.object(%{
            context: Zoi.integer() |> Zoi.min(1) |> Zoi.optional(),
            output: Zoi.integer() |> Zoi.min(1) |> Zoi.optional()
          })

  @type t :: unquote(Zoi.type_spec(@schema))

  @doc "Returns the Zoi schema for Limits"
  def schema, do: @schema
end
