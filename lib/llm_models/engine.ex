defmodule LLMModels.Engine do
  @moduledoc """
  Orchestrates the complete ETL pipeline for LLM model catalog generation.

  The engine coordinates data ingestion, normalization, validation, merging,
  enrichment, filtering, and indexing to produce a comprehensive model snapshot.
  """

  require Logger

  alias LLMModels.{Config, Packaged, Normalize, Validate, Merge, Enrich}

  @doc """
  Runs the complete ETL pipeline to generate a model catalog snapshot.

  ## Pipeline Stages

  1. **Ingest** - Collect data from sources in precedence order
  2. **Normalize** - Apply normalization to providers and models
  3. **Validate** - Validate schemas and log dropped records
  4. **Merge** - Combine sources with precedence rules
  5. **Enrich** - Add derived fields and defaults
  6. **Filter** - Apply allow/deny patterns
  7. **Index** - Build lookup indexes
  8. **Ensure viable** - Verify catalog has content

  ## Options

  - `:config` - Config map override (optional)

  ## Returns

  - `{:ok, snapshot_map}` - Success with indexed snapshot
  - `{:error, :empty_catalog}` - No providers or models in final catalog
  - `{:error, term}` - Other error

  ## Snapshot Structure

  ```elixir
  %{
    providers_by_id: %{atom => Provider.t()},
    models_by_key: %{{atom, String.t()} => Model.t()},
    aliases_by_key: %{{atom, String.t()} => String.t()},
    providers: [Provider.t()],
    models: %{atom => [Model.t()]},
    filters: %{allow: compiled, deny: compiled},
    prefer: [atom],
    meta: %{epoch: nil, generated_at: String.t()}
  }
  ```
  """
  @spec run(keyword()) :: {:ok, map()} | {:error, term()}
  def run(opts \\ []) do
    with {:ok, sources} <- ingest(opts),
         {:ok, normalized} <- normalize(sources),
         {:ok, validated} <- validate(normalized),
         {:ok, merged} <- merge(validated),
         {:ok, enriched} <- enrich(merged),
         {:ok, filtered} <- filter(enriched),
         {:ok, snapshot} <- build_snapshot(filtered),
         :ok <- ensure_viable(snapshot) do
      {:ok, snapshot}
    end
  end

  # Stage 1: Ingest
  defp ingest(opts) do
    config = Keyword.get(opts, :config) || Config.get()

    packaged = Packaged.snapshot() || %{providers: [], models: []}

    config_overrides = config.overrides

    behaviour_overrides =
      if config.overrides_module do
        Config.get_overrides_from_module(config.overrides_module)
      else
        %{providers: [], models: [], excludes: %{}}
      end

    sources = %{
      packaged: %{
        providers: Map.get(packaged, :providers, []),
        models: Map.get(packaged, :models, []),
        excludes: %{}
      },
      config: %{
        providers: config_overrides.providers,
        models: config_overrides.models,
        excludes: config_overrides.exclude
      },
      behaviour: %{
        providers: behaviour_overrides.providers,
        models: behaviour_overrides.models,
        excludes: behaviour_overrides.excludes
      },
      filters: %{
        allow: config.allow,
        deny: config.deny
      },
      prefer: config.prefer
    }

    {:ok, sources}
  end

  # Stage 2: Normalize
  defp normalize(sources) do
    normalized = %{
      packaged: %{
        providers: Normalize.normalize_providers(sources.packaged.providers),
        models: Normalize.normalize_models(sources.packaged.models),
        excludes: sources.packaged.excludes
      },
      config: %{
        providers: Normalize.normalize_providers(sources.config.providers),
        models: Normalize.normalize_models(sources.config.models),
        excludes: sources.config.excludes
      },
      behaviour: %{
        providers: Normalize.normalize_providers(sources.behaviour.providers),
        models: Normalize.normalize_models(sources.behaviour.models),
        excludes: sources.behaviour.excludes
      },
      filters: sources.filters,
      prefer: sources.prefer
    }

    {:ok, normalized}
  end

  # Stage 3: Validate
  defp validate(normalized) do
    {:ok, packaged_providers, packaged_providers_dropped} =
      Validate.validate_providers(normalized.packaged.providers)

    {:ok, packaged_models, packaged_models_dropped} =
      Validate.validate_models(normalized.packaged.models)

    {:ok, config_providers, config_providers_dropped} =
      Validate.validate_providers(normalized.config.providers)

    {:ok, config_models, config_models_dropped} =
      Validate.validate_models(normalized.config.models)

    {:ok, behaviour_providers, behaviour_providers_dropped} =
      Validate.validate_providers(normalized.behaviour.providers)

    {:ok, behaviour_models, behaviour_models_dropped} =
      Validate.validate_models(normalized.behaviour.models)

    log_validation_results(
      packaged_providers_dropped,
      packaged_models_dropped,
      config_providers_dropped,
      config_models_dropped,
      behaviour_providers_dropped,
      behaviour_models_dropped
    )

    validated = %{
      packaged: %{
        providers: packaged_providers,
        models: packaged_models,
        excludes: normalized.packaged.excludes
      },
      config: %{
        providers: config_providers,
        models: config_models,
        excludes: normalized.config.excludes
      },
      behaviour: %{
        providers: behaviour_providers,
        models: behaviour_models,
        excludes: normalized.behaviour.excludes
      },
      filters: normalized.filters,
      prefer: normalized.prefer
    }

    {:ok, validated}
  end

  # Stage 4: Merge
  defp merge(validated) do
    all_excludes =
      Map.merge(
        validated.packaged.excludes,
        Map.merge(validated.config.excludes, validated.behaviour.excludes, fn _k, _v1, v2 ->
          v2
        end),
        fn _k, _v1, v2 -> v2 end
      )

    providers =
      validated.packaged.providers
      |> Merge.merge_providers(validated.config.providers)
      |> Merge.merge_providers(validated.behaviour.providers)

    models =
      validated.packaged.models
      |> Merge.merge_models(validated.config.models, all_excludes)
      |> Merge.merge_models(validated.behaviour.models, all_excludes)

    merged = %{
      providers: providers,
      models: models,
      filters: validated.filters,
      prefer: validated.prefer
    }

    {:ok, merged}
  end

  # Stage 5: Enrich
  defp enrich(merged) do
    enriched = %{
      providers: merged.providers,
      models: Enrich.enrich_models(merged.models),
      filters: merged.filters,
      prefer: merged.prefer
    }

    {:ok, enriched}
  end

  # Stage 6: Filter
  defp filter(enriched) do
    compiled_filters = Config.compile_filters(enriched.filters.allow, enriched.filters.deny)

    filtered_models = apply_filters(enriched.models, compiled_filters)

    filtered = %{
      providers: enriched.providers,
      models: filtered_models,
      filters: compiled_filters,
      prefer: enriched.prefer
    }

    {:ok, filtered}
  end

  # Stage 7: Build snapshot
  defp build_snapshot(filtered) do
    indexes = build_indexes(filtered.providers, filtered.models)

    snapshot = %{
      providers_by_id: indexes.providers_by_id,
      models_by_key: indexes.models_by_key,
      aliases_by_key: indexes.aliases_by_key,
      providers: filtered.providers,
      models: indexes.models_by_provider,
      filters: filtered.filters,
      prefer: filtered.prefer,
      meta: %{
        epoch: nil,
        generated_at: DateTime.utc_now() |> DateTime.to_iso8601()
      }
    }

    {:ok, snapshot}
  end

  # Stage 8: Ensure viable
  defp ensure_viable(snapshot) do
    Validate.ensure_viable(snapshot.providers, Map.values(snapshot.models) |> List.flatten())
  end

  @doc """
  Builds lookup indexes for providers, models, and aliases.

  ## Returns

  A map with:
  - `:providers_by_id` - %{atom => Provider.t()}
  - `:models_by_key` - %{{atom, String.t()} => Model.t()}
  - `:models_by_provider` - %{atom => [Model.t()]}
  - `:aliases_by_key` - %{{atom, String.t()} => String.t()}
  """
  @spec build_indexes([map()], [map()]) :: map()
  def build_indexes(providers, models) do
    providers_by_id = Map.new(providers, fn p -> {p.id, p} end)

    models_by_key = Map.new(models, fn m -> {{m.provider, m.id}, m} end)

    models_by_provider =
      Enum.group_by(models, & &1.provider)
      |> Map.new(fn {provider, models_list} -> {provider, models_list} end)

    aliases_by_key = build_aliases_index(models)

    %{
      providers_by_id: providers_by_id,
      models_by_key: models_by_key,
      models_by_provider: models_by_provider,
      aliases_by_key: aliases_by_key
    }
  end

  @doc """
  Applies allow/deny filters to models.

  Deny patterns always win over allow patterns.

  ## Parameters

  - `models` - List of model maps
  - `filters` - %{allow: compiled_patterns, deny: compiled_patterns}

  ## Returns

  Filtered list of models
  """
  @spec apply_filters([map()], map()) :: [map()]
  def apply_filters(models, %{allow: allow, deny: deny}) do
    models
    |> Enum.filter(fn model ->
      provider = model.provider
      model_id = model.id

      # Deny wins - check first
      deny_patterns = Map.get(deny, provider, [])

      if matches_patterns?(model_id, deny_patterns) do
        false
      else
        # Then check allow
        case allow do
          :all ->
            true

          allow_map when is_map(allow_map) ->
            allow_patterns = Map.get(allow_map, provider, [])

            if map_size(allow_map) > 0 and allow_patterns == [] do
              false
            else
              allow_patterns == [] or matches_patterns?(model_id, allow_patterns)
            end
        end
      end
    end)
  end

  @doc """
  Builds an alias index mapping {provider, alias} to canonical model ID.

  ## Parameters

  - `models` - List of model maps

  ## Returns

  %{{provider_atom, alias_string} => canonical_id_string}
  """
  @spec build_aliases_index([map()]) :: %{{atom(), String.t()} => String.t()}
  def build_aliases_index(models) do
    models
    |> Enum.flat_map(fn model ->
      provider = model.provider
      canonical_id = model.id
      aliases = Map.get(model, :aliases, [])

      Enum.map(aliases, fn alias_name ->
        {{provider, alias_name}, canonical_id}
      end)
    end)
    |> Map.new()
  end

  # Private helpers

  defp matches_patterns?(_model_id, []), do: false

  defp matches_patterns?(model_id, patterns) when is_binary(model_id) do
    Enum.any?(patterns, fn
      %Regex{} = pattern -> Regex.match?(pattern, model_id)
      pattern when is_binary(pattern) -> model_id == pattern
    end)
  end

  defp log_validation_results(
         packaged_providers_dropped,
         packaged_models_dropped,
         config_providers_dropped,
         config_models_dropped,
         behaviour_providers_dropped,
         behaviour_models_dropped
       ) do
    if packaged_providers_dropped > 0 do
      Logger.warning(
        "Dropped #{packaged_providers_dropped} invalid provider(s) from packaged source"
      )
    end

    if packaged_models_dropped > 0 do
      Logger.warning("Dropped #{packaged_models_dropped} invalid model(s) from packaged source")
    end

    if config_providers_dropped > 0 do
      Logger.warning("Dropped #{config_providers_dropped} invalid provider(s) from config source")
    end

    if config_models_dropped > 0 do
      Logger.warning("Dropped #{config_models_dropped} invalid model(s) from config source")
    end

    if behaviour_providers_dropped > 0 do
      Logger.warning(
        "Dropped #{behaviour_providers_dropped} invalid provider(s) from behaviour source"
      )
    end

    if behaviour_models_dropped > 0 do
      Logger.warning("Dropped #{behaviour_models_dropped} invalid model(s) from behaviour source")
    end
  end
end
