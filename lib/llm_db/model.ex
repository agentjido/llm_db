defmodule LLMDb.Model do
  @moduledoc """
  Model struct with Zoi schema validation.

  Represents an LLM model with complete metadata including identity, provider,
  dates, limits, costs, modalities, capabilities, tags, deprecation status, and aliases.
  """

  @limits_schema Zoi.object(%{
                   context: Zoi.integer() |> Zoi.min(1) |> Zoi.nullish(),
                   output: Zoi.integer() |> Zoi.min(1) |> Zoi.nullish()
                 })

  @cost_schema Zoi.object(%{
                 input: Zoi.number() |> Zoi.nullish(),
                 output: Zoi.number() |> Zoi.nullish(),
                 request: Zoi.number() |> Zoi.nullish(),
                 cache_read: Zoi.number() |> Zoi.nullish(),
                 cache_write: Zoi.number() |> Zoi.nullish(),
                 training: Zoi.number() |> Zoi.nullish(),
                 reasoning: Zoi.number() |> Zoi.nullish(),
                 image: Zoi.number() |> Zoi.nullish(),
                 audio: Zoi.number() |> Zoi.nullish(),
                 input_audio: Zoi.number() |> Zoi.nullish(),
                 output_audio: Zoi.number() |> Zoi.nullish(),
                 input_video: Zoi.number() |> Zoi.nullish(),
                 output_video: Zoi.number() |> Zoi.nullish()
               })

  @reasoning_schema Zoi.object(%{
                      enabled: Zoi.boolean() |> Zoi.nullish(),
                      token_budget: Zoi.integer() |> Zoi.min(0) |> Zoi.nullish()
                    })

  @tools_schema Zoi.object(%{
                  enabled: Zoi.boolean() |> Zoi.nullish(),
                  streaming: Zoi.boolean() |> Zoi.nullish(),
                  strict: Zoi.boolean() |> Zoi.nullish(),
                  parallel: Zoi.boolean() |> Zoi.nullish()
                })

  @json_schema Zoi.object(%{
                 native: Zoi.boolean() |> Zoi.nullish(),
                 schema: Zoi.boolean() |> Zoi.nullish(),
                 strict: Zoi.boolean() |> Zoi.nullish()
               })

  @streaming_schema Zoi.object(%{
                      text: Zoi.boolean() |> Zoi.nullish(),
                      tool_calls: Zoi.boolean() |> Zoi.nullish()
                    })

  @embeddings_schema Zoi.object(%{
                       min_dimensions: Zoi.integer() |> Zoi.min(1) |> Zoi.nullish(),
                       max_dimensions: Zoi.integer() |> Zoi.min(1) |> Zoi.nullish(),
                       default_dimensions: Zoi.integer() |> Zoi.min(1) |> Zoi.nullish()
                     })

  @capabilities_schema Zoi.object(%{
                         chat: Zoi.boolean() |> Zoi.default(true),
                         embeddings:
                           Zoi.union([Zoi.boolean(), @embeddings_schema]) |> Zoi.default(false),
                         reasoning: @reasoning_schema |> Zoi.default(%{enabled: false}),
                         tools:
                           @tools_schema
                           |> Zoi.default(%{
                             enabled: false,
                             streaming: false,
                             strict: false,
                             parallel: false
                           }),
                         json:
                           @json_schema
                           |> Zoi.default(%{native: false, schema: false, strict: false}),
                         streaming:
                           @streaming_schema |> Zoi.default(%{text: true, tool_calls: false})
                       })

  @schema Zoi.struct(
            __MODULE__,
            %{
              id: Zoi.string(),
              provider: Zoi.atom(),
              provider_model_id: Zoi.string() |> Zoi.nullish(),
              name: Zoi.string() |> Zoi.nullish(),
              family: Zoi.string() |> Zoi.nullish(),
              release_date: Zoi.string() |> Zoi.nullish(),
              last_updated: Zoi.string() |> Zoi.nullish(),
              knowledge: Zoi.string() |> Zoi.nullish(),
              limits: @limits_schema |> Zoi.nullish(),
              cost: @cost_schema |> Zoi.nullish(),
              modalities:
                Zoi.object(%{
                  input: Zoi.array(Zoi.atom()) |> Zoi.nullish(),
                  output: Zoi.array(Zoi.atom()) |> Zoi.nullish()
                })
                |> Zoi.nullish(),
              capabilities: @capabilities_schema |> Zoi.nullish(),
              tags: Zoi.array(Zoi.string()) |> Zoi.nullish(),
              deprecated: Zoi.boolean() |> Zoi.default(false),
              aliases: Zoi.array(Zoi.string()) |> Zoi.default([]),
              extra: Zoi.map() |> Zoi.nullish()
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for Model"
  def schema, do: @schema

  @doc """
  Creates a new Model struct from a map, validating with Zoi schema.

  ## Examples

      iex> LLMDb.Model.new(%{id: "gpt-4", provider: :openai})
      {:ok, %LLMDb.Model{id: "gpt-4", provider: :openai}}

      iex> LLMDb.Model.new(%{})
      {:error, _validation_errors}
  """
  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_map(attrs) do
    Zoi.parse(@schema, attrs)
  end

  @doc """
  Creates a new Model struct from a map, raising on validation errors.

  ## Examples

      iex> LLMDb.Model.new!(%{id: "gpt-4", provider: :openai})
      %LLMDb.Model{id: "gpt-4", provider: :openai}
  """
  @spec new!(map()) :: t()
  def new!(attrs) when is_map(attrs) do
    case new(attrs) do
      {:ok, model} -> model
      {:error, reason} -> raise ArgumentError, "Invalid model: #{inspect(reason)}"
    end
  end
end

defimpl DeepMerge.Resolver, for: LLMDb.Model do
  @moduledoc false

  def resolve(original, override = %LLMDb.Model{}, resolver) do
    cleaned_override =
      override
      |> Map.from_struct()
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.new()

    Map.merge(original, cleaned_override, resolver)
  end

  def resolve(original, override, resolver) when is_map(override) do
    Map.merge(original, override, resolver)
  end

  def resolve(_original, override, _resolver), do: override
end
