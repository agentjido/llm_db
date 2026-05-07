defmodule LLMDB.SourcesTest do
  use ExUnit.Case, async: true

  alias LLMDB.Sources.{Config, Local}

  describe "Local source" do
    test "loads providers and models from TOML directory structure" do
      result = Local.load(%{dir: "priv/llm_db/local"})
      assert {:ok, data} = result
      assert is_map(data)
      assert map_size(data) > 0
    end

    test "returns error when directory not found" do
      result = Local.load(%{dir: "/nonexistent"})
      assert {:error, :directory_not_found} = result
    end

    test "requires dir parameter" do
      result = Local.load(%{})
      assert {:error, :dir_required} = result
    end
  end

  describe "Config source" do
    test "loads provider-keyed overrides (new format)" do
      overrides = %{
        openai: %{
          base_url: "https://staging-api.openai.com",
          models: [
            %{id: "gpt-4o", cost: %{input: 0.0, output: 0.0}},
            %{id: "gpt-4o-mini", limits: %{context: 200_000}}
          ]
        },
        anthropic: %{
          base_url: "https://proxy.example.com/anthropic",
          models: [
            %{id: "claude-3-5-sonnet", cost: %{input: 0.0, output: 0.0}}
          ]
        }
      }

      {:ok, data} = Config.load(%{overrides: overrides})

      assert map_size(data) == 2

      openai_provider = data["openai"]
      assert openai_provider.id == :openai
      assert openai_provider.base_url == "https://staging-api.openai.com"
      assert length(openai_provider.models) == 2

      gpt4o = Enum.find(openai_provider.models, fn m -> m.id == "gpt-4o" end)
      assert gpt4o.cost.input == 0.0
    end

    test "loads legacy format with providers/models keys" do
      overrides = %{
        providers: [%{id: :test_provider, name: "Test"}],
        models: [%{id: "test-model", provider: :test_provider}]
      }

      {:ok, data} = Config.load(%{overrides: overrides})

      assert map_size(data) == 1
      provider = data["test_provider"]
      assert provider.id == :test_provider
      assert provider.name == "Test"
      assert length(provider.models) == 1
      assert hd(provider.models).id == "test-model"
    end

    test "handles nil overrides" do
      {:ok, data} = Config.load(%{overrides: nil})

      assert data == %{}
    end

    test "handles empty overrides map" do
      {:ok, data} = Config.load(%{overrides: %{}})

      assert data == %{}
    end

    test "handles missing overrides parameter" do
      {:ok, data} = Config.load(%{})

      assert data == %{}
    end

    test "skips legacy keys in provider-keyed format" do
      overrides = %{
        openai: %{base_url: "https://api.openai.com"},
        providers: [%{id: :test}],
        models: [%{id: "test"}],
        exclude: %{openai: ["*"]}
      }

      {:ok, data} = Config.load(%{overrides: overrides})

      # Should only process openai, skip legacy keys
      assert map_size(data) == 1
      assert Map.has_key?(data, "openai")
      assert data["openai"].id == :openai
    end

    test "injects provider into models" do
      overrides = %{
        openai: %{
          models: [
            %{id: "gpt-4o"},
            %{id: "gpt-4o-mini"}
          ]
        }
      }

      {:ok, data} = Config.load(%{overrides: overrides})

      assert map_size(data) == 1
      provider = data["openai"]
      assert length(provider.models) == 2
    end
  end

  describe "OpenRouter embedding dimension overlays" do
    test "openai/text-embedding-3-large has correct dimension range" do
      {:ok, data} = Local.load(%{dir: "priv/llm_db/local"})
      openrouter = data["openrouter"]
      assert openrouter, "openrouter provider should be present in local overlays"

      model = Enum.find(openrouter.models, fn m -> m.id == "openai/text-embedding-3-large" end)
      assert model, "openai/text-embedding-3-large overlay should exist"

      embeddings = get_in(model, [:capabilities, :embeddings])
      assert is_map(embeddings), "capabilities.embeddings should be a map"
      assert embeddings[:min_dimensions] == 1
      assert embeddings[:max_dimensions] == 3072
      assert embeddings[:default_dimensions] == 3072
    end

    test "openai/text-embedding-3-small has correct dimension range" do
      {:ok, data} = Local.load(%{dir: "priv/llm_db/local"})

      model =
        data["openrouter"].models
        |> Enum.find(&(&1.id == "openai/text-embedding-3-small"))

      assert model
      embeddings = get_in(model, [:capabilities, :embeddings])
      assert embeddings[:min_dimensions] == 1
      assert embeddings[:max_dimensions] == 1536
      assert embeddings[:default_dimensions] == 1536
    end

    test "baai/bge-m3 has correct fixed dimensions" do
      {:ok, data} = Local.load(%{dir: "priv/llm_db/local"})
      model = Enum.find(data["openrouter"].models, &(&1.id == "baai/bge-m3"))

      assert model
      embeddings = get_in(model, [:capabilities, :embeddings])
      assert embeddings[:min_dimensions] == 1024
      assert embeddings[:max_dimensions] == 1024
      assert embeddings[:default_dimensions] == 1024
    end

    test "all 25 openrouter embedding overlays have required dimension fields" do
      {:ok, data} = Local.load(%{dir: "priv/llm_db/local"})

      expected_ids = ~w[
        openai/text-embedding-3-large
        openai/text-embedding-3-small
        openai/text-embedding-ada-002
        baai/bge-m3
        baai/bge-base-en-v1.5
        baai/bge-large-en-v1.5
        google/gemini-embedding-001
        google/gemini-embedding-2-preview
        intfloat/e5-base-v2
        intfloat/e5-large-v2
        intfloat/multilingual-e5-large
        mistralai/codestral-embed-2505
        mistralai/mistral-embed-2312
        nvidia/llama-nemotron-embed-vl-1b-v2:free
        perplexity/pplx-embed-v1-0.6b
        perplexity/pplx-embed-v1-4b
        qwen/qwen3-embedding-4b
        qwen/qwen3-embedding-8b
        sentence-transformers/all-minilm-l12-v2
        sentence-transformers/all-minilm-l6-v2
        sentence-transformers/all-mpnet-base-v2
        sentence-transformers/multi-qa-mpnet-base-dot-v1
        sentence-transformers/paraphrase-minilm-l6-v2
        thenlper/gte-base
        thenlper/gte-large
      ]

      models_by_id = Map.new(data["openrouter"].models, &{&1.id, &1})

      Enum.each(expected_ids, fn id ->
        model = models_by_id[id]
        assert model, "overlay for #{id} should be present"

        embeddings = get_in(model, [:capabilities, :embeddings])
        assert is_map(embeddings), "#{id} should have capabilities.embeddings map"
        assert is_integer(embeddings[:min_dimensions]), "#{id} should have min_dimensions"
        assert is_integer(embeddings[:max_dimensions]), "#{id} should have max_dimensions"
        assert is_integer(embeddings[:default_dimensions]), "#{id} should have default_dimensions"
      end)
    end
  end

  describe "Source behavior contract" do
    test "all sources return {:ok, data} format with nested structure" do
      # Config
      assert {:ok, data} = Config.load(%{overrides: %{}})
      assert is_map(data)
    end

    test "all sources handle error cases appropriately" do
      # Local returns error when dir not found
      assert {:error, :directory_not_found} = Local.load(%{dir: "/nonexistent"})

      # Local returns error when dir not provided
      assert {:error, :dir_required} = Local.load(%{})
    end
  end
end
