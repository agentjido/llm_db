defmodule LLMDB.Sources.AzureFoundryTest do
  use ExUnit.Case, async: true
  alias LLMDB.Sources.AzureFoundry

  @chat_model %{
    "annotations" => %{
      "name" => "Grok-3",
      "systemCatalogData" => %{
        "displayName" => "grok-3",
        "publisher" => "xAI",
        "license" => "proprietary",
        "textContextWindow" => 131_072,
        "maxOutputTokens" => 4096,
        "inputModalities" => ["text"],
        "outputModalities" => ["text"],
        "inferenceTasks" => ["chat-completion", "responses"],
        "modelCapabilities" => ["agentsV2", "streaming", "tool-calling"],
        "azureOffers" => ["standard-paygo"]
      }
    },
    "entityResourceName" => "azureml-xai"
  }

  @anthropic_model %{
    "annotations" => %{
      "name" => "Claude-4-Sonnet",
      "systemCatalogData" => %{
        "displayName" => "Claude 4 Sonnet",
        "publisher" => "Anthropic",
        "license" => "proprietary",
        "textContextWindow" => 200_000,
        "maxOutputTokens" => 8192,
        "inputModalities" => ["text", "image"],
        "outputModalities" => ["text"],
        "inferenceTasks" => ["messages"],
        "modelCapabilities" => ["streaming"],
        "azureOffers" => ["standard-paygo"]
      }
    },
    "entityResourceName" => "azureml-anthropic"
  }

  @embedding_model %{
    "annotations" => %{
      "name" => "Cohere-Embed-V3",
      "systemCatalogData" => %{
        "displayName" => "Cohere Embed v3",
        "publisher" => "Cohere",
        "license" => "proprietary",
        "textContextWindow" => 512,
        "inputModalities" => ["text"],
        "outputModalities" => nil,
        "inferenceTasks" => ["embeddings"],
        "modelCapabilities" => [],
        "azureOffers" => ["standard-paygo"]
      }
    },
    "entityResourceName" => "azureml-cohere"
  }

  @vm_model %{
    "annotations" => %{
      "name" => "Some-VM-Model",
      "systemCatalogData" => %{
        "displayName" => "VM Only Model",
        "publisher" => "Microsoft",
        "inferenceTasks" => ["chat-completion"],
        "modelCapabilities" => [],
        "azureOffers" => ["VM"]
      }
    },
    "entityResourceName" => "azureml"
  }

  describe "transform/1" do
    test "filters to standard-paygo models only" do
      input = [@chat_model, @vm_model]
      result = AzureFoundry.transform(input)

      models = result["azure_foundry"].models
      assert length(models) == 1
      assert hd(models).id == "grok-3"
    end

    test "includes azure-openai registry models regardless of offers" do
      openai_model = %{
        "annotations" => %{
          "name" => "gpt-5",
          "systemCatalogData" => %{
            "displayName" => "gpt-5",
            "publisher" => "OpenAI",
            "textContextWindow" => 200_000,
            "maxOutputTokens" => 16_384,
            "inputModalities" => ["text"],
            "outputModalities" => ["text"],
            "inferenceTasks" => ["chat-completion", "responses"],
            "modelCapabilities" => ["agentsV2", "reasoning"],
            "azureOffers" => nil
          }
        },
        "entityResourceName" => "azure-openai"
      }

      result = AzureFoundry.transform([openai_model, @vm_model])
      models = result["azure_foundry"].models

      assert length(models) == 1
      assert hd(models).id == "gpt-5"
    end

    test "correctly transforms chat model fields" do
      result = AzureFoundry.transform([@chat_model])
      model = hd(result["azure_foundry"].models)

      assert model.id == "grok-3"
      assert model.provider == :azure_foundry
      assert model.name == "grok-3"
      assert model.limits == %{context: 131_072, output: 4096}
      assert model.modalities == %{input: [:text], output: [:text]}
      assert model.type == :chat
    end

    test "lowercases model ID from annotations.name" do
      result = AzureFoundry.transform([@chat_model])
      model = hd(result["azure_foundry"].models)

      assert model.id == "grok-3"
    end

    test "assigns :anthropic_messages wire protocol for messages task" do
      result = AzureFoundry.transform([@anthropic_model])
      model = hd(result["azure_foundry"].models)

      assert model.extra.wire_protocol == :anthropic_messages
    end

    test "assigns :openai_responses wire protocol for responses task" do
      result = AzureFoundry.transform([@chat_model])
      model = hd(result["azure_foundry"].models)

      assert model.extra.wire_protocol == :openai_responses
    end

    test "assigns :openai_completion wire protocol for plain chat models" do
      plain_chat =
        @chat_model
        |> put_in(["annotations", "systemCatalogData", "modelCapabilities"], ["streaming"])
        |> put_in(["annotations", "systemCatalogData", "inferenceTasks"], ["chat-completion"])

      result = AzureFoundry.transform([plain_chat])
      model = hd(result["azure_foundry"].models)

      assert model.extra.wire_protocol == :openai_completion
    end

    test "assigns nil wire protocol for non-chat models" do
      result = AzureFoundry.transform([@embedding_model])
      model = hd(result["azure_foundry"].models)

      refute Map.has_key?(model.extra, :wire_protocol)
    end

    test "detects embedding model type" do
      result = AzureFoundry.transform([@embedding_model])
      model = hd(result["azure_foundry"].models)

      assert model.type == :embedding
    end

    test "embedding models output :embedding modality" do
      result = AzureFoundry.transform([@embedding_model])
      model = hd(result["azure_foundry"].models)

      assert model.modalities == %{input: [:text], output: [:embedding]}
    end

    test "includes publisher, license, capabilities, registry in extra" do
      result = AzureFoundry.transform([@chat_model])
      model = hd(result["azure_foundry"].models)

      assert model.extra.publisher == "xAI"
      assert model.extra.license == "proprietary"
      assert model.extra.capabilities == ["agentsV2", "streaming", "tool-calling"]
      assert model.extra.registry == "azureml-xai"
    end

    test "returns canonical format structure" do
      result = AzureFoundry.transform([@chat_model])

      assert %{"azure_foundry" => provider} = result
      assert provider.id == :azure_foundry
      assert provider.name == "Azure AI Foundry"
      assert is_list(provider.models)
    end

    test "include_families filters by case-insensitive prefix" do
      models = [
        @chat_model,
        @anthropic_model,
        @embedding_model
      ]

      result = AzureFoundry.transform(models, include_families: ["grok", "cohere"])
      model_ids = Enum.map(result["azure_foundry"].models, & &1.id)

      assert "grok-3" in model_ids
      assert "cohere-embed-v3" in model_ids
      refute "claude-4-sonnet" in model_ids
    end

    test "include_families is case-insensitive" do
      result = AzureFoundry.transform([@chat_model], include_families: ["GROK"])
      assert length(result["azure_foundry"].models) == 1
    end

    test "empty include_families includes all models" do
      models = [@chat_model, @anthropic_model]

      result = AzureFoundry.transform(models, include_families: [])
      assert length(result["azure_foundry"].models) == 2
    end

    test "omitted include_families includes all models" do
      models = [@chat_model, @anthropic_model]

      result = AzureFoundry.transform(models)
      assert length(result["azure_foundry"].models) == 2
    end

    test "detects image_generation type" do
      image_model =
        put_in(@chat_model, ["annotations", "systemCatalogData", "inferenceTasks"], [
          "text-to-image"
        ])

      image_model =
        put_in(image_model, ["annotations", "systemCatalogData", "modelCapabilities"], [])

      result = AzureFoundry.transform([image_model])
      model = hd(result["azure_foundry"].models)

      assert model.type == :image_generation
    end

    test "detects rerank type from text-classification" do
      rerank_model =
        put_in(@chat_model, ["annotations", "systemCatalogData", "inferenceTasks"], [
          "text-classification"
        ])

      rerank_model =
        put_in(rerank_model, ["annotations", "systemCatalogData", "modelCapabilities"], [])

      result = AzureFoundry.transform([rerank_model])
      model = hd(result["azure_foundry"].models)

      assert model.type == :rerank
    end

    test "handles missing limits gracefully" do
      model = %{
        "annotations" => %{
          "name" => "Minimal-Model",
          "systemCatalogData" => %{
            "displayName" => "Minimal",
            "publisher" => "Test",
            "inferenceTasks" => ["chat-completion"],
            "modelCapabilities" => [],
            "inputModalities" => ["text"],
            "azureOffers" => ["standard-paygo"]
          }
        },
        "entityResourceName" => "azureml"
      }

      result = AzureFoundry.transform([model])
      transformed = hd(result["azure_foundry"].models)

      assert transformed.id == "minimal-model"
      assert transformed.limits == %{}
    end
  end
end
