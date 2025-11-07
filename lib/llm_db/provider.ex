defmodule LLMDb.Provider do
  @moduledoc """
  Provider struct with Zoi schema validation.

  Represents an LLM provider with metadata including identity, base URL,
  environment variables, and documentation.
  """

  @schema LLMDb.Schema.Provider.schema()

  @type t :: %__MODULE__{
          id: atom(),
          name: String.t() | nil,
          base_url: String.t() | nil,
          env: [String.t()] | nil,
          config_schema: [map()] | nil,
          doc: String.t() | nil,
          extra: map() | nil
        }

  defstruct [:id, :name, :base_url, :env, :config_schema, :doc, :extra]

  @doc """
  Creates a new Provider struct from a map, validating with Zoi schema.

  ## Examples

      iex> LLMDb.Provider.new(%{id: :openai, name: "OpenAI"})
      {:ok, %LLMDb.Provider{id: :openai, name: "OpenAI"}}

      iex> LLMDb.Provider.new(%{})
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

      iex> LLMDb.Provider.new!(%{id: :openai, name: "OpenAI"})
      %LLMDb.Provider{id: :openai, name: "OpenAI"}
  """
  @spec new!(map()) :: t()
  def new!(attrs) when is_map(attrs) do
    case new(attrs) do
      {:ok, provider} -> provider
      {:error, reason} -> raise ArgumentError, "Invalid provider: #{inspect(reason)}"
    end
  end
end
