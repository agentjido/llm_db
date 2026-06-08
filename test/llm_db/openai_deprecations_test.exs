defmodule LLMDB.OpenAIDeprecationsTest do
  use ExUnit.Case, async: false

  alias LLMDB.{Model, Normalize, Provider, Store}
  alias LLMDB.Sources.Local

  @local_dir "priv/llm_db/local"

  @expected_lifecycle %{
    "babbage-002" => %{
      deprecated_at: "2025-09-26",
      retires_at: "2026-09-28",
      replacement: "gpt-5.4-mini"
    },
    "chatgpt-image-latest" => %{
      deprecated_at: "2026-06-02",
      retires_at: "2026-12-01",
      replacement: "gpt-image-2"
    },
    "computer-use-preview" => %{
      deprecated_at: "2026-04-22",
      retires_at: "2026-07-23",
      replacement: "gpt-5.4-mini"
    },
    "computer-use-preview-2025-03-11" => %{
      deprecated_at: "2026-04-22",
      retires_at: "2026-07-23",
      replacement: "gpt-5.4-mini"
    },
    "dall-e-2" => %{
      deprecated_at: "2025-11-14",
      retires_at: "2026-05-12",
      replacement: "gpt-image-2"
    },
    "dall-e-3" => %{
      deprecated_at: "2025-11-14",
      retires_at: "2026-05-12",
      replacement: "gpt-image-2"
    },
    "davinci-002" => %{
      deprecated_at: "2025-09-26",
      retires_at: "2026-09-28",
      replacement: "gpt-5.4-mini"
    },
    "ft-babbage-002" => %{
      deprecated_at: "2026-04-22",
      retires_at: "2026-10-23",
      replacement: "gpt-5.4-mini"
    },
    "ft-davinci-002" => %{
      deprecated_at: "2026-04-22",
      retires_at: "2026-10-23",
      replacement: "gpt-5.4-mini"
    },
    "ft-gpt-3.5-turbo" => %{
      deprecated_at: "2026-04-22",
      retires_at: "2026-10-23",
      replacement: "gpt-5.4-mini"
    },
    "ft-gpt-4" => %{deprecated_at: "2026-04-22", retires_at: "2026-10-23", replacement: "gpt-5.5"},
    "ft-gpt-4.1-nano-2025-04-14" => %{
      deprecated_at: "2026-04-22",
      retires_at: "2026-10-23",
      replacement: "gpt-5.4-nano"
    },
    "ft-o4-mini-2025-04-16" => %{
      deprecated_at: "2026-04-22",
      retires_at: "2026-10-23",
      replacement: "gpt-5.4-mini"
    },
    "gpt-3.5-turbo" => %{
      deprecated_at: "2026-04-22",
      retires_at: "2026-10-23",
      replacement: "gpt-5.4-mini"
    },
    "gpt-3.5-turbo-0125" => %{
      deprecated_at: "2026-04-22",
      retires_at: "2026-10-23",
      replacement: "gpt-5.4-mini"
    },
    "gpt-3.5-turbo-1106" => %{
      deprecated_at: "2025-09-26",
      retires_at: "2026-09-28",
      replacement: "gpt-5.4-mini"
    },
    "gpt-3.5-turbo-instruct" => %{
      deprecated_at: "2025-09-26",
      retires_at: "2026-09-28",
      replacement: "gpt-5.4-mini"
    },
    "gpt-4" => %{deprecated_at: "2026-04-22", retires_at: "2026-10-23", replacement: "gpt-5.5"},
    "gpt-4-0125-preview" => %{
      deprecated_at: "2025-09-26",
      retires_at: "2026-03-26",
      replacement: "gpt-5"
    },
    "gpt-4-0613" => %{
      deprecated_at: "2026-04-22",
      retires_at: "2026-10-23",
      replacement: "gpt-5.5"
    },
    "gpt-4-1106-preview" => %{
      deprecated_at: "2026-04-22",
      retires_at: "2026-10-23",
      replacement: "gpt-5.5"
    },
    "gpt-4-turbo" => %{
      deprecated_at: "2026-04-22",
      retires_at: "2026-10-23",
      replacement: "gpt-5.5"
    },
    "gpt-4-turbo-2024-04-09" => %{
      deprecated_at: "2026-04-22",
      retires_at: "2026-10-23",
      replacement: "gpt-5.5"
    },
    "gpt-4-turbo-preview" => %{
      deprecated_at: "2025-09-26",
      retires_at: "2026-03-26",
      replacement: "gpt-5"
    },
    "gpt-4.1-nano" => %{
      deprecated_at: "2026-04-22",
      retires_at: "2026-10-23",
      replacement: "gpt-5.4-nano"
    },
    "gpt-4.1-nano-2025-04-14" => %{
      deprecated_at: "2026-04-22",
      retires_at: "2026-10-23",
      replacement: "gpt-5.4-nano"
    },
    "gpt-4o-2024-05-13" => %{
      deprecated_at: "2026-04-22",
      retires_at: "2026-10-23",
      replacement: "gpt-5.5"
    },
    "gpt-4o-audio-preview-2024-12-17" => %{
      deprecated_at: "2025-09-15",
      retires_at: "2026-05-07",
      replacement: "gpt-audio-1.5"
    },
    "gpt-4o-mini-audio-preview-2024-12-17" => %{
      deprecated_at: "2025-09-15",
      retires_at: "2026-05-07",
      replacement: "gpt-audio-mini"
    },
    "gpt-4o-mini-realtime-preview-2024-12-17" => %{
      deprecated_at: "2025-09-15",
      retires_at: "2026-05-07",
      replacement: "gpt-realtime-mini"
    },
    "gpt-4o-mini-search-preview-2025-03-11" => %{
      deprecated_at: "2026-04-22",
      retires_at: "2026-07-23",
      replacement: "gpt-5.4-mini"
    },
    "gpt-4o-mini-tts-2025-03-20" => %{
      deprecated_at: "2026-04-22",
      retires_at: "2026-07-23",
      replacement: "gpt-4o-mini-tts-2025-12-15"
    },
    "gpt-4o-search-preview-2025-03-11" => %{
      deprecated_at: "2026-04-22",
      retires_at: "2026-07-23",
      replacement: "gpt-5.4-mini"
    },
    "gpt-5-chat-latest" => %{
      deprecated_at: "2026-04-22",
      retires_at: "2026-07-23",
      replacement: "gpt-5.5"
    },
    "gpt-5-codex" => %{
      deprecated_at: "2026-04-22",
      retires_at: "2026-07-23",
      replacement: "gpt-5.5"
    },
    "gpt-5.1-chat-latest" => %{
      deprecated_at: "2026-04-22",
      retires_at: "2026-07-23",
      replacement: "gpt-5.5"
    },
    "gpt-5.1-codex" => %{
      deprecated_at: "2026-04-22",
      retires_at: "2026-07-23",
      replacement: "gpt-5.5"
    },
    "gpt-5.1-codex-max" => %{
      deprecated_at: "2026-04-22",
      retires_at: "2026-07-23",
      replacement: "gpt-5.5"
    },
    "gpt-5.1-codex-mini" => %{
      deprecated_at: "2026-04-22",
      retires_at: "2026-07-23",
      replacement: "gpt-5.4-mini"
    },
    "gpt-5.2-chat-latest" => %{
      deprecated_at: "2026-05-08",
      retires_at: "2026-08-10",
      replacement: "gpt-5.5"
    },
    "gpt-5.2-codex" => %{
      deprecated_at: "2026-04-22",
      retires_at: "2026-07-23",
      replacement: "gpt-5.5"
    },
    "gpt-5.3-chat-latest" => %{
      deprecated_at: "2026-05-08",
      retires_at: "2026-08-10",
      replacement: "gpt-5.5"
    },
    "gpt-audio-mini-2025-10-06" => %{
      deprecated_at: "2026-04-22",
      retires_at: "2026-07-23",
      replacement: "gpt-audio-1.5"
    },
    "gpt-image-1" => %{
      deprecated_at: "2026-04-22",
      retires_at: "2026-10-23",
      replacement: "gpt-image-2"
    },
    "gpt-image-1-mini" => %{
      deprecated_at: "2026-06-02",
      retires_at: "2026-12-01",
      replacement: "gpt-image-2"
    },
    "gpt-image-1.5" => %{
      deprecated_at: "2026-06-02",
      retires_at: "2026-12-01",
      replacement: "gpt-image-2"
    },
    "gpt-realtime-mini-2025-10-06" => %{
      deprecated_at: "2026-04-22",
      retires_at: "2026-07-23",
      replacement: "gpt-realtime-mini"
    },
    "o1" => %{deprecated_at: "2026-04-22", retires_at: "2026-10-23", replacement: "gpt-5.5"},
    "o1-2024-12-17" => %{
      deprecated_at: "2026-04-22",
      retires_at: "2026-10-23",
      replacement: "gpt-5.5"
    },
    "o1-pro-2025-03-19" => %{
      deprecated_at: "2026-04-22",
      retires_at: "2026-10-23",
      replacement: "gpt-5.5-pro"
    },
    "o3-deep-research-2025-06-26" => %{
      deprecated_at: "2026-04-22",
      retires_at: "2026-07-23",
      replacement: "gpt-5.5-pro"
    },
    "o3-mini" => %{deprecated_at: "2026-04-22", retires_at: "2026-10-23", replacement: "gpt-5.5"},
    "o3-mini-2025-01-31" => %{
      deprecated_at: "2026-04-22",
      retires_at: "2026-10-23",
      replacement: "gpt-5.5"
    },
    "o4-mini" => %{
      deprecated_at: "2026-04-22",
      retires_at: "2026-10-23",
      replacement: "gpt-5.4-mini"
    },
    "o4-mini-2025-04-16" => %{
      deprecated_at: "2026-04-22",
      retires_at: "2026-10-23",
      replacement: "gpt-5.4-mini"
    },
    "o4-mini-deep-research-2025-06-26" => %{
      deprecated_at: "2026-04-22",
      retires_at: "2026-07-23",
      replacement: "gpt-5.5-pro"
    },
    "sora-2" => %{deprecated_at: "2026-03-24", retires_at: "2026-09-24", replacement: nil},
    "sora-2-pro" => %{deprecated_at: "2026-03-24", retires_at: "2026-09-24", replacement: nil}
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

  test "local OpenAI overrides codify documented deprecation batches" do
    models = openai_models()

    Enum.each(@expected_lifecycle, fn {model_id, expected} ->
      model = Map.fetch!(models, model_id)

      assert model.lifecycle.status == "deprecated"
      assert model.lifecycle.deprecated_at == expected.deprecated_at
      assert model.lifecycle.retires_at == expected.retires_at
      assert Map.get(model.lifecycle, :replacement) == expected.replacement
      assert Model.lifecycle_status(model) == "deprecated"
    end)
  end

  test "lifecycle helpers advance representative July and October rows" do
    models = openai_models()

    july_model = Map.fetch!(models, "gpt-5-codex")
    october_model = Map.fetch!(models, "gpt-4")
    past_model = Map.fetch!(models, "gpt-4-turbo-preview")

    assert Model.effective_status(july_model, ~U[2026-04-21 00:00:00Z]) == "deprecated"
    assert Model.effective_status(july_model, ~U[2026-07-24 00:00:00Z]) == "retired"
    assert Model.deprecated?(october_model, ~U[2026-05-01 00:00:00Z])
    assert Model.retired?(october_model, ~U[2026-10-24 00:00:00Z])
    assert Model.effective_status(past_model, ~U[2026-03-27 00:00:00Z]) == "retired"
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
