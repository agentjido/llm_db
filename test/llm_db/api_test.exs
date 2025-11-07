defmodule LLMDb.APITest do
  use ExUnit.Case, async: false

  alias LLMDb.Store

  setup do
    Store.clear!()
    Application.delete_env(:llm_db, :allow)
    Application.delete_env(:llm_db, :deny)
    Application.delete_env(:llm_db, :prefer)
    Application.delete_env(:llm_db, :filter)

    # Load minimal test data
    providers = [
      %{id: :openai, name: "OpenAI"},
      %{id: :anthropic, name: "Anthropic"}
    ]

    # Models need to be normalized (provider as atom) before being passed to Index.build
    models = [
      %{
        id: "gpt-4o",
        provider: :openai,
        capabilities: %{chat: true, tools: %{enabled: true}, json: %{native: true}}
      },
      %{
        id: "gpt-4o-mini",
        provider: :openai,
        capabilities: %{chat: true, tools: %{enabled: true}, json: %{native: true}}
      },
      %{
        id: "claude-3-5-sonnet-20241022",
        provider: :anthropic,
        capabilities: %{chat: true, tools: %{enabled: true}, json: %{native: false}}
      }
    ]

    app_config = LLMDb.Config.get()
    provider_ids = Enum.map(providers, & &1.id)

    {filters, _unknown_info} =
      LLMDb.Config.compile_filters(app_config.allow, app_config.deny, provider_ids)

    filtered_models = LLMDb.Engine.apply_filters(models, filters)
    indexes = LLMDb.Index.build(providers, filtered_models)

    snapshot = %{
      providers_by_id: indexes.providers_by_id,
      models_by_key: indexes.models_by_key,
      aliases_by_key: indexes.aliases_by_key,
      providers: providers,
      models: indexes.models_by_provider,
      base_models: models,
      filters: filters,
      prefer: app_config.prefer,
      meta: %{
        epoch: nil,
        generated_at: DateTime.utc_now() |> DateTime.to_iso8601()
      }
    }

    Store.put!(snapshot, [])
    :ok
  end

  describe "providers/0" do
    test "returns all providers as list" do
      providers = LLMDb.providers()

      assert is_list(providers)
      assert length(providers) == 2
      assert Enum.all?(providers, &match?(%LLMDb.Provider{}, &1))
      assert Enum.map(providers, & &1.id) |> Enum.sort() == [:anthropic, :openai]
    end
  end

  describe "models/0" do
    test "returns all models as list" do
      models = LLMDb.models()

      assert is_list(models)
      assert length(models) == 3
      assert Enum.all?(models, &match?(%LLMDb.Model{}, &1))
    end
  end

  describe "models/1" do
    test "returns models for specific provider" do
      openai_models = LLMDb.models(:openai)

      assert is_list(openai_models)
      assert length(openai_models) == 2
      assert Enum.all?(openai_models, &(&1.provider == :openai))

      anthropic_models = LLMDb.models(:anthropic)
      assert length(anthropic_models) == 1
      assert hd(anthropic_models).provider == :anthropic
    end

    test "returns empty list for unknown provider" do
      assert LLMDb.models(:unknown) == []
    end
  end

  describe "candidates/1" do
    test "returns all matching models in preference order" do
      candidates = LLMDb.candidates(require: [chat: true])

      assert is_list(candidates)
      assert length(candidates) >= 3
      assert Enum.all?(candidates, &match?({_provider, _model_id}, &1))
    end

    test "filters by required capabilities" do
      candidates = LLMDb.candidates(require: [chat: true, json_native: true])

      assert is_list(candidates)
      # Only OpenAI models have json.native: true in our test data
      assert Enum.all?(candidates, fn {provider, _id} -> provider == :openai end)
    end

    test "respects prefer option" do
      candidates = LLMDb.candidates(require: [chat: true], prefer: [:anthropic])

      # First result should be from anthropic if available
      assert match?({:anthropic, _}, hd(candidates))
    end

    test "respects scope option" do
      candidates = LLMDb.candidates(require: [chat: true], scope: :openai)

      assert length(candidates) == 2
      assert Enum.all?(candidates, fn {provider, _id} -> provider == :openai end)
    end

    test "respects forbid option" do
      candidates = LLMDb.candidates(require: [chat: true], forbid: [json_native: true])

      # Should exclude OpenAI models which have json_native: true
      refute Enum.any?(candidates, fn {provider, _id} -> provider == :openai end)
    end

    test "returns empty list when no matches" do
      candidates = LLMDb.candidates(require: [embeddings: true])

      assert candidates == []
    end
  end

  describe "parse/1" do
    test "parses valid spec string" do
      assert {:ok, {:openai, "gpt-4o"}} = LLMDb.parse("openai:gpt-4o")

      assert {:ok, {:anthropic, "claude-3-5-sonnet-20241022"}} =
               LLMDb.parse("anthropic:claude-3-5-sonnet-20241022")
    end

    test "accepts tuple format" do
      assert {:ok, {:openai, "gpt-4o"}} = LLMDb.parse({:openai, "gpt-4o"})
    end

    test "returns error for invalid format" do
      assert {:error, _} = LLMDb.parse("invalid")
      assert {:error, _} = LLMDb.parse("no-colon")
    end
  end

  describe "allowed?/1 with alias resolution" do
    setup do
      # Add a model with an alias to test alias resolution
      # We need to bypass filtering to keep the model in the catalog
      Store.clear!()

      on_exit(fn ->
        Application.delete_env(:llm_db, :filter)
      end)

      providers = [%{id: :openai, name: "OpenAI"}]

      models = [
        %{
          id: "gpt-4o",
          provider: :openai,
          aliases: ["gpt-4-omni"],
          capabilities: %{chat: true}
        }
      ]

      # Set deny filter to deny the canonical ID
      Application.put_env(:llm_db, :filter, %{
        allow: :all,
        deny: %{openai: ["gpt-4o"]}
      })

      app_config = LLMDb.Config.get()
      provider_ids = Enum.map(providers, & &1.id)

      {filters, _unknown_info} =
        LLMDb.Config.compile_filters(app_config.allow, app_config.deny, provider_ids)

      # Don't filter - we want the model in the catalog to test allowed?/1 filtering
      indexes = LLMDb.Index.build(providers, models)

      snapshot = %{
        providers_by_id: indexes.providers_by_id,
        models_by_key: indexes.models_by_key,
        aliases_by_key: indexes.aliases_by_key,
        providers: providers,
        models: indexes.models_by_provider,
        base_models: models,
        filters: filters,
        prefer: app_config.prefer,
        meta: %{
          epoch: nil,
          generated_at: DateTime.utc_now() |> DateTime.to_iso8601()
        }
      }

      Store.put!(snapshot, [])
      :ok
    end

    test "resolves aliases when checking allowed" do
      # The alias should be denied because it resolves to the canonical ID
      refute LLMDb.allowed?({:openai, "gpt-4-omni"})
      # The canonical ID is denied
      refute LLMDb.allowed?({:openai, "gpt-4o"})
    end
  end
end
