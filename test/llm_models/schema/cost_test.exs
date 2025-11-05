defmodule LLMModels.Schema.CostTest do
  use ExUnit.Case, async: true

  alias LLMModels.Schema.Cost

  describe "valid parsing" do
    test "parses empty cost" do
      input = %{}
      assert {:ok, result} = Zoi.parse(Cost.schema(), input)
      assert result == %{}
    end

    test "parses cost with input and output" do
      input = %{input: 0.15, output: 0.60}
      assert {:ok, result} = Zoi.parse(Cost.schema(), input)
      assert result.input == 0.15
      assert result.output == 0.60
    end

    test "parses cost with all fields" do
      input = %{
        input: 0.15,
        output: 0.60,
        cache_read: 0.015,
        cache_write: 0.30,
        training: 3.00,
        image: 1.25,
        audio: 0.50
      }

      assert {:ok, result} = Zoi.parse(Cost.schema(), input)
      assert result.input == 0.15
      assert result.output == 0.60
      assert result.cache_read == 0.015
      assert result.cache_write == 0.30
      assert result.training == 3.00
      assert result.image == 1.25
      assert result.audio == 0.50
    end

    test "parses cost with integer values" do
      input = %{input: 1, output: 2}
      assert {:ok, result} = Zoi.parse(Cost.schema(), input)
      assert result.input == 1
      assert result.output == 2
    end

    test "parses cost with zero values" do
      input = %{input: 0.0, output: 0.0}
      assert {:ok, result} = Zoi.parse(Cost.schema(), input)
      assert result.input == 0.0
      assert result.output == 0.0
    end
  end

  describe "optional fields" do
    test "input is optional" do
      input = %{output: 0.60}
      assert {:ok, result} = Zoi.parse(Cost.schema(), input)
      refute Map.has_key?(result, :input)
    end

    test "output is optional" do
      input = %{input: 0.15}
      assert {:ok, result} = Zoi.parse(Cost.schema(), input)
      refute Map.has_key?(result, :output)
    end

    test "cache_read is optional" do
      input = %{input: 0.15}
      assert {:ok, result} = Zoi.parse(Cost.schema(), input)
      refute Map.has_key?(result, :cache_read)
    end

    test "cache_write is optional" do
      input = %{input: 0.15}
      assert {:ok, result} = Zoi.parse(Cost.schema(), input)
      refute Map.has_key?(result, :cache_write)
    end

    test "training is optional" do
      input = %{input: 0.15}
      assert {:ok, result} = Zoi.parse(Cost.schema(), input)
      refute Map.has_key?(result, :training)
    end

    test "image is optional" do
      input = %{input: 0.15}
      assert {:ok, result} = Zoi.parse(Cost.schema(), input)
      refute Map.has_key?(result, :image)
    end

    test "audio is optional" do
      input = %{input: 0.15}
      assert {:ok, result} = Zoi.parse(Cost.schema(), input)
      refute Map.has_key?(result, :audio)
    end
  end

  describe "invalid inputs" do
    test "rejects non-numeric input" do
      input = %{input: "0.15"}
      assert {:error, _} = Zoi.parse(Cost.schema(), input)
    end

    test "rejects non-numeric output" do
      input = %{output: "0.60"}
      assert {:error, _} = Zoi.parse(Cost.schema(), input)
    end

    test "rejects non-numeric cache_read" do
      input = %{cache_read: "0.015"}
      assert {:error, _} = Zoi.parse(Cost.schema(), input)
    end

    test "rejects non-numeric cache_write" do
      input = %{cache_write: false}
      assert {:error, _} = Zoi.parse(Cost.schema(), input)
    end

    test "rejects non-numeric training" do
      input = %{training: [3.0]}
      assert {:error, _} = Zoi.parse(Cost.schema(), input)
    end

    test "rejects non-numeric image" do
      input = %{image: %{}}
      assert {:error, _} = Zoi.parse(Cost.schema(), input)
    end

    test "rejects non-numeric audio" do
      input = %{audio: :invalid}
      assert {:error, _} = Zoi.parse(Cost.schema(), input)
    end
  end

  describe "negative values" do
    test "accepts negative input cost" do
      input = %{input: -0.15}
      assert {:ok, result} = Zoi.parse(Cost.schema(), input)
      assert result.input == -0.15
    end

    test "accepts negative output cost" do
      input = %{output: -0.60}
      assert {:ok, result} = Zoi.parse(Cost.schema(), input)
      assert result.output == -0.60
    end
  end
end
