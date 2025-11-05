defmodule LLMModels.Schema.Cost do
  @moduledoc """
  Zoi schema for LLM model cost structure.

  Defines per-1M-token costs for various operations including input, output,
  caching, training, and multimodal costs (image, audio).
  """

  @schema Zoi.object(%{
            input: Zoi.number() |> Zoi.optional(),
            output: Zoi.number() |> Zoi.optional(),
            cache_read: Zoi.number() |> Zoi.optional(),
            cache_write: Zoi.number() |> Zoi.optional(),
            training: Zoi.number() |> Zoi.optional(),
            image: Zoi.number() |> Zoi.optional(),
            audio: Zoi.number() |> Zoi.optional()
          })

  @type t :: unquote(Zoi.type_spec(@schema))

  @doc "Returns the Zoi schema for Cost"
  def schema, do: @schema
end
