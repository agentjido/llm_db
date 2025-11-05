defmodule LLMModels.Schema.LimitsTest do
  use ExUnit.Case, async: true

  alias LLMModels.Schema.Limits

  describe "valid parsing" do
    test "parses empty limits" do
      input = %{}
      assert {:ok, result} = Zoi.parse(Limits.schema(), input)
      assert result == %{}
    end

    test "parses limits with context only" do
      input = %{context: 128_000}
      assert {:ok, result} = Zoi.parse(Limits.schema(), input)
      assert result.context == 128_000
      refute Map.has_key?(result, :output)
    end

    test "parses limits with output only" do
      input = %{output: 4096}
      assert {:ok, result} = Zoi.parse(Limits.schema(), input)
      assert result.output == 4096
      refute Map.has_key?(result, :context)
    end

    test "parses limits with both context and output" do
      input = %{context: 200_000, output: 8192}
      assert {:ok, result} = Zoi.parse(Limits.schema(), input)
      assert result.context == 200_000
      assert result.output == 8192
    end
  end

  describe "optional fields" do
    test "context is optional" do
      input = %{output: 4096}
      assert {:ok, result} = Zoi.parse(Limits.schema(), input)
      refute Map.has_key?(result, :context)
    end

    test "output is optional" do
      input = %{context: 128_000}
      assert {:ok, result} = Zoi.parse(Limits.schema(), input)
      refute Map.has_key?(result, :output)
    end
  end

  describe "invalid inputs" do
    test "rejects non-integer context" do
      input = %{context: "128000"}
      assert {:error, _} = Zoi.parse(Limits.schema(), input)
    end

    test "rejects non-integer output" do
      input = %{output: "4096"}
      assert {:error, _} = Zoi.parse(Limits.schema(), input)
    end

    test "rejects context less than 1" do
      input = %{context: 0}
      assert {:error, _} = Zoi.parse(Limits.schema(), input)
    end

    test "rejects negative context" do
      input = %{context: -1}
      assert {:error, _} = Zoi.parse(Limits.schema(), input)
    end

    test "rejects output less than 1" do
      input = %{output: 0}
      assert {:error, _} = Zoi.parse(Limits.schema(), input)
    end

    test "rejects negative output" do
      input = %{output: -100}
      assert {:error, _} = Zoi.parse(Limits.schema(), input)
    end
  end

  describe "boundary conditions" do
    test "accepts minimum valid context" do
      input = %{context: 1}
      assert {:ok, result} = Zoi.parse(Limits.schema(), input)
      assert result.context == 1
    end

    test "accepts minimum valid output" do
      input = %{output: 1}
      assert {:ok, result} = Zoi.parse(Limits.schema(), input)
      assert result.output == 1
    end

    test "accepts large limits" do
      input = %{context: 1_000_000, output: 100_000}
      assert {:ok, result} = Zoi.parse(Limits.schema(), input)
      assert result.context == 1_000_000
      assert result.output == 100_000
    end
  end
end
