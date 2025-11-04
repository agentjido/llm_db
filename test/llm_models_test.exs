defmodule LlmModelsTest do
  use ExUnit.Case, async: false

  alias LlmModels.Store

  setup do
    Store.clear!()
    :ok
  end

  describe "lifecycle functions" do
    test "load/1 runs engine and stores snapshot" do
      {:ok, snapshot} = LlmModels.load()

      assert is_map(snapshot)
      assert Map.has_key?(snapshot, :providers_by_id)
      assert Map.has_key?(snapshot, :models_by_key)
      assert Map.has_key?(snapshot, :aliases_by_key)
      assert Map.has_key?(snapshot, :models)
      assert Map.has_key?(snapshot, :filters)
      assert Map.has_key?(snapshot, :meta)

      assert Store.snapshot() == snapshot
    end

    test "load/1 returns error on empty catalog" do
      config = %{
        overrides: %{providers: [], models: [], exclude: %{}},
        overrides_module: nil,
        allow: %{},
        deny: %{openai: ["*"], anthropic: ["*"], google_vertex: ["*"]},
        prefer: []
      }

      result = LlmModels.load(config: config)
      assert {:error, :empty_catalog} = result
    end

    test "reload/0 uses last opts" do
      {:ok, _} = LlmModels.load()
      epoch1 = LlmModels.epoch()

      assert :ok = LlmModels.reload()
      epoch2 = LlmModels.epoch()

      assert epoch2 > epoch1
    end

    test "snapshot/0 returns current snapshot" do
      {:ok, snapshot} = LlmModels.load()
      assert LlmModels.snapshot() == snapshot
    end

    test "snapshot/0 returns nil when not loaded" do
      assert LlmModels.snapshot() == nil
    end

    test "epoch/0 returns current epoch" do
      {:ok, _} = LlmModels.load()
      epoch = LlmModels.epoch()

      assert is_integer(epoch)
      assert epoch > 0
    end

    test "epoch/0 returns 0 when not loaded" do
      assert LlmModels.epoch() == 0
    end
  end

  describe "provider listing and lookup" do
    setup do
      {:ok, _} = LlmModels.load()
      :ok
    end

    test "list_providers/0 returns sorted provider atoms" do
      providers = LlmModels.list_providers()

      assert is_list(providers)
      assert length(providers) > 0
      assert Enum.all?(providers, &is_atom/1)
      assert providers == Enum.sort(providers)
    end

    test "list_providers/0 returns empty list when not loaded" do
      Store.clear!()
      assert LlmModels.list_providers() == []
    end

    test "get_provider/1 returns provider metadata" do
      providers = LlmModels.list_providers()
      provider = hd(providers)

      {:ok, provider_data} = LlmModels.get_provider(provider)

      assert is_map(provider_data)
      assert provider_data.id == provider
    end

    test "get_provider/1 returns :error for unknown provider" do
      assert :error = LlmModels.get_provider(:nonexistent)
    end

    test "get_provider/1 returns :error when not loaded" do
      Store.clear!()
      assert :error = LlmModels.get_provider(:openai)
    end
  end

  describe "model listing with filters" do
    setup do
      {:ok, _} = LlmModels.load()
      :ok
    end

    test "list_models/2 returns all models for provider" do
      providers = LlmModels.list_providers()

      if providers != [] do
        provider = hd(providers)
        models = LlmModels.list_models(provider)

        assert is_list(models)
        assert Enum.all?(models, fn m -> m.provider == provider end)
      end
    end

    test "list_models/2 filters by required capabilities" do
      providers = LlmModels.list_providers()

      if providers != [] do
        provider = hd(providers)
        models = LlmModels.list_models(provider, require: [chat: true])

        assert is_list(models)

        Enum.each(models, fn model ->
          caps = Map.get(model, :capabilities, %{})
          assert Map.get(caps, :chat) == true
        end)
      end
    end

    test "list_models/2 filters by forbidden capabilities" do
      providers = LlmModels.list_providers()

      if providers != [] do
        provider = hd(providers)
        models = LlmModels.list_models(provider, forbid: [embeddings: true])

        assert is_list(models)

        Enum.each(models, fn model ->
          caps = Map.get(model, :capabilities, %{})
          refute Map.get(caps, :embeddings) == true
        end)
      end
    end

    test "list_models/2 combines require and forbid filters" do
      providers = LlmModels.list_providers()

      if providers != [] do
        provider = hd(providers)

        models =
          LlmModels.list_models(provider,
            require: [chat: true],
            forbid: [embeddings: true]
          )

        assert is_list(models)

        Enum.each(models, fn model ->
          caps = Map.get(model, :capabilities, %{})
          assert Map.get(caps, :chat) == true
          refute Map.get(caps, :embeddings) == true
        end)
      end
    end

    test "list_models/2 returns empty list when not loaded" do
      Store.clear!()
      assert LlmModels.list_models(:openai) == []
    end
  end

  describe "model lookup" do
    setup do
      {:ok, _} = LlmModels.load()
      :ok
    end

    test "get_model/2 returns model by provider and id" do
      providers = LlmModels.list_providers()

      if providers != [] do
        provider = hd(providers)
        models = LlmModels.list_models(provider)

        if models != [] do
          model = hd(models)
          {:ok, fetched} = LlmModels.get_model(provider, model.id)

          assert fetched.id == model.id
          assert fetched.provider == provider
        end
      end
    end

    test "get_model/2 resolves aliases" do
      providers = LlmModels.list_providers()

      if providers != [] do
        provider = hd(providers)
        models = LlmModels.list_models(provider)

        model_with_alias = Enum.find(models, fn m -> m.aliases != [] end)

        if model_with_alias do
          alias_name = hd(model_with_alias.aliases)
          {:ok, fetched} = LlmModels.get_model(provider, alias_name)

          assert fetched.id == model_with_alias.id
        end
      end
    end

    test "get_model/2 returns :error for unknown model" do
      assert :error = LlmModels.get_model(:openai, "nonexistent-model")
    end

    test "get_model/2 returns :error when not loaded" do
      Store.clear!()
      assert :error = LlmModels.get_model(:openai, "gpt-4")
    end
  end

  describe "capabilities/1" do
    setup do
      {:ok, _} = LlmModels.load()
      :ok
    end

    test "capabilities/1 with tuple spec returns capabilities or nil" do
      providers = LlmModels.list_providers()

      if providers != [] do
        provider = hd(providers)
        models = LlmModels.list_models(provider)

        if models != [] do
          model = hd(models)
          caps = LlmModels.capabilities({provider, model.id})

          # Capabilities may be nil if not in snapshot
          if caps do
            assert is_map(caps)
          end
        end
      end
    end

    test "capabilities/1 with string spec returns capabilities or nil" do
      providers = LlmModels.list_providers()

      if providers != [] do
        provider = hd(providers)
        models = LlmModels.list_models(provider)

        if models != [] do
          model = hd(models)
          spec = "#{provider}:#{model.id}"
          caps = LlmModels.capabilities(spec)

          # Capabilities may be nil if not in snapshot
          if caps do
            assert is_map(caps)
          end
        end
      end
    end

    test "capabilities/1 returns nil for unknown model" do
      assert LlmModels.capabilities({:openai, "nonexistent"}) == nil
    end

    test "capabilities/1 returns nil when not loaded" do
      Store.clear!()
      assert LlmModels.capabilities({:openai, "gpt-4"}) == nil
    end
  end

  describe "allowed?/1" do
    test "allowed?/1 returns true for allowed model with :all filter" do
      config = %{
        overrides: %{
          providers: [%{id: :test_provider}],
          models: [
            %{id: "test-model", provider: :test_provider, capabilities: %{chat: true}}
          ],
          exclude: %{}
        },
        overrides_module: nil,
        allow: :all,
        deny: %{},
        prefer: []
      }

      {:ok, _} = LlmModels.load(config: config)

      assert LlmModels.allowed?({:test_provider, "test-model"}) == true
    end

    test "allowed?/1 returns false for denied model" do
      config = %{
        overrides: %{
          providers: [%{id: :test_provider}],
          models: [
            %{id: "test-model", provider: :test_provider, capabilities: %{chat: true}}
          ],
          exclude: %{}
        },
        overrides_module: nil,
        allow: :all,
        deny: %{test_provider: ["test-model"]},
        prefer: []
      }

      {:ok, _} = LlmModels.load(config: config)

      assert LlmModels.allowed?({:test_provider, "test-model"}) == false
    end

    test "allowed?/1 with string spec" do
      config = %{
        overrides: %{
          providers: [%{id: :test_provider}],
          models: [
            %{id: "test-model", provider: :test_provider, capabilities: %{chat: true}}
          ],
          exclude: %{}
        },
        overrides_module: nil,
        allow: :all,
        deny: %{},
        prefer: []
      }

      {:ok, _} = LlmModels.load(config: config)

      assert LlmModels.allowed?("test_provider:test-model") == true
    end

    test "allowed?/1 returns false when not loaded" do
      Store.clear!()
      assert LlmModels.allowed?({:openai, "gpt-4"}) == false
    end
  end

  describe "select/1" do
    test "select/1 returns first matching model" do
      config = %{
        overrides: %{
          providers: [%{id: :provider_a}, %{id: :provider_b}],
          models: [
            %{
              id: "model-a1",
              provider: :provider_a,
              capabilities: %{chat: true, tools: %{enabled: true}}
            },
            %{
              id: "model-b1",
              provider: :provider_b,
              capabilities: %{chat: true, tools: %{enabled: true}}
            }
          ],
          exclude: %{}
        },
        overrides_module: nil,
        allow: %{provider_a: ["*"], provider_b: ["*"]},
        deny: %{openai: ["*"], anthropic: ["*"]},
        prefer: []
      }

      {:ok, _} = LlmModels.load(config: config)

      {:ok, {provider, model_id}} = LlmModels.select(require: [chat: true, tools: true])

      assert provider in [:provider_a, :provider_b]
      assert is_binary(model_id)
    end

    test "select/1 respects prefer order" do
      config = %{
        overrides: %{
          providers: [%{id: :provider_a}, %{id: :provider_b}],
          models: [
            %{
              id: "model-a1",
              provider: :provider_a,
              capabilities: %{chat: true, tools: %{enabled: true}}
            },
            %{
              id: "model-b1",
              provider: :provider_b,
              capabilities: %{chat: true, tools: %{enabled: true}}
            }
          ],
          exclude: %{}
        },
        overrides_module: nil,
        allow: :all,
        deny: %{},
        prefer: [:provider_b, :provider_a]
      }

      {:ok, _} = LlmModels.load(config: config)

      {:ok, {provider, model_id}} =
        LlmModels.select(require: [chat: true, tools: true], prefer: [:provider_b, :provider_a])

      assert provider == :provider_b
      assert model_id == "model-b1"
    end

    test "select/1 with scope restricts to single provider" do
      config = %{
        overrides: %{
          providers: [%{id: :provider_a}, %{id: :provider_b}],
          models: [
            %{
              id: "model-a1",
              provider: :provider_a,
              capabilities: %{chat: true}
            },
            %{
              id: "model-b1",
              provider: :provider_b,
              capabilities: %{chat: true}
            }
          ],
          exclude: %{}
        },
        overrides_module: nil,
        allow: :all,
        deny: %{},
        prefer: []
      }

      {:ok, _} = LlmModels.load(config: config)

      {:ok, {provider, model_id}} = LlmModels.select(require: [chat: true], scope: :provider_a)

      assert provider == :provider_a
      assert model_id == "model-a1"
    end

    test "select/1 respects forbid filter" do
      config = %{
        overrides: %{
          providers: [%{id: :provider_a}],
          models: [
            %{
              id: "model-a1",
              provider: :provider_a,
              capabilities: %{chat: true, embeddings: true}
            },
            %{
              id: "model-a2",
              provider: :provider_a,
              capabilities: %{chat: true, embeddings: false}
            }
          ],
          exclude: %{}
        },
        overrides_module: nil,
        allow: %{provider_a: ["*"]},
        deny: %{openai: ["*"], anthropic: ["*"]},
        prefer: []
      }

      {:ok, _} = LlmModels.load(config: config)

      {:ok, {provider, model_id}} =
        LlmModels.select(require: [chat: true], forbid: [embeddings: true])

      assert provider == :provider_a
      assert model_id == "model-a2"
    end

    test "select/1 returns :no_match when no models match" do
      config = %{
        overrides: %{
          providers: [%{id: :provider_a}],
          models: [
            %{
              id: "model-a1",
              provider: :provider_a,
              capabilities: %{chat: true, tools: %{enabled: false}}
            }
          ],
          exclude: %{}
        },
        overrides_module: nil,
        allow: %{provider_a: ["*"]},
        deny: %{openai: ["*"], anthropic: ["*"]},
        prefer: []
      }

      {:ok, _} = LlmModels.load(config: config)

      assert {:error, :no_match} = LlmModels.select(require: [tools: true])
    end

    test "select/1 returns :no_match when not loaded" do
      Store.clear!()
      assert {:error, :no_match} = LlmModels.select(require: [chat: true])
    end
  end

  describe "spec parsing" do
    setup do
      {:ok, _} = LlmModels.load()
      :ok
    end

    test "parse_provider/1 delegates to Spec module" do
      providers = LlmModels.list_providers()

      if providers != [] do
        provider = hd(providers)
        assert {:ok, ^provider} = LlmModels.parse_provider(provider)
      end
    end

    test "parse_provider/1 normalizes string to atom" do
      providers = LlmModels.list_providers()

      if :openai in providers do
        assert {:ok, :openai} = LlmModels.parse_provider("openai")
      end
    end

    test "parse_provider/1 returns error for unknown provider" do
      assert {:error, :unknown_provider} = LlmModels.parse_provider(:nonexistent)
    end

    test "parse_spec/1 parses provider:model format" do
      providers = LlmModels.list_providers()

      if providers != [] do
        provider = hd(providers)
        models = LlmModels.list_models(provider)

        if models != [] do
          model = hd(models)
          spec = "#{provider}:#{model.id}"

          assert {:ok, {^provider, model_id}} = LlmModels.parse_spec(spec)
          assert model_id == model.id
        end
      end
    end

    test "parse_spec/1 returns error for invalid format" do
      assert {:error, :invalid_format} = LlmModels.parse_spec("no-colon")
    end

    test "parse_spec/1 returns error for unknown provider" do
      assert {:error, :unknown_provider} = LlmModels.parse_spec("nonexistent:model")
    end

    test "resolve/2 resolves string spec to model" do
      providers = LlmModels.list_providers()

      if providers != [] do
        provider = hd(providers)
        models = LlmModels.list_models(provider)

        if models != [] do
          model = hd(models)
          spec = "#{provider}:#{model.id}"

          assert {:ok, {^provider, canonical_id, resolved_model}} = LlmModels.resolve(spec)
          assert canonical_id == model.id
          assert resolved_model.id == model.id
        end
      end
    end

    test "resolve/2 resolves tuple spec to model" do
      providers = LlmModels.list_providers()

      if providers != [] do
        provider = hd(providers)
        models = LlmModels.list_models(provider)

        if models != [] do
          model = hd(models)

          assert {:ok, {^provider, canonical_id, resolved_model}} =
                   LlmModels.resolve({provider, model.id})

          assert canonical_id == model.id
          assert resolved_model.id == model.id
        end
      end
    end

    test "resolve/2 resolves alias to canonical model" do
      providers = LlmModels.list_providers()

      if providers != [] do
        provider = hd(providers)
        models = LlmModels.list_models(provider)

        model_with_alias = Enum.find(models, fn m -> m.aliases != [] end)

        if model_with_alias do
          alias_name = hd(model_with_alias.aliases)

          assert {:ok, {^provider, canonical_id, resolved_model}} =
                   LlmModels.resolve({provider, alias_name})

          assert canonical_id == model_with_alias.id
          assert resolved_model.id == model_with_alias.id
        end
      end
    end

    test "resolve/2 returns error for unknown model" do
      assert {:error, :not_found} = LlmModels.resolve({:openai, "nonexistent"})
    end

    test "resolve/2 with scope resolves bare model id" do
      providers = LlmModels.list_providers()

      if providers != [] do
        provider = hd(providers)
        models = LlmModels.list_models(provider)

        if models != [] do
          model = hd(models)

          assert {:ok, {^provider, canonical_id, resolved_model}} =
                   LlmModels.resolve(model.id, scope: provider)

          assert canonical_id == model.id
          assert resolved_model.id == model.id
        end
      end
    end
  end

  describe "capability predicates" do
    test "matches chat capability" do
      config = %{
        overrides: %{
          providers: [%{id: :test_provider}],
          models: [
            %{id: "chat-model", provider: :test_provider, capabilities: %{chat: true}},
            %{id: "no-chat-model", provider: :test_provider, capabilities: %{chat: false}}
          ],
          exclude: %{}
        },
        overrides_module: nil,
        allow: :all,
        deny: %{},
        prefer: []
      }

      {:ok, _} = LlmModels.load(config: config)

      models = LlmModels.list_models(:test_provider, require: [chat: true])
      assert length(models) == 1
      assert hd(models).id == "chat-model"
    end

    test "matches nested tool capabilities" do
      config = %{
        overrides: %{
          providers: [%{id: :test_provider}],
          models: [
            %{
              id: "tools-model",
              provider: :test_provider,
              capabilities: %{tools: %{enabled: true, streaming: true}}
            },
            %{
              id: "no-tools-model",
              provider: :test_provider,
              capabilities: %{tools: %{enabled: false}}
            }
          ],
          exclude: %{}
        },
        overrides_module: nil,
        allow: :all,
        deny: %{},
        prefer: []
      }

      {:ok, _} = LlmModels.load(config: config)

      models = LlmModels.list_models(:test_provider, require: [tools: true])
      assert length(models) == 1
      assert hd(models).id == "tools-model"

      models =
        LlmModels.list_models(:test_provider, require: [tools: true, tools_streaming: true])

      assert length(models) == 1
      assert hd(models).id == "tools-model"
    end

    test "matches nested json capabilities" do
      config = %{
        overrides: %{
          providers: [%{id: :test_provider}],
          models: [
            %{
              id: "json-model",
              provider: :test_provider,
              capabilities: %{json: %{native: true, schema: true}}
            },
            %{
              id: "no-json-model",
              provider: :test_provider,
              capabilities: %{json: %{native: false}}
            }
          ],
          exclude: %{}
        },
        overrides_module: nil,
        allow: :all,
        deny: %{},
        prefer: []
      }

      {:ok, _} = LlmModels.load(config: config)

      models = LlmModels.list_models(:test_provider, require: [json_native: true])
      assert length(models) == 1
      assert hd(models).id == "json-model"

      models =
        LlmModels.list_models(:test_provider, require: [json_native: true, json_schema: true])

      assert length(models) == 1
      assert hd(models).id == "json-model"
    end

    test "matches nested streaming capabilities" do
      config = %{
        overrides: %{
          providers: [%{id: :test_provider}],
          models: [
            %{
              id: "streaming-model",
              provider: :test_provider,
              capabilities: %{streaming: %{text: true, tool_calls: true}}
            },
            %{
              id: "no-streaming-model",
              provider: :test_provider,
              capabilities: %{streaming: %{text: false, tool_calls: false}}
            }
          ],
          exclude: %{}
        },
        overrides_module: nil,
        allow: :all,
        deny: %{},
        prefer: []
      }

      {:ok, _} = LlmModels.load(config: config)

      models = LlmModels.list_models(:test_provider, require: [streaming_tool_calls: true])
      assert length(models) == 1
      assert hd(models).id == "streaming-model"
    end
  end

  describe "integration tests" do
    test "full pipeline: load, list, get, select" do
      config = %{
        overrides: %{
          providers: [
            %{id: :provider_a, name: "Provider A"},
            %{id: :provider_b, name: "Provider B"}
          ],
          models: [
            %{
              id: "model-a1",
              provider: :provider_a,
              capabilities: %{
                chat: true,
                tools: %{enabled: true, streaming: false},
                json: %{native: true}
              },
              aliases: ["model-a1-alias"]
            },
            %{
              id: "model-a2",
              provider: :provider_a,
              capabilities: %{chat: true, embeddings: true}
            },
            %{
              id: "model-b1",
              provider: :provider_b,
              capabilities: %{
                chat: true,
                tools: %{enabled: true, streaming: true},
                json: %{native: true}
              }
            }
          ],
          exclude: %{}
        },
        overrides_module: nil,
        allow: :all,
        deny: %{},
        prefer: [:provider_a, :provider_b]
      }

      {:ok, snapshot} = LlmModels.load(config: config)

      assert is_map(snapshot)

      providers = LlmModels.list_providers()
      assert :provider_a in providers
      assert :provider_b in providers

      {:ok, provider_a} = LlmModels.get_provider(:provider_a)
      assert provider_a.name == "Provider A"

      models_a = LlmModels.list_models(:provider_a)
      assert length(models_a) == 2

      {:ok, model} = LlmModels.get_model(:provider_a, "model-a1")
      assert model.id == "model-a1"

      {:ok, model_via_alias} = LlmModels.get_model(:provider_a, "model-a1-alias")
      assert model_via_alias.id == "model-a1"

      caps = LlmModels.capabilities({:provider_a, "model-a1"})
      assert caps.chat == true
      assert caps.tools.enabled == true

      assert LlmModels.allowed?({:provider_a, "model-a1"}) == true

      {:ok, {provider, model_id}} =
        LlmModels.select(
          require: [chat: true, tools: true],
          prefer: [:provider_a, :provider_b]
        )

      assert provider == :provider_a
      assert model_id == "model-a1"

      {:ok, {:provider_a, "model-a1"}} = LlmModels.parse_spec("provider_a:model-a1")

      {:ok, {provider, canonical_id, resolved_model}} =
        LlmModels.resolve("provider_a:model-a1")

      assert provider == :provider_a
      assert canonical_id == "model-a1"
      assert resolved_model.id == "model-a1"

      assert :ok = LlmModels.reload()
      assert LlmModels.epoch() > 0
    end

    test "filters work with deny patterns" do
      config = %{
        overrides: %{
          providers: [%{id: :test_provider}],
          models: [
            %{id: "allowed-model", provider: :test_provider, capabilities: %{chat: true}},
            %{id: "denied-model", provider: :test_provider, capabilities: %{chat: true}}
          ],
          exclude: %{}
        },
        overrides_module: nil,
        allow: %{test_provider: ["*"]},
        deny: %{test_provider: ["denied-model"], openai: ["*"], anthropic: ["*"]},
        prefer: []
      }

      {:ok, _} = LlmModels.load(config: config)

      assert LlmModels.allowed?({:test_provider, "allowed-model"}) == true
      assert LlmModels.allowed?({:test_provider, "denied-model"}) == false

      {:ok, {provider, model_id}} = LlmModels.select(require: [chat: true])
      assert provider == :test_provider
      assert model_id == "allowed-model"
    end
  end

  describe "error cases" do
    test "handles missing capabilities gracefully" do
      config = %{
        overrides: %{
          providers: [%{id: :test_provider}],
          models: [
            %{id: "minimal-model", provider: :test_provider}
          ],
          exclude: %{}
        },
        overrides_module: nil,
        allow: :all,
        deny: %{},
        prefer: []
      }

      {:ok, _} = LlmModels.load(config: config)

      models = LlmModels.list_models(:test_provider, require: [chat: true])
      assert models == []
    end

    test "handles invalid spec format" do
      {:ok, _} = LlmModels.load()

      assert {:error, :invalid_format} = LlmModels.parse_spec("invalid")
      assert {:error, :invalid_format} = LlmModels.resolve(:invalid)
    end

    test "handles snapshot not loaded" do
      Store.clear!()

      assert LlmModels.list_providers() == []
      assert LlmModels.get_provider(:openai) == :error
      assert LlmModels.list_models(:openai) == []
      assert LlmModels.get_model(:openai, "gpt-4") == :error
      assert LlmModels.capabilities({:openai, "gpt-4"}) == nil
      assert LlmModels.allowed?({:openai, "gpt-4"}) == false
      assert {:error, :no_match} = LlmModels.select(require: [chat: true])
    end
  end
end
