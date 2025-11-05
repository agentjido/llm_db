defmodule LLMModels.Schema.CapabilitiesTest do
  use ExUnit.Case, async: true

  alias LLMModels.Schema.Capabilities

  describe "defaults" do
    test "applies default values when empty" do
      input = %{}
      assert {:ok, result} = Zoi.parse(Capabilities.schema(), input)
      assert result.chat == true
      assert result.embeddings == false
      assert result.reasoning == %{enabled: false}
      assert result.tools == %{enabled: false, streaming: false, strict: false, parallel: false}
      assert result.json == %{native: false, schema: false, strict: false}
      assert result.streaming == %{text: true, tool_calls: false}
    end

    test "chat defaults to true" do
      input = %{}
      assert {:ok, result} = Zoi.parse(Capabilities.schema(), input)
      assert result.chat == true
    end

    test "embeddings defaults to false" do
      input = %{}
      assert {:ok, result} = Zoi.parse(Capabilities.schema(), input)
      assert result.embeddings == false
    end

    test "reasoning defaults to disabled" do
      input = %{}
      assert {:ok, result} = Zoi.parse(Capabilities.schema(), input)
      assert result.reasoning.enabled == false
    end

    test "tools defaults to all disabled" do
      input = %{}
      assert {:ok, result} = Zoi.parse(Capabilities.schema(), input)
      assert result.tools.enabled == false
      assert result.tools.streaming == false
      assert result.tools.strict == false
      assert result.tools.parallel == false
    end

    test "json defaults to all disabled" do
      input = %{}
      assert {:ok, result} = Zoi.parse(Capabilities.schema(), input)
      assert result.json.native == false
      assert result.json.schema == false
      assert result.json.strict == false
    end

    test "streaming defaults text to true, tool_calls to false" do
      input = %{}
      assert {:ok, result} = Zoi.parse(Capabilities.schema(), input)
      assert result.streaming.text == true
      assert result.streaming.tool_calls == false
    end
  end

  describe "valid parsing" do
    test "parses capabilities with overrides" do
      input = %{
        chat: false,
        embeddings: true,
        reasoning: %{enabled: true, token_budget: 10_000},
        tools: %{enabled: true, streaming: true, strict: true, parallel: true},
        json: %{native: true, schema: true, strict: true},
        streaming: %{text: false, tool_calls: true}
      }

      assert {:ok, result} = Zoi.parse(Capabilities.schema(), input)
      assert result.chat == false
      assert result.embeddings == true
      assert result.reasoning.enabled == true
      assert result.reasoning.token_budget == 10_000
      assert result.tools.enabled == true
      assert result.tools.streaming == true
      assert result.tools.strict == true
      assert result.tools.parallel == true
      assert result.json.native == true
      assert result.json.schema == true
      assert result.json.strict == true
      assert result.streaming.text == false
      assert result.streaming.tool_calls == true
    end

    test "parses partial overrides with defaults" do
      input = %{
        tools: %{enabled: true}
      }

      assert {:ok, result} = Zoi.parse(Capabilities.schema(), input)
      assert result.chat == true
      assert result.embeddings == false
      assert result.tools.enabled == true
      assert result.tools.streaming == false
      assert result.tools.strict == false
      assert result.tools.parallel == false
    end

    test "parses reasoning with token_budget" do
      input = %{
        reasoning: %{enabled: true, token_budget: 20_000}
      }

      assert {:ok, result} = Zoi.parse(Capabilities.schema(), input)
      assert result.reasoning.enabled == true
      assert result.reasoning.token_budget == 20_000
    end

    test "parses reasoning without token_budget" do
      input = %{
        reasoning: %{enabled: true}
      }

      assert {:ok, result} = Zoi.parse(Capabilities.schema(), input)
      assert result.reasoning.enabled == true
      refute Map.has_key?(result.reasoning, :token_budget)
    end
  end

  describe "optional fields" do
    test "reasoning token_budget is optional" do
      input = %{reasoning: %{enabled: false}}
      assert {:ok, result} = Zoi.parse(Capabilities.schema(), input)
      refute Map.has_key?(result.reasoning, :token_budget)
    end
  end

  describe "invalid inputs" do
    test "rejects non-boolean chat" do
      input = %{chat: "true"}
      assert {:error, _} = Zoi.parse(Capabilities.schema(), input)
    end

    test "rejects non-boolean embeddings" do
      input = %{embeddings: 1}
      assert {:error, _} = Zoi.parse(Capabilities.schema(), input)
    end

    test "rejects non-boolean reasoning.enabled" do
      input = %{reasoning: %{enabled: "false"}}
      assert {:error, _} = Zoi.parse(Capabilities.schema(), input)
    end

    test "rejects non-integer reasoning.token_budget" do
      input = %{reasoning: %{enabled: true, token_budget: "10000"}}
      assert {:error, _} = Zoi.parse(Capabilities.schema(), input)
    end

    test "rejects negative reasoning.token_budget" do
      input = %{reasoning: %{enabled: true, token_budget: -1}}
      assert {:error, _} = Zoi.parse(Capabilities.schema(), input)
    end

    test "rejects non-boolean tools.enabled" do
      input = %{tools: %{enabled: 1}}
      assert {:error, _} = Zoi.parse(Capabilities.schema(), input)
    end

    test "rejects non-boolean json.native" do
      input = %{json: %{native: "true"}}
      assert {:error, _} = Zoi.parse(Capabilities.schema(), input)
    end

    test "rejects non-boolean streaming.text" do
      input = %{streaming: %{text: 1}}
      assert {:error, _} = Zoi.parse(Capabilities.schema(), input)
    end
  end

  describe "nested defaults" do
    test "applies nested defaults when parent is provided but fields missing" do
      input = %{tools: %{enabled: true}}
      assert {:ok, result} = Zoi.parse(Capabilities.schema(), input)
      assert result.tools.streaming == false
      assert result.tools.strict == false
      assert result.tools.parallel == false
    end

    test "applies nested defaults for json" do
      input = %{json: %{native: true}}
      assert {:ok, result} = Zoi.parse(Capabilities.schema(), input)
      assert result.json.schema == false
      assert result.json.strict == false
    end

    test "applies nested defaults for streaming" do
      input = %{streaming: %{tool_calls: true}}
      assert {:ok, result} = Zoi.parse(Capabilities.schema(), input)
      assert result.streaming.text == true
    end
  end

  describe "boundary conditions" do
    test "accepts zero token_budget" do
      input = %{reasoning: %{enabled: true, token_budget: 0}}
      assert {:ok, result} = Zoi.parse(Capabilities.schema(), input)
      assert result.reasoning.token_budget == 0
    end

    test "accepts large token_budget" do
      input = %{reasoning: %{enabled: true, token_budget: 1_000_000}}
      assert {:ok, result} = Zoi.parse(Capabilities.schema(), input)
      assert result.reasoning.token_budget == 1_000_000
    end
  end
end
