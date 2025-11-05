defmodule LLMModels.Schema.Provider do
  @moduledoc """
  Zoi schema for LLM provider metadata.

  Defines the structure and validation rules for provider records,
  including provider identity, base URL, environment variables, and documentation.
  """

  @schema Zoi.object(%{
            id: Zoi.atom(),
            name: Zoi.string() |> Zoi.optional(),
            base_url: Zoi.string() |> Zoi.optional(),
            env: Zoi.array(Zoi.string()) |> Zoi.optional(),
            doc: Zoi.string() |> Zoi.optional(),
            extra: Zoi.map() |> Zoi.optional()
          })

  @type t :: unquote(Zoi.type_spec(@schema))

  @doc "Returns the Zoi schema for Provider"
  def schema, do: @schema
end
