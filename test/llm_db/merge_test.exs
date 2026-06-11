defmodule LLMDB.MergeTest do
  use ExUnit.Case, async: true

  alias LLMDB.Merge

  describe "deep_merge/3" do
    test "applies resolver list rules while recursively merging maps" do
      base = %{
        aliases: ["base-alias"],
        endpoints: ["base-endpoint"],
        nested: %{tags: ["base-tag"], modes: ["base-mode"]}
      }

      override = %{
        aliases: ["override-alias"],
        endpoints: ["override-endpoint"],
        nested: %{tags: ["override-tag"], modes: ["override-mode"]}
      }

      resolver = Merge.resolver(union_list_keys: [:aliases, :tags])

      assert Merge.deep_merge(base, override, resolver) == %{
               aliases: ["base-alias", "override-alias"],
               endpoints: ["override-endpoint"],
               nested: %{tags: ["base-tag", "override-tag"], modes: ["override-mode"]}
             }
    end

    test "preserves configured empty list overrides" do
      base = %{exclude_models: ["legacy-*"], endpoints: ["base-endpoint"]}
      override = %{exclude_models: [], endpoints: []}

      resolver = Merge.resolver(preserve_empty_list_keys: [:exclude_models])

      assert Merge.deep_merge(base, override, resolver) == %{
               exclude_models: ["legacy-*"],
               endpoints: []
             }
    end

    test "does not leak the continuation sentinel for non-map conflicts" do
      resolver = fn _key, _left, _right -> Merge.continue_deep_merge() end

      assert Merge.deep_merge(%{value: 1}, %{value: 2}, resolver) == %{value: 2}
    end

    test "drops nil fields from model struct overrides" do
      base = %LLMDB.Model{
        provider: :test_provider_alpha,
        id: "test-model-v1",
        name: "Base model",
        aliases: ["base-alias"]
      }

      override = %LLMDB.Model{
        provider: :test_provider_alpha,
        id: "test-model-v1",
        name: nil,
        aliases: ["override-alias"]
      }

      result = Merge.deep_merge(base, override, Merge.resolver(union_list_keys: [:aliases]))

      assert result.name == "Base model"
      assert result.aliases == ["base-alias", "override-alias"]
    end
  end

  test "merge_list_by_id preserves base order and appends extras" do
    base = [%{id: "a", rate: 1}, %{id: "b", rate: 2}]
    override = [%{id: "b", rate: 3}, %{id: "c", rate: 4}]

    result = Merge.merge_list_by_id(base, override)

    assert Enum.map(result, & &1.id) == ["a", "b", "c"]
    assert Enum.find(result, &(&1.id == "b")).rate == 3
  end

  test "merge_list_by_id matches string id keys" do
    base = [%{"id" => "a", "rate" => 1}]
    override = [%{"id" => "a", "rate" => 2}, %{"id" => "b", "rate" => 3}]

    result = Merge.merge_list_by_id(base, override)

    assert Enum.map(result, &Map.get(&1, "id")) == ["a", "b"]
    assert Enum.find(result, &(Map.get(&1, "id") == "a"))["rate"] == 2
  end

  test "merge_list_by_id matches atom ids with string id_key" do
    base = [%{id: "a", rate: 1}]
    override = [%{id: "a", rate: 2}, %{id: "b", rate: 3}]

    result = Merge.merge_list_by_id(base, override, "id")

    assert Enum.map(result, & &1.id) == ["a", "b"]
    assert Enum.find(result, &(&1.id == "a")).rate == 2
  end
end
