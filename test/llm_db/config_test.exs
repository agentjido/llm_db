defmodule LLMDB.ConfigTest do
  use ExUnit.Case, async: false
  doctest LLMDB.Config

  setup do
    original_config = Application.get_all_env(:llm_db)

    # Clear config BEFORE each test to avoid pollution from other test files
    Application.delete_env(:llm_db, :compile_embed)
    Application.delete_env(:llm_db, :allow)
    Application.delete_env(:llm_db, :deny)
    Application.delete_env(:llm_db, :prefer)
    Application.delete_env(:llm_db, :filter)
    Application.delete_env(:llm_db, :custom)

    on_exit(fn ->
      # Clear all llm_db config
      Application.get_all_env(:llm_db)
      |> Keyword.keys()
      |> Enum.each(&Application.delete_env(:llm_db, &1))

      # Restore original
      Application.put_all_env(llm_db: original_config)

      # Reload to reset state
      LLMDB.load()
    end)

    :ok
  end

  describe "get/0" do
    test "returns defaults when no config set" do
      Application.delete_env(:llm_db, :compile_embed)
      Application.delete_env(:llm_db, :allow)
      Application.delete_env(:llm_db, :deny)
      Application.delete_env(:llm_db, :prefer)

      config = LLMDB.Config.get()

      assert config.compile_embed == false
      assert config.allow == :all
      assert config.deny == %{}
      assert config.prefer == []
    end

    test "returns configured values" do
      Application.put_env(:llm_db, :compile_embed, true)
      Application.put_env(:llm_db, :prefer, [:openai, :anthropic])

      config = LLMDB.Config.get()

      assert config.compile_embed == true
      assert config.prefer == [:openai, :anthropic]
    end
  end

  describe "compile_filters/2" do
    test "compiles :all allow pattern" do
      {result, unknown: unknown} = LLMDB.Config.compile_filters(:all, %{})

      assert result.allow == :all
      assert result.deny == %{}
      assert unknown == []
    end

    test "compiles provider-specific allow patterns" do
      allow = %{openai: ["gpt-4*", "gpt-3*"]}
      deny = %{}

      {result, unknown: unknown} = LLMDB.Config.compile_filters(allow, deny)

      assert is_map(result.allow)
      assert Map.has_key?(result.allow, :openai)
      assert length(result.allow.openai) == 2
      assert Enum.all?(result.allow.openai, &match?(%Regex{}, &1))
      assert unknown == []
    end

    test "compiles deny patterns" do
      allow = :all
      deny = %{openai: ["gpt-5*"], anthropic: ["claude-2*"]}

      {result, unknown: unknown} = LLMDB.Config.compile_filters(allow, deny)

      assert result.allow == :all
      assert is_map(result.deny)
      assert Map.has_key?(result.deny, :openai)
      assert Map.has_key?(result.deny, :anthropic)
      assert Enum.all?(result.deny.openai, &match?(%Regex{}, &1))
      assert Enum.all?(result.deny.anthropic, &match?(%Regex{}, &1))
      assert unknown == []
    end

    test "compiles both allow and deny patterns" do
      allow = %{openai: ["gpt-4*"]}
      deny = %{openai: ["gpt-4-32k"]}

      {result, unknown: unknown} = LLMDB.Config.compile_filters(allow, deny)

      assert is_map(result.allow)
      assert is_map(result.deny)
      assert length(result.allow.openai) == 1
      assert length(result.deny.openai) == 1
      assert unknown == []
    end

    test "handles empty patterns" do
      {result, unknown: unknown} = LLMDB.Config.compile_filters(%{}, %{})

      assert result.allow == %{}
      assert result.deny == %{}
      assert unknown == []
    end

    test "compiled patterns match correctly" do
      allow = %{openai: ["gpt-4*"]}
      {result, _unknown_info} = LLMDB.Config.compile_filters(allow, %{})

      [pattern] = result.allow.openai

      assert Regex.match?(pattern, "gpt-4")
      assert Regex.match?(pattern, "gpt-4-turbo")
      refute Regex.match?(pattern, "gpt-3.5-turbo")
    end
  end

  describe "filter config" do
    test "reads :filter config" do
      Application.put_env(:llm_db, :filter, %{
        allow: %{anthropic: ["claude-3-haiku-*"]},
        deny: %{anthropic: ["*-legacy"]}
      })

      config = LLMDB.Config.get()

      assert config.allow == %{anthropic: ["claude-3-haiku-*"]}
      assert config.deny == %{anthropic: ["*-legacy"]}
    end

    test ":filter defaults to allow :all and deny %{}" do
      Application.delete_env(:llm_db, :filter)

      config = LLMDB.Config.get()

      assert config.allow == :all
      assert config.deny == %{}
    end

    test "accepts string provider keys" do
      allow = %{"anthropic" => ["claude-*"], "openrouter" => ["*haiku*"]}
      {result, _unknown_info} = LLMDB.Config.compile_filters(allow, %{})

      # Should be converted to atoms
      assert is_map(result.allow)
      assert Map.has_key?(result.allow, :anthropic)
      assert Map.has_key?(result.allow, :openrouter)
    end

    test "accepts Regex patterns" do
      allow = %{anthropic: [~r/claude-3-haiku.*/]}
      {result, _unknown_info} = LLMDB.Config.compile_filters(allow, %{})

      [pattern] = result.allow.anthropic
      assert %Regex{} = pattern
      assert Regex.match?(pattern, "claude-3-haiku-20240307")
    end

    test "raises on invalid provider key type" do
      allow = %{123 => ["model-*"]}

      assert_raise ArgumentError,
                   ~r/llm_db: filter provider keys must be atoms or strings/,
                   fn ->
                     LLMDB.Config.compile_filters(allow, %{})
                   end
    end

    test "raises on invalid pattern type" do
      allow = %{anthropic: [123]}

      assert_raise ArgumentError,
                   ~r/llm_db: filter pattern must be string or Regex/,
                   fn ->
                     LLMDB.Config.compile_filters(allow, %{})
                   end
    end
  end

  describe "integration tests" do
    test "full config workflow" do
      Application.put_env(:llm_db, :compile_embed, true)

      Application.put_env(:llm_db, :filter, %{
        allow: %{openai: ["gpt-4*"]},
        deny: %{openai: ["gpt-4-32k"]}
      })

      Application.put_env(:llm_db, :prefer, [:openai, :anthropic])

      config = LLMDB.Config.get()
      {filters, _unknown_info} = LLMDB.Config.compile_filters(config.allow, config.deny)

      assert config.compile_embed == true
      assert config.prefer == [:openai, :anthropic]

      assert is_map(filters.allow)
      assert is_map(filters.deny)
      assert Map.has_key?(filters.allow, :openai)
      assert Map.has_key?(filters.deny, :openai)
    end

    test "consumer use case: Phoenix app filtering to specific models" do
      # Simulate Phoenix app config.exs
      Application.put_env(:llm_db, :filter, %{
        allow: %{
          anthropic: ["claude-3-haiku-*"],
          openrouter: ["anthropic/claude-3-haiku-*"]
        }
      })

      config = LLMDB.Config.get()
      {filters, _unknown_info} = LLMDB.Config.compile_filters(config.allow, config.deny)

      assert is_map(filters.allow)
      assert Map.has_key?(filters.allow, :anthropic)
      assert Map.has_key?(filters.allow, :openrouter)

      # Verify patterns compile correctly
      [anthropic_pattern] = filters.allow.anthropic
      assert Regex.match?(anthropic_pattern, "claude-3-haiku-20240307")
      refute Regex.match?(anthropic_pattern, "claude-3-opus-20240229")

      [openrouter_pattern] = filters.allow.openrouter
      assert Regex.match?(openrouter_pattern, "anthropic/claude-3-haiku-20240307")
      refute Regex.match?(openrouter_pattern, "anthropic/claude-3-opus-20240229")
    end
  end
end
