defmodule LLMDB.ModelAliasTest do
  use ExUnit.Case, async: true

  alias LLMDB.Model

  describe "id ↔ model field sync" do
    test "syncs model from id when only :id provided (atom key)" do
      {:ok, result} = Model.new(%{id: "gpt-4o", provider: :openai})
      assert result.id == "gpt-4o"
      assert result.model == "gpt-4o"
    end

    test "syncs model from id when only id provided (string key)" do
      {:ok, result} = Model.new(%{"id" => "gpt-4o", "provider" => :openai})
      assert result.id == "gpt-4o"
      assert result.model == "gpt-4o"
    end

    test "syncs id from model when only :model provided (atom key)" do
      {:ok, result} = Model.new(%{model: "gpt-4o", provider: :openai})
      assert result.id == "gpt-4o"
      assert result.model == "gpt-4o"
    end

    test "syncs id from model when only model provided (string key)" do
      {:ok, result} = Model.new(%{"model" => "gpt-4o", "provider" => :openai})
      assert result.id == "gpt-4o"
      assert result.model == "gpt-4o"
    end

    test "preserves both when equal" do
      {:ok, result} = Model.new(%{id: "gpt-4o", model: "gpt-4o", provider: :openai})
      assert result.id == "gpt-4o"
      assert result.model == "gpt-4o"
    end

    test "id wins when both provided but different" do
      {:ok, result} = Model.new(%{id: "gpt-4o", model: "different", provider: :openai})
      assert result.id == "gpt-4o"
      assert result.model == "gpt-4o"
    end

    test "treats empty string as nil for id" do
      {:ok, result} = Model.new(%{id: "", model: "gpt-4o", provider: :openai})
      assert result.id == "gpt-4o"
      assert result.model == "gpt-4o"
    end

    test "treats empty string as nil for model" do
      {:ok, result} = Model.new(%{id: "gpt-4o", model: "", provider: :openai})
      assert result.id == "gpt-4o"
      assert result.model == "gpt-4o"
    end

    test "handles mixed string/atom keys" do
      {:ok, result} = Model.new(%{"id" => "gpt-4o", provider: :openai})
      assert result.id == "gpt-4o"
      assert result.model == "gpt-4o"
    end

    test "syncs in new!/1" do
      result = Model.new!(%{id: "gpt-4o", provider: :openai})
      assert result.id == "gpt-4o"
      assert result.model == "gpt-4o"
    end
  end

  describe "JSON encoding" do
    test "includes both id and model in JSON output" do
      {:ok, model} = Model.new(%{id: "gpt-4o", provider: :openai})
      json = Jason.encode!(model)
      decoded = Jason.decode!(json)

      assert decoded["id"] == "gpt-4o"
      assert decoded["model"] == "gpt-4o"
      assert decoded["provider"] == "openai"
    end

    test "includes all standard fields in JSON" do
      {:ok, model} =
        Model.new(%{
          id: "gpt-4o",
          provider: :openai,
          name: "GPT-4o",
          limits: %{context: 128_000, output: 4096},
          cost: %{input: 2.5, output: 10.0}
        })

      json = Jason.encode!(model)
      decoded = Jason.decode!(json)

      assert decoded["id"] == "gpt-4o"
      assert decoded["model"] == "gpt-4o"
      assert decoded["name"] == "GPT-4o"
      assert decoded["limits"]["context"] == 128_000
      assert decoded["cost"]["input"] == 2.5
    end
  end

  describe "capabilities flat structure" do
    test "accepts flat capabilities structure" do
      {:ok, model} =
        Model.new(%{
          id: "gpt-4o",
          provider: :openai,
          capabilities: %{
            chat: true,
            tools: %{enabled: true, streaming: true},
            reasoning: %{enabled: false}
          }
        })

      assert model.capabilities.chat == true
      assert model.capabilities.tools.enabled == true
      assert model.capabilities.tools.streaming == true
      assert model.capabilities.reasoning.enabled == false
    end

    test "preserves flat rerank capability" do
      {:ok, model} =
        Model.new(%{
          id: "jina-reranker-v3",
          provider: :jina,
          capabilities: %{rerank: true}
        })

      assert model.capabilities.rerank == true
    end

    test "capabilities defaults are applied correctly" do
      {:ok, model} = Model.new(%{id: "gpt-4o", provider: :openai, capabilities: %{}})

      assert model.capabilities.chat == true
      assert model.capabilities.rerank == false
      assert model.capabilities.tools.enabled == false
      assert model.capabilities.reasoning.enabled == false
    end
  end
end
