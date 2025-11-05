defmodule LLMModels.SpecTest do
  use ExUnit.Case, async: false

  alias LLMModels.{Spec, Store}

  setup do
    Store.clear!()

    providers = [
      %{id: :openai, name: "OpenAI"},
      %{id: :anthropic, name: "Anthropic"},
      %{id: :google_vertex, name: "Google Vertex AI"}
    ]

    models = [
      %{
        id: "gpt-4",
        provider: :openai,
        name: "GPT-4",
        aliases: ["gpt-4-0613"]
      },
      %{
        id: "gpt-3.5-turbo",
        provider: :openai,
        name: "GPT-3.5 Turbo",
        aliases: []
      },
      %{
        id: "claude-3-opus",
        provider: :anthropic,
        name: "Claude 3 Opus",
        aliases: ["claude-opus"]
      },
      %{
        id: "gemini-pro",
        provider: :google_vertex,
        name: "Gemini Pro",
        aliases: []
      },
      %{
        id: "model:with:colons",
        provider: :openai,
        name: "Model with colons in ID",
        aliases: []
      },
      %{
        id: "shared-model",
        provider: :openai,
        name: "Shared Model OpenAI",
        aliases: []
      },
      %{
        id: "shared-model",
        provider: :anthropic,
        name: "Shared Model Anthropic",
        aliases: []
      }
    ]

    providers_by_id = Map.new(providers, fn p -> {p.id, p} end)
    models_by_key = Map.new(models, fn m -> {{m.provider, m.id}, m} end)
    models_by_provider = Enum.group_by(models, & &1.provider)

    aliases_by_key =
      Enum.flat_map(models, fn model ->
        Enum.map(model.aliases, fn alias_id ->
          {{model.provider, alias_id}, model.id}
        end)
      end)
      |> Map.new()

    snapshot = %{
      providers_by_id: providers_by_id,
      models_by_key: models_by_key,
      models_by_provider: models_by_provider,
      aliases_by_key: aliases_by_key
    }

    Store.put!(snapshot, [])

    on_exit(fn -> Store.clear!() end)

    {:ok, snapshot: snapshot}
  end

  describe "parse_provider/1" do
    test "accepts atom provider" do
      assert {:ok, :openai} = Spec.parse_provider(:openai)
    end

    test "accepts string provider and normalizes" do
      assert {:ok, :google_vertex} = Spec.parse_provider("google-vertex")
    end

    test "accepts string provider without normalization" do
      assert {:ok, :openai} = Spec.parse_provider("openai")
    end

    test "returns error for unknown provider atom" do
      assert {:error, :unknown_provider} = Spec.parse_provider(:unknown)
    end

    test "returns error for unknown provider string" do
      assert {:error, :unknown_provider} = Spec.parse_provider("unknown")
    end

    test "returns error for invalid provider format" do
      assert {:error, :bad_provider} = Spec.parse_provider("")
      assert {:error, :bad_provider} = Spec.parse_provider(String.duplicate("a", 256))
      assert {:error, :bad_provider} = Spec.parse_provider("invalid@provider")
      assert {:error, :bad_provider} = Spec.parse_provider(123)
    end

    test "returns error when store is not initialized" do
      Store.clear!()
      assert {:error, :unknown_provider} = Spec.parse_provider(:openai)
    end
  end

  describe "parse_spec/1" do
    test "parses valid provider:model format" do
      assert {:ok, {:openai, "gpt-4"}} = Spec.parse_spec("openai:gpt-4")
    end

    test "normalizes provider with hyphens" do
      assert {:ok, {:google_vertex, "gemini-pro"}} = Spec.parse_spec("google-vertex:gemini-pro")
    end

    test "handles model IDs with colons (splits only at first colon)" do
      assert {:ok, {:openai, "model:with:colons"}} = Spec.parse_spec("openai:model:with:colons")
    end

    test "trims whitespace from model ID" do
      assert {:ok, {:openai, "gpt-4"}} = Spec.parse_spec("openai: gpt-4 ")
    end

    test "returns error when no colon present" do
      assert {:error, :invalid_format} = Spec.parse_spec("gpt-4")
    end

    test "returns error when provider is unknown" do
      assert {:error, :unknown_provider} = Spec.parse_spec("unknown:model")
    end

    test "returns error when provider is invalid" do
      assert {:error, :bad_provider} = Spec.parse_spec(":model")
      assert {:error, :bad_provider} = Spec.parse_spec("invalid@provider:model")
    end

    test "returns error for empty string" do
      assert {:error, :invalid_format} = Spec.parse_spec("")
    end

    test "handles edge case with only colon" do
      assert {:error, :bad_provider} = Spec.parse_spec(":")
    end
  end

  describe "resolve/2 with provider:model string" do
    test "resolves valid provider:model spec" do
      assert {:ok, {:openai, "gpt-4", model}} = Spec.resolve("openai:gpt-4")
      assert model.id == "gpt-4"
      assert model.provider == :openai
      assert model.name == "GPT-4"
    end

    test "resolves with normalized provider" do
      assert {:ok, {:google_vertex, "gemini-pro", model}} =
               Spec.resolve("google-vertex:gemini-pro")

      assert model.id == "gemini-pro"
    end

    test "resolves model ID with colons" do
      assert {:ok, {:openai, "model:with:colons", model}} =
               Spec.resolve("openai:model:with:colons")

      assert model.id == "model:with:colons"
    end

    test "returns error for nonexistent model" do
      assert {:error, :not_found} = Spec.resolve("openai:nonexistent")
    end

    test "returns error for unknown provider" do
      assert {:error, :unknown_provider} = Spec.resolve("unknown:model")
    end
  end

  describe "resolve/2 with {provider, model_id} tuple" do
    test "resolves valid tuple" do
      assert {:ok, {:openai, "gpt-4", model}} = Spec.resolve({:openai, "gpt-4"})
      assert model.id == "gpt-4"
    end

    test "resolves with different providers" do
      assert {:ok, {:anthropic, "claude-3-opus", model}} =
               Spec.resolve({:anthropic, "claude-3-opus"})

      assert model.id == "claude-3-opus"
    end

    test "returns error for nonexistent model" do
      assert {:error, :not_found} = Spec.resolve({:openai, "nonexistent"})
    end

    test "ignores opts when tuple provided" do
      assert {:ok, {:openai, "gpt-4", _}} = Spec.resolve({:openai, "gpt-4"}, scope: :anthropic)
    end
  end

  describe "resolve/2 with bare model ID and scope" do
    test "resolves bare model with scope option" do
      assert {:ok, {:openai, "gpt-4", model}} = Spec.resolve("gpt-4", scope: :openai)
      assert model.id == "gpt-4"
    end

    test "resolves different models with different scopes" do
      assert {:ok, {:openai, "shared-model", model1}} =
               Spec.resolve("shared-model", scope: :openai)

      assert model1.name == "Shared Model OpenAI"

      assert {:ok, {:anthropic, "shared-model", model2}} =
               Spec.resolve("shared-model", scope: :anthropic)

      assert model2.name == "Shared Model Anthropic"
    end

    test "returns error for nonexistent model in scope" do
      assert {:error, :not_found} = Spec.resolve("nonexistent", scope: :openai)
    end
  end

  describe "resolve/2 with bare model ID without scope" do
    test "resolves unique bare model ID" do
      assert {:ok, {:openai, "gpt-3.5-turbo", model}} = Spec.resolve("gpt-3.5-turbo")
      assert model.id == "gpt-3.5-turbo"
    end

    test "returns error for ambiguous bare model ID" do
      assert {:error, :ambiguous} = Spec.resolve("shared-model")
    end

    test "returns error for nonexistent bare model" do
      assert {:error, :not_found} = Spec.resolve("nonexistent")
    end
  end

  describe "resolve/2 with alias resolution" do
    test "resolves alias to canonical ID" do
      assert {:ok, {:openai, "gpt-4", model}} = Spec.resolve("openai:gpt-4-0613")
      assert model.id == "gpt-4"
      assert model.name == "GPT-4"
    end

    test "resolves alias with tuple input" do
      assert {:ok, {:openai, "gpt-4", model}} = Spec.resolve({:openai, "gpt-4-0613"})
      assert model.id == "gpt-4"
    end

    test "resolves alias with scope" do
      assert {:ok, {:anthropic, "claude-3-opus", model}} =
               Spec.resolve("claude-opus", scope: :anthropic)

      assert model.id == "claude-3-opus"
    end

    test "resolves bare alias when unique" do
      assert {:ok, {:anthropic, "claude-3-opus", model}} = Spec.resolve("claude-opus")
      assert model.id == "claude-3-opus"
    end
  end

  describe "resolve/2 edge cases" do
    test "returns error for invalid input types" do
      assert {:error, :invalid_format} = Spec.resolve(nil)
      assert {:error, :invalid_format} = Spec.resolve(123)
      assert {:error, :invalid_format} = Spec.resolve(%{})
      assert {:error, :invalid_format} = Spec.resolve([])
    end

    test "returns error for malformed tuple" do
      assert {:error, :invalid_format} = Spec.resolve({"openai", "gpt-4"})
      assert {:error, :invalid_format} = Spec.resolve({:openai, :gpt_4})
    end

    test "returns error for empty string" do
      assert {:error, :not_found} = Spec.resolve("")
    end

    test "handles nil snapshot gracefully" do
      Store.clear!()
      assert {:error, :unknown_provider} = Spec.resolve("openai:gpt-4")
      assert {:error, :not_found} = Spec.resolve({:openai, "gpt-4"})
      assert {:error, :not_found} = Spec.resolve("gpt-4", scope: :openai)
    end
  end

  describe "integration with real snapshot data" do
    test "resolves models across multiple providers" do
      assert {:ok, {:openai, "gpt-4", _}} = Spec.resolve("openai:gpt-4")
      assert {:ok, {:anthropic, "claude-3-opus", _}} = Spec.resolve("anthropic:claude-3-opus")
      assert {:ok, {:google_vertex, "gemini-pro", _}} = Spec.resolve("google-vertex:gemini-pro")
    end

    test "all test providers are recognized" do
      assert {:ok, :openai} = Spec.parse_provider(:openai)
      assert {:ok, :anthropic} = Spec.parse_provider(:anthropic)
      assert {:ok, :google_vertex} = Spec.parse_provider(:google_vertex)
    end

    test "all test models can be resolved by spec" do
      assert {:ok, {:openai, "gpt-4", _}} = Spec.resolve("openai:gpt-4")
      assert {:ok, {:openai, "gpt-3.5-turbo", _}} = Spec.resolve("openai:gpt-3.5-turbo")
      assert {:ok, {:anthropic, "claude-3-opus", _}} = Spec.resolve("anthropic:claude-3-opus")
      assert {:ok, {:google_vertex, "gemini-pro", _}} = Spec.resolve("google-vertex:gemini-pro")
    end

    test "canonical IDs are returned even when aliases used" do
      {:ok, {provider, canonical_id, _}} = Spec.resolve("openai:gpt-4-0613")
      assert provider == :openai
      assert canonical_id == "gpt-4"

      {:ok, {provider, canonical_id, _}} = Spec.resolve("anthropic:claude-opus")
      assert provider == :anthropic
      assert canonical_id == "claude-3-opus"
    end
  end
end
