defmodule LLMDB.ConsumerFilteringTest do
  use ExUnit.Case, async: false

  alias LLMDB.{Engine, Snapshot, Store}
  alias LLMDB.Sources.Config, as: ConfigSource

  setup do
    original_config = Application.get_all_env(:llm_db)
    clear_test_config!()
    Store.clear!()

    on_exit(fn ->
      clear_test_config!()
      Store.clear!()
      restore_config!(original_config)
      LLMDB.load()
    end)

    :ok
  end

  describe "consumer use case: Phoenix app with restricted model set" do
    test "filters models at load time using :filter config" do
      # Configure filter to only allow Claude Haiku models
      Application.put_env(:llm_db, :filter, %{
        allow: %{
          anthropic: ["claude-3-haiku-*"],
          openrouter: ["anthropic/claude-3-haiku-*"]
        }
      })

      # Load packaged snapshot (will be filtered)
      {:ok, _snapshot} = LLMDB.load()

      # Test with actual packaged models - Haiku models should be visible
      # Check anthropic provider
      anthropic_models = LLMDB.models(:anthropic)

      unless Enum.empty?(anthropic_models) do
        # Should only contain haiku models
        assert Enum.all?(anthropic_models, fn model ->
                 String.contains?(model.id, "haiku") or String.contains?(model.id, "Haiku")
               end)
      end

      # Check openrouter provider
      openrouter_models = LLMDB.models(:openrouter)

      unless Enum.empty?(openrouter_models) do
        # Should only contain haiku models
        assert Enum.all?(openrouter_models, fn model ->
                 String.contains?(model.id, "haiku") or String.contains?(model.id, "Haiku")
               end)
      end

      # OpenAI models should not be visible (provider not in allow)
      openai_models = LLMDB.models(:openai)
      assert Enum.empty?(openai_models)
    end

    test "filters with string provider keys" do
      test_data = %{
        anthropic: %{
          id: :anthropic,
          models: [
            %{id: "claude-3-haiku-20240307", provider: :anthropic},
            %{id: "claude-3-opus-20240229", provider: :anthropic}
          ]
        }
      }

      # Use string keys (common in config files)
      Application.put_env(:llm_db, :filter, %{
        allow: %{"anthropic" => ["claude-3-haiku-*"]}
      })

      {:ok, _snapshot} =
        LLMDB.load(runtime_overrides: %{sources: [{ConfigSource, %{overrides: test_data}}]})

      assert {:ok, _model} = LLMDB.model(:anthropic, "claude-3-haiku-20240307")
      assert {:error, :not_found} = LLMDB.model(:anthropic, "claude-3-opus-20240229")
    end

    test "warns on unknown providers in filters" do
      test_data = %{
        anthropic: %{
          id: :anthropic,
          models: [%{id: "claude-3-haiku-20240307", provider: :anthropic}]
        }
      }

      # Configure filter with unknown provider
      Application.put_env(:llm_db, :filter, %{
        allow: %{
          anthropic: ["claude-*"],
          unknown_provider: ["model-*"]
        }
      })

      # Should warn but still succeed
      assert capture_log(fn ->
               {:ok, _snapshot} =
                 LLMDB.load(
                   runtime_overrides: %{sources: [{ConfigSource, %{overrides: test_data}}]}
                 )
             end) =~ "unknown provider(s) in filter: [:unknown_provider]"
    end

    test "fails fast when filter with explicit allow map eliminates all models" do
      # Use test data with known providers
      test_data = %{
        anthropic: %{
          id: :anthropic,
          models: [
            %{id: "claude-3-haiku-20240307", provider: :anthropic},
            %{id: "claude-3-opus-20240229", provider: :anthropic}
          ]
        },
        openai: %{
          id: :openai,
          models: [%{id: "gpt-4o-mini", provider: :openai}]
        }
      }

      # Configure filter that matches no models (allow very specific patterns that don't exist)
      Application.put_env(:llm_db, :filter, %{
        allow: %{
          anthropic: ["nonexistent-model-xyz"],
          openai: ["also-nonexistent-abc"]
        },
        deny: %{}
      })

      # Should return error because no models match the allow patterns
      assert {:error, error_msg} =
               LLMDB.load(
                 runtime_overrides: %{sources: [{ConfigSource, %{overrides: test_data}}]}
               )

      assert error_msg =~ "filters eliminated all models"
    end

    test "supports runtime filter overrides" do
      # Start with Haiku filter in config
      Application.put_env(:llm_db, :filter, %{
        allow: %{anthropic: ["claude-3-haiku-*"]}
      })

      {:ok, _snapshot} = LLMDB.load()

      # Only Haiku models visible
      anthropic_models = LLMDB.models(:anthropic)

      unless Enum.empty?(anthropic_models) do
        assert Enum.all?(anthropic_models, fn model ->
                 String.contains?(model.id, "haiku") or String.contains?(model.id, "Haiku")
               end)
      end

      # Override at runtime to allow Opus/Sonnet models instead
      {:ok, _snapshot} =
        LLMDB.load(
          allow: %{
            anthropic: [
              "claude-3-opus*",
              "claude-*-opus-*",
              "claude-3-5-sonnet-*",
              "claude-*-sonnet-*"
            ]
          },
          deny: %{}
        )

      # Now Opus/Sonnet visible, Haiku not
      anthropic_models = LLMDB.models(:anthropic)

      unless Enum.empty?(anthropic_models) do
        refute Enum.any?(anthropic_models, fn model ->
                 String.contains?(model.id, "haiku") or String.contains?(model.id, "Haiku")
               end)
      end
    end

    test "supports deny patterns to carve out exceptions" do
      test_data = %{
        anthropic: %{
          id: :anthropic,
          models: [
            %{id: "claude-3-haiku-20240307", provider: :anthropic},
            %{id: "claude-3-haiku-legacy", provider: :anthropic},
            %{id: "claude-3-opus-20240229", provider: :anthropic}
          ]
        }
      }

      Application.put_env(:llm_db, :filter, %{
        allow: %{anthropic: ["claude-3-haiku-*"]},
        deny: %{anthropic: ["*-legacy"]}
      })

      {:ok, _snapshot} =
        LLMDB.load(runtime_overrides: %{sources: [{ConfigSource, %{overrides: test_data}}]})

      # Haiku allowed except legacy
      assert {:ok, _} = LLMDB.model(:anthropic, "claude-3-haiku-20240307")
      assert {:error, :not_found} = LLMDB.model(:anthropic, "claude-3-haiku-legacy")
      assert {:error, :not_found} = LLMDB.model(:anthropic, "claude-3-opus-20240229")
    end
  end

  describe "consumer use case: custom providers via app config" do
    test "loads custom provider and models from app env config" do
      Application.put_env(:llm_db, :custom, %{
        local_llm: [
          name: "Local LLM Server",
          base_url: "http://localhost:8080/v1",
          models: %{
            "llama-3-8b" => %{capabilities: %{chat: true}},
            "mistral-7b" => %{capabilities: %{chat: true}}
          }
        ]
      })

      {:ok, _snapshot} = LLMDB.load()

      # Custom provider should be available
      assert {:ok, provider} = LLMDB.provider(:local_llm)
      assert provider.name == "Local LLM Server"
      assert provider.base_url == "http://localhost:8080/v1"

      # Custom models should be available
      assert {:ok, model} = LLMDB.model(:local_llm, "llama-3-8b")
      assert model.capabilities.chat == true
      assert {:ok, _} = LLMDB.model(:local_llm, "mistral-7b")

      local_models = LLMDB.models(:local_llm)
      assert length(local_models) == 2
    end

    test "normalizes string modality names in custom models before validation" do
      Application.put_env(:llm_db, :custom, %{
        local_llm: [
          name: "Local LLM Server",
          models: %{
            "llama-3-8b" => %{
              modalities: %{
                input: ["text"],
                output: ["text"]
              }
            }
          }
        ]
      })

      {:ok, _snapshot} = LLMDB.load()

      assert {:ok, model} = LLMDB.model(:local_llm, "llama-3-8b")
      assert model.modalities.input == [:text]
      assert model.modalities.output == [:text]
    end

    test "deep merges partial custom model overlays without losing packaged metadata" do
      snapshot_path =
        write_test_snapshot!(%{
          providers: [%{id: :openai, name: "OpenAI"}],
          models: [
            %{
              id: "gpt-5-mini",
              provider: :openai,
              name: "GPT-5 Mini",
              cost: %{input: 0.25, output: 2.0},
              capabilities: %{
                chat: true,
                reasoning: %{enabled: true},
                tools: %{enabled: true, strict: true},
                streaming: %{tool_calls: true}
              }
            }
          ]
        })

      on_exit(fn ->
        File.rm_rf!(snapshot_path)
      end)

      Application.put_env(:llm_db, :snapshot_path, snapshot_path)

      {:ok, _snapshot} =
        LLMDB.load(
          custom: %{
            openai: [
              models: %{
                "gpt-5-mini" => %{
                  capabilities: %{
                    json: %{schema: true}
                  }
                }
              }
            ]
          }
        )

      assert {:ok, model} = LLMDB.model(:openai, "gpt-5-mini")
      assert model.name == "GPT-5 Mini"
      assert model.cost.input == 0.25
      assert model.capabilities.reasoning.enabled == true
      assert model.capabilities.tools.enabled == true
      assert model.capabilities.tools.strict == true
      assert model.capabilities.streaming.tool_calls == true
      assert model.capabilities.json.schema == true
    end
  end

  defp capture_log(fun) do
    ExUnit.CaptureLog.capture_log(fun)
  end

  defp clear_test_config! do
    Enum.each([:filter, :custom, :allow, :deny, :prefer, :snapshot_path], fn key ->
      Application.delete_env(:llm_db, key)
    end)
  end

  defp restore_config!(original_config) do
    Enum.each(Keyword.keys(Application.get_all_env(:llm_db)), fn key ->
      Application.delete_env(:llm_db, key)
    end)

    Application.put_all_env(llm_db: original_config)
  end

  defp write_test_snapshot!(overrides) do
    {:ok, engine_snapshot} = Engine.run(sources: [{ConfigSource, %{overrides: overrides}}])

    snapshot_path =
      Path.join(System.tmp_dir!(), "llm_db-snapshot-#{System.unique_integer([:positive])}.json")

    snapshot = Snapshot.from_engine_snapshot(engine_snapshot)
    Snapshot.write!(snapshot_path, snapshot)
    snapshot_path
  end
end
