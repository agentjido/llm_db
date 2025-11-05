defmodule LLMModels.EnrichTest do
  use ExUnit.Case, async: true

  alias LLMModels.Enrich

  doctest LLMModels.Enrich

  describe "derive_family/1" do
    test "derives family from gpt-* models" do
      assert Enrich.derive_family("gpt-4o-mini") == "gpt-4o"
      assert Enrich.derive_family("gpt-4o") == "gpt"
      assert Enrich.derive_family("gpt-4-turbo") == "gpt-4"
      assert Enrich.derive_family("gpt-3.5-turbo") == "gpt-3.5"
    end

    test "derives family from claude-* models" do
      assert Enrich.derive_family("claude-3-opus") == "claude-3"
      assert Enrich.derive_family("claude-3-sonnet") == "claude-3"
      assert Enrich.derive_family("claude-3-haiku") == "claude-3"
      assert Enrich.derive_family("claude-3.5-sonnet") == "claude-3.5"
    end

    test "derives family from gemini-* models" do
      assert Enrich.derive_family("gemini-1.5-pro") == "gemini-1.5"
      assert Enrich.derive_family("gemini-1.5-flash") == "gemini-1.5"
      assert Enrich.derive_family("gemini-pro") == "gemini"
    end

    test "derives family from llama-* models" do
      assert Enrich.derive_family("llama-3.1-70b") == "llama-3.1"
      assert Enrich.derive_family("llama-3-8b") == "llama-3"
      assert Enrich.derive_family("llama-2-13b-chat") == "llama-2-13b"
    end

    test "derives family from mistral-* models" do
      assert Enrich.derive_family("mistral-large-latest") == "mistral-large"
      assert Enrich.derive_family("mistral-small") == "mistral"
    end

    test "handles single segment names" do
      assert Enrich.derive_family("gpt4") == nil
      assert Enrich.derive_family("claude") == nil
      assert Enrich.derive_family("model") == nil
    end

    test "handles two segment names" do
      assert Enrich.derive_family("two-parts") == "two"
      assert Enrich.derive_family("model-name") == "model"
    end

    test "handles complex multi-segment names" do
      assert Enrich.derive_family("provider-family-version-variant-size") ==
               "provider-family-version-variant"

      assert Enrich.derive_family("a-b-c-d-e") == "a-b-c-d"
    end

    test "handles version numbers with dots" do
      assert Enrich.derive_family("model-1.5-pro") == "model-1.5"
      assert Enrich.derive_family("model-v2.1-turbo") == "model-v2.1"
    end

    test "handles date-based suffixes" do
      assert Enrich.derive_family("gpt-4o-2024-08-06") == "gpt-4o-2024-08"
      assert Enrich.derive_family("model-20241101") == "model"
    end
  end

  describe "enrich_model/1" do
    test "adds family from ID when not present" do
      input = %{id: "gpt-4o-mini", provider: :openai}
      result = Enrich.enrich_model(input)

      assert result.id == "gpt-4o-mini"
      assert result.provider == :openai
      assert result.family == "gpt-4o"
    end

    test "preserves existing family" do
      input = %{id: "gpt-4o-mini", provider: :openai, family: "custom-family"}
      result = Enrich.enrich_model(input)

      assert result.family == "custom-family"
    end

    test "does not add family when cannot be derived" do
      input = %{id: "model", provider: :openai}
      result = Enrich.enrich_model(input)

      assert result.id == "model"
      assert result.provider == :openai
      refute Map.has_key?(result, :family)
    end

    test "adds provider_model_id from ID when not present" do
      input = %{id: "gpt-4o-mini", provider: :openai}
      result = Enrich.enrich_model(input)

      assert result.provider_model_id == "gpt-4o-mini"
    end

    test "preserves existing provider_model_id" do
      input = %{id: "gpt-4o-mini", provider: :openai, provider_model_id: "gpt-4o-mini-2024-07-18"}
      result = Enrich.enrich_model(input)

      assert result.provider_model_id == "gpt-4o-mini-2024-07-18"
    end

    test "enriches both fields when both missing" do
      input = %{id: "claude-3-opus", provider: :anthropic}
      result = Enrich.enrich_model(input)

      assert result.id == "claude-3-opus"
      assert result.provider == :anthropic
      assert result.family == "claude-3"
      assert result.provider_model_id == "claude-3-opus"
    end

    test "preserves all existing fields" do
      input = %{
        id: "gpt-4o-mini",
        provider: :openai,
        name: "GPT-4o Mini",
        release_date: "2024-07-18",
        limits: %{context: 128_000},
        cost: %{input: 0.15, output: 0.60},
        capabilities: %{chat: true},
        tags: ["fast"],
        deprecated?: false,
        aliases: ["mini"],
        extra: %{"custom" => "value"}
      }

      result = Enrich.enrich_model(input)

      assert result.id == "gpt-4o-mini"
      assert result.provider == :openai
      assert result.name == "GPT-4o Mini"
      assert result.release_date == "2024-07-18"
      assert result.limits == %{context: 128_000}
      assert result.cost == %{input: 0.15, output: 0.60}
      assert result.capabilities == %{chat: true}
      assert result.tags == ["fast"]
      assert result.deprecated? == false
      assert result.aliases == ["mini"]
      assert result.extra == %{"custom" => "value"}
      assert result.family == "gpt-4o"
      assert result.provider_model_id == "gpt-4o-mini"
    end

    test "handles models with single segment IDs" do
      input = %{id: "model", provider: :custom, provider_model_id: "custom-id"}
      result = Enrich.enrich_model(input)

      assert result.id == "model"
      assert result.provider == :custom
      assert result.provider_model_id == "custom-id"
      refute Map.has_key?(result, :family)
    end
  end

  describe "enrich_models/1" do
    test "enriches empty list" do
      assert Enrich.enrich_models([]) == []
    end

    test "enriches single model" do
      models = [%{id: "gpt-4o", provider: :openai}]
      result = Enrich.enrich_models(models)

      assert length(result) == 1
      assert hd(result).id == "gpt-4o"
      assert hd(result).family == "gpt"
      assert hd(result).provider_model_id == "gpt-4o"
    end

    test "enriches multiple models" do
      models = [
        %{id: "gpt-4o-mini", provider: :openai},
        %{id: "claude-3-opus", provider: :anthropic},
        %{id: "gemini-1.5-pro", provider: :google}
      ]

      result = Enrich.enrich_models(models)

      assert length(result) == 3
      assert Enum.at(result, 0).family == "gpt-4o"
      assert Enum.at(result, 1).family == "claude-3"
      assert Enum.at(result, 2).family == "gemini-1.5"
    end

    test "preserves order of models" do
      models = [
        %{id: "first-model", provider: :p1},
        %{id: "second-model", provider: :p2},
        %{id: "third-model", provider: :p3}
      ]

      result = Enrich.enrich_models(models)

      assert Enum.map(result, & &1.id) == ["first-model", "second-model", "third-model"]
    end

    test "enriches models with mixed completeness" do
      models = [
        %{id: "gpt-4o", provider: :openai},
        %{id: "claude-3-opus", provider: :anthropic, family: "custom"},
        %{id: "gemini-1.5-pro", provider: :google, provider_model_id: "gemini-1.5-pro-002"}
      ]

      result = Enrich.enrich_models(models)

      assert Enum.at(result, 0).family == "gpt"
      assert Enum.at(result, 0).provider_model_id == "gpt-4o"

      assert Enum.at(result, 1).family == "custom"
      assert Enum.at(result, 1).provider_model_id == "claude-3-opus"

      assert Enum.at(result, 2).family == "gemini-1.5"
      assert Enum.at(result, 2).provider_model_id == "gemini-1.5-pro-002"
    end

    test "handles models where family cannot be derived" do
      models = [
        %{id: "model", provider: :custom},
        %{id: "another", provider: :custom}
      ]

      result = Enrich.enrich_models(models)

      assert length(result) == 2
      refute Map.has_key?(Enum.at(result, 0), :family)
      refute Map.has_key?(Enum.at(result, 1), :family)
      assert Enum.at(result, 0).provider_model_id == "model"
      assert Enum.at(result, 1).provider_model_id == "another"
    end
  end

  describe "integration with validation" do
    test "enrichment works before validation" do
      alias LLMModels.Validate

      raw_model = %{
        id: "gpt-4o-mini",
        provider: :openai
      }

      enriched = Enrich.enrich_model(raw_model)
      assert {:ok, validated} = Validate.validate_model(enriched)

      assert validated.id == "gpt-4o-mini"
      assert validated.provider == :openai
      assert validated.family == "gpt-4o"
      assert validated.provider_model_id == "gpt-4o-mini"
      assert validated.deprecated? == false
      assert validated.aliases == []
    end

    test "batch enrichment works before batch validation" do
      alias LLMModels.Validate

      raw_models = [
        %{id: "gpt-4o", provider: :openai},
        %{id: "claude-3-opus", provider: :anthropic},
        %{id: "invalid", provider: "string-not-atom"}
      ]

      enriched = Enrich.enrich_models(raw_models)
      assert {:ok, valid, 1} = Validate.validate_models(enriched)

      assert length(valid) == 2
      assert Enum.at(valid, 0).family == "gpt"
      assert Enum.at(valid, 1).family == "claude-3"
    end

    test "enrichment preserves complex nested structures for validation" do
      alias LLMModels.Validate

      raw_model = %{
        id: "gpt-4o-mini",
        provider: :openai,
        limits: %{context: 128_000, output: 16_384},
        cost: %{input: 0.15, output: 0.60},
        capabilities: %{
          chat: true,
          tools: %{enabled: true, streaming: true}
        },
        modalities: %{
          input: [:text, :image],
          output: [:text]
        }
      }

      enriched = Enrich.enrich_model(raw_model)
      assert {:ok, validated} = Validate.validate_model(enriched)

      assert validated.family == "gpt-4o"
      assert validated.limits.context == 128_000
      assert validated.cost.input == 0.15
      assert validated.capabilities.chat == true
      assert validated.capabilities.tools.enabled == true
      assert validated.modalities.input == [:text, :image]
    end
  end

  describe "real-world model naming patterns" do
    test "handles OpenAI model names" do
      assert Enrich.derive_family("gpt-4o") == "gpt"
      assert Enrich.derive_family("gpt-4o-mini") == "gpt-4o"
      assert Enrich.derive_family("gpt-4-turbo") == "gpt-4"
      assert Enrich.derive_family("gpt-4-turbo-preview") == "gpt-4-turbo"
      assert Enrich.derive_family("gpt-3.5-turbo") == "gpt-3.5"
      assert Enrich.derive_family("gpt-3.5-turbo-0125") == "gpt-3.5-turbo"
    end

    test "handles Anthropic model names" do
      assert Enrich.derive_family("claude-3-opus-20240229") == "claude-3-opus"
      assert Enrich.derive_family("claude-3-sonnet-20240229") == "claude-3-sonnet"
      assert Enrich.derive_family("claude-3-haiku-20240307") == "claude-3-haiku"
      assert Enrich.derive_family("claude-3.5-sonnet-20241022") == "claude-3.5-sonnet"
    end

    test "handles Google model names" do
      assert Enrich.derive_family("gemini-1.5-pro") == "gemini-1.5"
      assert Enrich.derive_family("gemini-1.5-pro-002") == "gemini-1.5-pro"
      assert Enrich.derive_family("gemini-1.5-flash") == "gemini-1.5"
      assert Enrich.derive_family("gemini-pro") == "gemini"
      assert Enrich.derive_family("gemini-pro-vision") == "gemini-pro"
    end

    test "handles Meta Llama model names" do
      assert Enrich.derive_family("llama-3.1-405b-instruct") == "llama-3.1-405b"
      assert Enrich.derive_family("llama-3.1-70b-instruct") == "llama-3.1-70b"
      assert Enrich.derive_family("llama-3.1-8b-instruct") == "llama-3.1-8b"
      assert Enrich.derive_family("llama-3-70b-instruct") == "llama-3-70b"
    end

    test "handles Mistral model names" do
      assert Enrich.derive_family("mistral-large-latest") == "mistral-large"
      assert Enrich.derive_family("mistral-large-2411") == "mistral-large"
      assert Enrich.derive_family("mistral-small-latest") == "mistral-small"
      assert Enrich.derive_family("mistral-tiny") == "mistral"
    end

    test "handles Cohere model names" do
      assert Enrich.derive_family("command-r-plus") == "command-r"
      assert Enrich.derive_family("command-r") == "command"
      assert Enrich.derive_family("command-light") == "command"
    end

    test "handles embedding model names" do
      assert Enrich.derive_family("text-embedding-3-small") == "text-embedding-3"
      assert Enrich.derive_family("text-embedding-3-large") == "text-embedding-3"
      assert Enrich.derive_family("text-embedding-ada-002") == "text-embedding-ada"
    end
  end
end
