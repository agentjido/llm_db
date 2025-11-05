defmodule LLMModels.Validate do
  @moduledoc """
  Validation functions for providers and models using Zoi schemas.

  Provides functions to validate individual records or batches of records,
  handling errors gracefully and ensuring catalog viability.
  """

  alias LLMModels.Schema.{Model, Provider}

  @type validation_error :: term()

  @doc """
  Validates a single provider map against the Provider schema.

  ## Examples

      iex> validate_provider(%{id: :openai})
      {:ok, %{id: :openai}}

      iex> validate_provider(%{id: "openai"})
      {:error, _}
  """
  @spec validate_provider(map()) :: {:ok, Provider.t()} | {:error, validation_error()}
  def validate_provider(map) when is_map(map) do
    Zoi.parse(Provider.schema(), map)
  end

  @doc """
  Validates a single model map against the Model schema.

  ## Examples

      iex> validate_model(%{id: "gpt-4o", provider: :openai})
      {:ok, %{id: "gpt-4o", provider: :openai, deprecated?: false, aliases: []}}

      iex> validate_model(%{id: "gpt-4o"})
      {:error, _}
  """
  @spec validate_model(map()) :: {:ok, Model.t()} | {:error, validation_error()}
  def validate_model(map) when is_map(map) do
    Zoi.parse(Model.schema(), map)
  end

  @doc """
  Validates a list of provider maps, collecting valid ones and counting invalid.

  Returns all valid providers and the count of invalid ones that were dropped.

  ## Examples

      iex> providers = [%{id: :openai}, %{id: "invalid"}, %{id: :anthropic}]
      iex> validate_providers(providers)
      {:ok, [%{id: :openai}, %{id: :anthropic}], 1}
  """
  @spec validate_providers([map()]) :: {:ok, [Provider.t()], non_neg_integer()}
  def validate_providers(maps) when is_list(maps) do
    {valid, invalid_count} =
      Enum.reduce(maps, {[], 0}, fn map, {valid_acc, invalid_acc} ->
        case validate_provider(map) do
          {:ok, provider} -> {[provider | valid_acc], invalid_acc}
          {:error, _} -> {valid_acc, invalid_acc + 1}
        end
      end)

    {:ok, Enum.reverse(valid), invalid_count}
  end

  @doc """
  Validates a list of model maps, collecting valid ones and counting invalid.

  Returns all valid models and the count of invalid ones that were dropped.

  ## Examples

      iex> models = [
      ...>   %{id: "gpt-4o", provider: :openai},
      ...>   %{id: :invalid, provider: :openai},
      ...>   %{id: "claude-3", provider: :anthropic}
      ...> ]
      iex> validate_models(models)
      {:ok, [%{id: "gpt-4o", ...}, %{id: "claude-3", ...}], 1}
  """
  @spec validate_models([map()]) :: {:ok, [Model.t()], non_neg_integer()}
  def validate_models(maps) when is_list(maps) do
    {valid, invalid_count} =
      Enum.reduce(maps, {[], 0}, fn map, {valid_acc, invalid_acc} ->
        case validate_model(map) do
          {:ok, model} -> {[model | valid_acc], invalid_acc}
          {:error, _} -> {valid_acc, invalid_acc + 1}
        end
      end)

    {:ok, Enum.reverse(valid), invalid_count}
  end

  @doc """
  Ensures that we have at least one provider and one model for a viable catalog.

  Returns :ok if both lists are non-empty, otherwise returns an error.

  ## Examples

      iex> ensure_viable([%{id: :openai}], [%{id: "gpt-4o", provider: :openai}])
      :ok

      iex> ensure_viable([], [%{id: "gpt-4o", provider: :openai}])
      {:error, :empty_catalog}

      iex> ensure_viable([%{id: :openai}], [])
      {:error, :empty_catalog}
  """
  @spec ensure_viable([Provider.t()], [Model.t()]) :: :ok | {:error, :empty_catalog}
  def ensure_viable(providers, models)
      when is_list(providers) and is_list(models) do
    if providers != [] and models != [] do
      :ok
    else
      {:error, :empty_catalog}
    end
  end
end
