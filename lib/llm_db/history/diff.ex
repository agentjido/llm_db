defmodule LLMDB.History.Diff do
  @moduledoc false

  @sortable_list_keys MapSet.new(["aliases", "tags", "input", "output"])

  @spec models(%{optional(String.t()) => map()}, %{optional(String.t()) => map()}) :: [map()]
  def models(previous_models, current_models)
      when is_map(previous_models) and is_map(current_models) do
    previous_keys = Map.keys(previous_models) |> MapSet.new()
    current_keys = Map.keys(current_models) |> MapSet.new()

    introduced =
      current_keys
      |> MapSet.difference(previous_keys)
      |> MapSet.to_list()
      |> Enum.sort()
      |> Enum.map(&%{type: "introduced", model_key: &1, changes: []})

    removed =
      previous_keys
      |> MapSet.difference(current_keys)
      |> MapSet.to_list()
      |> Enum.sort()
      |> Enum.map(&%{type: "removed", model_key: &1, changes: []})

    changed =
      previous_keys
      |> MapSet.intersection(current_keys)
      |> MapSet.to_list()
      |> Enum.sort()
      |> Enum.reduce([], fn model_key, acc ->
        changes =
          deep_changes(
            Map.fetch!(previous_models, model_key),
            Map.fetch!(current_models, model_key),
            []
          )

        if changes == [] do
          acc
        else
          [%{type: "changed", model_key: model_key, changes: changes} | acc]
        end
      end)
      |> Enum.reverse()

    introduced ++ removed ++ changed
  end

  @spec normalize(term()) :: term()
  def normalize(value), do: normalize_value(value, [])

  @spec snapshot_digest(%{optional(String.t()) => map()}) :: String.t()
  def snapshot_digest(models) when is_map(models) do
    models
    |> canonical_digest_term()
    |> :erlang.term_to_binary()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp normalize_value(value, path) when is_map(value) do
    value
    |> Enum.map(fn {key, nested} ->
      {key, normalize_value(nested, [to_string(key) | path])}
    end)
    |> Map.new()
  end

  defp normalize_value(value, path) when is_list(value) do
    normalized = Enum.map(value, &normalize_value(&1, path))

    case path do
      [key | _rest] ->
        if key in @sortable_list_keys and Enum.all?(normalized, &scalar?/1) do
          Enum.sort(normalized)
        else
          normalized
        end

      [] ->
        normalized
    end
  end

  defp normalize_value(value, _path), do: value

  defp scalar?(value),
    do: is_binary(value) or is_number(value) or is_boolean(value) or is_nil(value)

  defp deep_changes(before_value, after_value, path)
       when is_map(before_value) and is_map(after_value) do
    keys =
      (Map.keys(before_value) ++ Map.keys(after_value))
      |> Enum.uniq()
      |> Enum.sort()

    Enum.flat_map(keys, fn key ->
      in_before = Map.has_key?(before_value, key)
      in_after = Map.has_key?(after_value, key)
      next_path = path ++ [to_string(key)]

      cond do
        in_before and in_after ->
          deep_changes(Map.get(before_value, key), Map.get(after_value, key), next_path)

        in_before ->
          [
            %{
              path: Enum.join(next_path, "."),
              op: "remove",
              before: Map.get(before_value, key),
              after: nil
            }
          ]

        in_after ->
          [
            %{
              path: Enum.join(next_path, "."),
              op: "add",
              before: nil,
              after: Map.get(after_value, key)
            }
          ]
      end
    end)
  end

  defp deep_changes(before_value, after_value, path) do
    if before_value == after_value do
      []
    else
      [%{path: Enum.join(path, "."), op: "replace", before: before_value, after: after_value}]
    end
  end

  defp canonical_digest_term(value) when is_map(value) do
    entries =
      value
      |> Enum.map(fn {key, nested} -> {key, canonical_digest_term(nested)} end)
      |> Enum.sort_by(fn {key, _nested} -> canonical_sort_key(key) end)

    {:map, entries}
  end

  defp canonical_digest_term(value) when is_list(value) do
    {:list, Enum.map(value, &canonical_digest_term/1)}
  end

  defp canonical_digest_term(value), do: value

  defp canonical_sort_key(value) when is_binary(value), do: {0, value}
  defp canonical_sort_key(value) when is_atom(value), do: {1, Atom.to_string(value)}
  defp canonical_sort_key(value) when is_integer(value), do: {2, value}
  defp canonical_sort_key(value) when is_float(value), do: {3, value}
  defp canonical_sort_key(value), do: {6, inspect(value)}
end
