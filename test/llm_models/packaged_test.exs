defmodule LLMModels.PackagedTest do
  use ExUnit.Case, async: true

  alias LLMModels.Packaged

  describe "path/0" do
    test "returns correct snapshot path" do
      path = Packaged.path()
      assert String.ends_with?(path, "priv/llm_models/snapshot.json")
      assert is_binary(path)
    end
  end

  describe "snapshot/0" do
    test "loads snapshot from priv directory" do
      snapshot = Packaged.snapshot()

      if snapshot do
        assert is_map(snapshot)
        assert Map.has_key?(snapshot, :providers)
        assert Map.has_key?(snapshot, :models)
        assert is_list(snapshot.providers)
        assert is_list(snapshot.models)
      else
        assert snapshot == nil
      end
    end

    test "snapshot providers have expected structure" do
      snapshot = Packaged.snapshot()

      if snapshot && snapshot.providers != [] do
        provider = hd(snapshot.providers)
        assert Map.has_key?(provider, :id)
        assert is_binary(provider.id)
      end
    end

    test "snapshot models have expected structure" do
      snapshot = Packaged.snapshot()

      if snapshot && snapshot.models != [] do
        model = hd(snapshot.models)
        assert Map.has_key?(model, :id)
        assert Map.has_key?(model, :provider)
        assert is_binary(model.id)
        assert is_binary(model.provider)
      end
    end
  end
end
