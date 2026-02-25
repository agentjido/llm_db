defmodule LLMDB.History.BackfillTest do
  use ExUnit.Case, async: true

  alias LLMDB.History.Backfill

  describe "diff_models/2" do
    test "emits introduced, removed, and changed events deterministically" do
      previous = %{
        "openai:gpt-4o" => %{
          "id" => "gpt-4o",
          "provider" => "openai",
          "limits" => %{"context" => 128_000}
        },
        "openai:gpt-3.5-turbo" => %{"id" => "gpt-3.5-turbo", "provider" => "openai"}
      }

      current = %{
        "openai:gpt-4o" => %{
          "id" => "gpt-4o",
          "provider" => "openai",
          "limits" => %{"context" => 256_000}
        },
        "anthropic:claude-sonnet-4" => %{"id" => "claude-sonnet-4", "provider" => "anthropic"}
      }

      events = Backfill.diff_models(previous, current)

      assert [
               %{type: "introduced", model_key: "anthropic:claude-sonnet-4", changes: []},
               %{type: "removed", model_key: "openai:gpt-3.5-turbo", changes: []},
               %{
                 type: "changed",
                 model_key: "openai:gpt-4o",
                 changes: [
                   %{
                     path: "limits.context",
                     op: "replace",
                     before: 128_000,
                     after: 256_000
                   }
                 ]
               }
             ] = events
    end

    test "does not emit a changed event for reordered aliases" do
      previous = %{
        "openai:gpt-4o" => %{
          "id" => "gpt-4o",
          "provider" => "openai",
          "aliases" => ["gpt-4o-latest", "chatgpt-4o-latest"]
        }
      }

      current = %{
        "openai:gpt-4o" => %{
          "id" => "gpt-4o",
          "provider" => "openai",
          "aliases" => ["chatgpt-4o-latest", "gpt-4o-latest"]
        }
      }

      # Simulate post-normalization data used by the backfill engine.
      previous_normalized = %{
        "openai:gpt-4o" => %{
          "id" => "gpt-4o",
          "provider" => "openai",
          "aliases" => Enum.sort(previous["openai:gpt-4o"]["aliases"])
        }
      }

      current_normalized = %{
        "openai:gpt-4o" => %{
          "id" => "gpt-4o",
          "provider" => "openai",
          "aliases" => Enum.sort(current["openai:gpt-4o"]["aliases"])
        }
      }

      assert Backfill.diff_models(previous_normalized, current_normalized) == []
    end
  end
end
