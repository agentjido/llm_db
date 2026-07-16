defmodule LLMDB.History.Lineage do
  @moduledoc false

  @lineage_inference_threshold 30

  @spec initialize(map(), map()) :: map()
  def initialize(models, lineage_overrides) when is_map(models) and is_map(lineage_overrides) do
    models
    |> Map.keys()
    |> Enum.sort()
    |> Enum.reduce(%{}, fn model_key, acc ->
      lineage = lineage_for_model_key(model_key, lineage_overrides, %{}, acc, model_key)
      Map.put(acc, model_key, lineage)
    end)
  end

  @spec resolve(map(), map(), map(), map()) :: map()
  def resolve(previous_models, current_models, previous_lineage_by_key, lineage_overrides)
      when is_map(previous_models) and is_map(current_models) and
             is_map(previous_lineage_by_key) and is_map(lineage_overrides) do
    previous_keys = Map.keys(previous_models) |> MapSet.new()
    current_keys = Map.keys(current_models) |> MapSet.new()

    shared_keys = previous_keys |> MapSet.intersection(current_keys) |> sorted_keys()
    removed_keys = sorted_difference(previous_keys, current_keys)
    introduced_keys = sorted_difference(current_keys, previous_keys)

    current_lineage_by_key =
      Enum.reduce(shared_keys, %{}, fn model_key, acc ->
        default_lineage = Map.get(previous_lineage_by_key, model_key, model_key)

        lineage =
          lineage_for_model_key(
            model_key,
            lineage_overrides,
            previous_lineage_by_key,
            acc,
            default_lineage
          )

        Map.put(acc, model_key, lineage)
      end)

    {current_lineage_by_key, unresolved_introduced} =
      Enum.reduce(introduced_keys, {current_lineage_by_key, []}, fn model_key,
                                                                    {acc, unresolved} ->
        if Map.has_key?(lineage_overrides, model_key) do
          lineage =
            lineage_for_model_key(
              model_key,
              lineage_overrides,
              previous_lineage_by_key,
              acc,
              model_key
            )

          {Map.put(acc, model_key, lineage), unresolved}
        else
          {acc, [model_key | unresolved]}
        end
      end)

    unresolved_introduced = Enum.reverse(unresolved_introduced)

    inferred_matches =
      infer_matches(removed_keys, unresolved_introduced, previous_models, current_models)

    {current_lineage_by_key, matched_introduced} =
      Enum.reduce(inferred_matches, {current_lineage_by_key, MapSet.new()}, fn {new_key, old_key},
                                                                               {acc, matched} ->
        default_lineage = Map.get(previous_lineage_by_key, old_key, old_key)

        lineage =
          lineage_for_model_key(
            new_key,
            lineage_overrides,
            previous_lineage_by_key,
            acc,
            default_lineage
          )

        {Map.put(acc, new_key, lineage), MapSet.put(matched, new_key)}
      end)

    Enum.reduce(unresolved_introduced, current_lineage_by_key, fn model_key, acc ->
      if MapSet.member?(matched_introduced, model_key) do
        acc
      else
        lineage =
          lineage_for_model_key(
            model_key,
            lineage_overrides,
            previous_lineage_by_key,
            acc,
            model_key
          )

        Map.put(acc, model_key, lineage)
      end
    end)
  end

  @spec attach([map()], map(), map()) :: [map()]
  def attach(events, previous_lineage_by_key, current_lineage_by_key)
      when is_list(events) and is_map(previous_lineage_by_key) and
             is_map(current_lineage_by_key) do
    Enum.map(events, fn event ->
      lineage_key =
        case event.type do
          "removed" ->
            Map.get(previous_lineage_by_key, event.model_key, event.model_key)

          _other ->
            Map.get(current_lineage_by_key, event.model_key) ||
              Map.get(previous_lineage_by_key, event.model_key, event.model_key)
        end

      Map.put(event, :lineage_key, lineage_key)
    end)
  end

  defp sorted_difference(left, right) do
    left
    |> MapSet.difference(right)
    |> sorted_keys()
  end

  defp sorted_keys(keys) do
    keys
    |> MapSet.to_list()
    |> Enum.sort()
  end

  defp infer_matches(removed_keys, introduced_keys, previous_models, current_models) do
    candidates =
      for removed_key <- removed_keys,
          introduced_key <- introduced_keys,
          score =
            inference_score(
              Map.get(previous_models, removed_key, %{}),
              Map.get(current_models, introduced_key, %{})
            ),
          score >= @lineage_inference_threshold do
        {score, introduced_key, removed_key}
      end

    candidates
    |> Enum.sort_by(fn {score, introduced_key, removed_key} ->
      {-score, introduced_key, removed_key}
    end)
    |> Enum.reduce({[], MapSet.new(), MapSet.new()}, fn {_score, introduced_key, removed_key},
                                                        {acc, claimed_new, claimed_old} ->
      cond do
        MapSet.member?(claimed_new, introduced_key) ->
          {acc, claimed_new, claimed_old}

        MapSet.member?(claimed_old, removed_key) ->
          {acc, claimed_new, claimed_old}

        true ->
          {
            [{introduced_key, removed_key} | acc],
            MapSet.put(claimed_new, introduced_key),
            MapSet.put(claimed_old, removed_key)
          }
      end
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  defp inference_score(previous_model, current_model)
       when is_map(previous_model) and is_map(current_model) do
    previous_id = Map.get(previous_model, "id")
    current_id = Map.get(current_model, "id")
    previous_provider_model_id = Map.get(previous_model, "provider_model_id")
    current_provider_model_id = Map.get(current_model, "provider_model_id")
    previous_aliases = string_list(Map.get(previous_model, "aliases"))
    current_aliases = string_list(Map.get(current_model, "aliases"))

    id_match_score = score(is_binary(previous_id) and previous_id == current_id, 50)

    provider_model_score =
      score(
        is_binary(previous_provider_model_id) and
          previous_provider_model_id == current_provider_model_id,
        40
      )

    previous_id_in_current_aliases_score =
      score(is_binary(previous_id) and previous_id in current_aliases, 30)

    current_id_in_previous_aliases_score =
      score(is_binary(current_id) and current_id in previous_aliases, 30)

    model_field_score =
      score(
        is_binary(Map.get(previous_model, "model")) and
          Map.get(previous_model, "model") == Map.get(current_model, "model"),
        5
      )

    name_field_score =
      score(
        is_binary(Map.get(previous_model, "name")) and
          Map.get(previous_model, "name") == Map.get(current_model, "name"),
        2
      )

    id_match_score + provider_model_score + previous_id_in_current_aliases_score +
      current_id_in_previous_aliases_score +
      overlap_count(previous_aliases, current_aliases) * 5 + model_field_score +
      name_field_score
  end

  defp score(true, value), do: value
  defp score(false, _value), do: 0

  defp string_list(value) when is_list(value) do
    value
    |> Enum.filter(&is_binary/1)
    |> Enum.uniq()
  end

  defp string_list(_value), do: []

  defp overlap_count(left, right) do
    right_lookup = MapSet.new(right)
    Enum.count(left, &MapSet.member?(right_lookup, &1))
  end

  defp lineage_for_model_key(
         model_key,
         lineage_overrides,
         previous_lineage_by_key,
         current_lineage_by_key,
         default_lineage
       ) do
    case resolve_override_target(model_key, lineage_overrides) do
      nil ->
        default_lineage

      target_key ->
        Map.get(current_lineage_by_key, target_key) ||
          Map.get(previous_lineage_by_key, target_key) ||
          target_key
    end
  end

  defp resolve_override_target(model_key, lineage_overrides) do
    if Map.has_key?(lineage_overrides, model_key) do
      follow_override_target(model_key, lineage_overrides, [], 0)
    end
  end

  defp follow_override_target(model_key, _lineage_overrides, _seen, depth) when depth >= 32,
    do: model_key

  defp follow_override_target(model_key, lineage_overrides, seen, depth) do
    if model_key in seen do
      model_key
    else
      case Map.get(lineage_overrides, model_key) do
        nil ->
          model_key

        target when is_binary(target) ->
          follow_override_target(target, lineage_overrides, [model_key | seen], depth + 1)
      end
    end
  end
end
