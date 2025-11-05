defmodule LLMModels.Schema.ProviderTest do
  use ExUnit.Case, async: true

  alias LLMModels.Schema.Provider

  describe "valid parsing" do
    test "parses minimal valid provider" do
      input = %{id: :openai}
      assert {:ok, result} = Zoi.parse(Provider.schema(), input)
      assert result.id == :openai
    end

    test "parses complete provider with all fields" do
      input = %{
        id: :openai,
        name: "OpenAI",
        base_url: "https://api.openai.com",
        env: ["OPENAI_API_KEY"],
        doc: "OpenAI provider",
        extra: %{"custom" => "value"}
      }

      assert {:ok, result} = Zoi.parse(Provider.schema(), input)
      assert result.id == :openai
      assert result.name == "OpenAI"
      assert result.base_url == "https://api.openai.com"
      assert result.env == ["OPENAI_API_KEY"]
      assert result.doc == "OpenAI provider"
      assert result.extra == %{"custom" => "value"}
    end

    test "parses provider with multiple env vars" do
      input = %{
        id: :anthropic,
        env: ["ANTHROPIC_API_KEY", "ANTHROPIC_ORG_ID"]
      }

      assert {:ok, result} = Zoi.parse(Provider.schema(), input)
      assert result.env == ["ANTHROPIC_API_KEY", "ANTHROPIC_ORG_ID"]
    end
  end

  describe "optional fields" do
    test "name is optional" do
      input = %{id: :openai}
      assert {:ok, result} = Zoi.parse(Provider.schema(), input)
      refute Map.has_key?(result, :name)
    end

    test "base_url is optional" do
      input = %{id: :openai}
      assert {:ok, result} = Zoi.parse(Provider.schema(), input)
      refute Map.has_key?(result, :base_url)
    end

    test "env is optional" do
      input = %{id: :openai}
      assert {:ok, result} = Zoi.parse(Provider.schema(), input)
      refute Map.has_key?(result, :env)
    end

    test "doc is optional" do
      input = %{id: :openai}
      assert {:ok, result} = Zoi.parse(Provider.schema(), input)
      refute Map.has_key?(result, :doc)
    end

    test "extra is optional" do
      input = %{id: :openai}
      assert {:ok, result} = Zoi.parse(Provider.schema(), input)
      refute Map.has_key?(result, :extra)
    end
  end

  describe "invalid inputs" do
    test "rejects missing id" do
      input = %{name: "OpenAI"}
      assert {:error, _} = Zoi.parse(Provider.schema(), input)
    end

    test "rejects non-atom id" do
      input = %{id: "openai"}
      assert {:error, _} = Zoi.parse(Provider.schema(), input)
    end

    test "rejects non-string name" do
      input = %{id: :openai, name: 123}
      assert {:error, _} = Zoi.parse(Provider.schema(), input)
    end

    test "rejects non-string base_url" do
      input = %{id: :openai, base_url: 123}
      assert {:error, _} = Zoi.parse(Provider.schema(), input)
    end

    test "rejects non-array env" do
      input = %{id: :openai, env: "OPENAI_API_KEY"}
      assert {:error, _} = Zoi.parse(Provider.schema(), input)
    end

    test "rejects non-string elements in env array" do
      input = %{id: :openai, env: ["OPENAI_API_KEY", 123]}
      assert {:error, _} = Zoi.parse(Provider.schema(), input)
    end

    test "rejects non-map extra" do
      input = %{id: :openai, extra: "not a map"}
      assert {:error, _} = Zoi.parse(Provider.schema(), input)
    end
  end

  describe "extra fields pass through" do
    test "extra field contains unknown upstream keys" do
      input = %{
        id: :openai,
        extra: %{"upstream_version" => "1.0", "custom_field" => true}
      }

      assert {:ok, result} = Zoi.parse(Provider.schema(), input)
      assert result.extra["upstream_version"] == "1.0"
      assert result.extra["custom_field"] == true
    end
  end
end
