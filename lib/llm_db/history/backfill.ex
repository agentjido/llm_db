defmodule LLMDB.History.Backfill do
  @moduledoc """
  Backfills model history by diffing committed provider snapshots across git history.

  This module is intentionally git-driven and infrastructure-free: it reads
  `priv/llm_db/providers/*.json` from commit history and writes append-only
  NDJSON event files under a local history directory.
  """

  @providers_dir "priv/llm_db/providers"
  @manifest_path "priv/llm_db/manifest.json"

  @sortable_list_keys MapSet.new(["aliases", "tags", "input", "output"])

  @type summary :: %{
          commits_scanned: non_neg_integer(),
          commits_processed: non_neg_integer(),
          snapshots_written: non_neg_integer(),
          events_written: non_neg_integer(),
          output_dir: String.t(),
          from_commit: String.t() | nil,
          to_commit: String.t() | nil
        }

  @doc """
  Runs a full history backfill from git.

  ## Options

  - `:from` - Optional start commit (inclusive)
  - `:to` - Optional end commit/reference (default: `"HEAD"`)
  - `:output_dir` - Output directory (default: `"history"`)
  - `:force` - Remove previously generated history files first (default: `false`)
  """
  @spec run(keyword()) :: {:ok, summary()} | {:error, term()}
  def run(opts \\ []) do
    output_dir = Keyword.get(opts, :output_dir, "history")
    force? = Keyword.get(opts, :force, false)
    from_ref = Keyword.get(opts, :from)
    to_ref = Keyword.get(opts, :to, "HEAD")

    with :ok <- prepare_output_dir(output_dir, force?),
         {:ok, commits} <- history_commits(from_ref, to_ref),
         {:ok, summary} <- process_commits(commits, output_dir) do
      {:ok, summary}
    end
  end

  @doc """
  Diffs two model maps and returns deterministic model events.

  Expects maps keyed by `"provider:model_id"` with normalized model payload values.
  """
  @spec diff_models(%{optional(String.t()) => map()}, %{optional(String.t()) => map()}) :: [map()]
  def diff_models(previous_models, current_models)
      when is_map(previous_models) and is_map(current_models) do
    previous_keys = Map.keys(previous_models) |> MapSet.new()
    current_keys = Map.keys(current_models) |> MapSet.new()

    introduced =
      MapSet.difference(current_keys, previous_keys)
      |> MapSet.to_list()
      |> Enum.sort()
      |> Enum.map(fn model_key ->
        %{type: "introduced", model_key: model_key, changes: []}
      end)

    removed =
      MapSet.difference(previous_keys, current_keys)
      |> MapSet.to_list()
      |> Enum.sort()
      |> Enum.map(fn model_key ->
        %{type: "removed", model_key: model_key, changes: []}
      end)

    changed =
      MapSet.intersection(previous_keys, current_keys)
      |> MapSet.to_list()
      |> Enum.sort()
      |> Enum.reduce([], fn model_key, acc ->
        before_model = Map.fetch!(previous_models, model_key)
        after_model = Map.fetch!(current_models, model_key)
        changes = deep_changes(before_model, after_model, [])

        if changes == [] do
          acc
        else
          [%{type: "changed", model_key: model_key, changes: changes} | acc]
        end
      end)
      |> Enum.reverse()

    introduced ++ removed ++ changed
  end

  # Internal pipeline

  defp prepare_output_dir(output_dir, force?) do
    events_dir = Path.join(output_dir, "events")
    meta_path = Path.join(output_dir, "meta.json")
    snapshots_path = Path.join(output_dir, "snapshots.ndjson")

    if force? do
      File.rm_rf!(events_dir)
      File.rm_rf!(meta_path)
      File.rm_rf!(snapshots_path)
    end

    if not force? and
         (File.exists?(events_dir) or File.exists?(meta_path) or File.exists?(snapshots_path)) do
      {:error,
       "history output already exists at #{output_dir}. Re-run with --force for one-time regeneration."}
    else
      File.mkdir_p!(events_dir)
      :ok
    end
  end

  defp history_commits(from_ref, to_ref) do
    with {:ok, commits_output} <-
           git([
             "rev-list",
             "--reverse",
             "--topo-order",
             to_ref,
             "--",
             @providers_dir,
             @manifest_path
           ]),
         commits <- parse_lines(commits_output),
         {:ok, commits} <- maybe_apply_from(commits, from_ref) do
      {:ok, commits}
    end
  end

  defp maybe_apply_from(commits, nil), do: {:ok, commits}

  defp maybe_apply_from(commits, from_ref) do
    with {:ok, from_sha} <- git(["rev-parse", "--verify", from_ref]),
         from_sha <- String.trim(from_sha),
         true <- from_sha in commits do
      commits
      |> Enum.drop_while(&(&1 != from_sha))
      |> then(&{:ok, &1})
    else
      {:error, reason} ->
        {:error, reason}

      false ->
        {:error, "from commit #{from_ref} is not in the metadata history range"}
    end
  end

  defp process_commits(commits, output_dir) do
    initial = %{
      commits_scanned: length(commits),
      commits_processed: 0,
      snapshots_written: 0,
      events_written: 0,
      output_dir: output_dir,
      from_commit: nil,
      to_commit: nil,
      state_by_file: nil,
      previous_models: nil,
      previous_sha: nil
    }

    final =
      Enum.reduce(commits, initial, fn sha, acc ->
        process_commit(sha, acc)
      end)

    summary =
      final
      |> Map.drop([:state_by_file, :previous_models, :previous_sha])
      |> Map.put(:generated_at, DateTime.utc_now() |> DateTime.to_iso8601())
      |> Map.put(:source_repo, source_repo())

    write_meta(summary, output_dir)
    {:ok, summary}
  rescue
    error ->
      {:error, Exception.message(error)}
  end

  defp process_commit(sha, acc) do
    case acc.state_by_file do
      nil ->
        first_commit_state(sha, acc)

      state_by_file ->
        incremental_commit_state(sha, state_by_file, acc)
    end
  end

  defp first_commit_state(sha, acc) do
    case load_commit_state(sha) do
      {:ok, state_by_file} when map_size(state_by_file) == 0 ->
        acc

      {:ok, state_by_file} ->
        models = flatten_state_models(state_by_file)
        events = diff_models(%{}, models)
        commit_date = commit_date_iso8601(sha)
        manifest_generated_at = manifest_generated_at(sha)

        write_snapshot(sha, commit_date, manifest_generated_at, models, events, acc.output_dir)
        write_events(sha, commit_date, events, acc.output_dir)

        %{
          acc
          | commits_processed: acc.commits_processed + 1,
            snapshots_written: acc.snapshots_written + 1,
            events_written: acc.events_written + length(events),
            from_commit: sha,
            to_commit: sha,
            state_by_file: state_by_file,
            previous_models: models,
            previous_sha: sha
        }

      {:error, _} ->
        acc
    end
  end

  defp incremental_commit_state(sha, state_by_file, acc) do
    {:ok, next_state_by_file} = apply_commit_delta(acc.previous_sha, sha, state_by_file)

    previous_models = acc.previous_models || %{}
    current_models = flatten_state_models(next_state_by_file)
    events = diff_models(previous_models, current_models)

    if events == [] do
      %{
        acc
        | commits_processed: acc.commits_processed + 1,
          to_commit: sha,
          state_by_file: next_state_by_file,
          previous_models: current_models,
          previous_sha: sha
      }
    else
      commit_date = commit_date_iso8601(sha)
      manifest_generated_at = manifest_generated_at(sha)

      write_snapshot(
        sha,
        commit_date,
        manifest_generated_at,
        current_models,
        events,
        acc.output_dir
      )

      write_events(sha, commit_date, events, acc.output_dir)

      %{
        acc
        | commits_processed: acc.commits_processed + 1,
          snapshots_written: acc.snapshots_written + 1,
          events_written: acc.events_written + length(events),
          to_commit: sha,
          state_by_file: next_state_by_file,
          previous_models: current_models,
          previous_sha: sha
      }
    end
  end

  defp load_commit_state(sha) do
    with {:ok, files_output} <- git(["ls-tree", "-r", "--name-only", sha, "--", @providers_dir]) do
      files =
        files_output
        |> parse_lines()
        |> Enum.filter(&String.ends_with?(&1, ".json"))
        |> Enum.sort()

      state =
        Enum.reduce(files, %{}, fn path, acc ->
          case provider_models_for_path(sha, path) do
            {:ok, models} -> Map.put(acc, path, models)
            {:error, _} -> acc
          end
        end)

      {:ok, state}
    end
  end

  defp apply_commit_delta(previous_sha, current_sha, state_by_file) do
    with {:ok, diff_output} <-
           git([
             "diff",
             "--name-status",
             "--no-renames",
             previous_sha,
             current_sha,
             "--",
             @providers_dir
           ]) do
      next_state =
        diff_output
        |> parse_lines()
        |> Enum.reduce(state_by_file, fn line, acc ->
          case String.split(line, "\t", trim: true) do
            [status, path] when status in ["A", "M"] ->
              case provider_models_for_path(current_sha, path) do
                {:ok, models} -> Map.put(acc, path, models)
                {:error, _} -> acc
              end

            ["D", path] ->
              Map.delete(acc, path)

            _ ->
              acc
          end
        end)

      {:ok, next_state}
    end
  end

  defp provider_models_for_path(sha, path) do
    with {:ok, content} <- git(["show", "#{sha}:#{path}"]),
         {:ok, provider_data} <- Jason.decode(content) do
      provider_id = Map.get(provider_data, "id")
      models_map = Map.get(provider_data, "models", %{})

      if is_binary(provider_id) and is_map(models_map) do
        models =
          Enum.reduce(models_map, %{}, fn {model_id, model_data}, acc ->
            model =
              model_data
              |> Map.put_new("id", model_id)
              |> Map.put_new("provider", provider_id)
              |> normalize_value([])

            Map.put(acc, "#{provider_id}:#{model_id}", model)
          end)

        {:ok, models}
      else
        {:error, :invalid_provider_payload}
      end
    end
  end

  defp flatten_state_models(state_by_file) do
    Enum.reduce(state_by_file, %{}, fn {_path, models}, acc ->
      Map.merge(acc, models)
    end)
  end

  defp normalize_value(value, path)

  defp normalize_value(value, path) when is_map(value) do
    value
    |> Enum.map(fn {k, v} -> {k, normalize_value(v, [to_string(k) | path])} end)
    |> Map.new()
  end

  defp normalize_value(value, path) when is_list(value) do
    normalized = Enum.map(value, &normalize_value(&1, path))

    case path do
      [key | _] ->
        if key in @sortable_list_keys and Enum.all?(normalized, &scalar?/1) do
          Enum.sort(normalized)
        else
          normalized
        end

      _ ->
        normalized
    end
  end

  defp normalize_value(value, _path), do: value

  defp scalar?(value),
    do: is_binary(value) or is_number(value) or is_boolean(value) or is_nil(value)

  defp deep_changes(before_value, after_value, path)

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

  defp deep_changes(before_value, after_value, path)
       when is_list(before_value) and is_list(after_value) do
    if before_value == after_value do
      []
    else
      [%{path: Enum.join(path, "."), op: "replace", before: before_value, after: after_value}]
    end
  end

  defp deep_changes(before_value, after_value, path) do
    if before_value == after_value do
      []
    else
      [%{path: Enum.join(path, "."), op: "replace", before: before_value, after: after_value}]
    end
  end

  defp write_snapshot(sha, commit_date, manifest_generated_at, models, events, output_dir) do
    snapshot = %{
      schema_version: 1,
      snapshot_id: sha,
      source_commit: sha,
      captured_at: commit_date,
      manifest_generated_at: manifest_generated_at,
      model_count: map_size(models),
      digest: models_digest(models),
      event_count: length(events)
    }

    path = Path.join(output_dir, "snapshots.ndjson")
    append_ndjson(path, snapshot)
  end

  defp write_events(sha, commit_date, events, output_dir) do
    Enum.with_index(events, 1)
    |> Enum.each(fn {event, idx} ->
      year = String.slice(commit_date, 0, 4)
      path = Path.join([output_dir, "events", "#{year}.ndjson"])
      provider_model = String.split(event.model_key, ":", parts: 2)

      event_record = %{
        schema_version: 1,
        event_id: "#{sha}:#{idx}",
        snapshot_id: sha,
        source_commit: sha,
        captured_at: commit_date,
        type: event.type,
        model_key: event.model_key,
        provider: Enum.at(provider_model, 0),
        model_id: Enum.at(provider_model, 1),
        changes: event.changes
      }

      append_ndjson(path, event_record)
    end)
  end

  defp write_meta(summary, output_dir) do
    path = Path.join(output_dir, "meta.json")
    File.write!(path, Jason.encode!(summary, pretty: true))
  end

  defp append_ndjson(path, map) do
    line = Jason.encode!(map) <> "\n"
    File.write!(path, line, [:append])
  end

  defp models_digest(models) do
    models
    |> :erlang.term_to_binary()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp commit_date_iso8601(sha) do
    case git(["show", "-s", "--format=%cI", sha]) do
      {:ok, out} -> String.trim(out)
      {:error, _} -> DateTime.utc_now() |> DateTime.to_iso8601()
    end
  end

  defp manifest_generated_at(sha) do
    case git(["show", "#{sha}:#{@manifest_path}"]) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, manifest} -> Map.get(manifest, "generated_at")
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp source_repo do
    case git(["remote", "get-url", "origin"]) do
      {:ok, url} -> String.trim(url)
      _ -> nil
    end
  end

  defp parse_lines(output) do
    output
    |> String.split("\n", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp git(args) do
    case System.cmd("git", args, stderr_to_stdout: true) do
      {output, 0} -> {:ok, output}
      {output, _} -> {:error, String.trim(output)}
    end
  end
end
