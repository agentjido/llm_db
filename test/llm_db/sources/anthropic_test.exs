defmodule LLMDB.Sources.AnthropicTest do
  use ExUnit.Case, async: true

  alias LLMDB.Sources.Anthropic

  describe "transform/1" do
    test "maps model limits, modalities, and canonical capabilities" do
      input = %{
        "data" => [
          %{
            "id" => "claude-fable-5",
            "type" => "model",
            "display_name" => "Claude Fable 5",
            "created_at" => "2026-06-07T00:00:00Z",
            "max_input_tokens" => 1_000_000,
            "max_tokens" => 128_000,
            "capabilities" => %{
              "image_input" => %{"supported" => true},
              "pdf_input" => %{"supported" => true},
              "structured_outputs" => %{"supported" => true},
              "thinking" => %{
                "supported" => true,
                "types" => %{
                  "adaptive" => %{"supported" => true},
                  "enabled" => %{"supported" => false}
                }
              }
            }
          }
        ]
      }

      assert %{
               "anthropic" => %{
                 id: :anthropic,
                 name: "Anthropic",
                 models: [model]
               }
             } = Anthropic.transform(input)

      assert model.id == "claude-fable-5"
      assert model.provider == :anthropic
      assert model.name == "Claude Fable 5"
      assert model.limits == %{context: 1_000_000, output: 128_000}
      assert model.modalities == %{input: [:text, :image, :pdf], output: [:text]}
      assert model.capabilities.reasoning.enabled == true
      assert model.capabilities.json == %{native: false, schema: true, strict: false}
      assert model.extra.type == "model"
      assert model.extra.created_at == "2026-06-07T00:00:00Z"
      assert model.extra.capabilities["thinking"]["types"]["adaptive"]["supported"] == true
      refute Map.has_key?(model.extra, :max_input_tokens)
      refute Map.has_key?(model.extra, :max_tokens)
    end
  end
end
