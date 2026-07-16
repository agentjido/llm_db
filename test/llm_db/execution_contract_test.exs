defmodule LLMDB.ExecutionContractTest do
  use ExUnit.Case, async: true

  alias LLMDB.{ExecutionContract, Model, Provider, Validate}

  @cases [
    {"text", %{modalities: %{input: [:text], output: [:text]}}, [:object, :text]},
    {"embeddings", %{modalities: %{input: [:text], output: [:embedding]}}, [:embed]},
    {"image", %{modalities: %{input: [:text], output: [:image]}}, [:image]},
    {"audio transcription", %{modalities: %{input: [:audio], output: [:text]}}, [:transcription]},
    {"audio speech", %{modalities: %{input: [:text], output: [:audio]}}, [:speech]},
    {"video-input chat", %{modalities: %{input: [:text, :video], output: [:text]}},
     [:object, :text]},
    {"tool-using chat", %{capabilities: %{chat: true, tools: %{enabled: true}}}, [:object, :text]}
  ]

  test "enrichment and validation share table-driven operation inference" do
    provider = executable_provider()

    Enum.each(@cases, fn {name, attrs, expected_operations} ->
      model = Model.new!(Map.merge(%{id: name, provider: :openai}, attrs))
      enriched = ExecutionContract.enrich_model(model, provider)

      assert Enum.sort(ExecutionContract.implied_operations(model, provider)) ==
               expected_operations

      assert Enum.sort(Map.keys(enriched.execution)) == expected_operations
      assert :ok = Validate.validate_runtime_contract([provider], [enriched])
    end)
  end

  test "catalog-only providers infer no executable operations" do
    provider =
      Provider.new!(%{id: :catalog_only, catalog_only: true})
      |> ExecutionContract.enrich_provider()

    model = Model.new!(%{id: "docs-only", provider: :catalog_only})
    enriched = ExecutionContract.enrich_model(model, provider)

    assert ExecutionContract.implied_operations(model, provider) == []
    assert enriched.execution == nil
    assert enriched.catalog_only
    assert :ok = Validate.validate_runtime_contract([provider], [enriched])
  end

  test "explicit model execution overrides inferred provider and modality defaults" do
    provider = executable_provider()

    model =
      Model.new!(%{
        id: "explicit-responses",
        provider: :openai,
        modalities: %{input: [:text], output: [:text]},
        execution: %{
          text: %{
            family: "openai_responses_compatible",
            wire_protocol: "openai_responses",
            path: "/custom-responses"
          }
        }
      })

    enriched = ExecutionContract.enrich_model(model, provider)

    assert enriched.execution.text.family == "openai_responses_compatible"
    assert enriched.execution.text.path == "/custom-responses"
    assert enriched.execution.text.wire_protocol == "openai_responses"
    assert :ok = Validate.validate_runtime_contract([provider], [enriched])
  end

  defp executable_provider do
    Provider.new!(%{id: :openai, env: ["OPENAI_API_KEY"]})
    |> ExecutionContract.enrich_provider()
  end
end
