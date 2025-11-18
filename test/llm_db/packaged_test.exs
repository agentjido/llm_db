defmodule LLMDB.PackagedTest do
  use ExUnit.Case, async: true

  alias LLMDB.Packaged

  describe "manifest_path/0" do
    test "returns correct manifest path" do
      path = Packaged.manifest_path()
      assert String.ends_with?(path, "priv/llm_db/manifest.json")
      assert is_binary(path)
    end
  end

  describe "providers_dir/0" do
    test "returns correct providers directory path" do
      path = Packaged.providers_dir()
      assert String.ends_with?(path, "priv/llm_db/providers")
      assert is_binary(path)
    end
  end

  describe "snapshot/0" do
    test "loads snapshot from priv directory" do
      snapshot = Packaged.snapshot()

      if snapshot do
        assert is_map(snapshot)
        # v2 schema
        assert Map.has_key?(snapshot, :version)
        assert Map.has_key?(snapshot, :generated_at)
        assert Map.has_key?(snapshot, :providers)
        assert snapshot.version == 2
        assert is_map(snapshot.providers)
      else
        assert snapshot == nil
      end
    end

    test "snapshot providers have expected structure" do
      snapshot = Packaged.snapshot()

      if snapshot && map_size(snapshot.providers) > 0 do
        {provider_id, provider} = Enum.at(snapshot.providers, 0)
        assert is_atom(provider_id) or is_binary(provider_id)
        assert Map.has_key?(provider, :id)
        assert Map.has_key?(provider, :models)
        assert is_map(provider.models)
      end
    end

    test "snapshot models have expected structure" do
      snapshot = Packaged.snapshot()

      if snapshot && map_size(snapshot.providers) > 0 do
        {_provider_id, provider} = Enum.at(snapshot.providers, 0)

        if map_size(provider.models) > 0 do
          {model_id, model} = Enum.at(provider.models, 0)
          assert is_binary(model_id) or is_atom(model_id)
          assert Map.has_key?(model, :id)
          assert Map.has_key?(model, :provider)
        end
      end
    end
  end
end
