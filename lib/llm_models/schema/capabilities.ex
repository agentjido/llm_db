defmodule LLMModels.Schema.Capabilities do
  @moduledoc """
  Zoi schema for LLM model capabilities.

  Defines model capabilities including chat, embeddings, reasoning, tools,
  JSON support, and streaming. Provides sensible defaults for common scenarios.
  """

  @reasoning_schema Zoi.object(%{
                      enabled: Zoi.boolean() |> Zoi.default(false),
                      token_budget: Zoi.integer() |> Zoi.min(0) |> Zoi.optional()
                    })

  @tools_schema Zoi.object(%{
                  enabled: Zoi.boolean() |> Zoi.default(false),
                  streaming: Zoi.boolean() |> Zoi.default(false),
                  strict: Zoi.boolean() |> Zoi.default(false),
                  parallel: Zoi.boolean() |> Zoi.default(false)
                })

  @json_schema Zoi.object(%{
                 native: Zoi.boolean() |> Zoi.default(false),
                 schema: Zoi.boolean() |> Zoi.default(false),
                 strict: Zoi.boolean() |> Zoi.default(false)
               })

  @streaming_schema Zoi.object(%{
                      text: Zoi.boolean() |> Zoi.default(true),
                      tool_calls: Zoi.boolean() |> Zoi.default(false)
                    })

  @schema Zoi.object(%{
            chat: Zoi.boolean() |> Zoi.default(true),
            embeddings: Zoi.boolean() |> Zoi.default(false),
            reasoning: @reasoning_schema |> Zoi.default(%{enabled: false}),
            tools:
              @tools_schema
              |> Zoi.default(%{enabled: false, streaming: false, strict: false, parallel: false}),
            json: @json_schema |> Zoi.default(%{native: false, schema: false, strict: false}),
            streaming: @streaming_schema |> Zoi.default(%{text: true, tool_calls: false})
          })

  @type t :: unquote(Zoi.type_spec(@schema))

  @doc "Returns the Zoi schema for Capabilities"
  def schema, do: @schema
end
