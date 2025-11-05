defmodule LLMModels.ConfigTest do
  use ExUnit.Case, async: false
  doctest LLMModels.Config

  setup do
    original_config = Application.get_all_env(:llm_models)

    on_exit(fn ->
      Application.put_all_env(llm_models: original_config)
    end)

    :ok
  end

  describe "get/0" do
    test "returns defaults when no config set" do
      Application.delete_env(:llm_models, :compile_embed)
      Application.delete_env(:llm_models, :overrides)
      Application.delete_env(:llm_models, :overrides_module)
      Application.delete_env(:llm_models, :allow)
      Application.delete_env(:llm_models, :deny)
      Application.delete_env(:llm_models, :prefer)

      config = LLMModels.Config.get()

      assert config.compile_embed == false
      assert config.overrides == %{providers: [], models: [], exclude: %{}}
      assert config.overrides_module == nil
      assert config.allow == :all
      assert config.deny == %{}
      assert config.prefer == []
    end

    test "returns configured values" do
      Application.put_env(:llm_models, :compile_embed, true)
      Application.put_env(:llm_models, :prefer, [:openai, :anthropic])

      config = LLMModels.Config.get()

      assert config.compile_embed == true
      assert config.prefer == [:openai, :anthropic]
    end

    test "normalizes map overrides" do
      Application.put_env(:llm_models, :overrides, %{
        providers: [%{id: :openai}],
        models: [%{id: "gpt-4"}],
        exclude: %{openai: ["gpt-5"]}
      })

      config = LLMModels.Config.get()

      assert config.overrides.providers == [%{id: :openai}]
      assert config.overrides.models == [%{id: "gpt-4"}]
      assert config.overrides.exclude == %{openai: ["gpt-5"]}
    end

    test "normalizes keyword overrides" do
      Application.put_env(:llm_models, :overrides,
        providers: [%{id: :anthropic}],
        models: [%{id: "claude"}],
        exclude: %{anthropic: ["claude-2"]}
      )

      config = LLMModels.Config.get()

      assert config.overrides.providers == [%{id: :anthropic}]
      assert config.overrides.models == [%{id: "claude"}]
      assert config.overrides.exclude == %{anthropic: ["claude-2"]}
    end

    test "handles partial overrides" do
      Application.put_env(:llm_models, :overrides, %{
        models: [%{id: "test"}]
      })

      config = LLMModels.Config.get()

      assert config.overrides.providers == []
      assert config.overrides.models == [%{id: "test"}]
      assert config.overrides.exclude == %{}
    end

    test "handles invalid overrides gracefully" do
      Application.put_env(:llm_models, :overrides, "invalid")

      config = LLMModels.Config.get()

      assert config.overrides == %{providers: [], models: [], exclude: %{}}
    end
  end

  describe "compile_filters/2" do
    test "compiles :all allow pattern" do
      result = LLMModels.Config.compile_filters(:all, %{})

      assert result.allow == :all
      assert result.deny == %{}
    end

    test "compiles provider-specific allow patterns" do
      allow = %{openai: ["gpt-4*", "gpt-3*"]}
      deny = %{}

      result = LLMModels.Config.compile_filters(allow, deny)

      assert is_map(result.allow)
      assert Map.has_key?(result.allow, :openai)
      assert length(result.allow.openai) == 2
      assert Enum.all?(result.allow.openai, &match?(%Regex{}, &1))
    end

    test "compiles deny patterns" do
      allow = :all
      deny = %{openai: ["gpt-5*"], anthropic: ["claude-2*"]}

      result = LLMModels.Config.compile_filters(allow, deny)

      assert result.allow == :all
      assert is_map(result.deny)
      assert Map.has_key?(result.deny, :openai)
      assert Map.has_key?(result.deny, :anthropic)
      assert Enum.all?(result.deny.openai, &match?(%Regex{}, &1))
      assert Enum.all?(result.deny.anthropic, &match?(%Regex{}, &1))
    end

    test "compiles both allow and deny patterns" do
      allow = %{openai: ["gpt-4*"]}
      deny = %{openai: ["gpt-4-32k"]}

      result = LLMModels.Config.compile_filters(allow, deny)

      assert is_map(result.allow)
      assert is_map(result.deny)
      assert length(result.allow.openai) == 1
      assert length(result.deny.openai) == 1
    end

    test "handles empty patterns" do
      result = LLMModels.Config.compile_filters(%{}, %{})

      assert result.allow == %{}
      assert result.deny == %{}
    end

    test "compiled patterns match correctly" do
      allow = %{openai: ["gpt-4*"]}
      result = LLMModels.Config.compile_filters(allow, %{})

      [pattern] = result.allow.openai

      assert Regex.match?(pattern, "gpt-4")
      assert Regex.match?(pattern, "gpt-4-turbo")
      refute Regex.match?(pattern, "gpt-3.5-turbo")
    end
  end

  describe "get_overrides_from_module/1" do
    defmodule TestOverrides do
      use LLMModels.Overrides

      @impl true
      def providers do
        [%{id: :test_provider}]
      end

      @impl true
      def models do
        [%{id: "test-model", provider: :test_provider}]
      end

      @impl true
      def excludes do
        %{test_provider: ["excluded-*"]}
      end
    end

    test "returns empty maps when module is nil" do
      result = LLMModels.Config.get_overrides_from_module(nil)

      assert result == %{providers: [], models: [], excludes: %{}}
    end

    test "retrieves overrides from valid module" do
      result = LLMModels.Config.get_overrides_from_module(TestOverrides)

      assert result.providers == [%{id: :test_provider}]
      assert result.models == [%{id: "test-model", provider: :test_provider}]
      assert result.excludes == %{test_provider: ["excluded-*"]}
    end

    test "handles non-existent module gracefully" do
      result = LLMModels.Config.get_overrides_from_module(NonExistent.Module)

      assert result == %{providers: [], models: [], excludes: %{}}
    end

    test "handles module without behaviour gracefully" do
      defmodule NotAnOverride do
        def some_function, do: :ok
      end

      result = LLMModels.Config.get_overrides_from_module(NotAnOverride)

      assert result == %{providers: [], models: [], excludes: %{}}
    end
  end

  describe "integration tests" do
    defmodule IntegrationOverrides do
      use LLMModels.Overrides

      @impl true
      def providers do
        [%{id: :custom, env: ["CUSTOM_KEY"]}]
      end

      @impl true
      def models do
        [%{id: "custom-model", provider: :custom}]
      end

      @impl true
      def excludes do
        %{custom: ["old-*"]}
      end
    end

    test "full config workflow" do
      Application.put_env(:llm_models, :compile_embed, true)
      Application.put_env(:llm_models, :overrides_module, IntegrationOverrides)

      Application.put_env(:llm_models, :overrides, %{
        models: [%{id: "config-model", provider: :openai}]
      })

      Application.put_env(:llm_models, :allow, %{openai: ["gpt-4*"]})
      Application.put_env(:llm_models, :deny, %{openai: ["gpt-4-32k"]})
      Application.put_env(:llm_models, :prefer, [:openai, :custom])

      config = LLMModels.Config.get()
      module_overrides = LLMModels.Config.get_overrides_from_module(config.overrides_module)
      filters = LLMModels.Config.compile_filters(config.allow, config.deny)

      assert config.compile_embed == true
      assert config.prefer == [:openai, :custom]
      assert config.overrides.models == [%{id: "config-model", provider: :openai}]

      assert module_overrides.providers == [%{id: :custom, env: ["CUSTOM_KEY"]}]
      assert module_overrides.models == [%{id: "custom-model", provider: :custom}]
      assert module_overrides.excludes == %{custom: ["old-*"]}

      assert is_map(filters.allow)
      assert is_map(filters.deny)
      assert Map.has_key?(filters.allow, :openai)
      assert Map.has_key?(filters.deny, :openai)
    end
  end
end
