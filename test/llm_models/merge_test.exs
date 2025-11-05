defmodule LLMModels.MergeTest do
  use ExUnit.Case, async: true
  alias LLMModels.Merge

  doctest LLMModels.Merge

  describe "merge/3 scalar values" do
    test "higher precedence wins on scalar conflict" do
      base = %{value: 1}
      override = %{value: 2}
      assert Merge.merge(base, override, :higher) == %{value: 2}
    end

    test "lower precedence preserves base on scalar conflict" do
      base = %{value: 1}
      override = %{value: 2}
      assert Merge.merge(base, override, :lower) == %{value: 1}
    end

    test "combines non-conflicting scalars" do
      base = %{a: 1}
      override = %{b: 2}
      assert Merge.merge(base, override, :higher) == %{a: 1, b: 2}
    end

    test "handles nil values with higher precedence" do
      base = %{value: 1}
      override = %{value: nil}
      assert Merge.merge(base, override, :higher) == %{value: nil}
    end

    test "handles nil values with lower precedence" do
      base = %{value: nil}
      override = %{value: 2}
      assert Merge.merge(base, override, :lower) == %{value: nil}
    end
  end

  describe "merge/3 deep map merging" do
    test "deep merges nested maps" do
      base = %{config: %{api: %{timeout: 30}}}
      override = %{config: %{api: %{retries: 3}}}

      result = Merge.merge(base, override, :higher)

      assert result == %{config: %{api: %{timeout: 30, retries: 3}}}
    end

    test "higher precedence wins on nested scalar conflicts" do
      base = %{config: %{value: 1}}
      override = %{config: %{value: 2}}

      result = Merge.merge(base, override, :higher)

      assert result == %{config: %{value: 2}}
    end

    test "lower precedence preserves base on nested scalar conflicts" do
      base = %{config: %{value: 1}}
      override = %{config: %{value: 2}}

      result = Merge.merge(base, override, :lower)

      assert result == %{config: %{value: 1}}
    end

    test "merges deeply nested structures" do
      base = %{
        level1: %{
          level2: %{
            level3: %{
              value: "base"
            }
          }
        }
      }

      override = %{
        level1: %{
          level2: %{
            level3: %{
              extra: "override"
            }
          }
        }
      }

      result = Merge.merge(base, override, :higher)

      assert result == %{
               level1: %{
                 level2: %{
                   level3: %{
                     value: "base",
                     extra: "override"
                   }
                 }
               }
             }
    end
  end

  describe "merge/3 list handling" do
    test "concatenates and deduplicates lists" do
      base = %{tags: [1, 2, 3]}
      override = %{tags: [3, 4, 5]}

      result = Merge.merge(base, override, :higher)

      assert result.tags |> Enum.sort() == [1, 2, 3, 4, 5]
    end

    test "preserves list order while deduplicating" do
      base = %{items: ["a", "b"]}
      override = %{items: ["b", "c"]}

      result = Merge.merge(base, override, :higher)

      assert result.items == ["a", "b", "c"]
    end

    test "handles empty lists" do
      base = %{items: []}
      override = %{items: [1, 2]}

      result = Merge.merge(base, override, :higher)

      assert result.items == [1, 2]
    end

    test "deduplicates string lists" do
      base = %{aliases: ["gpt-4", "gpt-4-turbo"]}
      override = %{aliases: ["gpt-4-turbo", "gpt-4-latest"]}

      result = Merge.merge(base, override, :higher)

      assert result.aliases == ["gpt-4", "gpt-4-turbo", "gpt-4-latest"]
    end
  end

  describe "merge_providers/2" do
    test "merges providers by id with higher precedence" do
      base = [
        %{id: :openai, name: "OpenAI", api_version: "v1"}
      ]

      override = [
        %{id: :openai, name: "OpenAI Updated"}
      ]

      result = Merge.merge_providers(base, override)

      assert length(result) == 1
      provider = Enum.find(result, fn p -> p.id == :openai end)
      assert provider.name == "OpenAI Updated"
      assert provider.api_version == "v1"
    end

    test "combines providers from both sources" do
      base = [
        %{id: :openai, name: "OpenAI"}
      ]

      override = [
        %{id: :anthropic, name: "Anthropic"}
      ]

      result = Merge.merge_providers(base, override)

      assert length(result) == 2
      assert Enum.any?(result, fn p -> p.id == :openai end)
      assert Enum.any?(result, fn p -> p.id == :anthropic end)
    end

    test "deep merges provider configuration" do
      base = [
        %{id: :openai, config: %{timeout: 30, retries: 3}}
      ]

      override = [
        %{id: :openai, config: %{retries: 5, max_tokens: 1000}}
      ]

      result = Merge.merge_providers(base, override)

      provider = Enum.find(result, fn p -> p.id == :openai end)
      assert provider.config.timeout == 30
      assert provider.config.retries == 5
      assert provider.config.max_tokens == 1000
    end

    test "handles empty base list" do
      result = Merge.merge_providers([], [%{id: :openai}])
      assert length(result) == 1
    end

    test "handles empty override list" do
      result = Merge.merge_providers([%{id: :openai}], [])
      assert length(result) == 1
    end
  end

  describe "merge_models/3" do
    test "merges models by {provider, id} identity" do
      base = [
        %{id: "gpt-4", provider: :openai, version: 1}
      ]

      override = [
        %{id: "gpt-4", provider: :openai, version: 2}
      ]

      result = Merge.merge_models(base, override, %{})

      assert length(result) == 1
      model = Enum.find(result, fn m -> m.id == "gpt-4" end)
      assert model.version == 2
    end

    test "combines models from both sources" do
      base = [
        %{id: "gpt-4", provider: :openai}
      ]

      override = [
        %{id: "claude-3", provider: :anthropic}
      ]

      result = Merge.merge_models(base, override, %{})

      assert length(result) == 2
    end

    test "deep merges model capabilities" do
      base = [
        %{
          id: "gpt-4",
          provider: :openai,
          capabilities: %{
            chat: true,
            tools: %{enabled: true, streaming: false}
          }
        }
      ]

      override = [
        %{
          id: "gpt-4",
          provider: :openai,
          capabilities: %{
            tools: %{streaming: true, parallel: true}
          }
        }
      ]

      result = Merge.merge_models(base, override, %{})

      model = Enum.find(result, fn m -> m.id == "gpt-4" end)
      assert model.capabilities.chat == true
      assert model.capabilities.tools.enabled == true
      assert model.capabilities.tools.streaming == true
      assert model.capabilities.tools.parallel == true
    end

    test "applies exact exclude patterns" do
      base = [
        %{id: "gpt-4", provider: :openai},
        %{id: "gpt-3", provider: :openai},
        %{id: "gpt-3.5-turbo", provider: :openai}
      ]

      excludes = %{openai: ["gpt-3"]}

      result = Merge.merge_models(base, [], excludes)

      assert length(result) == 2
      assert Enum.any?(result, fn m -> m.id == "gpt-4" end)
      assert Enum.any?(result, fn m -> m.id == "gpt-3.5-turbo" end)
      refute Enum.any?(result, fn m -> m.id == "gpt-3" end)
    end

    test "applies glob exclude patterns" do
      base = [
        %{id: "gpt-4o-mini", provider: :openai},
        %{id: "gpt-5-pro", provider: :openai},
        %{id: "gpt-5-ultra", provider: :openai},
        %{id: "claude-3", provider: :anthropic}
      ]

      excludes = %{openai: ["gpt-5-*"]}

      result = Merge.merge_models(base, [], excludes)

      assert length(result) == 2
      assert Enum.any?(result, fn m -> m.id == "gpt-4o-mini" end)
      assert Enum.any?(result, fn m -> m.id == "claude-3" end)
      refute Enum.any?(result, fn m -> m.id == "gpt-5-pro" end)
      refute Enum.any?(result, fn m -> m.id == "gpt-5-ultra" end)
    end

    test "applies multiple exclude patterns" do
      base = [
        %{id: "gpt-4", provider: :openai},
        %{id: "gpt-3", provider: :openai},
        %{id: "gpt-5-pro", provider: :openai},
        %{id: "text-davinci-003", provider: :openai}
      ]

      excludes = %{openai: ["gpt-3", "gpt-5-*", "text-*"]}

      result = Merge.merge_models(base, [], excludes)

      assert length(result) == 1
      assert Enum.any?(result, fn m -> m.id == "gpt-4" end)
    end

    test "applies excludes to multiple providers" do
      base = [
        %{id: "gpt-4", provider: :openai},
        %{id: "gpt-5-pro", provider: :openai},
        %{id: "claude-2", provider: :anthropic},
        %{id: "claude-3", provider: :anthropic}
      ]

      excludes = %{
        openai: ["gpt-5-*"],
        anthropic: ["claude-2"]
      }

      result = Merge.merge_models(base, [], excludes)

      assert length(result) == 2
      assert Enum.any?(result, fn m -> m.id == "gpt-4" end)
      assert Enum.any?(result, fn m -> m.id == "claude-3" end)
    end

    test "handles empty excludes" do
      base = [%{id: "gpt-4", provider: :openai}]
      result = Merge.merge_models(base, [], %{})
      assert length(result) == 1
    end

    test "handles provider not in excludes" do
      base = [
        %{id: "gpt-4", provider: :openai},
        %{id: "claude-3", provider: :anthropic}
      ]

      excludes = %{openai: ["gpt-5-*"]}

      result = Merge.merge_models(base, [], excludes)

      assert length(result) == 2
    end
  end

  describe "compile_pattern/1" do
    test "compiles simple glob pattern" do
      pattern = Merge.compile_pattern("gpt-*")
      assert Regex.match?(pattern, "gpt-4")
      assert Regex.match?(pattern, "gpt-3")
      refute Regex.match?(pattern, "claude-3")
    end

    test "compiles pattern with multiple wildcards" do
      pattern = Merge.compile_pattern("gpt-*-*")
      assert Regex.match?(pattern, "gpt-4-turbo")
      assert Regex.match?(pattern, "gpt-3-5")
      refute Regex.match?(pattern, "gpt-4")
    end

    test "compiles pattern with wildcard at end" do
      pattern = Merge.compile_pattern("gpt-5-*")
      assert Regex.match?(pattern, "gpt-5-pro")
      assert Regex.match?(pattern, "gpt-5-ultra")
      refute Regex.match?(pattern, "gpt-4-pro")
    end

    test "compiles pattern with wildcard at start" do
      pattern = Merge.compile_pattern("*-turbo")
      assert Regex.match?(pattern, "gpt-4-turbo")
      assert Regex.match?(pattern, "claude-3-turbo")
      refute Regex.match?(pattern, "gpt-4")
    end

    test "escapes regex special characters" do
      pattern = Merge.compile_pattern("model.v2+*")
      assert Regex.match?(pattern, "model.v2+beta")
      refute Regex.match?(pattern, "modelXv2Xbeta")
    end

    test "anchors pattern to start and end" do
      pattern = Merge.compile_pattern("gpt-*")
      refute Regex.match?(pattern, "prefix-gpt-4")
      assert Regex.match?(pattern, "gpt-4-suffix")

      pattern2 = Merge.compile_pattern("gpt-4")
      refute Regex.match?(pattern2, "gpt-4-suffix")
      refute Regex.match?(pattern2, "prefix-gpt-4")
    end
  end

  describe "matches_exclude?/2" do
    test "matches exact string pattern" do
      assert Merge.matches_exclude?("gpt-3", ["gpt-3", "gpt-4"])
      refute Merge.matches_exclude?("gpt-5", ["gpt-3", "gpt-4"])
    end

    test "matches regex pattern" do
      patterns = [~r/^gpt-5-.*$/]
      assert Merge.matches_exclude?("gpt-5-pro", patterns)
      refute Merge.matches_exclude?("gpt-4-pro", patterns)
    end

    test "matches mixed patterns" do
      patterns = ["gpt-3", ~r/^gpt-5-.*$/]
      assert Merge.matches_exclude?("gpt-3", patterns)
      assert Merge.matches_exclude?("gpt-5-ultra", patterns)
      refute Merge.matches_exclude?("gpt-4", patterns)
    end

    test "returns false for empty pattern list" do
      refute Merge.matches_exclude?("gpt-4", [])
    end

    test "matches first matching pattern" do
      patterns = ["gpt-4", "gpt-5"]
      assert Merge.matches_exclude?("gpt-4", patterns)
    end
  end

  describe "compile_excludes/1" do
    test "compiles glob patterns to regex" do
      excludes = %{openai: ["gpt-3", "gpt-5-*"]}
      result = Merge.compile_excludes(excludes)

      [exact, pattern] = result.openai
      assert exact == "gpt-3"
      assert is_struct(pattern, Regex)
    end

    test "preserves exact patterns as strings" do
      excludes = %{openai: ["gpt-3", "gpt-4"]}
      result = Merge.compile_excludes(excludes)

      assert result.openai == ["gpt-3", "gpt-4"]
    end

    test "handles multiple providers" do
      excludes = %{
        openai: ["gpt-5-*"],
        anthropic: ["claude-2"]
      }

      result = Merge.compile_excludes(excludes)

      assert length(result.openai) == 1
      assert is_struct(hd(result.openai), Regex)
      assert result.anthropic == ["claude-2"]
    end

    test "handles empty excludes" do
      assert Merge.compile_excludes(%{}) == %{}
    end
  end

  describe "complex nested merges" do
    test "merges complex model with capabilities, limits, and cost" do
      base = [
        %{
          id: "gpt-4",
          provider: :openai,
          capabilities: %{
            chat: true,
            tools: %{enabled: true, streaming: false}
          },
          limits: %{
            context: 128_000,
            output: 4_096
          },
          cost: %{
            input: 30.0,
            output: 60.0
          }
        }
      ]

      override = [
        %{
          id: "gpt-4",
          provider: :openai,
          capabilities: %{
            tools: %{streaming: true, parallel: true},
            json: %{native: true}
          },
          limits: %{
            output: 8_192
          },
          cost: %{
            cache_read: 15.0
          }
        }
      ]

      result = Merge.merge_models(base, override, %{})

      model = hd(result)
      assert model.capabilities.chat == true
      assert model.capabilities.tools.enabled == true
      assert model.capabilities.tools.streaming == true
      assert model.capabilities.tools.parallel == true
      assert model.capabilities.json.native == true
      assert model.limits.context == 128_000
      assert model.limits.output == 8_192
      assert model.cost.input == 30.0
      assert model.cost.output == 60.0
      assert model.cost.cache_read == 15.0
    end

    test "merges lists in nested structures" do
      base = [
        %{
          id: "gpt-4",
          provider: :openai,
          modalities: %{
            input: [:text, :image],
            output: [:text]
          },
          tags: ["production", "stable"]
        }
      ]

      override = [
        %{
          id: "gpt-4",
          provider: :openai,
          modalities: %{
            input: [:image, :audio],
            output: [:text, :json]
          },
          tags: ["stable", "recommended"]
        }
      ]

      result = Merge.merge_models(base, override, %{})

      model = hd(result)
      assert :text in model.modalities.input
      assert :image in model.modalities.input
      assert :audio in model.modalities.input
      assert :text in model.modalities.output
      assert :json in model.modalities.output
      assert "production" in model.tags
      assert "stable" in model.tags
      assert "recommended" in model.tags
    end
  end

  describe "edge cases" do
    test "handles nil in nested maps" do
      base = %{config: nil}
      override = %{config: %{value: 1}}

      result = Merge.merge(base, override, :higher)

      assert result == %{config: %{value: 1}}
    end

    test "handles models with missing provider or id" do
      base = [
        %{id: "gpt-4"},
        %{provider: :openai}
      ]

      override = []

      result = Merge.merge_models(base, override, %{})

      assert length(result) == 2
    end

    test "handles wildcard matching empty string" do
      pattern = Merge.compile_pattern("*")
      assert Regex.match?(pattern, "")
      assert Regex.match?(pattern, "anything")
    end

    test "merges with atom keys and string keys separately" do
      base = %{"value" => 2, value: 1}
      override = %{value: 10}

      result = Merge.merge(base, override, :higher)

      assert result.value == 10
      assert result["value"] == 2
    end
  end
end
