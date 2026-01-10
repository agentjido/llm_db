defmodule LLMDB.Sources.ZenmuxTest do
  use ExUnit.Case, async: true
  alias LLMDB.Sources.Zenmux

  describe "transform/1" do
    test "correctly transforms basic model list" do
      input = %{
        "object" => "list",
        "data" => [
          %{
            "id" => "openai/gpt-5",
            "object" => "model",
            "created" => 1_686_935_002,
            "owned_by" => "openai"
          }
        ]
      }

      assert %{
               "zenmux" => %{
                 id: :zenmux,
                 name: "Zenmux",
                 models: [model]
               }
             } = Zenmux.transform(input)

      assert model.id == "openai/gpt-5"
      assert model.provider == :zenmux
      assert model.extra.created == 1_686_935_002
    end

    test "infers implicit caching for GPT models" do
      input = %{
        "data" => [%{"id" => "openai/gpt-4o"}]
      }

      result = Zenmux.transform(input)
      model = hd(result["zenmux"].models)

      assert model.capabilities.caching.type == :implicit
    end

    test "infers explicit caching for Claude models" do
      input = %{
        "data" => [%{"id" => "anthropic/claude-3.5-sonnet"}]
      }

      result = Zenmux.transform(input)
      model = hd(result["zenmux"].models)

      assert model.capabilities.caching.type == :explicit
    end

    test "infers image generation modality" do
      input = %{
        "data" => [%{"id" => "google/gemini-3-pro-image-preview"}]
      }

      result = Zenmux.transform(input)
      model = hd(result["zenmux"].models)

      assert model.modalities.output == [:image]
    end

    test "infers vision input modality" do
      input = %{
        "data" => [%{"id" => "openai/gpt-4o"}]
      }

      result = Zenmux.transform(input)
      model = hd(result["zenmux"].models)

      assert :image in model.modalities.input
    end
  end
end
