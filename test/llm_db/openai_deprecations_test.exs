defmodule LLMDB.OpenAIDeprecationsTest do
  use ExUnit.Case, async: false

  alias LLMDB.{Model, Normalize, Provider, Store}
  alias LLMDB.Sources.Local

  @local_dir "priv/llm_db/local"

  @expected_lifecycle %{
    "computer-use-preview" => {"2026-07-23", "gpt-5.4-mini"},
    "computer-use-preview-2025-03-11" => {"2026-07-23", "gpt-5.4-mini"},
    "ft-babbage-002" => {"2026-10-23", "gpt-5-mini"},
    "ft-davinci-002" => {"2026-10-23", "gpt-5-mini"},
    "ft-gpt-3.5-turbo" => {"2026-10-23", "gpt-4.1-mini"},
    "ft-gpt-4" => {"2026-10-23", "gpt-4.1"},
    "ft-gpt-4.1-nano-2025-04-14" => {"2026-10-23", "gpt-5-nano"},
    "ft-o4-mini-2025-04-16" => {"2026-10-23", "gpt-5-mini"},
    "gpt-3.5-turbo" => {"2026-10-23", "gpt-4.1-mini"},
    "gpt-3.5-turbo-0125" => {"2026-10-23", "gpt-4.1-mini"},
    "gpt-4" => {"2026-10-23", "gpt-4.1"},
    "gpt-4-0613" => {"2026-10-23", "gpt-4.1"},
    "gpt-4-1106-preview" => {"2026-10-23", "gpt-4.1"},
    "gpt-4-turbo" => {"2026-10-23", "gpt-4.1"},
    "gpt-4-turbo-2024-04-09" => {"2026-10-23", "gpt-4.1"},
    "gpt-4.1-nano" => {"2026-10-23", "gpt-5-nano"},
    "gpt-4.1-nano-2025-04-14" => {"2026-10-23", "gpt-5-nano"},
    "gpt-4o-2024-05-13" => {"2026-10-23", "gpt-4.1"},
    "gpt-4o-audio-preview-2024-12-17" => {"2026-07-23", "gpt-audio"},
    "gpt-4o-mini-audio-preview-2024-12-17" => {"2026-07-23", "gpt-audio"},
    "gpt-4o-mini-realtime-preview-2024-12-17" => {"2026-07-23", "gpt-realtime-mini"},
    "gpt-4o-mini-search-preview-2025-03-11" => {"2026-07-23", "gpt-4.1-mini"},
    "gpt-4o-mini-tts-2025-03-20" => {"2026-07-23", "gpt-realtime"},
    "gpt-4o-search-preview-2025-03-11" => {"2026-07-23", "gpt-4.1-mini"},
    "gpt-5-chat-latest" => {"2026-07-23", "gpt-5.3-chat-latest"},
    "gpt-5-codex" => {"2026-07-23", "gpt-5.4"},
    "gpt-5.1-chat-latest" => {"2026-07-23", "gpt-5.3-chat-latest"},
    "gpt-5.1-codex" => {"2026-07-23", "gpt-5"},
    "gpt-5.1-codex-max" => {"2026-07-23", "gpt-5.4"},
    "gpt-5.1-codex-mini" => {"2026-07-23", "gpt-5.4-mini"},
    "gpt-5.2-codex" => {"2026-07-23", "gpt-5.4"},
    "gpt-audio-mini-2025-10-06" => {"2026-07-23", "gpt-audio"},
    "gpt-image-1" => {"2026-10-23", "gpt-image-1.5"},
    "gpt-realtime-mini-2025-10-06" => {"2026-07-23", "gpt-realtime-mini"},
    "o1" => {"2026-10-23", "o3"},
    "o1-2024-12-17" => {"2026-10-23", "o3"},
    "o1-pro-2025-03-19" => {"2026-10-23", "gpt-5.4-pro"},
    "o3-deep-research-2025-06-26" => {"2026-07-23", "gpt-5.4-pro"},
    "o3-mini" => {"2026-10-23", "o3"},
    "o3-mini-2025-01-31" => {"2026-10-23", "o3"},
    "o4-mini" => {"2026-10-23", "gpt-5-mini"},
    "o4-mini-2025-04-16" => {"2026-10-23", "gpt-5-mini"},
    "o4-mini-deep-research-2025-06-26" => {"2026-07-23", "gpt-5.4-pro"}
  }

  @alias_expectations %{
    "gpt-3.5-turbo-completions" => "gpt-3.5-turbo",
    "gpt-4-completions" => "gpt-4",
    "gpt-4-0613-completions" => "gpt-4-0613",
    "gpt-4-turbo-completions" => "gpt-4-turbo",
    "o1-pro" => "o1-pro-2025-03-19",
    "o3-deep-research" => "o3-deep-research-2025-06-26",
    "o4-mini-deep-research" => "o4-mini-deep-research-2025-06-26"
  }

  setup do
    Store.clear!()

    on_exit(fn ->
      Store.clear!()
    end)

    :ok
  end

  test "local OpenAI overrides codify the 2026-04-22 deprecation batch" do
    models = openai_models()

    Enum.each(@expected_lifecycle, fn {model_id, {retires_at, replacement}} ->
      model = Map.fetch!(models, model_id)

      assert model.lifecycle.status == "deprecated"
      assert model.lifecycle.deprecated_at == "2026-04-22"
      assert model.lifecycle.retires_at == retires_at
      assert model.lifecycle.replacement == replacement
      assert Model.lifecycle_status(model) == "deprecated"
    end)
  end

  test "lifecycle helpers advance representative July and October rows" do
    models = openai_models()

    july_model = Map.fetch!(models, "gpt-5-codex")
    october_model = Map.fetch!(models, "gpt-4")

    assert Model.effective_status(july_model, ~U[2026-04-21 00:00:00Z]) == "deprecated"
    assert Model.effective_status(july_model, ~U[2026-07-24 00:00:00Z]) == "retired"
    assert Model.deprecated?(october_model, ~U[2026-05-01 00:00:00Z])
    assert Model.retired?(october_model, ~U[2026-10-24 00:00:00Z])
  end

  test "deprecated OpenAI aliases resolve to queryable canonical records" do
    load_openai_models_into_store!()

    Enum.each(@alias_expectations, fn {alias_id, canonical_id} ->
      assert {:ok, model} = LLMDB.model(:openai, alias_id)
      assert model.id == canonical_id
      assert model.lifecycle.status == "deprecated"
    end)
  end

  defp openai_models do
    {_provider, models} = openai_provider_and_models()
    models
  end

  defp openai_provider_and_models do
    {:ok, data} = Local.load(%{dir: @local_dir})
    openai = Map.fetch!(data, "openai")
    provider = openai |> Map.delete(:models) |> Map.put(:id, :openai) |> Provider.new!()

    models =
      openai.models
      |> Normalize.normalize_models()
      |> Enum.map(&Model.new!/1)
      |> Map.new(&{&1.id, &1})

    {provider, models}
  end

  defp load_openai_models_into_store! do
    {provider, models_by_id} = openai_provider_and_models()
    models = Map.values(models_by_id)

    snapshot = %{
      providers_by_id: %{openai: provider},
      models_by_key: Map.new(models, &{{&1.provider, &1.id}, &1}),
      aliases_by_key: build_aliases_index(models),
      providers: [provider],
      models: %{openai: models},
      base_models: models,
      filters: %{allow: :all, deny: %{}},
      prefer: [],
      meta: %{epoch: nil, generated_at: DateTime.utc_now() |> DateTime.to_iso8601()}
    }

    Store.put!(snapshot, [])
  end

  defp build_aliases_index(models) do
    models
    |> Enum.flat_map(fn model ->
      Enum.map(model.aliases, fn alias_name ->
        {{model.provider, alias_name}, model.id}
      end)
    end)
    |> Map.new()
  end
end
