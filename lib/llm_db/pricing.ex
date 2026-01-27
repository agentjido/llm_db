defmodule LLMDB.Pricing do
  @moduledoc """
  Pricing helpers for applying provider defaults and merging model overrides.
  """

  alias LLMDB.Merge

  @spec apply_cost_components([LLMDB.Model.t()]) :: [LLMDB.Model.t()]
  def apply_cost_components(models) when is_list(models) do
    Enum.map(models, &apply_cost_components_to_model/1)
  end

  @spec apply_provider_defaults([LLMDB.Provider.t()], [LLMDB.Model.t()]) :: [LLMDB.Model.t()]
  def apply_provider_defaults(providers, models) when is_list(providers) and is_list(models) do
    defaults_by_provider =
      Map.new(providers, fn provider ->
        {provider.id, Map.get(provider, :pricing_defaults)}
      end)

    Enum.map(models, fn model ->
      case Map.get(defaults_by_provider, model.provider) do
        nil -> model
        defaults -> apply_defaults_to_model(model, defaults)
      end
    end)
  end

  defp apply_defaults_to_model(model, defaults) do
    case Map.get(model, :pricing) do
      nil -> Map.put(model, :pricing, defaults)
      pricing -> Map.put(model, :pricing, merge_pricing(defaults, pricing))
    end
  end

  defp apply_cost_components_to_model(model) do
    cost = Map.get(model, :cost) || Map.get(model, "cost")

    if is_map(cost) and map_size(cost) > 0 do
      pricing = Map.get(model, :pricing) || Map.get(model, "pricing") || %{}
      existing_components = components_list(pricing)
      cost_components = cost_components(cost)
      merged_components = Merge.merge_list_by_id(cost_components, existing_components)

      currency =
        Map.get(pricing, :currency) || Map.get(pricing, "currency") || "USD"

      updated_pricing =
        pricing
        |> Map.put(:currency, currency)
        |> Map.put(:components, merged_components)

      Map.put(model, :pricing, updated_pricing)
    else
      model
    end
  end

  defp merge_pricing(defaults, pricing) do
    case merge_mode(pricing) do
      "replace" -> pricing
      _ -> merge_by_id(defaults, pricing)
    end
  end

  defp merge_mode(pricing) do
    mode = Map.get(pricing, :merge) || Map.get(pricing, "merge")

    case mode do
      :replace -> "replace"
      "replace" -> "replace"
      :merge_by_id -> "merge_by_id"
      "merge_by_id" -> "merge_by_id"
      _ -> "merge_by_id"
    end
  end

  defp merge_by_id(defaults, pricing) do
    currency =
      Map.get(pricing, :currency) ||
        Map.get(pricing, "currency") ||
        Map.get(defaults, :currency) ||
        Map.get(defaults, "currency")

    default_components = components_list(defaults)
    pricing_components = components_list(pricing)
    merged_components = Merge.merge_list_by_id(default_components, pricing_components)

    pricing
    |> Map.put(:currency, currency)
    |> Map.put(:components, merged_components)
  end

  defp components_list(pricing) do
    Map.get(pricing, :components) || Map.get(pricing, "components") || []
  end

  defp cost_components(cost) when is_map(cost) do
    []
    |> maybe_add_token_component("token.input", Map.get(cost, :input) || Map.get(cost, "input"))
    |> maybe_add_token_component(
      "token.output",
      Map.get(cost, :output) || Map.get(cost, "output")
    )
    |> maybe_add_token_component(
      "token.cache_read",
      Map.get(cost, :cache_read) || Map.get(cost, "cache_read") ||
        Map.get(cost, :cached_input) || Map.get(cost, "cached_input")
    )
    |> maybe_add_token_component(
      "token.cache_write",
      Map.get(cost, :cache_write) || Map.get(cost, "cache_write")
    )
    |> maybe_add_token_component(
      "token.reasoning",
      Map.get(cost, :reasoning) || Map.get(cost, "reasoning")
    )
  end

  defp maybe_add_token_component(components, _id, nil), do: components

  defp maybe_add_token_component(components, id, rate) when is_number(rate) do
    components ++ [%{id: id, kind: "token", unit: "token", per: 1_000_000, rate: rate}]
  end

  defp maybe_add_token_component(components, _id, _rate), do: components
end
