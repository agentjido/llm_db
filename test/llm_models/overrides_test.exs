defmodule LLMModels.OverridesTest do
  use ExUnit.Case, async: true
  doctest LLMModels.Overrides

  describe "behaviour defaults" do
    defmodule DefaultOverrides do
      use LLMModels.Overrides
    end

    test "provides empty providers by default" do
      assert DefaultOverrides.providers() == []
    end

    test "provides empty models by default" do
      assert DefaultOverrides.models() == []
    end

    test "provides empty excludes by default" do
      assert DefaultOverrides.excludes() == %{}
    end
  end

  describe "behaviour with custom implementation" do
    defmodule CustomOverrides do
      use LLMModels.Overrides

      @impl true
      def providers do
        [
          %{id: :openai, env: ["OPENAI_API_KEY"]},
          %{id: :anthropic, env: ["ANTHROPIC_API_KEY"]}
        ]
      end

      @impl true
      def models do
        [
          %{
            id: "gpt-4o-mini",
            provider: :openai,
            capabilities: %{tools: %{enabled: true, streaming: false}}
          },
          %{
            id: "claude-3-7-sonnet",
            provider: :anthropic,
            capabilities: %{json: %{native: true}}
          }
        ]
      end

      @impl true
      def excludes do
        %{openai: ["gpt-5-pro", "o3-*"], anthropic: ["claude-2-*"]}
      end
    end

    test "returns custom providers" do
      providers = CustomOverrides.providers()
      assert length(providers) == 2
      assert Enum.any?(providers, &(&1.id == :openai))
      assert Enum.any?(providers, &(&1.id == :anthropic))
    end

    test "returns custom models" do
      models = CustomOverrides.models()
      assert length(models) == 2
      assert Enum.any?(models, &(&1.id == "gpt-4o-mini"))
      assert Enum.any?(models, &(&1.id == "claude-3-7-sonnet"))
    end

    test "returns custom excludes" do
      excludes = CustomOverrides.excludes()
      assert excludes[:openai] == ["gpt-5-pro", "o3-*"]
      assert excludes[:anthropic] == ["claude-2-*"]
    end
  end

  describe "behaviour with partial overrides" do
    defmodule PartialOverrides do
      use LLMModels.Overrides

      @impl true
      def models do
        [%{id: "test-model", provider: :test}]
      end
    end

    test "overrides only models, keeps other defaults" do
      assert PartialOverrides.providers() == []
      assert length(PartialOverrides.models()) == 1
      assert PartialOverrides.excludes() == %{}
    end
  end

  describe "behaviour implementation validation" do
    test "module implements required callbacks" do
      behaviours =
        LLMModels.OverridesTest.CustomOverrides.__info__(:attributes)[:behaviour] || []

      assert LLMModels.Overrides in behaviours
    end

    test "callbacks are defoverridable" do
      # All callbacks should be overridable, which we've tested by overriding them
      assert function_exported?(LLMModels.OverridesTest.CustomOverrides, :providers, 0)
      assert function_exported?(LLMModels.OverridesTest.CustomOverrides, :models, 0)
      assert function_exported?(LLMModels.OverridesTest.CustomOverrides, :excludes, 0)
    end
  end
end
