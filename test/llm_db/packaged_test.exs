defmodule LLMDB.PackagedTest do
  use ExUnit.Case, async: true

  alias LLMDB.Packaged

  @local_cohere_dir Path.expand("../../priv/llm_db/local/cohere", __DIR__)
  @local_cohere_rerank_model_ids "rerank-*.toml"
                                 |> then(&Path.join(@local_cohere_dir, &1))
                                 |> Path.wildcard()
                                 |> Enum.map(fn path ->
                                   path
                                   |> File.read!()
                                   |> Toml.decode!()
                                   |> Map.fetch!("id")
                                 end)
                                 |> Enum.sort()

  describe "snapshot_path/0" do
    test "returns correct snapshot path" do
      path = Packaged.snapshot_path()
      assert String.ends_with?(path, "priv/llm_db/snapshot.json")
      assert is_binary(path)
    end
  end

  describe "snapshot/0" do
    test "loads snapshot from priv directory" do
      snapshot = Packaged.snapshot()

      if snapshot do
        assert is_map(snapshot)
        assert snapshot["version"] == 2
        assert is_binary(snapshot["snapshot_id"])
        assert is_binary(snapshot["generated_at"])
        assert is_map(snapshot["providers"])
      else
        assert snapshot == nil
      end
    end

    test "snapshot providers have expected structure" do
      snapshot = Packaged.snapshot()

      if snapshot && map_size(snapshot["providers"]) > 0 do
        {provider_id, provider} = Enum.at(snapshot["providers"], 0)
        assert is_atom(provider_id) or is_binary(provider_id)
        assert Map.has_key?(provider, "id")
        assert Map.has_key?(provider, "models")
        assert is_map(provider["models"])
      end
    end

    test "snapshot models have expected structure" do
      snapshot = Packaged.snapshot()

      if snapshot && map_size(snapshot["providers"]) > 0 do
        {_provider_id, provider} = Enum.at(snapshot["providers"], 0)

        if map_size(provider["models"]) > 0 do
          {model_id, model} = Enum.at(provider["models"], 0)
          assert is_binary(model_id) or is_atom(model_id)
          assert Map.has_key?(model, "id")
          assert Map.has_key?(model, "provider")
        end
      end
    end

    test "snapshot carries representative provider runtime metadata" do
      snapshot = Packaged.snapshot()

      if snapshot do
        openai = snapshot["providers"]["openai"]
        anthropic = snapshot["providers"]["anthropic"]
        fireworks = snapshot["providers"]["fireworks_ai"]
        minimax = snapshot["providers"]["minimax"]

        assert openai["runtime"]["auth"]["type"] == "bearer"
        assert openai["runtime"]["base_url"] == "https://api.openai.com/v1"
        assert anthropic["runtime"]["auth"]["type"] == "x_api_key"
        assert anthropic["runtime"]["auth"]["header_name"] == "x-api-key"
        assert fireworks["base_url"] == "https://api.fireworks.ai/inference/v1"
        assert fireworks["runtime"]["base_url"] == "https://api.fireworks.ai/inference/v1"
        assert minimax["base_url"] == "https://api.minimax.io/v1"
        assert minimax["runtime"]["base_url"] == "https://api.minimax.io/v1"
      end
    end

    test "snapshot carries representative model execution metadata" do
      snapshot = Packaged.snapshot()

      if snapshot do
        responses_model = snapshot["providers"]["openai"]["models"]["gpt-4.1"]
        speech_model = snapshot["providers"]["openai"]["models"]["gpt-4o-mini-tts"]
        google_model = snapshot["providers"]["google"]["models"]["gemini-2.5-pro"]
        elevenlabs_model = snapshot["providers"]["elevenlabs"]["models"]["eleven_flash_v2_5"]
        claude_opus_4 = snapshot["providers"]["anthropic"]["models"]["claude-opus-4-20250514"]

        claude_opus_4_1 =
          snapshot["providers"]["anthropic"]["models"]["claude-opus-4-1-20250805"]

        assert responses_model["execution"]["text"]["family"] == "openai_responses_compatible"
        assert speech_model["execution"]["speech"]["family"] == "openai_speech"
        assert google_model["execution"]["text"]["family"] == "google_generate_content"
        assert elevenlabs_model["execution"]["speech"]["family"] == "elevenlabs_speech"
        assert claude_opus_4["execution"]["text"]["family"] == "anthropic_messages"
        refute Map.has_key?(claude_opus_4["execution"], "object")
        assert claude_opus_4_1["execution"]["object"]["family"] == "anthropic_messages"
      end
    end

    test "snapshot maps recent OpenAI GPT-5 text and tool models to Responses API" do
      snapshot = Packaged.snapshot()

      if snapshot do
        openai_models = snapshot["providers"]["openai"]["models"]

        for model_id <- [
              "gpt-5.3-chat-latest",
              "gpt-5.3-codex",
              "gpt-5.3-codex-spark",
              "gpt-5.4",
              "gpt-5.4-2026-03-05",
              "gpt-5.4-mini",
              "gpt-5.4-mini-2026-03-17",
              "gpt-5.4-nano",
              "gpt-5.4-nano-2026-03-17",
              "gpt-5.4-pro",
              "gpt-5.4-pro-2026-03-05",
              "gpt-5.5",
              "gpt-5.5-2026-04-23",
              "gpt-5.5-pro",
              "gpt-5.5-pro-2026-04-23"
            ] do
          model = openai_models[model_id]

          assert is_map(model), "expected #{model_id} in packaged OpenAI snapshot"
          assert model["execution"]["text"]["family"] == "openai_responses_compatible"
          assert model["execution"]["text"]["wire_protocol"] == "openai_responses"
          assert model["execution"]["text"]["path"] == "/responses"
          assert model["execution"]["object"]["family"] == "openai_responses_compatible"
          assert model["execution"]["object"]["wire_protocol"] == "openai_responses"
          assert model["execution"]["object"]["path"] == "/responses"
        end
      end
    end

    test "snapshot carries rerank capability metadata for packaged local rerank models" do
      snapshot = Packaged.snapshot()

      if snapshot do
        assert Enum.any?(@local_cohere_rerank_model_ids)

        cohere_models = snapshot["providers"]["cohere"]["models"]

        for model_id <- @local_cohere_rerank_model_ids do
          model = cohere_models[model_id]

          assert is_map(model),
                 "expected local Cohere rerank model #{inspect(model_id)} in packaged snapshot"

          assert model["capabilities"]["rerank"] == true
          assert model["capabilities"]["chat"] == false
          assert model["capabilities"]["embeddings"] == false
          assert model["capabilities"]["streaming"]["text"] == false
          assert model["execution"] == nil
        end
      end
    end
  end
end
