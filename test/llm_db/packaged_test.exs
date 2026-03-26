defmodule LLMDB.PackagedTest do
  use ExUnit.Case, async: true

  alias LLMDB.Packaged

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

        assert openai["runtime"]["auth"]["type"] == "bearer"
        assert openai["runtime"]["base_url"] == "https://api.openai.com/v1"
        assert anthropic["runtime"]["auth"]["type"] == "x_api_key"
        assert anthropic["runtime"]["auth"]["header_name"] == "x-api-key"
      end
    end

    test "snapshot carries representative model execution metadata" do
      snapshot = Packaged.snapshot()

      if snapshot do
        responses_model = snapshot["providers"]["openai"]["models"]["gpt-4.1"]
        speech_model = snapshot["providers"]["openai"]["models"]["gpt-4o-mini-tts"]
        google_model = snapshot["providers"]["google"]["models"]["gemini-2.5-pro"]
        elevenlabs_model = snapshot["providers"]["elevenlabs"]["models"]["eleven_flash_v2_5"]

        assert responses_model["execution"]["text"]["family"] == "openai_responses_compatible"
        assert speech_model["execution"]["speech"]["family"] == "openai_speech"
        assert google_model["execution"]["text"]["family"] == "google_generate_content"
        assert elevenlabs_model["execution"]["speech"]["family"] == "elevenlabs_speech"
      end
    end
  end
end
