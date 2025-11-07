defmodule LLMDb.EngineTest do
  use ExUnit.Case, async: true

  alias LLMDb.Engine

  setup do
    # Clear any polluted application env
    Application.delete_env(:llm_db, :allow)
    Application.delete_env(:llm_db, :deny)
    Application.delete_env(:llm_db, :prefer)
    :ok
  end

  # Minimal test data for basic tests
  defp minimal_test_data do
    %{
      providers: [%{id: :test_provider, name: "Test Provider"}],
      models: [
        %{
          id: "test-model",
          provider: :test_provider,
          capabilities: %{chat: true},
          aliases: ["test-alias"]
        }
      ]
    }
  end

  # Helper to convert old test config format to new sources format
  defp run_with_test_data(config) when is_map(config) do
    # Use Config source with legacy format (providers/models keys)
    overrides = %{
      providers: get_in(config, [:overrides, :providers]) || [],
      models: get_in(config, [:overrides, :models]) || []
    }

    sources = [{LLMDb.Sources.Config, %{overrides: overrides}}]

    # Set application env for filters
    if Map.has_key?(config, :allow), do: Application.put_env(:llm_db, :allow, config.allow)
    if Map.has_key?(config, :deny), do: Application.put_env(:llm_db, :deny, config.deny)
    if Map.has_key?(config, :prefer), do: Application.put_env(:llm_db, :prefer, config.prefer)

    Engine.run(sources: sources)
  end

  describe "run/1" do
    test "runs complete ETL pipeline with test data" do
      sources = [{LLMDb.Sources.Config, %{overrides: minimal_test_data()}}]
      {:ok, snapshot} = Engine.run(sources: sources)

      assert is_map(snapshot)
      # v2 schema: minimal structure (no indexes at build time)
      assert Map.has_key?(snapshot, :version)
      assert Map.has_key?(snapshot, :generated_at)
      assert Map.has_key?(snapshot, :providers)
      assert snapshot.version == 2

      # Should NOT have indexes (built at load time)
      refute Map.has_key?(snapshot, :providers_by_id)
      refute Map.has_key?(snapshot, :models_by_key)
      refute Map.has_key?(snapshot, :aliases_by_key)
      refute Map.has_key?(snapshot, :filters)
      refute Map.has_key?(snapshot, :prefer)
    end

    test "snapshot has correct metadata structure" do
      {:ok, snapshot} = Engine.run(runtime_overrides: minimal_test_data(), sources: [])

      # v2 schema: version and generated_at at top level
      assert snapshot.version == 2
      assert is_binary(snapshot.generated_at)
    end

    test "builds nested provider structure correctly" do
      {:ok, snapshot} = Engine.run(runtime_overrides: minimal_test_data(), sources: [])

      if map_size(snapshot.providers) > 0 do
        {provider_id, provider} = Enum.at(snapshot.providers, 0)
        assert is_atom(provider_id)
        assert provider.id == provider_id
        assert Map.has_key?(provider, :models)
        assert is_map(provider.models)
      end
    end

    test "nests models under providers" do
      {:ok, snapshot} = Engine.run(runtime_overrides: minimal_test_data(), sources: [])

      # v2 schema: models are nested under providers[provider_id].models
      if map_size(snapshot.providers) > 0 do
        {provider_id, provider_data} = Enum.at(snapshot.providers, 0)
        assert is_atom(provider_id)
        assert is_map(provider_data.models)

        if map_size(provider_data.models) > 0 do
          models_list = Map.values(provider_data.models)
          assert Enum.all?(models_list, fn m -> m.provider == provider_id end)
        end
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

      {:ok, snapshot} = run_with_test_data(config)

      assert Map.has_key?(snapshot.providers, :test_provider)
      assert Map.has_key?(snapshot.providers[:test_provider].models, "test-model")
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

      {filters, _unknown_info} =
        LLMDb.Config.compile_filters(
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

  describe "list merge behavior" do
    test "unions accumulative list fields across sources" do
      # First source (lower precedence)
      source1 =
        {LLMDb.Sources.Config,
         %{
           overrides: %{
             providers: [%{id: :openai, name: "OpenAI"}],
             models: [
               %{
                 provider: :openai,
                 id: "gpt-4",
                 aliases: ["gpt-4-0314"],
                 tags: ["general", "production"],
                 modalities: %{input: [:text], output: [:text]}
               }
             ]
           }
         }}

      # Second source (higher precedence)
      source2 =
        {LLMDb.Sources.Config,
         %{
           overrides: %{
             providers: [],
             models: [
               %{
                 provider: :openai,
                 id: "gpt-4",
                 aliases: ["gpt-4-2023", "gpt4"],
                 tags: ["fast"],
                 modalities: %{input: [:image], output: [:json]}
               }
             ]
           }
         }}

      {:ok, snapshot} = Engine.run(sources: [source1, source2])
      m = snapshot.providers[:openai].models["gpt-4"]

      # Should union aliases and tags
      assert m.aliases == ["gpt-4-0314", "gpt-4-2023", "gpt4"]
      assert m.tags == ["general", "production", "fast"]

      # Should union nested modalities
      assert m.modalities.input == [:text, :image]
      assert m.modalities.output == [:text, :json]
    end

    test "replaces non-accumulative lists with last-wins" do
      # First source (lower precedence)
      source1 =
        {LLMDb.Sources.Config,
         %{
           overrides: %{
             providers: [%{id: :openai, name: "OpenAI"}],
             models: [
               %{
                 provider: :openai,
                 id: "gpt-4",
                 extra: %{custom_list: ["a", "b"]}
               }
             ]
           }
         }}

      # Second source (higher precedence)
      source2 =
        {LLMDb.Sources.Config,
         %{
           overrides: %{
             providers: [],
             models: [
               %{
                 provider: :openai,
                 id: "gpt-4",
                 extra: %{custom_list: ["c"]}
               }
             ]
           }
         }}

      {:ok, snapshot} = Engine.run(sources: [source1, source2])
      m = snapshot.providers[:openai].models["gpt-4"]

      # Unknown list fields should replace (last-wins)
      assert m.extra.custom_list == ["c"]
    end

    test "removes duplicates when unioning lists" do
      # First source
      source1 =
        {LLMDb.Sources.Config,
         %{
           overrides: %{
             providers: [%{id: :openai, name: "OpenAI"}],
             models: [
               %{
                 provider: :openai,
                 id: "gpt-4",
                 aliases: ["gpt4", "gpt-4-0314"],
                 tags: ["production"]
               }
             ]
           }
         }}

      # Second source with some duplicates
      source2 =
        {LLMDb.Sources.Config,
         %{
           overrides: %{
             providers: [],
             models: [
               %{
                 provider: :openai,
                 id: "gpt-4",
                 aliases: ["gpt4", "gpt-4-2023"],
                 tags: ["production", "fast"]
               }
             ]
           }
         }}

      {:ok, snapshot} = Engine.run(sources: [source1, source2])
      m = snapshot.providers[:openai].models["gpt-4"]

      # Should preserve left-first order and remove duplicates
      assert m.aliases == ["gpt4", "gpt-4-0314", "gpt-4-2023"]
      assert m.tags == ["production", "fast"]
    end

    test "handles empty lists in union" do
      # First source with populated lists
      source1 =
        {LLMDb.Sources.Config,
         %{
           overrides: %{
             providers: [%{id: :openai, name: "OpenAI"}],
             models: [
               %{
                 provider: :openai,
                 id: "gpt-4",
                 aliases: ["gpt-4-0314"],
                 tags: ["production"]
               }
             ]
           }
         }}

      # Second source with empty lists
      source2 =
        {LLMDb.Sources.Config,
         %{
           overrides: %{
             providers: [],
             models: [
               %{
                 provider: :openai,
                 id: "gpt-4",
                 aliases: [],
                 tags: []
               }
             ]
           }
         }}

      {:ok, snapshot} = Engine.run(sources: [source1, source2])
      m = snapshot.providers[:openai].models["gpt-4"]

      # Empty lists should not clear earlier values (union behavior)
      assert m.aliases == ["gpt-4-0314"]
      assert m.tags == ["production"]
    end

    test "unions lists across multiple sources" do
      # Three sources with different data
      source1 =
        {LLMDb.Sources.Config,
         %{
           overrides: %{
             providers: [%{id: :openai, name: "OpenAI"}],
             models: [
               %{
                 provider: :openai,
                 id: "gpt-4",
                 aliases: ["alias1"],
                 tags: ["tag1"]
               }
             ]
           }
         }}

      source2 =
        {LLMDb.Sources.Config,
         %{
           overrides: %{
             providers: [],
             models: [
               %{
                 provider: :openai,
                 id: "gpt-4",
                 aliases: ["alias2"],
                 tags: ["tag2"]
               }
             ]
           }
         }}

      source3 =
        {LLMDb.Sources.Config,
         %{
           overrides: %{
             providers: [],
             models: [
               %{
                 provider: :openai,
                 id: "gpt-4",
                 aliases: ["alias3"],
                 tags: ["tag3"]
               }
             ]
           }
         }}

      {:ok, snapshot} = Engine.run(sources: [source1, source2, source3])
      m = snapshot.providers[:openai].models["gpt-4"]

      # Should union all values from all sources
      assert m.aliases == ["alias1", "alias2", "alias3"]
      assert m.tags == ["tag1", "tag2", "tag3"]
    end
  end
end
