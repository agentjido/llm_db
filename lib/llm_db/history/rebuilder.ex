defmodule LLMDB.History.Rebuilder do
  @moduledoc """
  Rebuilds snapshot-based history artifacts from an ordered snapshot observation chain.

  The observation chain is typically sourced from `snapshot-index.json` and contains
  entries keyed by immutable `snapshot_id`, with optional provenance such as
  `captured_at`, `source_commit`, and `parent_snapshot_id`.

  Direct use is documentation-deprecated in favor of
  `mix llm_db.history.rebuild`.
  """

  alias LLMDB.{History.Diff, History.Lineage, Snapshot}

  @lineage_overrides_file "lineage_overrides.json"
  @type observation :: map()

  @type summary :: %{
          snapshots_written: non_neg_integer(),
          unique_snapshots_written: non_neg_integer(),
          events_written: non_neg_integer(),
          output_dir: String.t(),
          snapshot_index_path: String.t(),
          latest_path: String.t(),
          from_snapshot_id: String.t() | nil,
          to_snapshot_id: String.t() | nil
        }

  @spec rebuild(keyword()) :: {:ok, summary()} | {:error, term()}
  def rebuild(opts) when is_list(opts) do
    observations =
      opts
      |> Keyword.get(:observations, [])
      |> Enum.map(&stringify_observation/1)

    snapshot_loader = Keyword.fetch!(opts, :snapshot_loader)
    output_dir = output_dir(opts)
    snapshot_index_path = snapshot_index_path(opts, output_dir)
    latest_path = latest_path(opts, output_dir)
    source = Keyword.get(opts, :source)

    with :ok <- validate_observations(observations),
         :ok <- prepare_output_dir(output_dir),
         {:ok, lineage_overrides} <- load_lineage_overrides(output_dir),
         {:ok, result} <- rebuild_records(observations, snapshot_loader, lineage_overrides),
         :ok <-
           write_outputs(
             output_dir,
             snapshot_index_path,
             latest_path,
             observations,
             result,
             source
           ) do
      {:ok,
       %{
         snapshots_written: length(observations),
         unique_snapshots_written:
           observations |> Enum.map(& &1["snapshot_id"]) |> MapSet.new() |> MapSet.size(),
         events_written: result.events_written,
         output_dir: output_dir,
         snapshot_index_path: snapshot_index_path,
         latest_path: latest_path,
         from_snapshot_id: observations |> List.first() |> snapshot_id_from_observation(),
         to_snapshot_id: observations |> List.last() |> snapshot_id_from_observation()
       }}
    end
  end

  defp rebuild_records(observations, snapshot_loader, lineage_overrides) do
    initial = %{
      previous_models: %{},
      previous_lineage_by_key: %{},
      snapshot_records: [],
      events_by_year: %{},
      events_written: 0
    }

    result =
      observations
      |> Enum.with_index(1)
      |> Enum.reduce_while(initial, fn {observation, observation_idx}, acc ->
        case snapshot_loader.(observation["snapshot_id"]) do
          {:ok, snapshot} ->
            current_models = flatten_snapshot_models(snapshot)

            {events, current_lineage_by_key} =
              case acc.snapshot_records do
                [] ->
                  current_lineage_by_key = Lineage.initialize(current_models, lineage_overrides)

                  events =
                    Diff.models(%{}, current_models)
                    |> Lineage.attach(%{}, current_lineage_by_key)

                  {events, current_lineage_by_key}

                _ ->
                  current_lineage_by_key =
                    Lineage.resolve(
                      acc.previous_models,
                      current_models,
                      acc.previous_lineage_by_key,
                      lineage_overrides
                    )

                  events =
                    Diff.models(acc.previous_models, current_models)
                    |> Lineage.attach(acc.previous_lineage_by_key, current_lineage_by_key)

                  {events, current_lineage_by_key}
              end

            counts = Snapshot.counts(snapshot)
            captured_at = observation["captured_at"] || snapshot["generated_at"]

            snapshot_record =
              %{
                "schema_version" => Snapshot.schema_version(),
                "snapshot_id" => observation["snapshot_id"],
                "source_commit" => observation["source_commit"],
                "captured_at" => captured_at,
                "manifest_generated_at" => observation["manifest_generated_at"],
                "parent_snapshot_id" => observation["parent_snapshot_id"],
                "provider_count" => observation["provider_count"] || counts.provider_count,
                "model_count" => observation["model_count"] || map_size(current_models),
                "digest" => Diff.snapshot_digest(current_models),
                "event_count" => length(events)
              }
              |> compact_nils()

            events_by_year =
              Enum.with_index(events, 1)
              |> Enum.reduce(acc.events_by_year, fn {event, event_idx}, inner_acc ->
                year = captured_at |> to_string() |> String.slice(0, 4)

                record =
                  %{
                    "schema_version" => Snapshot.schema_version(),
                    "event_id" => event_id(observation, observation_idx, event_idx),
                    "snapshot_id" => observation["snapshot_id"],
                    "source_commit" => observation["source_commit"],
                    "captured_at" => captured_at,
                    "type" => event.type,
                    "model_key" => event.model_key,
                    "lineage_key" => Map.get(event, :lineage_key, event.model_key),
                    "provider" => provider_from_model_key(event.model_key),
                    "model_id" => model_id_from_model_key(event.model_key),
                    "changes" => event.changes
                  }
                  |> compact_nils()

                Map.update(inner_acc, year, [record], &[record | &1])
              end)

            {:cont,
             %{
               previous_models: current_models,
               previous_lineage_by_key: current_lineage_by_key,
               snapshot_records: [snapshot_record | acc.snapshot_records],
               events_by_year: events_by_year,
               events_written: acc.events_written + length(events)
             }}

          {:error, reason} ->
            {:halt, {:error, {observation["snapshot_id"], reason}}}
        end
      end)

    case result do
      {:error, _reason} = error ->
        error

      state ->
        {:ok,
         %{
           snapshot_records: Enum.reverse(state.snapshot_records),
           events_by_year:
             Map.new(state.events_by_year, fn {year, records} ->
               {year, Enum.reverse(records)}
             end),
           events_written: state.events_written
         }}
    end
  end

  defp write_outputs(output_dir, snapshot_index_path, latest_path, observations, result, source) do
    write_ndjson(Path.join(output_dir, "snapshots.ndjson"), result.snapshot_records)

    Enum.each(result.events_by_year, fn {year, records} ->
      write_ndjson(Path.join([output_dir, "events", "#{year}.ndjson"]), records)
    end)

    Snapshot.write!(snapshot_index_path, %{
      "schema_version" => Snapshot.schema_version(),
      "snapshots" => observations
    })

    case List.last(observations) do
      nil -> :ok
      latest -> Snapshot.write!(latest_path, latest)
    end

    Snapshot.write!(Path.join(output_dir, "meta.json"), %{
      "schema_version" => Snapshot.schema_version(),
      "generated_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "source" => source,
      "snapshots_written" => length(observations),
      "unique_snapshots_written" =>
        observations |> Enum.map(& &1["snapshot_id"]) |> MapSet.new() |> MapSet.size(),
      "events_written" => result.events_written,
      "event_count" => result.events_written,
      "from_snapshot_id" => observations |> List.first() |> snapshot_id_from_observation(),
      "to_snapshot_id" => observations |> List.last() |> snapshot_id_from_observation(),
      "snapshot_index_path" => snapshot_index_path
    })
  end

  defp flatten_snapshot_models(%{"providers" => providers}) when is_map(providers) do
    providers
    |> Enum.sort_by(fn {provider_id, _provider} -> to_string(provider_id) end)
    |> Enum.reduce(%{}, fn {provider_id, provider}, acc ->
      provider_id = provider["id"] || provider[:id] || to_string(provider_id)

      provider
      |> Map.get("models", provider[:models] || %{})
      |> Enum.sort_by(fn {model_id, _model} -> to_string(model_id) end)
      |> Enum.reduce(acc, fn {model_id, model}, inner_acc ->
        model_id = to_string(model_id)

        normalized =
          model
          |> stringify_map()
          |> Map.put_new("id", model_id)
          |> Map.put_new("provider", provider_id)
          |> Diff.normalize()

        Map.put(inner_acc, "#{provider_id}:#{model_id}", normalized)
      end)
    end)
  end

  defp flatten_snapshot_models(_), do: %{}

  defp load_lineage_overrides(output_dir) do
    path = Path.join(output_dir, @lineage_overrides_file)

    if not File.exists?(path) do
      {:ok, %{}}
    else
      with {:ok, content} <- File.read(path),
           {:ok, decoded} <- Jason.decode(content),
           {:ok, overrides} <- parse_lineage_overrides(decoded) do
        {:ok, overrides}
      else
        {:error, reason} ->
          {:error, "invalid lineage overrides at #{path}: #{inspect(reason)}"}
      end
    end
  end

  defp parse_lineage_overrides(%{"lineage" => lineage}) when is_map(lineage),
    do: validate_lineage_overrides(lineage)

  defp parse_lineage_overrides(map) when is_map(map), do: validate_lineage_overrides(map)
  defp parse_lineage_overrides(_), do: {:error, :invalid_format}

  defp validate_lineage_overrides(lineage_overrides) do
    Enum.reduce_while(lineage_overrides, {:ok, %{}}, fn {from, to}, {:ok, acc} ->
      if is_binary(from) and is_binary(to) do
        {:cont, {:ok, Map.put(acc, from, to)}}
      else
        {:halt, {:error, :non_string_keys_or_values}}
      end
    end)
  end

  defp provider_from_model_key(model_key) do
    model_key
    |> String.split(":", parts: 2)
    |> List.first()
  end

  defp model_id_from_model_key(model_key) do
    case String.split(model_key, ":", parts: 2) do
      [_provider, model_id] -> model_id
      _ -> model_key
    end
  end

  defp event_id(observation, observation_idx, event_idx) do
    observation_key =
      observation["source_commit"] ||
        observation["captured_at"] ||
        Integer.to_string(observation_idx)

    "#{observation["snapshot_id"]}:#{observation_key}:#{event_idx}"
  end

  defp stringify_observation(observation) when is_map(observation), do: stringify_map(observation)

  defp stringify_map(map) when is_map(map) do
    map
    |> Enum.map(fn {key, value} ->
      {
        to_string(key),
        cond do
          is_map(value) -> stringify_map(value)
          is_list(value) -> Enum.map(value, &stringify_nested/1)
          true -> value
        end
      }
    end)
    |> Map.new()
  end

  defp stringify_nested(value) when is_map(value), do: stringify_map(value)
  defp stringify_nested(value), do: value

  defp validate_observations([]), do: {:error, :no_snapshots}

  defp validate_observations(observations) do
    case Enum.find(observations, &(not is_binary(&1["snapshot_id"]))) do
      nil -> :ok
      invalid -> {:error, {:invalid_observation, invalid}}
    end
  end

  defp prepare_output_dir(output_dir) do
    File.rm_rf!(Path.join(output_dir, "events"))
    File.rm_rf!(Path.join(output_dir, "snapshots.ndjson"))
    File.rm_rf!(Path.join(output_dir, "meta.json"))
    File.rm_rf!(Path.join(output_dir, Snapshot.snapshot_index_filename()))
    File.rm_rf!(Path.join(output_dir, Snapshot.latest_filename()))
    File.mkdir_p!(Path.join(output_dir, "events"))
    :ok
  end

  defp write_ndjson(path, records) do
    path
    |> Path.dirname()
    |> File.mkdir_p!()

    lines =
      records
      |> Enum.map(&Jason.encode!/1)
      |> Enum.join("\n")

    File.write!(path, lines <> if(lines == "", do: "", else: "\n"))
  end

  defp compact_nils(map) do
    map
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp output_dir(opts) do
    opts
    |> Keyword.get(:output_dir, "priv/llm_db/history")
    |> expand_path()
  end

  defp snapshot_index_path(opts, output_dir) do
    opts
    |> Keyword.get(
      :snapshot_index_path,
      Path.join(output_dir, Snapshot.snapshot_index_filename())
    )
    |> expand_path()
  end

  defp latest_path(opts, output_dir) do
    opts
    |> Keyword.get(:latest_path, Path.join(output_dir, Snapshot.latest_filename()))
    |> expand_path()
  end

  defp snapshot_id_from_observation(nil), do: nil
  defp snapshot_id_from_observation(observation), do: observation["snapshot_id"]

  defp expand_path(path) when is_binary(path) do
    if Path.type(path) == :absolute do
      path
    else
      Path.expand(path)
    end
  end
end
