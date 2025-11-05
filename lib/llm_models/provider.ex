defmodule LLMModels.Provider do
  @moduledoc """
  Provider struct with Zoi schema validation.

  Represents an LLM provider with metadata including identity, base URL,
  environment variables, and documentation.
  """

  @schema LLMModels.Schema.Provider.schema()

  @type t :: %__MODULE__{
          id: atom(),
          name: String.t() | nil,
          base_url: String.t() | nil,
          env: [String.t()] | nil,
          doc: String.t() | nil,
          extra: map() | nil
        }

  defstruct [:id, :name, :base_url, :env, :doc, :extra]

  @doc """
  Creates a new Provider struct from a map, validating with Zoi schema.

  ## Examples

      iex> LLMModels.Provider.new(%{id: :openai, name: "OpenAI"})
      {:ok, %LLMModels.Provider{id: :openai, name: "OpenAI"}}

      iex> LLMModels.Provider.new(%{})
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
  Creates a new Provider struct from a map, raising on validation errors.

  ## Examples

      iex> LLMModels.Provider.new!(%{id: :openai, name: "OpenAI"})
      %LLMModels.Provider{id: :openai, name: "OpenAI"}
  """
  @spec new!(map()) :: t()
  def new!(attrs) when is_map(attrs) do
    case new(attrs) do
      {:ok, provider} -> provider
      {:error, reason} -> raise ArgumentError, "Invalid provider: #{inspect(reason)}"
    end
  end
end
