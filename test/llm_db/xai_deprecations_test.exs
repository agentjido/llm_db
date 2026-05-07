defmodule LLMDB.XAIDeprecationsTest do
  use ExUnit.Case, async: false

  alias LLMDB.{Model, Normalize}
  alias LLMDB.Sources.Local

  @local_dir "priv/llm_db/local"
  @deprecated_at "2026-05-07"
  @retires_at "2026-05-15T19:00:00Z"

  @expected_lifecycle %{
    "grok-4-1-fast-reasoning" => "grok-4.3",
    "grok-4-1-fast-non-reasoning" => "grok-4.20-non-reasoning",
    "grok-4-fast-reasoning" => "grok-4.3",
    "grok-4-fast-non-reasoning" => "grok-4.20-non-reasoning",
    "grok-4-0709" => "grok-4.3",
    "grok-code-fast-1" => "grok-4.20-non-reasoning",
    "grok-3" => "grok-4.20-non-reasoning",
    "grok-imagine-image-pro" => "grok-imagine-image"
  }

  test "local xAI overrides codify the 2026-05-15 retirement batch" do
    models = xai_models()

    Enum.each(@expected_lifecycle, fn {model_id, replacement} ->
      model = Map.fetch!(models, model_id)

      assert model.lifecycle.status == "deprecated"
      assert model.lifecycle.deprecated_at == @deprecated_at
      assert model.lifecycle.retires_at == @retires_at
      assert model.lifecycle.replacement == replacement
      assert Model.lifecycle_status(model) == "deprecated"
      assert Model.effective_status(model, ~U[2026-05-15 18:59:59Z]) == "deprecated"
      assert Model.effective_status(model, ~U[2026-05-15 19:00:00Z]) == "retired"
    end)
  end

  test "Grok 4.3 metadata captures launch details from xAI announcement" do
    model = xai_models() |> Map.fetch!("grok-4.3")

    assert model.limits.context == 1_000_000
    assert model.cost.input == 1.25
    assert model.cost.output == 2.5
    assert model.capabilities.reasoning.enabled == true
    assert model.capabilities.tools.enabled == true
    assert get_in(model.extra, [:constraints, :reasoning_effort]) == "supported"

    assert get_in(model.extra, [:constraints, :reasoning_effort_values]) == [
             "low",
             "medium",
             "high"
           ]
  end

  test "recommended replacement models are present for non-reasoning and image workloads" do
    models = xai_models()
    non_reasoning = Map.fetch!(models, "grok-4.20-non-reasoning")
    image = Map.fetch!(models, "grok-imagine-image")

    assert non_reasoning.capabilities.reasoning.enabled == false
    assert non_reasoning.limits.context == 2_000_000
    assert non_reasoning.cost.input == 2
    assert non_reasoning.cost.output == 6

    assert image.capabilities.chat == false
    assert image.modalities.output == [:image]
  end

  defp xai_models do
    {:ok, data} = Local.load(%{dir: @local_dir})
    xai = Map.fetch!(data, "xai")

    xai.models
    |> Normalize.normalize_models()
    |> Enum.map(&Model.new!/1)
    |> Map.new(&{&1.id, &1})
  end
end
