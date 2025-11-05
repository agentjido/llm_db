defmodule LLMModels.NormalizeTest do
  use ExUnit.Case, async: true

  alias LLMModels.Normalize

  doctest Normalize

  describe "normalize_provider_id/1" do
    test "converts binary provider ID with hyphens to atom with underscores" do
      assert {:ok, :google_vertex} =
               Normalize.normalize_provider_id("google-vertex", unsafe: true)

      assert {:ok, :azure_openai} = Normalize.normalize_provider_id("azure-openai", unsafe: true)

      assert {:ok, :anthropic_vertex} =
               Normalize.normalize_provider_id("anthropic-vertex", unsafe: true)
    end

    test "converts binary provider ID with underscores to atom" do
      assert {:ok, :google_vertex} =
               Normalize.normalize_provider_id("google_vertex", unsafe: true)

      assert {:ok, :some_provider} =
               Normalize.normalize_provider_id("some_provider", unsafe: true)
    end

    test "converts simple binary provider ID to atom" do
      assert {:ok, :openai} = Normalize.normalize_provider_id("openai", unsafe: true)
      assert {:ok, :anthropic} = Normalize.normalize_provider_id("anthropic", unsafe: true)
      assert {:ok, :cohere} = Normalize.normalize_provider_id("cohere", unsafe: true)
    end

    test "passes through already-atom providers unchanged" do
      assert {:ok, :openai} = Normalize.normalize_provider_id(:openai)
      assert {:ok, :google_vertex} = Normalize.normalize_provider_id(:google_vertex)
      assert {:ok, :some_atom} = Normalize.normalize_provider_id(:some_atom)
    end

    test "returns error for invalid provider strings" do
      assert {:error, :bad_provider} = Normalize.normalize_provider_id("")
      assert {:error, :bad_provider} = Normalize.normalize_provider_id("has spaces")
      assert {:error, :bad_provider} = Normalize.normalize_provider_id("has@special")
      assert {:error, :bad_provider} = Normalize.normalize_provider_id("has.dot")
    end

    test "returns error for excessively long strings" do
      long_string = String.duplicate("a", 300)
      assert {:error, :bad_provider} = Normalize.normalize_provider_id(long_string)
    end

    test "returns error for non-binary, non-atom types" do
      assert {:error, :bad_provider} = Normalize.normalize_provider_id(123)
      assert {:error, :bad_provider} = Normalize.normalize_provider_id([])
      assert {:error, :bad_provider} = Normalize.normalize_provider_id(%{})
    end

    test "handles mixed case provider IDs" do
      assert {:ok, :OpenAI} = Normalize.normalize_provider_id("OpenAI", unsafe: true)

      assert {:ok, :Google_Vertex} =
               Normalize.normalize_provider_id("Google-Vertex", unsafe: true)
    end

    test "handles alphanumeric provider IDs" do
      assert {:ok, :provider123} = Normalize.normalize_provider_id("provider123", unsafe: true)
      assert {:ok, :abc_123_xyz} = Normalize.normalize_provider_id("abc-123-xyz", unsafe: true)
    end
  end

  describe "normalize_model_identity/1" do
    test "extracts provider and id from model map with binary provider" do
      model = %{provider: "google-vertex", id: "gemini-pro"}
      assert {:ok, {:google_vertex, "gemini-pro"}} = Normalize.normalize_model_identity(model)
    end

    test "extracts provider and id from model map with atom provider" do
      model = %{provider: :openai, id: "gpt-4"}
      assert {:ok, {:openai, "gpt-4"}} = Normalize.normalize_model_identity(model)
    end

    test "handles provider with underscores" do
      model = %{provider: "azure_openai", id: "gpt-4-turbo"}

      assert {:ok, {:azure_openai, "gpt-4-turbo"}} =
               Normalize.normalize_model_identity(model, unsafe: true)
    end

    test "returns error when id is missing" do
      model = %{provider: "openai"}
      assert {:error, :missing_id} = Normalize.normalize_model_identity(model)
    end

    test "returns error when provider is missing" do
      model = %{id: "gpt-4"}
      assert {:error, :missing_provider} = Normalize.normalize_model_identity(model)
    end

    test "returns error when both provider and id are missing" do
      model = %{name: "Some Model"}
      assert {:error, :invalid_model} = Normalize.normalize_model_identity(model)
    end

    test "returns error for invalid provider" do
      model = %{provider: "invalid@provider", id: "model-1"}
      assert {:error, :bad_provider} = Normalize.normalize_model_identity(model)
    end

    test "returns error when id is not a string" do
      model = %{provider: "openai", id: 123}
      assert {:error, :invalid_id} = Normalize.normalize_model_identity(model)
    end

    test "handles complex model IDs" do
      model = %{provider: "anthropic", id: "claude-3-opus-20240229"}

      assert {:ok, {:anthropic, "claude-3-opus-20240229"}} =
               Normalize.normalize_model_identity(model)
    end
  end

  describe "normalize_date/1" do
    test "returns nil for nil input" do
      assert nil == Normalize.normalize_date(nil)
    end

    test "returns empty string for empty string" do
      assert "" == Normalize.normalize_date("")
    end

    test "keeps already normalized dates unchanged" do
      assert "2024-01-15" == Normalize.normalize_date("2024-01-15")
      assert "2023-12-31" == Normalize.normalize_date("2023-12-31")
      assert "2025-06-01" == Normalize.normalize_date("2025-06-01")
    end

    test "normalizes dates with forward slashes" do
      assert "2024-01-15" == Normalize.normalize_date("2024/01/15")
      assert "2023-12-31" == Normalize.normalize_date("2023/12/31")
    end

    test "normalizes dates with single-digit months and days" do
      assert "2024-01-05" == Normalize.normalize_date("2024-1-5")
      assert "2024-03-09" == Normalize.normalize_date("2024-3-9")
    end

    test "leaves invalid dates as-is" do
      assert "invalid-date" == Normalize.normalize_date("invalid-date")
      assert "2024-13-01" == Normalize.normalize_date("2024-13-01")
      assert "2024-00-15" == Normalize.normalize_date("2024-00-15")
      assert "2024-01-32" == Normalize.normalize_date("2024-01-32")
      assert "not-a-date" == Normalize.normalize_date("not-a-date")
    end

    test "leaves malformed date strings as-is" do
      assert "2024" == Normalize.normalize_date("2024")
      assert "2024-01" == Normalize.normalize_date("2024-01")
      assert "24-01-15" == Normalize.normalize_date("24-01-15")
    end

    test "handles dates with text" do
      assert "2024-01-15 extra text" == Normalize.normalize_date("2024-01-15 extra text")
    end

    test "normalizes years with proper padding" do
      assert "1000-01-01" == Normalize.normalize_date("1000-1-1")
      assert "9999-12-31" == Normalize.normalize_date("9999-12-31")
    end

    test "leaves dates outside valid year range as-is" do
      assert "999-01-01" == Normalize.normalize_date("999-01-01")
      assert "10000-01-01" == Normalize.normalize_date("10000-01-01")
    end
  end

  describe "normalize_providers/1" do
    test "normalizes list of provider maps" do
      providers = [
        %{id: "google-vertex", name: "Google Vertex AI"},
        %{id: :openai, name: "OpenAI"},
        %{id: "anthropic", name: "Anthropic"}
      ]

      normalized = Normalize.normalize_providers(providers)

      assert [
               %{id: :google_vertex, name: "Google Vertex AI"},
               %{id: :openai, name: "OpenAI"},
               %{id: :anthropic, name: "Anthropic"}
             ] = normalized
    end

    test "handles empty list" do
      assert [] = Normalize.normalize_providers([])
    end

    test "preserves provider maps without id" do
      providers = [
        %{name: "Some Provider"},
        %{id: "openai", name: "OpenAI"}
      ]

      normalized = Normalize.normalize_providers(providers)

      assert [
               %{name: "Some Provider"},
               %{id: :openai, name: "OpenAI"}
             ] = normalized
    end

    test "keeps invalid provider IDs unchanged" do
      providers = [
        %{id: "valid-provider"},
        %{id: "invalid@provider"}
      ]

      normalized = Normalize.normalize_providers(providers)

      assert [
               %{id: :valid_provider},
               %{id: "invalid@provider"}
             ] = normalized
    end

    test "preserves all other fields in provider maps" do
      providers = [
        %{
          id: "google-vertex",
          name: "Google Vertex AI",
          base_url: "https://vertex.googleapis.com",
          env: ["GOOGLE_API_KEY"],
          extra: %{some: "data"}
        }
      ]

      normalized = Normalize.normalize_providers(providers)

      assert [
               %{
                 id: :google_vertex,
                 name: "Google Vertex AI",
                 base_url: "https://vertex.googleapis.com",
                 env: ["GOOGLE_API_KEY"],
                 extra: %{some: "data"}
               }
             ] = normalized
    end
  end

  describe "normalize_models/1" do
    test "normalizes list of model maps" do
      models = [
        %{provider: "google-vertex", id: "gemini-pro"},
        %{provider: :openai, id: "gpt-4"},
        %{provider: "anthropic", id: "claude-3-opus"}
      ]

      normalized = Normalize.normalize_models(models)

      assert [
               %{provider: :google_vertex, id: "gemini-pro"},
               %{provider: :openai, id: "gpt-4"},
               %{provider: :anthropic, id: "claude-3-opus"}
             ] = normalized
    end

    test "handles empty list" do
      assert [] = Normalize.normalize_models([])
    end

    test "preserves model maps without provider" do
      models = [
        %{id: "some-model"},
        %{provider: "openai", id: "gpt-4"}
      ]

      normalized = Normalize.normalize_models(models)

      assert [
               %{id: "some-model"},
               %{provider: :openai, id: "gpt-4"}
             ] = normalized
    end

    test "keeps invalid provider IDs unchanged" do
      models = [
        %{provider: "valid-provider", id: "model-1"},
        %{provider: "invalid@provider", id: "model-2"}
      ]

      normalized = Normalize.normalize_models(models)

      assert [
               %{provider: :valid_provider, id: "model-1"},
               %{provider: "invalid@provider", id: "model-2"}
             ] = normalized
    end

    test "preserves all other fields in model maps" do
      models = [
        %{
          provider: "google-vertex",
          id: "gemini-pro",
          name: "Gemini Pro",
          family: "gemini",
          release_date: "2024-01-15",
          capabilities: %{chat: true},
          tags: ["production"],
          extra: %{some: "data"}
        }
      ]

      normalized = Normalize.normalize_models(models)

      assert [
               %{
                 provider: :google_vertex,
                 id: "gemini-pro",
                 name: "Gemini Pro",
                 family: "gemini",
                 release_date: "2024-01-15",
                 capabilities: %{chat: true},
                 tags: ["production"],
                 extra: %{some: "data"}
               }
             ] = normalized
    end
  end
end
