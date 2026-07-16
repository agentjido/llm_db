defmodule LLMDB.History do
  @moduledoc """
  Read-only runtime access to generated model history artifacts.

  History is loaded from `priv/llm_db/history` (or `config :llm_db, :history_dir`).
  NDJSON files are parsed into one immutable index published atomically through
  `:persistent_term` for fast timeline/recent lookups without a cache process.

  The cache uses one bounded key. Reloading replaces that key and therefore has
  the normal `:persistent_term` global-GC update cost; reads remain lock-free.
  """

  @cache_key {__MODULE__, :index}
  @load_lock {__MODULE__, :index_load}
  @max_limit 500

  @type event :: map()

  @doc """
  Returns `true` when history artifacts are available and readable.
  """
  @spec available?() :: boolean()
  def available? do
    case ensure_loaded() do
      {:ok, _} -> true
      _ -> false
    end
  end

  @doc """
  Returns parsed history metadata from `meta.json`.
  """
  @spec meta() :: {:ok, map()} | {:error, :history_unavailable | term()}
  def meta do
    with {:ok, index} <- ensure_loaded() do
      {:ok, index.meta}
    else
      {:error, _reason} -> {:error, :history_unavailable}
    end
  end

  @doc """
  Returns all timeline events for a model, lineage-aware and ordered by
  `captured_at` then `event_id` ascending.
  """
  @spec timeline(atom() | String.t(), String.t()) :: {:ok, [event()]} | {:error, term()}
  def timeline(provider, model_id) when is_binary(model_id) do
    with {:ok, provider_str} <- normalize_provider(provider),
         {:ok, index} <- ensure_loaded() do
      model_key = provider_str <> ":" <> model_id
      lineage_key = Map.get(index.lineage_by_model, model_key, model_key)

      events =
        Map.get(index.lineage_index, lineage_key) ||
          Map.get(index.model_index, model_key, [])

      {:ok, events}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Returns most recent events globally, ordered by `captured_at` then `event_id` descending.

  Limit is capped to #{@max_limit}.
  """
  @spec recent(pos_integer()) :: {:ok, [event()]} | {:error, term()}
  def recent(limit) when is_integer(limit) and limit > 0 do
    with {:ok, index} <- ensure_loaded() do
      {:ok, Enum.take(index.recent_events, min(limit, @max_limit))}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  def recent(_), do: {:error, :invalid_limit}

  @doc false
  @spec clear_cache() :: :ok
  def clear_cache do
    with_load_lock(fn ->
      :persistent_term.erase(@cache_key)
      :ok
    end)
  end

  @doc false
  @spec reload() :: {:ok, :loaded} | {:error, term()}
  def reload do
    with_load_lock(fn ->
      with {:ok, signature} <- history_signature(),
           {:ok, index} <- load_index() do
        publish_index(signature, index)
        {:ok, :loaded}
      end
    end)
  end

  defp normalize_provider(provider) when is_atom(provider), do: {:ok, Atom.to_string(provider)}

  defp normalize_provider(provider) when is_binary(provider) do
    trimmed = String.trim(provider)

    if trimmed == "" do
      {:error, :bad_provider}
    else
      {:ok, trimmed}
    end
  end

  defp normalize_provider(_), do: {:error, :bad_provider}

  defp ensure_loaded do
    with {:ok, signature} <- history_signature() do
      case cached_index(signature) do
        {:ok, index} ->
          {:ok, index}

        :stale ->
          with_load_lock(fn -> load_and_publish_if_stale(signature) end)
      end
    end
  end

  defp with_load_lock(fun), do: :global.trans(@load_lock, fun)

  defp cached_index(signature) do
    case :persistent_term.get(@cache_key, :missing) do
      %{signature: ^signature, index: index} -> {:ok, index}
      _other -> :stale
    end
  end

  defp load_and_publish_if_stale(signature) do
    case cached_index(signature) do
      {:ok, index} ->
        {:ok, index}

      :stale ->
        with {:ok, index} <- load_index() do
          publish_index(signature, index)
          {:ok, index}
        end
    end
  end

  defp publish_index(signature, index) do
    :persistent_term.put(@cache_key, %{signature: signature, index: index})
  end

  defp load_index do
    history_dir = history_dir()
    meta_path = Path.join(history_dir, "meta.json")

    with {:ok, meta_json} <- File.read(meta_path),
         {:ok, meta} <- Jason.decode(meta_json) do
      event_paths =
        history_dir
        |> Path.join("events/*.ndjson")
        |> Path.wildcard()
        |> Enum.sort()

      reduced =
        Enum.reduce(
          event_paths,
          %{model: %{}, lineage: %{}, lineage_by_model: %{}, recent: []},
          fn path, acc ->
            File.stream!(path)
            |> Enum.reduce(acc, fn line, inner_acc ->
              case Jason.decode(line) do
                {:ok, event} ->
                  normalized = normalize_event(event)
                  model_key = normalized["model_key"]
                  lineage_key = normalized["lineage_key"]

                  %{
                    model:
                      Map.update(inner_acc.model, model_key, [normalized], fn events ->
                        [normalized | events]
                      end),
                    lineage:
                      Map.update(inner_acc.lineage, lineage_key, [normalized], fn events ->
                        [normalized | events]
                      end),
                    lineage_by_model: Map.put(inner_acc.lineage_by_model, model_key, lineage_key),
                    recent: [normalized | inner_acc.recent]
                  }

                _ ->
                  inner_acc
              end
            end)
          end
        )

      model_index =
        Map.new(reduced.model, fn {model_key, events} ->
          {model_key, events |> Enum.reverse() |> sort_events_asc()}
        end)

      lineage_index =
        Map.new(reduced.lineage, fn {lineage_key, events} ->
          {lineage_key, events |> Enum.reverse() |> sort_events_asc()}
        end)

      lineage_by_model =
        Map.new(model_index, fn {model_key, events} ->
          last_event = List.last(events) || %{}
          {model_key, Map.get(last_event, "lineage_key", model_key)}
        end)

      recent_events =
        reduced.recent
        |> sort_events_desc()

      {:ok,
       %{
         meta: meta,
         model_index: model_index,
         lineage_index: lineage_index,
         lineage_by_model: lineage_by_model,
         recent_events: recent_events
       }}
    else
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp normalize_event(event) do
    model_key =
      Map.get(event, "model_key") ||
        [Map.get(event, "provider"), Map.get(event, "model_id")]
        |> Enum.filter(&is_binary/1)
        |> Enum.join(":")

    lineage_key = Map.get(event, "lineage_key") || model_key

    event
    |> Map.put("model_key", model_key)
    |> Map.put("lineage_key", lineage_key)
  end

  defp sort_events_asc(events) do
    Enum.sort_by(events, fn event ->
      {Map.get(event, "captured_at", ""), Map.get(event, "event_id", "")}
    end)
  end

  defp sort_events_desc(events) do
    Enum.sort_by(
      events,
      fn event ->
        {Map.get(event, "captured_at", ""), Map.get(event, "event_id", "")}
      end,
      :desc
    )
  end

  defp history_signature do
    history_dir = history_dir()
    meta_path = Path.join(history_dir, "meta.json")

    with true <- File.exists?(meta_path),
         {:ok, meta_stat} <- File.stat(meta_path) do
      event_stats =
        history_dir
        |> Path.join("events/*.ndjson")
        |> Path.wildcard()
        |> Enum.sort()
        |> Enum.map(fn path ->
          case File.stat(path) do
            {:ok, stat} -> {path, stat.size, stat.mtime}
            _ -> {path, 0, nil}
          end
        end)

      snapshots_path = Path.join(history_dir, "snapshots.ndjson")

      snapshots_stat =
        case File.stat(snapshots_path) do
          {:ok, stat} -> {stat.size, stat.mtime}
          _ -> {0, nil}
        end

      {:ok, {history_dir, meta_stat.size, meta_stat.mtime, snapshots_stat, event_stats}}
    else
      false -> {:error, :history_unavailable}
      {:error, reason} -> {:error, reason}
    end
  end

  defp history_dir do
    Application.get_env(
      :llm_db,
      :history_dir,
      Application.app_dir(:llm_db, "priv/llm_db/history")
    )
  end
end
