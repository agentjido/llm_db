defmodule LLMDB.Enrich do
  @moduledoc """
  Lightweight, deterministic enrichment of model data.

  This module performs simple derivations and defaults, such as:
  - Deriving model family from model ID
  - Setting provider_model_id to id if not present
  - Ensuring capability defaults are applied (handled by Zoi schemas)
  """

  @doc """
  Derives the family name from a model ID using prefix logic.

  Extracts family from model ID by splitting on "-" and taking all but the last segment.
  Returns nil if the family cannot be reasonably derived.

  ## Examples

      iex> LLMDB.Enrich.derive_family("gpt-4o-mini")
      "gpt-4o"

      iex> LLMDB.Enrich.derive_family("claude-3-opus")
      "claude-3"

      iex> LLMDB.Enrich.derive_family("gemini-1.5-pro")
      "gemini-1.5"

      iex> LLMDB.Enrich.derive_family("single")
      nil

      iex> LLMDB.Enrich.derive_family("two-parts")
      "two"
  """
  @spec derive_family(String.t()) :: String.t() | nil
  def derive_family(model_id) when is_binary(model_id) do
    parts = String.split(model_id, "-")

    case parts do
      [_single] ->
        nil

      parts when length(parts) >= 2 ->
        parts
        |> Enum.slice(0..-2//1)
        |> Enum.join("-")
    end
  end

  @doc """
  Enriches a single model map with derived and default values.

  Sets the following fields if not already present:
  - `family`: Derived from model ID
  - `provider_model_id`: Set to model ID

  Note: Capability defaults are handled automatically by Zoi schema validation.

  ## Examples

      iex> LLMDB.Enrich.enrich_model(%{id: "gpt-4o-mini", provider: :openai})
      %{id: "gpt-4o-mini", provider: :openai, family: "gpt-4o", provider_model_id: "gpt-4o-mini"}

      iex> LLMDB.Enrich.enrich_model(%{id: "claude-3-opus", provider: :anthropic, family: "claude-3-custom"})
      %{id: "claude-3-opus", provider: :anthropic, family: "claude-3-custom", provider_model_id: "claude-3-opus"}

      iex> LLMDB.Enrich.enrich_model(%{id: "model", provider: :openai, provider_model_id: "custom-id"})
      %{id: "model", provider: :openai, provider_model_id: "custom-id"}
  """
  @spec enrich_model(map()) :: map()
  def enrich_model(model) when is_map(model) do
    model
    |> maybe_set_family()
    |> maybe_set_provider_model_id()
  end

  @doc """
  Enriches a list of model maps.

  Applies `enrich_model/1` to each model in the list.

  ## Examples

      iex> LLMDB.Enrich.enrich_models([
      ...>   %{id: "gpt-4o", provider: :openai},
      ...>   %{id: "claude-3-opus", provider: :anthropic}
      ...> ])
      [
        %{id: "gpt-4o", provider: :openai, family: "gpt", provider_model_id: "gpt-4o"},
        %{id: "claude-3-opus", provider: :anthropic, family: "claude-3", provider_model_id: "claude-3-opus"}
      ]
  """
  @spec enrich_models([map()]) :: [map()]
  def enrich_models(models) when is_list(models) do
    models
    |> Enum.map(&enrich_model/1)
    |> inherit_canonical_costs()
  end

  @date_suffix ~r/-\d{4}-\d{2}-\d{2}$/

  @doc """
  Propagates cost from canonical models to their dated variants.

  For models with a date suffix (e.g., `gpt-4o-mini-2024-07-18`), if the model
  has no cost, looks up the canonical model (e.g., `gpt-4o-mini`) from the same
  provider and copies its cost.

  Models that already have a cost are left unchanged.

  ## Examples

      iex> models = [
      ...>   %{id: "gpt-4o-mini", provider: :openai, cost: %{input: 0.15, output: 0.6}},
      ...>   %{id: "gpt-4o-mini-2024-07-18", provider: :openai}
      ...> ]
      iex> [_, dated] = LLMDB.Enrich.inherit_canonical_costs(models)
      iex> dated.cost
      %{input: 0.15, output: 0.6}
  """
  @spec inherit_canonical_costs([map()]) :: [map()]
  def inherit_canonical_costs(models) when is_list(models) do
    canonicals_with_cost =
      models
      |> Enum.reject(&dated_model?/1)
      |> Enum.filter(&has_cost?/1)
      |> Map.new(&{{&1.provider, &1.id}, &1.cost})

    Enum.map(models, fn model ->
      if dated_model?(model) and not has_cost?(model) do
        canonical_id = Regex.replace(@date_suffix, model.id, "")

        case Map.get(canonicals_with_cost, {model.provider, canonical_id}) do
          nil -> model
          cost -> Map.put(model, :cost, cost)
        end
      else
        model
      end
    end)
  end

  defp dated_model?(%{id: id}), do: Regex.match?(@date_suffix, id)

  defp has_cost?(%{cost: cost}) when is_map(cost) and map_size(cost) > 0, do: true
  defp has_cost?(_), do: false

  # Private helpers

  defp maybe_set_family(%{family: _} = model), do: model

  defp maybe_set_family(%{id: id} = model) do
    case derive_family(id) do
      nil -> model
      family -> Map.put(model, :family, family)
    end
  end

  defp maybe_set_provider_model_id(%{provider_model_id: _} = model), do: model

  defp maybe_set_provider_model_id(%{id: id} = model) do
    Map.put(model, :provider_model_id, id)
  end
end
