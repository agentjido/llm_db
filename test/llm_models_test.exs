defmodule LlmModelsTest do
  use ExUnit.Case
  doctest LlmModels

  test "greets the world" do
    assert LlmModels.hello() == :world
  end
end
