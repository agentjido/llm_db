defmodule LLMDB.ProviderRuntimeDataTest do
  use ExUnit.Case, async: true

  alias LLMDB.Provider
  alias LLMDB.Sources.Local

  @openai_compatible [
    :openai,
    :openrouter,
    :groq,
    :xai,
    :zenmux,
    :mistral,
    :togetherai,
    :github_models,
    :perplexity,
    :cloudflare_workers_ai,
    :fireworks_ai,
    :minimax,
    :friendli,
    :ollama_cloud,
    :deepseek,
    :alibaba,
    :venice,
    :cerebras,
    :zai
  ]

  test "provider TOML owns every executable provider runtime policy" do
    {:ok, providers} = Local.load(%{dir: "priv/llm_db/local"})

    Enum.each(@openai_compatible, fn id ->
      runtime = provider_runtime(providers, id)

      assert is_binary(runtime.base_url), "missing runtime base URL for #{id}"
      assert runtime.auth.type == "bearer"
      assert runtime.execution.text == "openai_chat_compatible"
      assert runtime.execution.object == "openai_chat_compatible"
    end)

    assert provider_runtime(providers, :anthropic).execution.text == "anthropic_messages"
    assert provider_runtime(providers, :google).execution.text == "google_generate_content"
    assert provider_runtime(providers, :cohere).execution.text == "cohere_chat"

    elevenlabs = provider_runtime(providers, :elevenlabs)
    assert elevenlabs.execution.speech == "elevenlabs_speech"
    assert elevenlabs.execution.transcription == "elevenlabs_transcription"
  end

  defp provider_runtime(providers, id) do
    providers
    |> Map.fetch!(Atom.to_string(id))
    |> Map.delete(:models)
    |> Map.put(:id, id)
    |> Provider.new!()
    |> Map.fetch!(:runtime)
  end
end
