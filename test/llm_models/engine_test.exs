defmodule LlmModels.EngineTest do
  use ExUnit.Case, async: true

  alias LlmModels.Engine

  describe "run/1" do
    test "runs complete ETL pipeline with packaged snapshot" do
      {:ok, snapshot} = Engine.run()

      assert is_map(snapshot)
      assert Map.has_key?(snapshot, :providers_by_id)
      assert Map.has_key?(snapshot, :models_by_key)
      assert Map.has_key?(snapshot, :aliases_by_key)
      assert Map.has_key?(snapshot, :providers)
      assert Map.has_key?(snapshot, :models)
      assert Map.has_key?(snapshot, :filters)
      assert Map.has_key?(snapshot, :prefer)
      assert Map.has_key?(snapshot, :meta)
    end

    test "snapshot has correct metadata structure" do
      {:ok, snapshot} = Engine.run()

      assert Map.has_key?(snapshot.meta, :epoch)
      assert Map.has_key?(snapshot.meta, :generated_at)
      assert is_binary(snapshot.meta.generated_at)
    end

    test "builds provider index correctly" do
      {:ok, snapshot} = Engine.run()

      if map_size(snapshot.providers_by_id) > 0 do
        {provider_id, provider} = Enum.at(snapshot.providers_by_id, 0)
        assert is_atom(provider_id)
        assert provider.id == provider_id
      end
    end

    test "builds model key index correctly" do
      {:ok, snapshot} = Engine.run()

      if map_size(snapshot.models_by_key) > 0 do
        {{provider, model_id}, model} = Enum.at(snapshot.models_by_key, 0)
        assert is_atom(provider)
        assert is_binary(model_id)
        assert model.provider == provider
        assert model.id == model_id
      end
    end

    test "builds models by provider index correctly" do
      {:ok, snapshot} = Engine.run()

      if map_size(snapshot.models) > 0 do
        {provider, models_list} = Enum.at(snapshot.models, 0)
        assert is_atom(provider)
        assert is_list(models_list)

        if models_list != [] do
          assert Enum.all?(models_list, fn m -> m.provider == provider end)
        end
      end
    end

    test "builds aliases index correctly" do
      {:ok, snapshot} = Engine.run()

      if map_size(snapshot.aliases_by_key) > 0 do
        {{provider, alias_name}, canonical_id} = Enum.at(snapshot.aliases_by_key, 0)
        assert is_atom(provider)
        assert is_binary(alias_name)
        assert is_binary(canonical_id)

        assert Map.has_key?(snapshot.models_by_key, {provider, canonical_id})
      end
    end

    test "accepts config override" do
      config = %{
        overrides: %{
          providers: [%{id: :test_provider}],
          models: [%{id: "test-model", provider: :test_provider, capabilities: %{chat: true}}],
          exclude: %{}
        },
        overrides_module: nil,
        allow: :all,
        deny: %{},
        prefer: []
      }

      {:ok, snapshot} = Engine.run(config: config)

      assert Map.has_key?(snapshot.providers_by_id, :test_provider)
      assert Map.has_key?(snapshot.models_by_key, {:test_provider, "test-model"})
    end

    test "returns error on empty catalog" do
      config = %{
        overrides: %{providers: [], models: [], exclude: %{}},
        overrides_module: nil,
        allow: %{},
        deny: %{openai: ["*"], anthropic: ["*"], google_vertex: ["*"]},
        prefer: []
      }

      result = Engine.run(config: config)
      assert {:error, :empty_catalog} = result
    end
  end

  describe "build_indexes/2" do
    test "builds all indexes from providers and models" do
      providers = [
        %{id: :provider_a, name: "Provider A"},
        %{id: :provider_b, name: "Provider B"}
      ]

      models = [
        %{id: "model-a1", provider: :provider_a, aliases: ["alias-a1"]},
        %{id: "model-a2", provider: :provider_a, aliases: []},
        %{id: "model-b1", provider: :provider_b, aliases: ["alias-b1", "alias-b2"]}
      ]

      indexes = Engine.build_indexes(providers, models)

      assert map_size(indexes.providers_by_id) == 2
      assert indexes.providers_by_id[:provider_a].name == "Provider A"

      assert map_size(indexes.models_by_key) == 3
      assert indexes.models_by_key[{:provider_a, "model-a1"}].id == "model-a1"

      assert map_size(indexes.models_by_provider) == 2
      assert length(indexes.models_by_provider[:provider_a]) == 2

      assert map_size(indexes.aliases_by_key) == 3
      assert indexes.aliases_by_key[{:provider_a, "alias-a1"}] == "model-a1"
      assert indexes.aliases_by_key[{:provider_b, "alias-b1"}] == "model-b1"
    end

    test "handles empty providers and models" do
      indexes = Engine.build_indexes([], [])

      assert map_size(indexes.providers_by_id) == 0
      assert map_size(indexes.models_by_key) == 0
      assert map_size(indexes.models_by_provider) == 0
      assert map_size(indexes.aliases_by_key) == 0
    end
  end

  describe "apply_filters/2" do
    test "allows all models with :all filter" do
      models = [
        %{id: "model-1", provider: :provider_a},
        %{id: "model-2", provider: :provider_b}
      ]

      filters = %{allow: :all, deny: %{}}

      filtered = Engine.apply_filters(models, filters)
      assert length(filtered) == 2
    end

    test "filters by allow patterns" do
      models = [
        %{id: "model-a1", provider: :provider_a},
        %{id: "model-a2", provider: :provider_a},
        %{id: "model-b1", provider: :provider_b}
      ]

      filters = %{allow: %{provider_a: ["model-a1"]}, deny: %{}}

      filtered = Engine.apply_filters(models, filters)
      assert length(filtered) == 1
      assert hd(filtered).id == "model-a1"
    end

    test "filters by deny patterns" do
      models = [
        %{id: "model-a1", provider: :provider_a},
        %{id: "model-a2", provider: :provider_a}
      ]

      filters = %{allow: :all, deny: %{provider_a: ["model-a2"]}}

      filtered = Engine.apply_filters(models, filters)
      assert length(filtered) == 1
      assert hd(filtered).id == "model-a1"
    end

    test "deny patterns win over allow patterns" do
      models = [
        %{id: "model-a1", provider: :provider_a},
        %{id: "model-a2", provider: :provider_a}
      ]

      filters = LlmModels.Config.compile_filters(
        %{provider_a: ["*"]},
        %{provider_a: ["model-a2"]}
      )

      filtered = Engine.apply_filters(models, filters)
      assert length(filtered) == 1
      assert hd(filtered).id == "model-a1"
    end

    test "handles regex patterns" do
      models = [
        %{id: "gpt-4", provider: :openai},
        %{id: "gpt-3.5-turbo", provider: :openai},
        %{id: "claude-3", provider: :anthropic}
      ]

      filters = %{allow: %{openai: [~r/^gpt-4/]}, deny: %{}}

      filtered = Engine.apply_filters(models, filters)
      assert length(filtered) == 1
      assert hd(filtered).id == "gpt-4"
    end
  end

  describe "build_aliases_index/1" do
    test "builds alias mappings" do
      models = [
        %{id: "model-a", provider: :provider_a, aliases: ["alias-1", "alias-2"]},
        %{id: "model-b", provider: :provider_b, aliases: ["alias-3"]}
      ]

      index = Engine.build_aliases_index(models)

      assert map_size(index) == 3
      assert index[{:provider_a, "alias-1"}] == "model-a"
      assert index[{:provider_a, "alias-2"}] == "model-a"
      assert index[{:provider_b, "alias-3"}] == "model-b"
    end

    test "handles models without aliases" do
      models = [
        %{id: "model-a", provider: :provider_a, aliases: []},
        %{id: "model-b", provider: :provider_b}
      ]

      index = Engine.build_aliases_index(models)

      assert map_size(index) == 0
    end

    test "handles empty model list" do
      index = Engine.build_aliases_index([])
      assert map_size(index) == 0
    end
  end
end
