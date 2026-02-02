defmodule LLMDB.Schema.ModelTest do
  use ExUnit.Case, async: true

  alias LLMDB.Model

  describe "valid parsing" do
    test "parses minimal valid model" do
      input = %{
        id: "gpt-4o-mini",
        provider: :openai
      }

      assert {:ok, result} = Zoi.parse(Model.schema(), input)
      assert result.id == "gpt-4o-mini"
      assert result.provider == :openai
      assert result.deprecated == false
      assert result.aliases == []
    end

    test "parses complete model with all fields" do
      input = %{
        id: "gpt-4o-mini",
        provider: :openai,
        provider_model_id: "gpt-4o-mini-2024-07-18",
        name: "GPT-4o Mini",
        family: "gpt-4o",
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
        aliases: ["gpt-4o-mini-latest"],
        extra: %{"custom" => "value"}
      }

      assert {:ok, result} = Zoi.parse(Model.schema(), input)
      assert result.id == "gpt-4o-mini"
      assert result.provider == :openai
      assert result.provider_model_id == "gpt-4o-mini-2024-07-18"
      assert result.name == "GPT-4o Mini"
      assert result.family == "gpt-4o"
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
      assert result.aliases == ["gpt-4o-mini-latest"]
      assert result.extra == %{"custom" => "value"}
    end
  end

  describe "defaults" do
    test "deprecated defaults to false" do
      input = %{id: "gpt-4o", provider: :openai}
      assert {:ok, result} = Zoi.parse(Model.schema(), input)
      assert result.deprecated == false
    end

    test "aliases defaults to empty list" do
      input = %{id: "gpt-4o", provider: :openai}
      assert {:ok, result} = Zoi.parse(Model.schema(), input)
      assert result.aliases == []
    end

    test "can override deprecated to true" do
      input = %{id: "gpt-3.5-turbo", provider: :openai, deprecated: true}
      assert {:ok, result} = Zoi.parse(Model.schema(), input)
      assert result.deprecated == true
    end
  end

  describe "optional fields" do
    test "provider_model_id is optional" do
      input = %{id: "gpt-4o", provider: :openai}
      assert {:ok, result} = Zoi.parse(Model.schema(), input)
      assert result.provider_model_id == nil
    end

    test "name is optional" do
      input = %{id: "gpt-4o", provider: :openai}
      assert {:ok, result} = Zoi.parse(Model.schema(), input)
      assert result.name == nil
    end

    test "family is optional" do
      input = %{id: "gpt-4o", provider: :openai}
      assert {:ok, result} = Zoi.parse(Model.schema(), input)
      assert result.family == nil
    end

    test "release_date is optional" do
      input = %{id: "gpt-4o", provider: :openai}
      assert {:ok, result} = Zoi.parse(Model.schema(), input)
      assert result.release_date == nil
    end

    test "last_updated is optional" do
      input = %{id: "gpt-4o", provider: :openai}
      assert {:ok, result} = Zoi.parse(Model.schema(), input)
      assert result.last_updated == nil
    end

    test "knowledge is optional" do
      input = %{id: "gpt-4o", provider: :openai}
      assert {:ok, result} = Zoi.parse(Model.schema(), input)
      assert result.knowledge == nil
    end

    test "base_url is optional" do
      input = %{id: "gpt-4o", provider: :openai}
      assert {:ok, result} = Zoi.parse(Model.schema(), input)
      assert result.base_url == nil
    end

    test "limits is optional" do
      input = %{id: "gpt-4o", provider: :openai}
      assert {:ok, result} = Zoi.parse(Model.schema(), input)
      assert result.limits == nil
    end

    test "cost is optional" do
      input = %{id: "gpt-4o", provider: :openai}
      assert {:ok, result} = Zoi.parse(Model.schema(), input)
      assert result.cost == nil
    end

    test "modalities is optional" do
      input = %{id: "gpt-4o", provider: :openai}
      assert {:ok, result} = Zoi.parse(Model.schema(), input)
      assert result.modalities == nil
    end

    test "capabilities is optional" do
      input = %{id: "gpt-4o", provider: :openai}
      assert {:ok, result} = Zoi.parse(Model.schema(), input)
      assert result.capabilities == nil
    end

    test "tags is optional" do
      input = %{id: "gpt-4o", provider: :openai}
      assert {:ok, result} = Zoi.parse(Model.schema(), input)
      assert result.tags == nil
    end

    test "extra is optional" do
      input = %{id: "gpt-4o", provider: :openai}
      assert {:ok, result} = Zoi.parse(Model.schema(), input)
      assert result.extra == nil
    end
  end

  describe "invalid inputs" do
    test "rejects missing id" do
      input = %{provider: :openai}
      assert {:error, _} = Zoi.parse(Model.schema(), input)
    end

    test "rejects missing provider" do
      input = %{id: "gpt-4o"}
      assert {:error, _} = Zoi.parse(Model.schema(), input)
    end

    test "rejects non-string id" do
      input = %{id: :gpt_4o, provider: :openai}
      assert {:error, _} = Zoi.parse(Model.schema(), input)
    end

    test "rejects non-atom provider" do
      input = %{id: "gpt-4o", provider: "openai"}
      assert {:error, _} = Zoi.parse(Model.schema(), input)
    end

    test "rejects non-string name" do
      input = %{id: "gpt-4o", provider: :openai, name: 123}
      assert {:error, _} = Zoi.parse(Model.schema(), input)
    end

    test "rejects non-boolean deprecated" do
      input = %{id: "gpt-4o", provider: :openai, deprecated: "true"}
      assert {:error, _} = Zoi.parse(Model.schema(), input)
    end

    test "rejects non-array aliases" do
      input = %{id: "gpt-4o", provider: :openai, aliases: "gpt-4o-latest"}
      assert {:error, _} = Zoi.parse(Model.schema(), input)
    end

    test "rejects non-string elements in aliases" do
      input = %{id: "gpt-4o", provider: :openai, aliases: ["gpt-4o-latest", 123]}
      assert {:error, _} = Zoi.parse(Model.schema(), input)
    end

    test "rejects non-array tags" do
      input = %{id: "gpt-4o", provider: :openai, tags: "fast"}
      assert {:error, _} = Zoi.parse(Model.schema(), input)
    end
  end

  describe "nested schema validation" do
    test "validates limits schema" do
      input = %{
        id: "gpt-4o",
        provider: :openai,
        limits: %{context: -1}
      }

      assert {:error, _} = Zoi.parse(Model.schema(), input)
    end

    test "validates cost schema" do
      input = %{
        id: "gpt-4o",
        provider: :openai,
        cost: %{input: "invalid"}
      }

      assert {:error, _} = Zoi.parse(Model.schema(), input)
    end

    test "validates capabilities schema" do
      input = %{
        id: "gpt-4o",
        provider: :openai,
        capabilities: %{chat: "true"}
      }

      assert {:error, _} = Zoi.parse(Model.schema(), input)
    end
  end

  describe "modalities" do
    test "parses modalities with input and output" do
      input = %{
        id: "gpt-4o",
        provider: :openai,
        modalities: %{
          input: [:text, :image, :audio],
          output: [:text, :audio]
        }
      }

      assert {:ok, result} = Zoi.parse(Model.schema(), input)
      assert result.modalities.input == [:text, :image, :audio]
      assert result.modalities.output == [:text, :audio]
    end

    test "modalities input is optional" do
      input = %{
        id: "gpt-4o",
        provider: :openai,
        modalities: %{output: [:text]}
      }

      assert {:ok, result} = Zoi.parse(Model.schema(), input)
      refute Map.has_key?(result.modalities, :input)
      assert result.modalities.output == [:text]
    end

    test "modalities output is optional" do
      input = %{
        id: "gpt-4o",
        provider: :openai,
        modalities: %{input: [:text]}
      }

      assert {:ok, result} = Zoi.parse(Model.schema(), input)
      assert result.modalities.input == [:text]
      refute Map.has_key?(result.modalities, :output)
    end

    test "rejects non-atom modalities" do
      input = %{
        id: "gpt-4o",
        provider: :openai,
        modalities: %{input: ["text"]}
      }

      assert {:error, _} = Zoi.parse(Model.schema(), input)
    end
  end

  describe "extra fields pass through" do
    test "extra field contains unknown upstream keys" do
      input = %{
        id: "gpt-4o",
        provider: :openai,
        extra: %{
          "upstream_id" => "abc123",
          "custom_metadata" => %{"foo" => "bar"}
        }
      }

      assert {:ok, result} = Zoi.parse(Model.schema(), input)
      assert result.extra["upstream_id"] == "abc123"
      assert result.extra["custom_metadata"] == %{"foo" => "bar"}
    end
  end

  describe "cost schema" do
    test "parses cost with all fields" do
      input = %{
        id: "o1",
        provider: :openai,
        cost: %{
          input: 0.15,
          output: 0.60,
          request: 0.01,
          cache_read: 0.015,
          cache_write: 0.30,
          training: 3.00,
          reasoning: 1.00,
          image: 1.25,
          audio: 0.50,
          input_audio: 0.75,
          output_audio: 2.00,
          input_video: 1.50,
          output_video: 3.00
        }
      }

      assert {:ok, result} = Zoi.parse(Model.schema(), input)
      assert result.cost.input == 0.15
      assert result.cost.output == 0.60
      assert result.cost.request == 0.01
      assert result.cost.cache_read == 0.015
      assert result.cost.cache_write == 0.30
      assert result.cost.training == 3.00
      assert result.cost.reasoning == 1.00
      assert result.cost.image == 1.25
      assert result.cost.audio == 0.50
      assert result.cost.input_audio == 0.75
      assert result.cost.output_audio == 2.00
      assert result.cost.input_video == 1.50
      assert result.cost.output_video == 3.00
    end

    test "parses cost with only reasoning" do
      input = %{
        id: "o1",
        provider: :openai,
        cost: %{reasoning: 1.00}
      }

      assert {:ok, result} = Zoi.parse(Model.schema(), input)
      assert result.cost.reasoning == 1.00
    end

    test "parses cost with audio fields" do
      input = %{
        id: "gemini-2.5-flash",
        provider: :google,
        cost: %{
          input: 0.15,
          output: 0.60,
          input_audio: 0.75,
          output_audio: 2.00
        }
      }

      assert {:ok, result} = Zoi.parse(Model.schema(), input)
      assert result.cost.input == 0.15
      assert result.cost.output == 0.60
      assert result.cost.input_audio == 0.75
      assert result.cost.output_audio == 2.00
    end

    test "parses cost with video fields" do
      input = %{
        id: "test-model",
        provider: :test,
        cost: %{
          input_video: 1.50,
          output_video: 3.00
        }
      }

      assert {:ok, result} = Zoi.parse(Model.schema(), input)
      assert result.cost.input_video == 1.50
      assert result.cost.output_video == 3.00
    end

    test "all cost fields are optional" do
      input = %{
        id: "test-model",
        provider: :test,
        cost: %{}
      }

      assert {:ok, result} = Zoi.parse(Model.schema(), input)
      assert result.cost == %{}
    end

    test "accepts integer cost values" do
      input = %{
        id: "test-model",
        provider: :test,
        cost: %{input: 1, output: 2}
      }

      assert {:ok, result} = Zoi.parse(Model.schema(), input)
      assert result.cost.input == 1
      assert result.cost.output == 2
    end

    test "accepts zero cost values" do
      input = %{
        id: "test-model",
        provider: :test,
        cost: %{input: 0.0, reasoning: 0.0}
      }

      assert {:ok, result} = Zoi.parse(Model.schema(), input)
      assert result.cost.input == 0.0
      assert result.cost.reasoning == 0.0
    end
  end

  describe "lifecycle synchronization" do
    test "syncs both flags when lifecycle status is retired" do
      input = %{
        id: "claude-3-opus-20240229",
        provider: :anthropic,
        lifecycle: %{status: "retired", retires_at: "2025-01-01"}
      }

      assert {:ok, result} = Model.new(input)
      assert result.deprecated == true
      assert result.retired == true
      assert result.lifecycle.status == "retired"
      assert result.lifecycle.retires_at == "2025-01-01"
    end

    test "syncs both flags when lifecycle status is deprecated" do
      input = %{
        id: "claude-3-5-sonnet-20241022",
        provider: :anthropic,
        lifecycle: %{status: "deprecated", deprecated_at: "2025-02-19"}
      }

      assert {:ok, result} = Model.new(input)
      assert result.deprecated == true
      assert result.retired == false
      assert result.lifecycle.status == "deprecated"
      assert result.lifecycle.deprecated_at == "2025-02-19"
    end

    test "syncs both flags when lifecycle status is deprecated with retires_at" do
      # Test the exact scenario from issue #99
      input = %{
        id: "dall-e-3",
        provider: :openai,
        lifecycle: %{
          status: "deprecated",
          deprecated_at: "2025-05-12",
          retires_at: "2026-05-12",
          replacement: "gpt-image-1.5"
        }
      }

      assert {:ok, result} = Model.new(input)
      # The fix: model.deprecated should now return true
      assert result.deprecated == true
      assert result.retired == false
      assert result.lifecycle.status == "deprecated"
    end

    test "sets retired to false when lifecycle status is active" do
      input = %{
        id: "gpt-4o",
        provider: :openai,
        lifecycle: %{status: "active"}
      }

      assert {:ok, result} = Model.new(input)
      assert result.retired == false
      assert result.deprecated == false
      assert result.lifecycle.status == "active"
    end

    test "preserves explicit deprecated flag when no lifecycle info" do
      input = %{
        id: "gpt-3.5-turbo",
        provider: :openai,
        deprecated: true
      }

      assert {:ok, result} = Model.new(input)
      assert result.deprecated == true
      assert result.retired == false
      assert result.lifecycle == nil
    end

    test "backwards compatibility: upstream source with only deprecated flag" do
      # Simulates upstream sources like models.dev that only provide deprecated: true
      input = %{
        id: "legacy-model",
        provider: :test,
        deprecated: true
      }

      assert {:ok, result} = Model.new(input)
      assert result.deprecated == true
      assert result.retired == false
      assert result.lifecycle == nil
    end

    test "local override with lifecycle overrides upstream deprecated flag" do
      # Simulates merge where upstream has deprecated: false
      # but local TOML override has full lifecycle info
      input = %{
        id: "claude-3-5-sonnet-20241022",
        provider: :anthropic,
        deprecated: false,
        lifecycle: %{status: "deprecated"}
      }

      assert {:ok, result} = Model.new(input)
      # Sync logic should set both based on lifecycle
      assert result.deprecated == true
      assert result.retired == false
    end

    test "nil lifecycle with explicit true deprecated preserves both" do
      input = %{
        id: "model-with-nil-lifecycle-status",
        provider: :test,
        deprecated: true,
        lifecycle: %{status: nil}
      }

      assert {:ok, result} = Model.new(input)
      # nil status preserves both flags as-is
      assert result.deprecated == true
      assert result.retired == false
    end
  end

  describe "helper functions" do
    test "deprecated?/1 returns true when deprecated flag is set" do
      model = Model.new!(%{id: "gpt-3", provider: :openai, deprecated: true})
      assert Model.deprecated?(model) == true
    end

    test "deprecated?/1 returns true when lifecycle status is deprecated" do
      model =
        Model.new!(%{
          id: "gpt-3",
          provider: :openai,
          lifecycle: %{status: "deprecated"}
        })

      assert Model.deprecated?(model) == true
    end

    test "deprecated?/1 returns true when lifecycle status is retired" do
      model =
        Model.new!(%{
          id: "gpt-3",
          provider: :openai,
          lifecycle: %{status: "retired"}
        })

      assert Model.deprecated?(model) == true
    end

    test "deprecated?/1 returns false for active models" do
      model =
        Model.new!(%{
          id: "gpt-4",
          provider: :openai,
          lifecycle: %{status: "active"}
        })

      assert Model.deprecated?(model) == false
    end

    test "deprecated?/1 returns false for models without lifecycle" do
      model = Model.new!(%{id: "gpt-4", provider: :openai})
      assert Model.deprecated?(model) == false
    end

    test "retired?/1 returns true when retired flag is set" do
      model = Model.new!(%{id: "gpt-3", provider: :openai, retired: true})
      assert Model.retired?(model) == true
    end

    test "retired?/1 returns true when lifecycle status is retired" do
      model =
        Model.new!(%{
          id: "gpt-3",
          provider: :openai,
          lifecycle: %{status: "retired"}
        })

      assert Model.retired?(model) == true
    end

    test "retired?/1 returns false for deprecated models" do
      model =
        Model.new!(%{
          id: "gpt-3",
          provider: :openai,
          lifecycle: %{status: "deprecated"}
        })

      assert Model.retired?(model) == false
    end

    test "retired?/1 returns false for active models" do
      model =
        Model.new!(%{
          id: "gpt-4",
          provider: :openai,
          lifecycle: %{status: "active"}
        })

      assert Model.retired?(model) == false
    end

    test "retired?/1 returns false for models without lifecycle" do
      model = Model.new!(%{id: "gpt-4", provider: :openai})
      assert Model.retired?(model) == false
    end
  end

  describe "retired field" do
    test "retired defaults to false" do
      input = %{id: "gpt-4o", provider: :openai}
      assert {:ok, result} = Zoi.parse(Model.schema(), input)
      assert result.retired == false
    end

    test "can override retired to true" do
      input = %{id: "gpt-3", provider: :openai, retired: true}
      assert {:ok, result} = Zoi.parse(Model.schema(), input)
      assert result.retired == true
    end

    test "rejects non-boolean retired" do
      input = %{id: "gpt-4o", provider: :openai, retired: "true"}
      assert {:error, _} = Zoi.parse(Model.schema(), input)
    end
  end

  describe "flexible lifecycle status handling" do
    test "beta status is treated as active" do
      input = %{
        id: "gpt-4o-beta",
        provider: :openai,
        lifecycle: %{status: "beta"}
      }

      assert {:ok, result} = Model.new(input)
      assert result.retired == false
      assert result.deprecated == false
      assert Model.deprecated?(result) == false
      assert Model.retired?(result) == false
    end

    test "experimental status is treated as active" do
      input = %{
        id: "experimental-model",
        provider: :test,
        lifecycle: %{status: "experimental"}
      }

      assert {:ok, result} = Model.new(input)
      assert result.retired == false
      assert Model.deprecated?(result) == false
    end

    test "alpha status is treated as active" do
      input = %{
        id: "alpha-model",
        provider: :test,
        lifecycle: %{status: "alpha"}
      }

      assert {:ok, result} = Model.new(input)
      assert result.retired == false
      assert Model.deprecated?(result) == false
    end

    test "archived status is treated as retired" do
      input = %{
        id: "old-model",
        provider: :test,
        lifecycle: %{status: "archived"}
      }

      assert {:ok, result} = Model.new(input)
      assert result.deprecated == true
      assert result.retired == true
      assert Model.deprecated?(result) == true
      assert Model.retired?(result) == true
    end

    test "removed status is treated as retired" do
      input = %{
        id: "removed-model",
        provider: :test,
        lifecycle: %{status: "removed"}
      }

      assert {:ok, result} = Model.new(input)
      assert result.deprecated == true
      assert result.retired == true
      assert Model.deprecated?(result) == true
      assert Model.retired?(result) == true
    end

    test "unknown custom status preserves existing flags" do
      input = %{
        id: "custom-model",
        provider: :test,
        deprecated: false,
        lifecycle: %{status: "custom_provider_status"}
      }

      assert {:ok, result} = Model.new(input)
      # Unknown status preserves flags as-is
      assert result.deprecated == false
      assert result.retired == false
      # But helper functions check against known statuses
      assert Model.deprecated?(result) == false
      assert Model.retired?(result) == false
    end

    test "unknown custom status with explicit deprecated true is preserved" do
      input = %{
        id: "custom-model",
        provider: :test,
        deprecated: true,
        lifecycle: %{status: "some_future_status"}
      }

      assert {:ok, result} = Model.new(input)
      # Unknown status preserves flags as-is
      assert result.deprecated == true
      assert result.retired == false
      # Helper returns true because the boolean flag is set
      assert Model.deprecated?(result) == true
    end

    test "status accepts any string value" do
      input = %{
        id: "model",
        provider: :test,
        lifecycle: %{status: "google_preview"}
      }

      assert {:ok, result} = Model.new(input)
      assert result.lifecycle.status == "google_preview"
    end
  end

  describe "lifecycle accessor functions" do
    test "lifecycle_status/1 returns the status" do
      model = Model.new!(%{id: "gpt-4", provider: :openai, lifecycle: %{status: "active"}})
      assert Model.lifecycle_status(model) == "active"
    end

    test "lifecycle_status/1 returns nil for models without lifecycle" do
      model = Model.new!(%{id: "gpt-4", provider: :openai})
      assert Model.lifecycle_status(model) == nil
    end

    test "deprecated_at/1 returns the deprecation date" do
      model =
        Model.new!(%{
          id: "gpt-3",
          provider: :openai,
          lifecycle: %{status: "deprecated", deprecated_at: "2024-01-01"}
        })

      assert Model.deprecated_at(model) == "2024-01-01"
    end

    test "deprecated_at/1 returns nil for models without deprecation date" do
      model = Model.new!(%{id: "gpt-4", provider: :openai})
      assert Model.deprecated_at(model) == nil
    end

    test "retires_at/1 returns the retirement date" do
      model =
        Model.new!(%{
          id: "gpt-3",
          provider: :openai,
          lifecycle: %{status: "deprecated", retires_at: "2025-01-01"}
        })

      assert Model.retires_at(model) == "2025-01-01"
    end

    test "retires_at/1 returns nil for models without retirement date" do
      model = Model.new!(%{id: "gpt-4", provider: :openai})
      assert Model.retires_at(model) == nil
    end

    test "replacement/1 returns the replacement model ID" do
      model =
        Model.new!(%{
          id: "gpt-3",
          provider: :openai,
          lifecycle: %{replacement: "gpt-4"}
        })

      assert Model.replacement(model) == "gpt-4"
    end

    test "replacement/1 returns nil for models without replacement" do
      model = Model.new!(%{id: "gpt-4", provider: :openai})
      assert Model.replacement(model) == nil
    end

    test "has_replacement?/1 returns true when replacement is set" do
      model =
        Model.new!(%{
          id: "gpt-3",
          provider: :openai,
          lifecycle: %{replacement: "gpt-4"}
        })

      assert Model.has_replacement?(model) == true
    end

    test "has_replacement?/1 returns false when no replacement" do
      model = Model.new!(%{id: "gpt-4", provider: :openai})
      assert Model.has_replacement?(model) == false
    end

    test "full lifecycle data is accessible via accessors" do
      # Test the exact scenario from issue #99
      model =
        Model.new!(%{
          id: "dall-e-3",
          provider: :openai,
          lifecycle: %{
            status: "deprecated",
            deprecated_at: "2025-05-12",
            retires_at: "2026-05-12",
            replacement: "gpt-image-1.5"
          }
        })

      assert Model.lifecycle_status(model) == "deprecated"
      assert Model.deprecated_at(model) == "2025-05-12"
      assert Model.retires_at(model) == "2026-05-12"
      assert Model.replacement(model) == "gpt-image-1.5"
      assert Model.has_replacement?(model) == true
      assert Model.deprecated?(model) == true
      assert Model.retired?(model) == false
    end
  end
end
