defmodule LLMModels.ValidateTest do
  use ExUnit.Case, async: true

  alias LLMModels.Validate

  describe "validate_provider/1" do
    test "validates minimal valid provider" do
      input = %{id: :openai}
      assert {:ok, result} = Validate.validate_provider(input)
      assert result.id == :openai
    end

    test "validates complete provider with all fields" do
      input = %{
        id: :openai,
        name: "OpenAI",
        base_url: "https://api.openai.com",
        env: ["OPENAI_API_KEY"],
        doc: "OpenAI provider",
        extra: %{"custom" => "value"}
      }

      assert {:ok, result} = Validate.validate_provider(input)
      assert result.id == :openai
      assert result.name == "OpenAI"
      assert result.base_url == "https://api.openai.com"
      assert result.env == ["OPENAI_API_KEY"]
      assert result.doc == "OpenAI provider"
      assert result.extra == %{"custom" => "value"}
    end

    test "rejects provider with missing required id" do
      input = %{name: "OpenAI"}
      assert {:error, _} = Validate.validate_provider(input)
    end

    test "rejects provider with wrong type for id" do
      input = %{id: "openai"}
      assert {:error, _} = Validate.validate_provider(input)
    end

    test "rejects provider with wrong type for name" do
      input = %{id: :openai, name: 123}
      assert {:error, _} = Validate.validate_provider(input)
    end

    test "rejects provider with wrong type for base_url" do
      input = %{id: :openai, base_url: 456}
      assert {:error, _} = Validate.validate_provider(input)
    end

    test "rejects provider with wrong type for env" do
      input = %{id: :openai, env: "OPENAI_API_KEY"}
      assert {:error, _} = Validate.validate_provider(input)
    end

    test "rejects provider with non-string elements in env array" do
      input = %{id: :openai, env: ["OPENAI_API_KEY", 123]}
      assert {:error, _} = Validate.validate_provider(input)
    end

    test "rejects provider with wrong type for extra" do
      input = %{id: :openai, extra: "not a map"}
      assert {:error, _} = Validate.validate_provider(input)
    end
  end

  describe "validate_model/1" do
    test "validates minimal valid model" do
      input = %{
        id: "gpt-4o-mini",
        provider: :openai
      }

      assert {:ok, result} = Validate.validate_model(input)
      assert result.id == "gpt-4o-mini"
      assert result.provider == :openai
      assert result.deprecated? == false
      assert result.aliases == []
    end

    test "validates complete model with all fields" do
      input = %{
        id: "gpt-4o-mini",
        provider: :openai,
        provider_model_id: "gpt-4o-mini-2024-07-18",
        name: "GPT-4o Mini",
        family: "gpt-4o",
        release_date: "2024-07-18",
        last_updated: "2024-10-01",
        knowledge: "2023-10",
        limits: %{context: 128_000, output: 16_384},
        cost: %{input: 0.15, output: 0.60},
        modalities: %{
          input: [:text, :image],
          output: [:text]
        },
        capabilities: %{
          chat: true,
          tools: %{enabled: true, streaming: true}
        },
        tags: ["fast", "cheap"],
        deprecated?: false,
        aliases: ["gpt-4o-mini-latest"],
        extra: %{"custom" => "value"}
      }

      assert {:ok, result} = Validate.validate_model(input)
      assert result.id == "gpt-4o-mini"
      assert result.provider == :openai
      assert result.provider_model_id == "gpt-4o-mini-2024-07-18"
      assert result.name == "GPT-4o Mini"
      assert result.family == "gpt-4o"
      assert result.release_date == "2024-07-18"
      assert result.last_updated == "2024-10-01"
      assert result.knowledge == "2023-10"
      assert result.limits.context == 128_000
      assert result.limits.output == 16_384
      assert result.cost.input == 0.15
      assert result.cost.output == 0.60
      assert result.modalities.input == [:text, :image]
      assert result.modalities.output == [:text]
      assert result.capabilities.chat == true
      assert result.capabilities.tools.enabled == true
      assert result.capabilities.tools.streaming == true
      assert result.tags == ["fast", "cheap"]
      assert result.deprecated? == false
      assert result.aliases == ["gpt-4o-mini-latest"]
      assert result.extra == %{"custom" => "value"}
    end

    test "rejects model with missing required id" do
      input = %{provider: :openai}
      assert {:error, _} = Validate.validate_model(input)
    end

    test "rejects model with missing required provider" do
      input = %{id: "gpt-4o"}
      assert {:error, _} = Validate.validate_model(input)
    end

    test "rejects model with wrong type for id" do
      input = %{id: :gpt_4o, provider: :openai}
      assert {:error, _} = Validate.validate_model(input)
    end

    test "rejects model with wrong type for provider" do
      input = %{id: "gpt-4o", provider: "openai"}
      assert {:error, _} = Validate.validate_model(input)
    end

    test "rejects model with wrong type for name" do
      input = %{id: "gpt-4o", provider: :openai, name: 123}
      assert {:error, _} = Validate.validate_model(input)
    end

    test "rejects model with wrong type for deprecated?" do
      input = %{id: "gpt-4o", provider: :openai, deprecated?: "true"}
      assert {:error, _} = Validate.validate_model(input)
    end

    test "rejects model with wrong type for aliases" do
      input = %{id: "gpt-4o", provider: :openai, aliases: "gpt-4o-latest"}
      assert {:error, _} = Validate.validate_model(input)
    end

    test "rejects model with non-string elements in aliases" do
      input = %{id: "gpt-4o", provider: :openai, aliases: ["gpt-4o-latest", 123]}
      assert {:error, _} = Validate.validate_model(input)
    end

    test "rejects model with wrong type for tags" do
      input = %{id: "gpt-4o", provider: :openai, tags: "fast"}
      assert {:error, _} = Validate.validate_model(input)
    end
  end

  describe "validate_model/1 nested schema validation" do
    test "validates limits schema - rejects negative context" do
      input = %{
        id: "gpt-4o",
        provider: :openai,
        limits: %{context: -1}
      }

      assert {:error, _} = Validate.validate_model(input)
    end

    test "validates limits schema - rejects zero context" do
      input = %{
        id: "gpt-4o",
        provider: :openai,
        limits: %{context: 0}
      }

      assert {:error, _} = Validate.validate_model(input)
    end

    test "validates limits schema - rejects negative output" do
      input = %{
        id: "gpt-4o",
        provider: :openai,
        limits: %{output: -1}
      }

      assert {:error, _} = Validate.validate_model(input)
    end

    test "validates limits schema - accepts valid limits" do
      input = %{
        id: "gpt-4o",
        provider: :openai,
        limits: %{context: 128_000, output: 4_096}
      }

      assert {:ok, result} = Validate.validate_model(input)
      assert result.limits.context == 128_000
      assert result.limits.output == 4_096
    end

    test "validates cost schema - rejects wrong type for input" do
      input = %{
        id: "gpt-4o",
        provider: :openai,
        cost: %{input: "invalid"}
      }

      assert {:error, _} = Validate.validate_model(input)
    end

    test "validates cost schema - accepts integers and floats" do
      input = %{
        id: "gpt-4o",
        provider: :openai,
        cost: %{input: 0.15, output: 1, cache_read: 0.05}
      }

      assert {:ok, result} = Validate.validate_model(input)
      assert result.cost.input == 0.15
      assert result.cost.output == 1
      assert result.cost.cache_read == 0.05
    end

    test "validates capabilities schema - rejects wrong type for chat" do
      input = %{
        id: "gpt-4o",
        provider: :openai,
        capabilities: %{chat: "true"}
      }

      assert {:error, _} = Validate.validate_model(input)
    end

    test "validates capabilities schema - rejects wrong type for embeddings" do
      input = %{
        id: "gpt-4o",
        provider: :openai,
        capabilities: %{embeddings: 1}
      }

      assert {:error, _} = Validate.validate_model(input)
    end

    test "validates capabilities schema - validates nested tools" do
      input = %{
        id: "gpt-4o",
        provider: :openai,
        capabilities: %{
          tools: %{enabled: true, streaming: "invalid"}
        }
      }

      assert {:error, _} = Validate.validate_model(input)
    end

    test "validates capabilities schema - validates nested reasoning" do
      input = %{
        id: "gpt-4o",
        provider: :openai,
        capabilities: %{
          reasoning: %{enabled: true, token_budget: -5}
        }
      }

      assert {:error, _} = Validate.validate_model(input)
    end

    test "validates capabilities schema - accepts valid nested capabilities" do
      input = %{
        id: "gpt-4o",
        provider: :openai,
        capabilities: %{
          chat: true,
          embeddings: false,
          reasoning: %{enabled: true, token_budget: 10_000},
          tools: %{enabled: true, streaming: true, strict: true, parallel: true},
          json: %{native: true, schema: true, strict: true},
          streaming: %{text: true, tool_calls: true}
        }
      }

      assert {:ok, result} = Validate.validate_model(input)
      assert result.capabilities.chat == true
      assert result.capabilities.embeddings == false
      assert result.capabilities.reasoning.enabled == true
      assert result.capabilities.reasoning.token_budget == 10_000
      assert result.capabilities.tools.enabled == true
      assert result.capabilities.tools.streaming == true
      assert result.capabilities.json.native == true
      assert result.capabilities.streaming.text == true
    end

    test "validates modalities - rejects non-atom input elements" do
      input = %{
        id: "gpt-4o",
        provider: :openai,
        modalities: %{input: ["text"]}
      }

      assert {:error, _} = Validate.validate_model(input)
    end

    test "validates modalities - rejects non-atom output elements" do
      input = %{
        id: "gpt-4o",
        provider: :openai,
        modalities: %{output: ["text", "audio"]}
      }

      assert {:error, _} = Validate.validate_model(input)
    end

    test "validates modalities - accepts valid atom arrays" do
      input = %{
        id: "gpt-4o",
        provider: :openai,
        modalities: %{
          input: [:text, :image, :audio],
          output: [:text, :audio]
        }
      }

      assert {:ok, result} = Validate.validate_model(input)
      assert result.modalities.input == [:text, :image, :audio]
      assert result.modalities.output == [:text, :audio]
    end
  end

  describe "validate_providers/1" do
    test "validates all valid providers" do
      providers = [
        %{id: :openai},
        %{id: :anthropic, name: "Anthropic"},
        %{id: :google, env: ["GOOGLE_API_KEY"]}
      ]

      assert {:ok, valid, 0} = Validate.validate_providers(providers)
      assert length(valid) == 3
      assert Enum.at(valid, 0).id == :openai
      assert Enum.at(valid, 1).id == :anthropic
      assert Enum.at(valid, 2).id == :google
    end

    test "validates empty list" do
      assert {:ok, [], 0} = Validate.validate_providers([])
    end

    test "collects valid providers and counts invalid ones" do
      providers = [
        %{id: :openai},
        %{id: "invalid_string"},
        %{id: :anthropic},
        %{name: "Missing ID"},
        %{id: :google}
      ]

      assert {:ok, valid, 2} = Validate.validate_providers(providers)
      assert length(valid) == 3
      assert Enum.at(valid, 0).id == :openai
      assert Enum.at(valid, 1).id == :anthropic
      assert Enum.at(valid, 2).id == :google
    end

    test "drops all invalid providers" do
      providers = [
        %{id: "string_not_atom"},
        %{name: "No ID"},
        %{id: 123}
      ]

      assert {:ok, [], 3} = Validate.validate_providers(providers)
    end

    test "preserves order of valid providers" do
      providers = [
        %{id: :first},
        %{id: "invalid"},
        %{id: :second},
        %{id: :third}
      ]

      assert {:ok, valid, 1} = Validate.validate_providers(providers)
      assert Enum.map(valid, & &1.id) == [:first, :second, :third]
    end
  end

  describe "validate_models/1" do
    test "validates all valid models" do
      models = [
        %{id: "gpt-4o", provider: :openai},
        %{id: "claude-3", provider: :anthropic},
        %{id: "gemini-pro", provider: :google}
      ]

      assert {:ok, valid, 0} = Validate.validate_models(models)
      assert length(valid) == 3
      assert Enum.at(valid, 0).id == "gpt-4o"
      assert Enum.at(valid, 1).id == "claude-3"
      assert Enum.at(valid, 2).id == "gemini-pro"
    end

    test "validates empty list" do
      assert {:ok, [], 0} = Validate.validate_models([])
    end

    test "collects valid models and counts invalid ones" do
      models = [
        %{id: "gpt-4o", provider: :openai},
        %{id: :invalid_atom, provider: :openai},
        %{id: "claude-3", provider: :anthropic},
        %{id: "missing-provider"},
        %{id: "gemini-pro", provider: :google}
      ]

      assert {:ok, valid, 2} = Validate.validate_models(models)
      assert length(valid) == 3
      assert Enum.at(valid, 0).id == "gpt-4o"
      assert Enum.at(valid, 1).id == "claude-3"
      assert Enum.at(valid, 2).id == "gemini-pro"
    end

    test "drops all invalid models" do
      models = [
        %{id: :atom_not_string, provider: :openai},
        %{id: "no-provider"},
        %{provider: :openai}
      ]

      assert {:ok, [], 3} = Validate.validate_models(models)
    end

    test "preserves order of valid models" do
      models = [
        %{id: "first", provider: :openai},
        %{id: :invalid, provider: :openai},
        %{id: "second", provider: :anthropic},
        %{id: "third", provider: :google}
      ]

      assert {:ok, valid, 1} = Validate.validate_models(models)
      assert Enum.map(valid, & &1.id) == ["first", "second", "third"]
    end

    test "validates models with complex nested schemas" do
      models = [
        %{
          id: "gpt-4o",
          provider: :openai,
          limits: %{context: 128_000},
          cost: %{input: 0.15},
          capabilities: %{chat: true}
        },
        %{
          id: "invalid",
          provider: :openai,
          limits: %{context: -1}
        },
        %{
          id: "claude-3",
          provider: :anthropic,
          capabilities: %{
            reasoning: %{enabled: true, token_budget: 5000}
          }
        }
      ]

      assert {:ok, valid, 1} = Validate.validate_models(models)
      assert length(valid) == 2
      assert Enum.at(valid, 0).id == "gpt-4o"
      assert Enum.at(valid, 1).id == "claude-3"
    end
  end

  describe "ensure_viable/2" do
    test "returns :ok with non-empty providers and models" do
      providers = [%{id: :openai}]
      models = [%{id: "gpt-4o", provider: :openai, deprecated?: false, aliases: []}]

      assert :ok = Validate.ensure_viable(providers, models)
    end

    test "returns :ok with multiple providers and models" do
      providers = [
        %{id: :openai},
        %{id: :anthropic},
        %{id: :google}
      ]

      models = [
        %{id: "gpt-4o", provider: :openai, deprecated?: false, aliases: []},
        %{id: "claude-3", provider: :anthropic, deprecated?: false, aliases: []},
        %{id: "gemini-pro", provider: :google, deprecated?: false, aliases: []}
      ]

      assert :ok = Validate.ensure_viable(providers, models)
    end

    test "returns error when providers is empty" do
      providers = []
      models = [%{id: "gpt-4o", provider: :openai, deprecated?: false, aliases: []}]

      assert {:error, :empty_catalog} = Validate.ensure_viable(providers, models)
    end

    test "returns error when models is empty" do
      providers = [%{id: :openai}]
      models = []

      assert {:error, :empty_catalog} = Validate.ensure_viable(providers, models)
    end

    test "returns error when both are empty" do
      assert {:error, :empty_catalog} = Validate.ensure_viable([], [])
    end
  end

  describe "integration: validate then ensure_viable" do
    test "validates batch and ensures viability - success case" do
      raw_providers = [
        %{id: :openai},
        %{id: "invalid"},
        %{id: :anthropic}
      ]

      raw_models = [
        %{id: "gpt-4o", provider: :openai},
        %{id: :invalid, provider: :openai},
        %{id: "claude-3", provider: :anthropic}
      ]

      assert {:ok, providers, 1} = Validate.validate_providers(raw_providers)
      assert {:ok, models, 1} = Validate.validate_models(raw_models)
      assert :ok = Validate.ensure_viable(providers, models)
    end

    test "validates batch and ensures viability - failure case all providers invalid" do
      raw_providers = [
        %{id: "invalid"},
        %{name: "No ID"}
      ]

      raw_models = [
        %{id: "gpt-4o", provider: :openai}
      ]

      assert {:ok, providers, 2} = Validate.validate_providers(raw_providers)
      assert {:ok, models, 0} = Validate.validate_models(raw_models)
      assert {:error, :empty_catalog} = Validate.ensure_viable(providers, models)
    end

    test "validates batch and ensures viability - failure case all models invalid" do
      raw_providers = [
        %{id: :openai}
      ]

      raw_models = [
        %{id: :invalid, provider: :openai},
        %{id: "no-provider"}
      ]

      assert {:ok, providers, 0} = Validate.validate_providers(raw_providers)
      assert {:ok, models, 2} = Validate.validate_models(raw_models)
      assert {:error, :empty_catalog} = Validate.ensure_viable(providers, models)
    end
  end
end
