defmodule LLMDB.Snapshot.Sparse do
  @moduledoc false

  # Sparse snapshot fields are deliberately enumerated. Unknown keys and every
  # value below provider/model scope pass through untouched.
  @provider_defaults %{
    "alias_of" => nil,
    "base_url" => nil,
    "catalog_only" => false,
    "config_schema" => nil,
    "doc" => nil,
    "env" => nil,
    "exclude_models" => [],
    "extra" => nil,
    "name" => nil,
    "pricing_defaults" => nil,
    "runtime" => nil
  }

  @model_defaults %{
    "aliases" => [],
    "base_url" => nil,
    "capabilities" => nil,
    "catalog_only" => false,
    "cost" => nil,
    "deprecated" => false,
    "doc_url" => nil,
    "execution" => nil,
    "extra" => nil,
    "family" => nil,
    "knowledge" => nil,
    "last_updated" => nil,
    "lifecycle" => nil,
    "limits" => nil,
    "modalities" => nil,
    "model" => nil,
    "name" => nil,
    "pricing" => nil,
    "provider_model_id" => nil,
    "release_date" => nil,
    "retired" => false,
    "tags" => nil
  }

  @spec encode(map()) :: map()
  def encode(snapshot) when is_map(snapshot) do
    update_providers(snapshot, fn provider ->
      provider
      |> update_models(&drop_defaults(&1, @model_defaults))
      |> drop_defaults(@provider_defaults)
    end)
  end

  @spec expand(map()) :: map()
  def expand(snapshot) when is_map(snapshot) do
    update_providers(snapshot, fn provider ->
      @provider_defaults
      |> Map.merge(provider)
      |> update_models(fn model ->
        Map.merge(@model_defaults, model)
      end)
    end)
  end

  defp update_providers(%{"providers" => providers} = snapshot, fun)
       when is_map(providers) do
    updated =
      Map.new(providers, fn {provider_id, provider} ->
        {provider_id, update_map(provider, fun)}
      end)

    Map.put(snapshot, "providers", updated)
  end

  defp update_providers(snapshot, _fun), do: snapshot

  defp update_models(%{"models" => models} = provider, fun) when is_map(models) do
    updated = Map.new(models, fn {model_id, model} -> {model_id, update_map(model, fun)} end)
    Map.put(provider, "models", updated)
  end

  defp update_models(provider, _fun), do: provider

  defp update_map(value, fun) when is_map(value), do: fun.(value)
  defp update_map(value, _fun), do: value

  defp drop_defaults(document, defaults) do
    Enum.reduce(defaults, document, fn {key, default}, acc ->
      case Map.fetch(acc, key) do
        {:ok, ^default} -> Map.delete(acc, key)
        _other -> acc
      end
    end)
  end
end
