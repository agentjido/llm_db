defmodule LLMDB.CatalogTest do
  use ExUnit.Case, async: false

  alias LLMDB.{Catalog, Model, Provider, Spec, Store}

  setup do
    Catalog.clear!()
    on_exit(&Catalog.clear!/0)
    :ok
  end

  test "builds the canonical indexes and retains snapshot identity" do
    catalog = catalog_fixture()

    assert catalog.providers_by_id.google_vertex.name == "Google Vertex"

    assert catalog.models_by_key[{:google_vertex_anthropic, "claude-model"}].name ==
             "Claude Model"

    assert catalog.aliases_by_key[{:google_vertex_anthropic, "claude-alias"}] ==
             "claude-model"

    assert catalog.meta.source_snapshot_id == "snapshot-123"
    assert catalog.meta.digest == "semantic-digest"
    assert catalog.meta.source_generated_at == "2026-07-16T00:00:00Z"
  end

  test "provider and model aliases share one map-based resolution path" do
    catalog = catalog_fixture()

    # Resolution continues from immutable indexes even if the presentation list
    # is absent, proving direct lookup does not scan providers.
    indexed_only = Map.put(catalog, :providers, [])

    assert {:ok, {:google_vertex, "claude-model", model}} =
             Catalog.resolve_model(indexed_only, :google_vertex, "claude-alias")

    assert model.id == "claude-model"
    assert model.provider == :google_vertex
  end

  test "Store and Spec compatibility facades resolve through Catalog" do
    catalog = catalog_fixture()
    Catalog.put!(catalog, source: :test)

    assert {:ok, store_model} = Store.model(:google_vertex, "claude-alias")

    assert {:ok, {:google_vertex, "claude-model", spec_model}} =
             Spec.resolve({:google_vertex, "claude-alias"})

    assert store_model == spec_model
    assert Catalog.last_opts() == [source: :test]
  end

  test "runtime views rebuild every model resolution index" do
    catalog = catalog_fixture()
    filtered = Catalog.with_runtime_view(catalog, [], %{allow: %{}, deny: %{}})

    assert {:error, :not_found} =
             Catalog.resolve_model(filtered, :google_vertex, "claude-alias")

    assert {:error, :not_found} = Catalog.resolve_bare(filtered, "claude-alias")
  end

  test "legacy string alias_of values resolve without creating provider atoms" do
    catalog =
      catalog_fixture()
      |> update_in([:providers], fn providers ->
        Enum.map(providers, fn provider ->
          if provider.id == :google_vertex_anthropic do
            provider |> Map.from_struct() |> Map.put(:alias_of, "google_vertex")
          else
            provider
          end
        end)
      end)
      |> Map.delete(:__llm_db_provider_lookup_ids__)

    assert {:ok, model} = Catalog.model(catalog, :google_vertex, "claude-alias")
    assert model.provider == :google_vertex
  end

  defp catalog_fixture do
    providers = [
      Provider.new!(%{id: :google_vertex, name: "Google Vertex"}),
      Provider.new!(%{id: :google_vertex_anthropic, name: "Vertex Anthropic"})
    ]

    model =
      Model.new!(%{
        id: "claude-model",
        provider: :google_vertex_anthropic,
        name: "Claude Model",
        aliases: ["claude-alias"]
      })

    Catalog.build(providers, [model], [model],
      filters: %{allow: :all, deny: %{}},
      prefer: [:google_vertex],
      source_generated_at: "2026-07-16T00:00:00Z",
      source_snapshot_id: "snapshot-123",
      loaded_at: "2026-07-16T00:01:00Z",
      digest: "semantic-digest"
    )
  end
end
