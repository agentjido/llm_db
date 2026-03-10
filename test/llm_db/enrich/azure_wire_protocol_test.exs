defmodule LLMDB.Enrich.AzureWireProtocolTest do
  use ExUnit.Case, async: false

  alias LLMDB.Enrich.AzureWireProtocol

  setup do
    cache_dir =
      Path.join(
        System.tmp_dir!(),
        "azure_wire_protocol_#{System.unique_integer([:positive])}"
      )

    previous_cache_dir = Application.get_env(:llm_db, :azure_foundry_cache_dir)

    File.mkdir_p!(cache_dir)
    Application.put_env(:llm_db, :azure_foundry_cache_dir, cache_dir)

    on_exit(fn ->
      if previous_cache_dir do
        Application.put_env(:llm_db, :azure_foundry_cache_dir, previous_cache_dir)
      else
        Application.delete_env(:llm_db, :azure_foundry_cache_dir)
      end

      File.rm_rf!(cache_dir)
    end)

    {:ok, cache_dir: cache_dir}
  end

  test "matches instruct-suffixed cache entries for azure providers", %{cache_dir: cache_dir} do
    write_cache(cache_dir, [
      foundry_model("Phi-4-mini-instruct", ["chat-completion"]),
      foundry_model("Phi-4-multimodal-instruct", ["chat-completion"])
    ])

    [azure_model, cognitive_model, preserved, non_azure] =
      AzureWireProtocol.enrich_models([
        %{id: "phi-4-mini", provider: :azure},
        %{id: "phi-4-multimodal-2025-01-01", provider: :azure_cognitive_services},
        %{id: "phi-4-mini", provider: :azure, extra: %{wire_protocol: :openai_responses}},
        %{id: "phi-4-mini", provider: :openai}
      ])

    assert get_in(azure_model, [:extra, :wire_protocol]) == :openai_completion
    assert get_in(cognitive_model, [:extra, :wire_protocol]) == :openai_completion
    assert preserved.extra.wire_protocol == :openai_responses
    refute Map.has_key?(non_azure, :extra)
  end

  defp write_cache(cache_dir, models) do
    cache_path = Path.join(cache_dir, "azure-foundry.json")
    File.write!(cache_path, Jason.encode!(models))
  end

  defp foundry_model(name, tasks) do
    %{
      "annotations" => %{
        "name" => name,
        "systemCatalogData" => %{
          "inferenceTasks" => tasks
        }
      }
    }
  end
end
