defmodule LLMDB.History.DiffLineageTest do
  use ExUnit.Case, async: true

  alias LLMDB.History.{Backfill, Diff, Lineage}

  test "classifies additions, removals, and lifecycle changes deterministically" do
    previous = %{
      "openai:removed" => model("removed"),
      "openai:stable" => model("stable", %{"status" => %{"state" => "active"}})
    }

    current = %{
      "openai:added" => model("added"),
      "openai:stable" => model("stable", %{"status" => %{"state" => "deprecated"}})
    }

    assert [
             %{type: "introduced", model_key: "openai:added", changes: []},
             %{type: "removed", model_key: "openai:removed", changes: []},
             %{
               type: "changed",
               model_key: "openai:stable",
               changes: [
                 %{
                   path: "status.state",
                   op: "replace",
                   before: "active",
                   after: "deprecated"
                 }
               ]
             }
           ] = Diff.models(previous, current)

    assert Backfill.diff_models(previous, current) == Diff.models(previous, current)
  end

  test "normalization prevents alias and modality ordering noise" do
    previous = %{
      "aliases" => ["latest", "stable"],
      "modalities" => %{"input" => ["text", "image"], "output" => ["text"]}
    }

    current = %{
      "aliases" => ["stable", "latest"],
      "modalities" => %{"input" => ["image", "text"], "output" => ["text"]}
    }

    assert Diff.models(%{"openai:model" => Diff.normalize(previous)}, %{
             "openai:model" => Diff.normalize(current)
           }) == []
  end

  test "carries lineage through an alias-based rename" do
    previous = %{"openai:gpt-old" => model("gpt-old")}

    current = %{
      "openai:gpt-new" => model("gpt-new", %{"aliases" => ["gpt-old"]})
    }

    previous_lineage = %{"openai:gpt-old" => "openai:gpt-old"}
    current_lineage = Lineage.resolve(previous, current, previous_lineage, %{})

    assert current_lineage == %{"openai:gpt-new" => "openai:gpt-old"}

    assert Diff.models(previous, current)
           |> Lineage.attach(previous_lineage, current_lineage)
           |> Enum.map(&{&1.type, &1.model_key, &1.lineage_key}) == [
             {"introduced", "openai:gpt-new", "openai:gpt-old"},
             {"removed", "openai:gpt-old", "openai:gpt-old"}
           ]
  end

  test "uses provider model identity and explicit overrides" do
    previous = %{
      "provider:old" => model("old", %{"provider_model_id" => "upstream-id"})
    }

    current = %{
      "provider:new" => model("new", %{"provider_model_id" => "upstream-id"}),
      "provider:manual" => model("manual")
    }

    previous_lineage = %{"provider:old" => "provider:origin"}
    overrides = %{"provider:manual" => "provider:old"}

    assert Lineage.resolve(previous, current, previous_lineage, overrides) == %{
             "provider:new" => "provider:origin",
             "provider:manual" => "provider:origin"
           }
  end

  test "resolves equally-scored ambiguous candidates deterministically one-to-one" do
    previous = %{
      "provider:old-a" => model("old-a", %{"provider_model_id" => "shared"}),
      "provider:old-b" => model("old-b", %{"provider_model_id" => "shared"})
    }

    current = %{
      "provider:new-a" => model("new-a", %{"provider_model_id" => "shared"}),
      "provider:new-b" => model("new-b", %{"provider_model_id" => "shared"})
    }

    previous_lineage = %{
      "provider:old-a" => "lineage:a",
      "provider:old-b" => "lineage:b"
    }

    assert Lineage.resolve(previous, current, previous_lineage, %{}) == %{
             "provider:new-a" => "lineage:a",
             "provider:new-b" => "lineage:b"
           }
  end

  defp model(id, extra \\ %{}) do
    Map.merge(%{"id" => id, "provider" => "provider"}, extra)
  end
end
