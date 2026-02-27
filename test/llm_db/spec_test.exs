defmodule LLMDB.SpecTest do
  use ExUnit.Case, async: false

  alias LLMDB.{Spec, Store}

  setup do
    Store.clear!()

    providers = [
      %{id: :openai, name: "OpenAI"},
      %{id: :anthropic, name: "Anthropic"},
      %{id: :google_vertex, name: "Google Vertex AI"},
      %{id: :amazon_bedrock, name: "Amazon Bedrock"}
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
      },
      %{
        id: "anthropic.claude-opus-4-1-20250805-v1:0",
        provider: :amazon_bedrock,
        name: "Claude Opus 4.1",
        aliases: ["anthropic.claude-opus"]
      },
      %{
        id: "meta.llama3-2-3b-instruct-v1:0",
        provider: :amazon_bedrock,
        name: "Llama 3.2 3B",
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

  describe "parse_spec/1 with colon format" do
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

    test "returns error when no separator present" do
      assert {:error, :invalid_format} = Spec.parse_spec("gpt-4")
    end

    test "returns error when provider is unknown" do
      assert {:error, :unknown_provider} = Spec.parse_spec("unknown:model")
    end

    test "returns error when provider is invalid" do
      assert {:error, :empty_segment} = Spec.parse_spec(":model")
    end

    test "returns error for empty string" do
      assert {:error, :invalid_format} = Spec.parse_spec("")
    end

    test "handles edge case with only colon" do
      assert {:error, :empty_segment} = Spec.parse_spec(":")
    end
  end

  describe "parse_spec/1 with @ format" do
    test "parses valid model@provider format" do
      assert {:ok, {:openai, "gpt-4"}} = Spec.parse_spec("gpt-4@openai")
    end

    test "normalizes provider with hyphens in @ format" do
      assert {:ok, {:google_vertex, "gemini-pro"}} =
               Spec.parse_spec("gemini-pro@google-vertex")
    end

    test "trims whitespace from model ID in @ format" do
      assert {:ok, {:openai, "gpt-4"}} = Spec.parse_spec(" gpt-4 @openai")
    end

    test "returns error when provider is unknown in @ format" do
      assert {:error, :unknown_provider} = Spec.parse_spec("model@unknown")
    end

    test "returns error when provider is invalid in @ format" do
      assert {:error, :empty_segment} = Spec.parse_spec("model@")
    end

    test "handles edge case with only @ symbol" do
      assert {:error, :empty_segment} = Spec.parse_spec("@")
    end

    test "parses models with dashes and dots" do
      assert {:ok, {:openai, "gpt-4o-mini"}} = Spec.parse_spec("gpt-4o-mini@openai")
    end
  end

  describe "parse_spec/2 with explicit format" do
    test "parses with explicit :colon format" do
      assert {:ok, {:openai, "gpt-4"}} = Spec.parse_spec("openai:gpt-4", format: :colon)
    end

    test "parses with explicit :at format" do
      assert {:ok, {:openai, "gpt-4"}} = Spec.parse_spec("gpt-4@openai", format: :at)
    end

    test "resolves ambiguous format by prioritizing first separator" do
      # When both : and @ present without explicit format, check which comes first
      # provider:model@suffix -> colon comes first -> parse as provider:model@suffix
      assert {:ok, {:openai, "model@ambiguous"}} = Spec.parse_spec("openai:model@ambiguous")
    end

    test "allows @ in model segment with explicit :colon format" do
      # Changed: Now allows @ in model IDs for Google Vertex compatibility
      assert {:ok, {:openai, "model@ambiguous"}} =
               Spec.parse_spec("openai:model@ambiguous", format: :colon)
    end

    test "allows colon in model segment with explicit :at format" do
      # Changed: Now allows : in model IDs
      assert {:ok, {:anthropic, "provider:model"}} =
               Spec.parse_spec("provider:model@anthropic", format: :at)
    end
  end

  describe "parse_spec/2 with tuple input" do
    test "accepts tuple format" do
      assert {:ok, {:openai, "gpt-4"}} = Spec.parse_spec({:openai, "gpt-4"})
    end

    test "ignores format option for tuple input" do
      assert {:ok, {:openai, "gpt-4"}} = Spec.parse_spec({:openai, "gpt-4"}, format: :at)
    end
  end

  describe "parse_spec!/1" do
    test "returns tuple on success for colon format" do
      assert {:openai, "gpt-4"} = Spec.parse_spec!("openai:gpt-4")
    end

    test "returns tuple on success for @ format" do
      assert {:openai, "gpt-4"} = Spec.parse_spec!("gpt-4@openai")
    end

    test "raises ArgumentError on invalid format" do
      assert_raise ArgumentError, ~r/invalid model spec/, fn ->
        Spec.parse_spec!("no-separator")
      end
    end

    test "resolves ambiguous format by prioritizing first separator" do
      # Changed: Now resolves ambiguous formats instead of raising
      assert {:openai, "model@ambiguous"} = Spec.parse_spec!("openai:model@ambiguous")
    end

    test "raises ArgumentError on unknown provider" do
      assert_raise ArgumentError, ~r/unknown_provider/, fn ->
        Spec.parse_spec!("unknown:model")
      end
    end
  end

  describe "format_spec/2" do
    test "formats as provider:model by default" do
      assert "openai:gpt-4" = Spec.format_spec({:openai, "gpt-4"})
    end

    test "formats with explicit :provider_colon_model" do
      assert "openai:gpt-4" = Spec.format_spec({:openai, "gpt-4"}, :provider_colon_model)
    end

    test "formats as model@provider with :model_at_provider" do
      assert "gpt-4@openai" = Spec.format_spec({:openai, "gpt-4"}, :model_at_provider)
    end

    test "formats as model@provider with :filename_safe" do
      assert "gpt-4o-mini@openai" = Spec.format_spec({:openai, "gpt-4o-mini"}, :filename_safe)
    end

    test "handles providers with underscores" do
      assert "gemini-pro@google_vertex" =
               Spec.format_spec({:google_vertex, "gemini-pro"}, :model_at_provider)
    end

    test "raises on unknown format" do
      assert_raise ArgumentError, ~r/unknown format/, fn ->
        Spec.format_spec({:openai, "gpt-4"}, :invalid_format)
      end
    end
  end

  describe "build_spec/2" do
    test "builds from colon format to @ format" do
      assert "gpt-4@openai" = Spec.build_spec("openai:gpt-4", format: :filename_safe)
    end

    test "builds from @ format to colon format" do
      assert "openai:gpt-4" = Spec.build_spec("gpt-4@openai", format: :provider_colon_model)
    end

    test "builds from tuple to @ format" do
      assert "gpt-4@openai" = Spec.build_spec({:openai, "gpt-4"}, format: :model_at_provider)
    end

    test "builds from tuple to colon format" do
      assert "openai:gpt-4" = Spec.build_spec({:openai, "gpt-4"}, format: :provider_colon_model)
    end

    test "uses default format when not specified" do
      result = Spec.build_spec("openai:gpt-4")
      assert result == "openai:gpt-4"
    end
  end

  describe "normalize_spec/1" do
    test "normalizes colon format to tuple" do
      assert {:openai, "gpt-4"} = Spec.normalize_spec("openai:gpt-4")
    end

    test "normalizes @ format to tuple" do
      assert {:openai, "gpt-4"} = Spec.normalize_spec("gpt-4@openai")
    end

    test "passes through tuple unchanged" do
      assert {:openai, "gpt-4"} = Spec.normalize_spec({:openai, "gpt-4"})
    end

    test "raises on invalid input" do
      assert_raise ArgumentError, fn ->
        Spec.normalize_spec("no-separator")
      end
    end
  end

  describe "validation rules" do
    test "rejects empty provider segment in colon format" do
      assert {:error, :empty_segment} = Spec.parse_spec(":gpt-4")
    end

    test "rejects empty model segment in colon format" do
      assert {:error, :empty_segment} = Spec.parse_spec("openai:")
    end

    test "rejects empty provider segment in @ format" do
      assert {:error, :empty_segment} = Spec.parse_spec("gpt-4@")
    end

    test "rejects empty model segment in @ format" do
      assert {:error, :empty_segment} = Spec.parse_spec("@openai")
    end

    test "rejects @ in provider segment when ambiguous" do
      # open@ai:gpt-4 -> both formats have invalid provider segments
      # @ format: provider="ai:gpt-4" (has :) -> :invalid_chars
      # Colon format: provider="open@ai" (has @) -> :invalid_chars
      assert {:error, :invalid_chars} = Spec.parse_spec("open@ai:gpt-4")
    end

    test "rejects colon in provider segment when ambiguous" do
      # gpt-4@open:ai -> provider="open:ai" contains :
      assert {:error, :invalid_chars} = Spec.parse_spec("gpt-4@open:ai")
    end

    test "allows colons in model ID for colon format" do
      assert {:ok, {:openai, "model:with:colons"}} =
               Spec.parse_spec("openai:model:with:colons")
    end

    test "resolves @ in model ID for colon format" do
      # Changed: Now allowed for Google Vertex compatibility
      assert {:ok, {:openai, "model@with@ats"}} = Spec.parse_spec("openai:model@with@ats")
    end

    test "resolves colon in model ID for @ format" do
      # Changed: Now allowed
      assert {:ok, {:openai, "model:with:colons"}} =
               Spec.parse_spec("model:with:colons@openai")
    end

    test "with explicit format: rejects @ in provider for colon format" do
      # Provider segment "open@ai" contains @ which is invalid
      assert {:error, :invalid_chars} = Spec.parse_spec("open@ai:model", format: :colon)
    end

    test "with explicit format: rejects : in provider for @ format" do
      # Provider segment "open:ai" contains : which is invalid
      assert {:error, :invalid_chars} = Spec.parse_spec("model@open:ai", format: :at)
    end
  end

  describe "round-trip parsing and formatting" do
    test "colon format round-trips correctly" do
      original = "openai:gpt-4"
      {:ok, spec} = Spec.parse_spec(original)
      formatted = Spec.format_spec(spec, :provider_colon_model)
      assert formatted == original
    end

    test "@ format round-trips correctly" do
      original = "gpt-4@openai"
      {:ok, spec} = Spec.parse_spec(original)
      formatted = Spec.format_spec(spec, :model_at_provider)
      assert formatted == original
    end

    test "can convert between formats" do
      colon_format = "openai:gpt-4"
      {:ok, spec} = Spec.parse_spec(colon_format)

      at_format = Spec.format_spec(spec, :model_at_provider)
      assert at_format == "gpt-4@openai"

      {:ok, spec2} = Spec.parse_spec(at_format)
      assert spec == spec2
    end

    test "round-trips with complex Bedrock model IDs in colon format" do
      original = "amazon_bedrock:anthropic.claude-opus-4-1-20250805-v1:0"
      {:ok, spec} = Spec.parse_spec(original)
      formatted = Spec.format_spec(spec, :provider_colon_model)
      assert formatted == original
    end

    test "round-trips with complex model IDs in @ format" do
      original = "gpt-4o-mini@openai"
      {:ok, spec} = Spec.parse_spec(original)
      formatted = Spec.format_spec(spec, :model_at_provider)
      assert formatted == original
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

  describe "resolve/2 with Bedrock inference profiles" do
    test "resolves inference profile with us. prefix" do
      assert {:ok, {:amazon_bedrock, "us.anthropic.claude-opus-4-1-20250805-v1:0", model}} =
               Spec.resolve("amazon_bedrock:us.anthropic.claude-opus-4-1-20250805-v1:0")

      assert model.id == "anthropic.claude-opus-4-1-20250805-v1:0"
      assert model.name == "Claude Opus 4.1"
    end

    test "resolves inference profile with global. prefix" do
      assert {:ok, {:amazon_bedrock, "global.anthropic.claude-opus-4-1-20250805-v1:0", model}} =
               Spec.resolve("amazon_bedrock:global.anthropic.claude-opus-4-1-20250805-v1:0")

      assert model.id == "anthropic.claude-opus-4-1-20250805-v1:0"
    end

    test "resolves inference profile with eu. prefix" do
      assert {:ok, {:amazon_bedrock, "eu.meta.llama3-2-3b-instruct-v1:0", model}} =
               Spec.resolve("amazon_bedrock:eu.meta.llama3-2-3b-instruct-v1:0")

      assert model.id == "meta.llama3-2-3b-instruct-v1:0"
      assert model.name == "Llama 3.2 3B"
    end

    test "resolves inference profile with ap. prefix" do
      assert {:ok, {:amazon_bedrock, "ap.anthropic.claude-opus-4-1-20250805-v1:0", model}} =
               Spec.resolve("amazon_bedrock:ap.anthropic.claude-opus-4-1-20250805-v1:0")

      assert model.id == "anthropic.claude-opus-4-1-20250805-v1:0"
    end

    test "resolves inference profile with ca. prefix" do
      assert {:ok, {:amazon_bedrock, "ca.anthropic.claude-opus-4-1-20250805-v1:0", model}} =
               Spec.resolve("amazon_bedrock:ca.anthropic.claude-opus-4-1-20250805-v1:0")

      assert model.id == "anthropic.claude-opus-4-1-20250805-v1:0"
    end

    test "resolves inference profile with au. prefix" do
      assert {:ok, {:amazon_bedrock, "au.anthropic.claude-opus-4-1-20250805-v1:0", model}} =
               Spec.resolve("amazon_bedrock:au.anthropic.claude-opus-4-1-20250805-v1:0")

      assert model.id == "anthropic.claude-opus-4-1-20250805-v1:0"
    end

    test "resolves inference profile with apac. prefix" do
      assert {:ok, {:amazon_bedrock, "apac.anthropic.claude-opus-4-1-20250805-v1:0", model}} =
               Spec.resolve("amazon_bedrock:apac.anthropic.claude-opus-4-1-20250805-v1:0")

      assert model.id == "anthropic.claude-opus-4-1-20250805-v1:0"
    end

    test "resolves inference profile with jp. prefix" do
      assert {:ok, {:amazon_bedrock, "jp.anthropic.claude-opus-4-1-20250805-v1:0", model}} =
               Spec.resolve("amazon_bedrock:jp.anthropic.claude-opus-4-1-20250805-v1:0")

      assert model.id == "anthropic.claude-opus-4-1-20250805-v1:0"
    end

    test "resolves inference profile with us-gov. prefix" do
      assert {:ok, {:amazon_bedrock, "us-gov.anthropic.claude-opus-4-1-20250805-v1:0", model}} =
               Spec.resolve("amazon_bedrock:us-gov.anthropic.claude-opus-4-1-20250805-v1:0")

      assert model.id == "anthropic.claude-opus-4-1-20250805-v1:0"
    end

    test "resolves native Bedrock model without prefix" do
      assert {:ok, {:amazon_bedrock, "anthropic.claude-opus-4-1-20250805-v1:0", model}} =
               Spec.resolve("amazon_bedrock:anthropic.claude-opus-4-1-20250805-v1:0")

      assert model.id == "anthropic.claude-opus-4-1-20250805-v1:0"
    end

    test "resolves inference profile with tuple input" do
      assert {:ok, {:amazon_bedrock, "us.anthropic.claude-opus-4-1-20250805-v1:0", model}} =
               Spec.resolve({:amazon_bedrock, "us.anthropic.claude-opus-4-1-20250805-v1:0"})

      assert model.id == "anthropic.claude-opus-4-1-20250805-v1:0"
    end

    test "resolves inference profile alias to canonical with prefix preserved" do
      assert {:ok, {:amazon_bedrock, "us.anthropic.claude-opus-4-1-20250805-v1:0", model}} =
               Spec.resolve("amazon_bedrock:us.anthropic.claude-opus")

      assert model.id == "anthropic.claude-opus-4-1-20250805-v1:0"
      assert model.name == "Claude Opus 4.1"
    end

    test "resolves inference profile alias with different prefix" do
      assert {:ok, {:amazon_bedrock, "global.anthropic.claude-opus-4-1-20250805-v1:0", model}} =
               Spec.resolve("amazon_bedrock:global.anthropic.claude-opus")

      assert model.id == "anthropic.claude-opus-4-1-20250805-v1:0"
    end

    test "returns error for inference profile with nonexistent base model" do
      assert {:error, :not_found} = Spec.resolve("amazon_bedrock:us.nonexistent.model")
    end

    test "preserves prefix for bare alias resolution with scope" do
      assert {:ok, {:amazon_bedrock, "us.anthropic.claude-opus-4-1-20250805-v1:0", model}} =
               Spec.resolve("us.anthropic.claude-opus", scope: :amazon_bedrock)

      assert model.id == "anthropic.claude-opus-4-1-20250805-v1:0"
    end

    test "only strips known Bedrock prefixes, not arbitrary prefixes" do
      assert {:error, :not_found} =
               Spec.resolve("amazon_bedrock:unknown.anthropic.claude-opus-4-1-20250805-v1:0")
    end

    test "does not affect non-Bedrock providers with similar prefixes" do
      # Add a model that starts with "us." to OpenAI
      Store.clear!()

      providers = [
        %{id: :openai, name: "OpenAI"}
      ]

      models = [
        %{
          id: "us.model-123",
          provider: :openai,
          name: "US Model",
          aliases: []
        }
      ]

      providers_by_id = Map.new(providers, fn p -> {p.id, p} end)
      models_by_key = Map.new(models, fn m -> {{m.provider, m.id}, m} end)
      models_by_provider = Enum.group_by(models, & &1.provider)

      snapshot = %{
        providers_by_id: providers_by_id,
        models_by_key: models_by_key,
        models_by_provider: models_by_provider,
        aliases_by_key: %{}
      }

      Store.put!(snapshot, [])

      # For non-Bedrock providers, "us." should NOT be stripped
      assert {:ok, {:openai, "us.model-123", model}} = Spec.resolve("openai:us.model-123")
      assert model.id == "us.model-123"
    end
  end

  describe "parse_spec/1 with both separators (ambiguous format resolution)" do
    setup do
      Store.clear!()

      providers = [
        %{id: :google_vertex, name: "Google Vertex AI"}
      ]

      models = [
        %{
          id: "claude-haiku-4-5@20251001",
          provider: :google_vertex,
          name: "Claude Haiku 4.5",
          aliases: []
        }
      ]

      providers_by_id = Map.new(providers, fn p -> {p.id, p} end)
      models_by_key = Map.new(models, fn m -> {{m.provider, m.id}, m} end)
      models_by_provider = Enum.group_by(models, & &1.provider)

      snapshot = %{
        providers_by_id: providers_by_id,
        models_by_key: models_by_key,
        models_by_provider: models_by_provider,
        aliases_by_key: %{}
      }

      Store.put!(snapshot, [])

      :ok
    end

    test "prioritizes colon when it appears first" do
      # Format: provider:model@version
      # Colon comes first, so parse as provider:model where model="model@version"
      assert {:ok, {:google_vertex, "claude-haiku-4-5@20251001"}} =
               Spec.parse_spec("google_vertex:claude-haiku-4-5@20251001")
    end

    test "prioritizes @ when it appears first" do
      # Format: model:version@provider
      # @ comes first (after colon), so this would parse as model:version @ provider
      # But this is a weird case - let's test the actual behavior
      assert {:ok, {:google_vertex, "model:version"}} =
               Spec.parse_spec("model:version@google_vertex")
    end

    test "handles Google Vertex model IDs with @ in them" do
      # Real-world case: google_vertex:claude-haiku-4-5@20251001
      assert {:ok, {:google_vertex, "claude-haiku-4-5@20251001"}} =
               Spec.parse_spec("google_vertex:claude-haiku-4-5@20251001")
    end

    test "resolves Google Vertex models with @ version suffix" do
      # Google Vertex AI uses @ for versioning (e.g., model-name@version)
      # This is the exact pattern that motivated removing strict character validation
      assert {:ok, {:google_vertex, "claude-haiku-4-5@20251001"}} =
               Spec.parse_spec("google_vertex:claude-haiku-4-5@20251001")

      # Should also work with resolve/1
      assert {:ok, {:google_vertex, "claude-haiku-4-5@20251001", model}} =
               Spec.resolve("google_vertex:claude-haiku-4-5@20251001")

      assert model.id == "claude-haiku-4-5@20251001"
      assert model.name == "Claude Haiku 4.5"
    end
  end

  describe "validation with special characters" do
    setup do
      Store.clear!()

      providers = [
        %{id: :openai, name: "OpenAI"},
        %{id: :google_vertex, name: "Google Vertex AI"}
      ]

      models = [
        %{
          id: "model@version",
          provider: :openai,
          name: "Model with @ in ID",
          aliases: []
        },
        %{
          id: "model:version",
          provider: :google_vertex,
          name: "Model with : in ID",
          aliases: []
        }
      ]

      providers_by_id = Map.new(providers, fn p -> {p.id, p} end)
      models_by_key = Map.new(models, fn m -> {{m.provider, m.id}, m} end)
      models_by_provider = Enum.group_by(models, & &1.provider)

      snapshot = %{
        providers_by_id: providers_by_id,
        models_by_key: models_by_key,
        models_by_provider: models_by_provider,
        aliases_by_key: %{}
      }

      Store.put!(snapshot, [])

      :ok
    end

    test "allows @ in model ID when using colon format" do
      # This used to be rejected but is now allowed for Google Vertex compatibility
      assert {:ok, {:openai, "model@version"}} = Spec.parse_spec("openai:model@version")
    end

    test "allows : in model ID when using @ format" do
      # This used to be rejected but is now allowed
      assert {:ok, {:google_vertex, "model:version"}} =
               Spec.parse_spec("model:version@google_vertex")
    end
  end
end
