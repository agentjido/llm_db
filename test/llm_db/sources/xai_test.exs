defmodule LLMDB.Sources.XAITest do
  use ExUnit.Case, async: true

  alias LLMDB.Sources.XAI

  describe "transform/1" do
    test "preserves token pricing returned by the xAI models endpoint" do
      result =
        XAI.transform(%{
          "object" => "list",
          "data" => [
            %{
              "id" => "grok-4.3",
              "object" => "model",
              "created" => 1_776_384_000,
              "owned_by" => "xai",
              "aliases" => ["grok-4.3-latest", "grok-latest"],
              "context_length" => 1_000_000,
              "prompt_text_token_price" => 12_500,
              "cached_prompt_text_token_price" => 2_000,
              "completion_text_token_price" => 25_000,
              "prompt_image_token_price" => 12_500,
              "long_context_threshold" => 200_000,
              "prompt_text_token_price_long_context" => 25_000,
              "cached_prompt_text_token_price_long_context" => 4_000,
              "completion_text_token_price_long_context" => 50_000
            }
          ]
        })

      [model] = result["xai"].models

      assert model.id == "grok-4.3"
      assert model.provider == :xai
      assert model.extra.created == 1_776_384_000
      assert model.extra.owned_by == "xai"
      assert model.extra.long_context_threshold == 200_000
      assert model.aliases == ["grok-4.3-latest", "grok-latest"]
      assert model.limits.context == 1_000_000

      assert model.cost.input == 1.25
      assert model.cost.cache_read == 0.2
      assert model.cost.output == 2.5
      assert model.cost.image == 1.25

      components = Map.new(model.pricing.components, &{&1.id, &1})

      assert components["token.input.long_context"].rate == 2.5
      assert components["token.cache_read.long_context"].rate == 0.4
      assert components["token.output.long_context"].rate == 5.0
    end
  end
end
