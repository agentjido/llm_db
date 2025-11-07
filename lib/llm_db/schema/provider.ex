defmodule LLMDb.Schema.Provider do
  @moduledoc """
  Zoi schema for LLM provider metadata.

  Defines the structure and validation rules for provider records,
  including provider identity, base URL, environment variables, configuration
  requirements, and documentation.
  """

  @config_field_schema Zoi.object(%{
                         name: Zoi.string(),
                         type: Zoi.string(),
                         required: Zoi.boolean() |> Zoi.default(false),
                         default: Zoi.any() |> Zoi.optional(),
                         doc: Zoi.string() |> Zoi.optional()
                       })

  @schema Zoi.object(%{
            id: Zoi.atom(),
            name: Zoi.string() |> Zoi.optional(),
            base_url: Zoi.string() |> Zoi.optional(),
            env: Zoi.array(Zoi.string()) |> Zoi.optional(),
            config_schema: Zoi.array(@config_field_schema) |> Zoi.optional(),
            doc: Zoi.string() |> Zoi.optional(),
            exclude_models: Zoi.array(Zoi.string()) |> Zoi.default([]) |> Zoi.optional(),
            extra: Zoi.map() |> Zoi.optional()
          })

  @type t :: unquote(Zoi.type_spec(@schema))

  @doc "Returns the Zoi schema for Provider"
  def schema, do: @schema
end
