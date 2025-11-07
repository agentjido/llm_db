defmodule LLMDb.EngineOverrideTest do
  use ExUnit.Case, async: false

  alias LLMDb.{Config, Engine, Index, Store}

  setup do
    Store.clear!()
    Application.delete_env(:llm_db, :allow)
    Application.delete_env(:llm_db, :deny)
    Application.delete_env(:llm_db, :prefer)
    :ok
  end

  # Helper to run Engine and build indexes for Store
  defp run_and_store(sources, opts \\ []) do
    config = Config.get()
    {:ok, snapshot} = Engine.run([sources: sources] ++ opts)

    # Extract providers and models from v2 nested structure
    providers = Map.values(snapshot.providers)

    all_models =
      providers
      |> Enum.flat_map(fn p -> Map.values(p.models) end)

    # Build indexes at load time using filters from opts or config
    provider_ids = Enum.map(providers, & &1.id)

    {filters, _unknown_info} =
      case Keyword.get(opts, :filters) do
        nil ->
          Config.compile_filters(config.allow, config.deny, provider_ids)

        filter_opts ->
          Config.compile_filters(
            Map.get(filter_opts, :allow, config.allow),
            Map.get(filter_opts, :deny, config.deny),
            provider_ids
          )
      end

    filtered_models = Engine.apply_filters(all_models, filters)
    indexes = Index.build(providers, filtered_models)

    # Build runtime snapshot with indexes
    runtime_snapshot = %{
      providers_by_id: indexes.providers_by_id,
      models_by_key: indexes.models_by_key,
      aliases_by_key: indexes.aliases_by_key,
      providers: providers,
      models: indexes.models_by_provider,
      base_models: all_models,
      filters: filters,
      prefer: config.prefer,
      meta: %{
        epoch: nil,
        generated_at: snapshot.generated_at
      }
    }

    Store.put!(runtime_snapshot, [])
    {:ok, runtime_snapshot}
  end

  describe "provider metadata override" do
    test "overrides existing provider's base_url, env, name, doc" do
      base = %{
        providers: [
          %{
            id: :openai,
            name: "OpenAI",
            base_url: "https://api.openai.com/v1",
            env: ["OPENAI_API_KEY"]
          }
        ],
        models: [
          %{id: "gpt-4", provider: :openai, capabilities: %{chat: true}}
        ]
      }

      override = %{
        providers: [
          %{
            id: :openai,
            name: "OpenAI Custom",
            base_url: "https://custom.openai.proxy/v1",
            env: ["CUSTOM_OPENAI_KEY"],
            doc: "Custom OpenAI configuration"
          }
        ],
        models: []
      }

      sources = [
        {LLMDb.Sources.Config, %{overrides: base}},
        {LLMDb.Sources.Config, %{overrides: override}}
      ]

      assert {:ok, _snapshot} = run_and_store(sources)

      {:ok, provider} = LLMDb.provider(:openai)
      assert provider.name == "OpenAI Custom"
      assert provider.base_url == "https://custom.openai.proxy/v1"
      # Arrays are replaced, not unioned (later source wins)
      assert provider.env == ["CUSTOM_OPENAI_KEY"]
      assert provider.doc == "Custom OpenAI configuration"
    end

    test "array fields should be replaced not unioned (req_llm requirement)" do
      base = %{
        providers: [
          %{
            id: :anthropic,
            name: "Anthropic",
            env: ["ANTHROPIC_API_KEY", "ANTHROPIC_VERSION"]
          }
        ],
        models: [
          %{id: "claude", provider: :anthropic, capabilities: %{chat: true}}
        ]
      }

      override = %{
        providers: [
          %{
            id: :anthropic,
            env: ["CUSTOM_KEY"]
          }
        ],
        models: []
      }

      sources = [
        {LLMDb.Sources.Config, %{overrides: base}},
        {LLMDb.Sources.Config, %{overrides: override}}
      ]

      assert {:ok, _snapshot} = run_and_store(sources)

      {:ok, provider} = LLMDb.provider(:anthropic)
      # Expected for req_llm: arrays should be replaced
      assert provider.env == ["CUSTOM_KEY"]
      refute "ANTHROPIC_API_KEY" in provider.env
    end

    test "adds new provider from scratch" do
      base = %{
        providers: [%{id: :openai, name: "OpenAI"}],
        models: [%{id: "gpt-4", provider: :openai, capabilities: %{chat: true}}]
      }

      override = %{
        providers: [
          %{
            id: :custom_provider,
            name: "Custom Provider",
            base_url: "https://custom.api/v1",
            env: ["CUSTOM_API_KEY"]
          }
        ],
        models: [
          %{id: "custom-model", provider: :custom_provider, capabilities: %{chat: true}}
        ]
      }

      sources = [
        {LLMDb.Sources.Config, %{overrides: base}},
        {LLMDb.Sources.Config, %{overrides: override}}
      ]

      assert {:ok, _snapshot} = run_and_store(sources)

      {:ok, provider} = LLMDb.provider(:custom_provider)
      assert provider.name == "Custom Provider"
      assert provider.base_url == "https://custom.api/v1"
    end
  end

  describe "model field modification" do
    test "adds new model to existing provider" do
      base = %{
        providers: [%{id: :openai, name: "OpenAI"}],
        models: [
          %{id: "gpt-4", provider: :openai, name: "GPT-4", capabilities: %{chat: true}}
        ]
      }

      override = %{
        providers: [],
        models: [
          %{
            id: "gpt-4-custom",
            provider: :openai,
            name: "GPT-4 Custom",
            capabilities: %{chat: true}
          }
        ]
      }

      sources = [
        {LLMDb.Sources.Config, %{overrides: base}},
        {LLMDb.Sources.Config, %{overrides: override}}
      ]

      assert {:ok, _snapshot} = run_and_store(sources)

      assert {:ok, _} = LLMDb.model(:openai, "gpt-4")
      assert {:ok, _} = LLMDb.model(:openai, "gpt-4-custom")
    end

    test "modifies capability fields (reasoning, tools)" do
      base = %{
        providers: [%{id: :openai, name: "OpenAI"}],
        models: [
          %{
            id: "gpt-4",
            provider: :openai,
            name: "GPT-4",
            capabilities: %{
              chat: true,
              reasoning: %{enabled: false},
              tools: %{enabled: true, strict: true}
            }
          }
        ]
      }

      override = %{
        providers: [],
        models: [
          %{
            id: "gpt-4",
            provider: :openai,
            capabilities: %{
              reasoning: %{enabled: true},
              tools: %{strict: false}
            }
          }
        ]
      }

      sources = [
        {LLMDb.Sources.Config, %{overrides: base}},
        {LLMDb.Sources.Config, %{overrides: override}}
      ]

      assert {:ok, _snapshot} = run_and_store(sources)

      {:ok, model} = LLMDb.model(:openai, "gpt-4")
      assert model.capabilities.reasoning.enabled == true
      assert model.capabilities.tools.strict == false
      assert model.capabilities.tools.enabled == true
    end

    test "deep merges nested maps - cost (override input, preserve output)" do
      base = %{
        providers: [%{id: :openai, name: "OpenAI"}],
        models: [
          %{
            id: "gpt-4",
            provider: :openai,
            name: "GPT-4",
            capabilities: %{chat: true},
            cost: %{
              input: 30.0,
              output: 60.0
            }
          }
        ]
      }

      override = %{
        providers: [],
        models: [
          %{
            id: "gpt-4",
            provider: :openai,
            cost: %{
              input: 25.0
            }
          }
        ]
      }

      sources = [
        {LLMDb.Sources.Config, %{overrides: base}},
        {LLMDb.Sources.Config, %{overrides: override}}
      ]

      assert {:ok, _snapshot} = run_and_store(sources)

      {:ok, model} = LLMDb.model(:openai, "gpt-4")
      assert model.cost.input == 25.0
      assert model.cost.output == 60.0
    end

    test "deep merges limits (override context, preserve output)" do
      base = %{
        providers: [%{id: :anthropic, name: "Anthropic"}],
        models: [
          %{
            id: "claude-3-opus",
            provider: :anthropic,
            name: "Claude 3 Opus",
            capabilities: %{chat: true},
            limits: %{
              context: 200_000,
              output: 4096
            }
          }
        ]
      }

      override = %{
        providers: [],
        models: [
          %{
            id: "claude-3-opus",
            provider: :anthropic,
            limits: %{
              context: 180_000
            }
          }
        ]
      }

      sources = [
        {LLMDb.Sources.Config, %{overrides: base}},
        {LLMDb.Sources.Config, %{overrides: override}}
      ]

      assert {:ok, _snapshot} = run_and_store(sources)

      {:ok, model} = LLMDb.model(:anthropic, "claude-3-opus")
      assert model.limits.context == 180_000
      assert model.limits.output == 4096
    end

    test "deep merges modalities (unions input, preserves output)" do
      base = %{
        providers: [%{id: :openai, name: "OpenAI"}],
        models: [
          %{
            id: "gpt-4",
            provider: :openai,
            name: "GPT-4",
            capabilities: %{chat: true},
            modalities: %{
              input: [:text, :image],
              output: [:text]
            }
          }
        ]
      }

      override = %{
        providers: [],
        models: [
          %{
            id: "gpt-4",
            provider: :openai,
            modalities: %{
              input: [:text]
            }
          }
        ]
      }

      sources = [
        {LLMDb.Sources.Config, %{overrides: base}},
        {LLMDb.Sources.Config, %{overrides: override}}
      ]

      assert {:ok, _snapshot} = run_and_store(sources)

      {:ok, model} = LLMDb.model(:openai, "gpt-4")
      # Input should union since it's an accumulative field
      assert model.modalities.input == [:text, :image]
      # Output should be preserved from base
      assert model.modalities.output == [:text]
    end
  end

  describe "unknown field pass-through" do
    test "adds custom fields to provider (doc, custom_field)" do
      base = %{
        providers: [%{id: :openai, name: "OpenAI"}],
        models: [%{id: "gpt-4", provider: :openai, capabilities: %{chat: true}}]
      }

      override = %{
        providers: [
          %{
            id: :openai,
            doc: "Custom documentation",
            extra: %{custom_field: "custom value"}
          }
        ],
        models: []
      }

      sources = [
        {LLMDb.Sources.Config, %{overrides: base}},
        {LLMDb.Sources.Config, %{overrides: override}}
      ]

      assert {:ok, _snapshot} = run_and_store(sources)

      {:ok, provider} = LLMDb.provider(:openai)
      assert provider.doc == "Custom documentation"
      assert provider.extra.custom_field == "custom value"
    end

    test "adds custom fields to model (extra map)" do
      base = %{
        providers: [%{id: :openai, name: "OpenAI"}],
        models: [
          %{id: "gpt-4", provider: :openai, name: "GPT-4", capabilities: %{chat: true}}
        ]
      }

      override = %{
        providers: [],
        models: [
          %{
            id: "gpt-4",
            provider: :openai,
            extra: %{
              supports_strict_tools: true,
              api: "chat",
              type: "llm"
            }
          }
        ]
      }

      sources = [
        {LLMDb.Sources.Config, %{overrides: base}},
        {LLMDb.Sources.Config, %{overrides: override}}
      ]

      assert {:ok, _snapshot} = run_and_store(sources)

      {:ok, model} = LLMDb.model(:openai, "gpt-4")
      assert model.extra.supports_strict_tools == true
      assert model.extra.api == "chat"
      assert model.extra.type == "llm"
    end

    test "unknown fields survive merge in extra" do
      base = %{
        providers: [
          %{
            id: :openai,
            name: "OpenAI",
            extra: %{custom_base: "base value"}
          }
        ],
        models: [
          %{
            id: "gpt-4",
            provider: :openai,
            name: "GPT-4",
            capabilities: %{chat: true},
            extra: %{custom_model_base: "model base value"}
          }
        ]
      }

      override = %{
        providers: [
          %{
            id: :openai,
            extra: %{custom_override: "override value"}
          }
        ],
        models: [
          %{
            id: "gpt-4",
            provider: :openai,
            extra: %{custom_model_override: "model override value"}
          }
        ]
      }

      sources = [
        {LLMDb.Sources.Config, %{overrides: base}},
        {LLMDb.Sources.Config, %{overrides: override}}
      ]

      assert {:ok, _snapshot} = run_and_store(sources)

      {:ok, provider} = LLMDb.provider(:openai)
      assert provider.extra.custom_base == "base value"
      assert provider.extra.custom_override == "override value"

      {:ok, model} = LLMDb.model(:openai, "gpt-4")
      assert model.extra.custom_model_base == "model base value"
      assert model.extra.custom_model_override == "model override value"
    end
  end

  describe "model exclusion via filter/deny" do
    test "excludes models via deny patterns" do
      base = %{
        providers: [%{id: :openai, name: "OpenAI"}],
        models: [
          %{id: "gpt-4", provider: :openai, name: "GPT-4", capabilities: %{chat: true}},
          %{
            id: "gpt-3.5-turbo",
            provider: :openai,
            name: "GPT-3.5 Turbo",
            capabilities: %{chat: true}
          },
          %{
            id: "gpt-4-vision",
            provider: :openai,
            name: "GPT-4 Vision",
            capabilities: %{chat: true}
          }
        ]
      }

      sources = [{LLMDb.Sources.Config, %{overrides: base}}]
      filters = %{deny: %{openai: ["gpt-3.5-turbo", "gpt-4-vision"]}}

      assert {:ok, _snapshot} = run_and_store(sources, filters: filters)

      assert {:ok, _} = LLMDb.model(:openai, "gpt-4")
      assert {:error, :not_found} = LLMDb.model(:openai, "gpt-3.5-turbo")
      assert {:error, :not_found} = LLMDb.model(:openai, "gpt-4-vision")
    end

    test "exact ID matching for special characters (colon, slash, @, dots)" do
      base = %{
        providers: [%{id: :custom, name: "Custom"}],
        models: [
          %{
            id: "model:with:colons",
            provider: :custom,
            name: "Model with colons",
            capabilities: %{chat: true}
          },
          %{
            id: "model/with/slashes",
            provider: :custom,
            name: "Model with slashes",
            capabilities: %{chat: true}
          },
          %{
            id: "model@version",
            provider: :custom,
            name: "Model with @",
            capabilities: %{chat: true}
          },
          %{
            id: "model.v1.2.3",
            provider: :custom,
            name: "Model with dots",
            capabilities: %{chat: true}
          }
        ]
      }

      sources = [{LLMDb.Sources.Config, %{overrides: base}}]

      filters = %{
        deny: %{
          custom: [
            "model:with:colons",
            "model/with/slashes",
            "model@version"
          ]
        }
      }

      assert {:ok, _snapshot} = run_and_store(sources, filters: filters)

      assert {:error, :not_found} = LLMDb.model(:custom, "model:with:colons")
      assert {:error, :not_found} = LLMDb.model(:custom, "model/with/slashes")
      assert {:error, :not_found} = LLMDb.model(:custom, "model@version")
      assert {:ok, _} = LLMDb.model(:custom, "model.v1.2.3")
    end

    test "wildcard deny patterns" do
      base = %{
        providers: [%{id: :openai, name: "OpenAI"}],
        models: [
          %{id: "gpt-4", provider: :openai, name: "GPT-4", capabilities: %{chat: true}},
          %{
            id: "gpt-3.5-turbo",
            provider: :openai,
            name: "GPT-3.5 Turbo",
            capabilities: %{chat: true}
          },
          %{id: "davinci", provider: :openai, name: "Davinci", capabilities: %{chat: true}}
        ]
      }

      sources = [{LLMDb.Sources.Config, %{overrides: base}}]
      filters = %{deny: %{openai: ["gpt-*"]}}

      assert {:ok, _snapshot} = run_and_store(sources, filters: filters)

      assert {:error, :not_found} = LLMDb.model(:openai, "gpt-4")
      assert {:error, :not_found} = LLMDb.model(:openai, "gpt-3.5-turbo")
      assert {:ok, _} = LLMDb.model(:openai, "davinci")
    end
  end

  describe "multi-source precedence" do
    test "last source wins for conflicting fields" do
      source1 = %{
        providers: [
          %{
            id: :openai,
            name: "OpenAI Source 1",
            base_url: "https://source1.api/v1"
          }
        ],
        models: [
          %{
            id: "gpt-4",
            provider: :openai,
            name: "GPT-4 Source 1",
            capabilities: %{chat: true},
            cost: %{input: 10.0}
          }
        ]
      }

      source2 = %{
        providers: [
          %{
            id: :openai,
            name: "OpenAI Source 2",
            base_url: "https://source2.api/v1"
          }
        ],
        models: [
          %{
            id: "gpt-4",
            provider: :openai,
            name: "GPT-4 Source 2",
            cost: %{input: 20.0}
          }
        ]
      }

      source3 = %{
        providers: [
          %{
            id: :openai,
            name: "OpenAI Source 3"
          }
        ],
        models: [
          %{
            id: "gpt-4",
            provider: :openai,
            cost: %{input: 30.0}
          }
        ]
      }

      sources = [
        {LLMDb.Sources.Config, %{overrides: source1}},
        {LLMDb.Sources.Config, %{overrides: source2}},
        {LLMDb.Sources.Config, %{overrides: source3}}
      ]

      assert {:ok, _snapshot} = run_and_store(sources)

      {:ok, provider} = LLMDb.provider(:openai)
      assert provider.name == "OpenAI Source 3"
      assert provider.base_url == "https://source2.api/v1"

      {:ok, model} = LLMDb.model(:openai, "gpt-4")
      assert model.name == "GPT-4 Source 2"
      assert model.cost.input == 30.0
    end

    test "array fields replaced by last source, not unioned (except for accumulative fields)" do
      source1 = %{
        providers: [
          %{
            id: :openai,
            name: "OpenAI",
            env: ["KEY1", "KEY2"]
          }
        ],
        models: [
          %{
            id: "gpt-4",
            provider: :openai,
            name: "GPT-4",
            capabilities: %{chat: true},
            modalities: %{
              input: [:text, :image]
            }
          }
        ]
      }

      source2 = %{
        providers: [
          %{
            id: :openai,
            env: ["KEY3"]
          }
        ],
        models: [
          %{
            id: "gpt-4",
            provider: :openai,
            modalities: %{
              input: [:text, :audio]
            }
          }
        ]
      }

      sources = [
        {LLMDb.Sources.Config, %{overrides: source1}},
        {LLMDb.Sources.Config, %{overrides: source2}}
      ]

      assert {:ok, _snapshot} = run_and_store(sources)

      {:ok, provider} = LLMDb.provider(:openai)
      # Provider env is not a union field, should replace
      assert provider.env == ["KEY3"]
      refute "KEY1" in provider.env
      refute "KEY2" in provider.env

      {:ok, model} = LLMDb.model(:openai, "gpt-4")
      # Modalities.input IS a union field, should union
      assert model.modalities.input == [:text, :image, :audio]
      assert :image in model.modalities.input
      assert :audio in model.modalities.input
    end

    test "deep merge preserves fields from earlier sources" do
      source1 = %{
        providers: [%{id: :openai, name: "OpenAI"}],
        models: [
          %{
            id: "gpt-4",
            provider: :openai,
            name: "GPT-4",
            capabilities: %{chat: true},
            cost: %{
              input: 30.0,
              output: 60.0,
              request: 0.01
            },
            limits: %{
              context: 8192,
              output: 4096
            }
          }
        ]
      }

      source2 = %{
        providers: [],
        models: [
          %{
            id: "gpt-4",
            provider: :openai,
            cost: %{
              input: 25.0
            },
            limits: %{
              context: 128_000
            }
          }
        ]
      }

      sources = [
        {LLMDb.Sources.Config, %{overrides: source1}},
        {LLMDb.Sources.Config, %{overrides: source2}}
      ]

      assert {:ok, _snapshot} = run_and_store(sources)

      {:ok, model} = LLMDb.model(:openai, "gpt-4")
      assert model.cost.input == 25.0
      assert model.cost.output == 60.0
      assert model.cost.request == 0.01
      assert model.limits.context == 128_000
      assert model.limits.output == 4096
    end
  end
end
