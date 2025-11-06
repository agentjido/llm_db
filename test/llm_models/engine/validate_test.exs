defmodule LLMModels.Engine.ValidateTest do
  use ExUnit.Case, async: true

  alias LLMModels.Validate

  describe "validate_provider/1" do
    test "validates minimal valid provider" do
      input = %{id: :test_provider_alpha}
      assert {:ok, result} = Validate.validate_provider(input)
      assert result.id == :test_provider_alpha
    end

    test "validates complete provider with all fields" do
      input = %{
        id: :test_provider_alpha,
        name: "Test Provider Alpha",
        base_url: "https://alpha.example.com",
        env: ["TEST_API_KEY"],
        doc: "Test provider",
        extra: %{"custom" => "value"}
      }

      assert {:ok, result} = Validate.validate_provider(input)
      assert result.id == :test_provider_alpha
      assert result.name == "Test Provider Alpha"
      assert result.base_url == "https://alpha.example.com"
      assert result.env == ["TEST_API_KEY"]
      assert result.doc == "Test provider"
      assert result.extra == %{"custom" => "value"}
    end

    test "rejects provider with missing required id" do
      input = %{name: "Test Provider"}
      assert {:error, _} = Validate.validate_provider(input)
    end

    test "rejects provider with wrong type for id" do
      input = %{id: "test-provider"}
      assert {:error, _} = Validate.validate_provider(input)
    end

    test "rejects provider with wrong type for name" do
      input = %{id: :test_provider_alpha, name: 123}
      assert {:error, _} = Validate.validate_provider(input)
    end

    test "rejects provider with wrong type for base_url" do
      input = %{id: :test_provider_alpha, base_url: 456}
      assert {:error, _} = Validate.validate_provider(input)
    end

    test "rejects provider with wrong type for env" do
      input = %{id: :test_provider_alpha, env: "TEST_API_KEY"}
      assert {:error, _} = Validate.validate_provider(input)
    end

    test "rejects provider with non-string elements in env array" do
      input = %{id: :test_provider_alpha, env: ["TEST_API_KEY", 123]}
      assert {:error, _} = Validate.validate_provider(input)
    end

    test "rejects provider with wrong type for extra" do
      input = %{id: :test_provider_alpha, extra: "not a map"}
      assert {:error, _} = Validate.validate_provider(input)
    end
  end

  describe "validate_model/1" do
    test "validates minimal valid model" do
      input = %{
        id: "test-model-v1",
        provider: :test_provider_alpha
      }

      assert {:ok, result} = Validate.validate_model(input)
      assert result.id == "test-model-v1"
      assert result.provider == :test_provider_alpha
      assert result.deprecated == false
      assert result.aliases == []
    end

    test "validates complete model with all fields" do
      input = %{
        id: "test-model-v2-advanced",
        provider: :test_provider_alpha,
        provider_model_id: "test-model-v2-advanced-2024-07-18",
        name: "Test Model V2 Advanced",
        family: "test-model-v2",
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
        deprecated: false,
        aliases: ["test-model-latest"],
        extra: %{"custom" => "value"}
      }

      assert {:ok, result} = Validate.validate_model(input)
      assert result.id == "test-model-v2-advanced"
      assert result.provider == :test_provider_alpha
      assert result.provider_model_id == "test-model-v2-advanced-2024-07-18"
      assert result.name == "Test Model V2 Advanced"
      assert result.family == "test-model-v2"
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
      assert result.deprecated == false
      assert result.aliases == ["test-model-latest"]
      assert result.extra == %{"custom" => "value"}
    end

    test "rejects model with missing required id" do
      input = %{provider: :test_provider_alpha}
      assert {:error, _} = Validate.validate_model(input)
    end

    test "rejects model with missing required provider" do
      input = %{id: "test-model-v1"}
      assert {:error, _} = Validate.validate_model(input)
    end

    test "rejects model with wrong type for id" do
      input = %{id: :test_model_v1, provider: :test_provider_alpha}
      assert {:error, _} = Validate.validate_model(input)
    end

    test "rejects model with wrong type for provider" do
      input = %{id: "test-model-v1", provider: "test-provider"}
      assert {:error, _} = Validate.validate_model(input)
    end

    test "rejects model with wrong type for name" do
      input = %{id: "test-model-v1", provider: :test_provider_alpha, name: 123}
      assert {:error, _} = Validate.validate_model(input)
    end

    test "rejects model with wrong type for deprecated" do
      input = %{id: "test-model-v1", provider: :test_provider_alpha, deprecated: "true"}
      assert {:error, _} = Validate.validate_model(input)
    end

    test "rejects model with wrong type for aliases" do
      input = %{id: "test-model-v1", provider: :test_provider_alpha, aliases: "test-model-latest"}
      assert {:error, _} = Validate.validate_model(input)
    end

    test "rejects model with non-string elements in aliases" do
      input = %{
        id: "test-model-v1",
        provider: :test_provider_alpha,
        aliases: ["test-model-latest", 123]
      }

      assert {:error, _} = Validate.validate_model(input)
    end

    test "rejects model with wrong type for tags" do
      input = %{id: "test-model-v1", provider: :test_provider_alpha, tags: "fast"}
      assert {:error, _} = Validate.validate_model(input)
    end
  end

  describe "validate_model/1 nested schema validation" do
    test "validates limits schema - rejects negative context" do
      input = %{
        id: "test-model-v1",
        provider: :test_provider_alpha,
        limits: %{context: -1}
      }

      assert {:error, _} = Validate.validate_model(input)
    end

    test "validates limits schema - rejects zero context" do
      input = %{
        id: "test-model-v1",
        provider: :test_provider_alpha,
        limits: %{context: 0}
      }

      assert {:error, _} = Validate.validate_model(input)
    end

    test "validates limits schema - rejects negative output" do
      input = %{
        id: "test-model-v1",
        provider: :test_provider_alpha,
        limits: %{output: -1}
      }

      assert {:error, _} = Validate.validate_model(input)
    end

    test "validates limits schema - accepts valid limits" do
      input = %{
        id: "test-model-v1",
        provider: :test_provider_alpha,
        limits: %{context: 128_000, output: 4_096}
      }

      assert {:ok, result} = Validate.validate_model(input)
      assert result.limits.context == 128_000
      assert result.limits.output == 4_096
    end

    test "validates cost schema - rejects wrong type for input" do
      input = %{
        id: "test-model-v1",
        provider: :test_provider_alpha,
        cost: %{input: "invalid"}
      }

      assert {:error, _} = Validate.validate_model(input)
    end

    test "validates cost schema - accepts integers and floats" do
      input = %{
        id: "test-model-v1",
        provider: :test_provider_alpha,
        cost: %{input: 0.15, output: 1, cache_read: 0.05}
      }

      assert {:ok, result} = Validate.validate_model(input)
      assert result.cost.input == 0.15
      assert result.cost.output == 1
      assert result.cost.cache_read == 0.05
    end

    test "validates capabilities schema - rejects wrong type for chat" do
      input = %{
        id: "test-model-v1",
        provider: :test_provider_alpha,
        capabilities: %{chat: "true"}
      }

      assert {:error, _} = Validate.validate_model(input)
    end

    test "validates capabilities schema - rejects wrong type for embeddings" do
      input = %{
        id: "test-model-v1",
        provider: :test_provider_alpha,
        capabilities: %{embeddings: 1}
      }

      assert {:error, _} = Validate.validate_model(input)
    end

    test "validates capabilities schema - validates nested tools" do
      input = %{
        id: "test-model-v1",
        provider: :test_provider_alpha,
        capabilities: %{
          tools: %{enabled: true, streaming: "invalid"}
        }
      }

      assert {:error, _} = Validate.validate_model(input)
    end

    test "validates capabilities schema - validates nested reasoning" do
      input = %{
        id: "test-model-v1",
        provider: :test_provider_alpha,
        capabilities: %{
          reasoning: %{enabled: true, token_budget: -5}
        }
      }

      assert {:error, _} = Validate.validate_model(input)
    end

    test "validates capabilities schema - accepts valid nested capabilities" do
      input = %{
        id: "test-model-v1",
        provider: :test_provider_alpha,
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
        id: "test-model-v1",
        provider: :test_provider_alpha,
        modalities: %{input: ["text"]}
      }

      assert {:error, _} = Validate.validate_model(input)
    end

    test "validates modalities - rejects non-atom output elements" do
      input = %{
        id: "test-model-v1",
        provider: :test_provider_alpha,
        modalities: %{output: ["text", "audio"]}
      }

      assert {:error, _} = Validate.validate_model(input)
    end

    test "validates modalities - accepts valid atom arrays" do
      input = %{
        id: "test-model-v1",
        provider: :test_provider_alpha,
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
        %{id: :test_provider_alpha},
        %{id: :test_provider_beta, name: "Anthropic"},
        %{id: :test_provider_gamma, env: ["GOOGLE_API_KEY"]}
      ]

      assert {:ok, valid, 0} = Validate.validate_providers(providers)
      assert length(valid) == 3
      assert Enum.at(valid, 0).id == :test_provider_alpha
      assert Enum.at(valid, 1).id == :test_provider_beta
      assert Enum.at(valid, 2).id == :test_provider_gamma
    end

    test "validates empty list" do
      assert {:ok, [], 0} = Validate.validate_providers([])
    end

    test "collects valid providers and counts invalid ones" do
      providers = [
        %{id: :test_provider_alpha},
        %{id: "invalid_string"},
        %{id: :test_provider_beta},
        %{name: "Missing ID"},
        %{id: :test_provider_gamma}
      ]

      assert {:ok, valid, 2} = Validate.validate_providers(providers)
      assert length(valid) == 3
      assert Enum.at(valid, 0).id == :test_provider_alpha
      assert Enum.at(valid, 1).id == :test_provider_beta
      assert Enum.at(valid, 2).id == :test_provider_gamma
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
        %{id: "test-model-v1", provider: :test_provider_alpha},
        %{id: "test-model-v2", provider: :test_provider_beta},
        %{id: "test-model-v3", provider: :test_provider_gamma}
      ]

      assert {:ok, valid, 0} = Validate.validate_models(models)
      assert length(valid) == 3
      assert Enum.at(valid, 0).id == "test-model-v1"
      assert Enum.at(valid, 1).id == "test-model-v2"
      assert Enum.at(valid, 2).id == "test-model-v3"
    end

    test "validates empty list" do
      assert {:ok, [], 0} = Validate.validate_models([])
    end

    test "collects valid models and counts invalid ones" do
      models = [
        %{id: "test-model-v1", provider: :test_provider_alpha},
        %{id: :invalid_atom, provider: :test_provider_alpha},
        %{id: "test-model-v2", provider: :test_provider_beta},
        %{id: "missing-provider"},
        %{id: "test-model-v3", provider: :test_provider_gamma}
      ]

      assert {:ok, valid, 2} = Validate.validate_models(models)
      assert length(valid) == 3
      assert Enum.at(valid, 0).id == "test-model-v1"
      assert Enum.at(valid, 1).id == "test-model-v2"
      assert Enum.at(valid, 2).id == "test-model-v3"
    end

    test "drops all invalid models" do
      models = [
        %{id: :atom_not_string, provider: :test_provider_alpha},
        %{id: "no-provider"},
        %{provider: :test_provider_alpha}
      ]

      assert {:ok, [], 3} = Validate.validate_models(models)
    end

    test "preserves order of valid models" do
      models = [
        %{id: "first", provider: :test_provider_alpha},
        %{id: :invalid, provider: :test_provider_alpha},
        %{id: "second", provider: :test_provider_beta},
        %{id: "third", provider: :test_provider_gamma}
      ]

      assert {:ok, valid, 1} = Validate.validate_models(models)
      assert Enum.map(valid, & &1.id) == ["first", "second", "third"]
    end

    test "validates models with complex nested schemas" do
      models = [
        %{
          id: "test-model-v1",
          provider: :test_provider_alpha,
          limits: %{context: 128_000},
          cost: %{input: 0.15},
          capabilities: %{chat: true}
        },
        %{
          id: "invalid",
          provider: :test_provider_alpha,
          limits: %{context: -1}
        },
        %{
          id: "test-model-v2",
          provider: :test_provider_beta,
          capabilities: %{
            reasoning: %{enabled: true, token_budget: 5000}
          }
        }
      ]

      assert {:ok, valid, 1} = Validate.validate_models(models)
      assert length(valid) == 2
      assert Enum.at(valid, 0).id == "test-model-v1"
      assert Enum.at(valid, 1).id == "test-model-v2"
    end
  end

  describe "ensure_viable/2" do
    test "returns :ok with non-empty providers and models" do
      providers = [%{id: :test_provider_alpha}]

      models = [
        %{id: "test-model-v1", provider: :test_provider_alpha, deprecated: false, aliases: []}
      ]

      assert :ok = Validate.ensure_viable(providers, models)
    end

    test "returns :ok with multiple providers and models" do
      providers = [
        %{id: :test_provider_alpha},
        %{id: :test_provider_beta},
        %{id: :test_provider_gamma}
      ]

      models = [
        %{id: "test-model-v1", provider: :test_provider_alpha, deprecated: false, aliases: []},
        %{id: "test-model-v2", provider: :test_provider_beta, deprecated: false, aliases: []},
        %{id: "test-model-v3", provider: :test_provider_gamma, deprecated: false, aliases: []}
      ]

      assert :ok = Validate.ensure_viable(providers, models)
    end

    test "returns error when providers is empty" do
      providers = []

      models = [
        %{id: "test-model-v1", provider: :test_provider_alpha, deprecated: false, aliases: []}
      ]

      assert {:error, :empty_catalog} = Validate.ensure_viable(providers, models)
    end

    test "returns error when models is empty" do
      providers = [%{id: :test_provider_alpha}]
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
        %{id: :test_provider_alpha},
        %{id: "invalid"},
        %{id: :test_provider_beta}
      ]

      raw_models = [
        %{id: "test-model-v1", provider: :test_provider_alpha},
        %{id: :invalid, provider: :test_provider_alpha},
        %{id: "test-model-v2", provider: :test_provider_beta}
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
        %{id: "test-model-v1", provider: :test_provider_alpha}
      ]

      assert {:ok, providers, 2} = Validate.validate_providers(raw_providers)
      assert {:ok, models, 0} = Validate.validate_models(raw_models)
      assert {:error, :empty_catalog} = Validate.ensure_viable(providers, models)
    end

    test "validates batch and ensures viability - failure case all models invalid" do
      raw_providers = [
        %{id: :test_provider_alpha}
      ]

      raw_models = [
        %{id: :invalid, provider: :test_provider_alpha},
        %{id: "no-provider"}
      ]

      assert {:ok, providers, 0} = Validate.validate_providers(raw_providers)
      assert {:ok, models, 2} = Validate.validate_models(raw_models)
      assert {:error, :empty_catalog} = Validate.ensure_viable(providers, models)
    end
  end
end
