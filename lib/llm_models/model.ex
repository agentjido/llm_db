defmodule LLMModels.Model do
  @moduledoc """
  Model struct with Zoi schema validation.

  Represents an LLM model with complete metadata including identity, provider,
  dates, limits, costs, modalities, capabilities, tags, deprecation status, and aliases.
  """

  @schema LLMModels.Schema.Model.schema()

  @type t :: %__MODULE__{
          id: String.t(),
          provider: atom(),
          provider_model_id: String.t() | nil,
          name: String.t() | nil,
          family: String.t() | nil,
          release_date: String.t() | nil,
          last_updated: String.t() | nil,
          knowledge: String.t() | nil,
          limits: map() | nil,
          cost: map() | nil,
          modalities: map() | nil,
          capabilities: map() | nil,
          tags: [String.t()] | nil,
          deprecated?: boolean(),
          aliases: [String.t()],
          extra: map() | nil
        }

  defstruct [
    :id,
    :provider,
    :provider_model_id,
    :name,
    :family,
    :release_date,
    :last_updated,
    :knowledge,
    :limits,
    :cost,
    :modalities,
    :capabilities,
    :tags,
    :extra,
    deprecated?: false,
    aliases: []
  ]

  @doc """
  Creates a new Model struct from a map, validating with Zoi schema.

  ## Examples

      iex> LLMModels.Model.new(%{id: "gpt-4", provider: :openai})
      {:ok, %LLMModels.Model{id: "gpt-4", provider: :openai}}

      iex> LLMModels.Model.new(%{})
      {:error, _validation_errors}
  """
  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_map(attrs) do
    case Zoi.parse(@schema, attrs) do
      {:ok, validated} -> {:ok, struct(__MODULE__, validated)}
      {:error, _} = error -> error
    end
  end

  @doc """
  Creates a new Model struct from a map, raising on validation errors.

  ## Examples

      iex> LLMModels.Model.new!(%{id: "gpt-4", provider: :openai})
      %LLMModels.Model{id: "gpt-4", provider: :openai}
  """
  @spec new!(map()) :: t()
  def new!(attrs) when is_map(attrs) do
    case new(attrs) do
      {:ok, model} -> model
      {:error, reason} -> raise ArgumentError, "Invalid model: #{inspect(reason)}"
    end
  end
end
