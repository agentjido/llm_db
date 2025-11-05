defmodule LLMModels.Schema.Model do
  @moduledoc """
  Zoi schema for LLM model metadata.

  Defines the complete structure for model records including identity, provider,
  dates, limits, costs, modalities, capabilities, tags, deprecation status, and aliases.
  """

  require LLMModels.Schema.Capabilities
  require LLMModels.Schema.Cost
  require LLMModels.Schema.Limits

  @limits_schema LLMModels.Schema.Limits.schema()
  @cost_schema LLMModels.Schema.Cost.schema()
  @capabilities_schema LLMModels.Schema.Capabilities.schema()

  @schema Zoi.object(%{
            id: Zoi.string(),
            provider: Zoi.atom(),
            provider_model_id: Zoi.string() |> Zoi.optional(),
            name: Zoi.string() |> Zoi.optional(),
            family: Zoi.string() |> Zoi.optional(),
            release_date: Zoi.string() |> Zoi.optional(),
            last_updated: Zoi.string() |> Zoi.optional(),
            knowledge: Zoi.string() |> Zoi.optional(),
            limits: @limits_schema |> Zoi.optional(),
            cost: @cost_schema |> Zoi.optional(),
            modalities:
              Zoi.object(%{
                input: Zoi.array(Zoi.atom()) |> Zoi.optional(),
                output: Zoi.array(Zoi.atom()) |> Zoi.optional()
              })
              |> Zoi.optional(),
            capabilities: @capabilities_schema |> Zoi.optional(),
            tags: Zoi.array(Zoi.string()) |> Zoi.optional(),
            deprecated?: Zoi.boolean() |> Zoi.default(false),
            aliases: Zoi.array(Zoi.string()) |> Zoi.default([]),
            extra: Zoi.map() |> Zoi.optional()
          })

  @type t :: unquote(Zoi.type_spec(@schema))

  @doc "Returns the Zoi schema for Model"
  def schema, do: @schema
end
