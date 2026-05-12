defmodule LLMDB.GeminiDeprecationsTest do
  use ExUnit.Case, async: false

  alias LLMDB.{Model, Normalize}
  alias LLMDB.Sources.Local

  @local_dir "priv/llm_db/local"
  @deprecated_at "2026-05-12"
  @retires_at "2026-05-25"

  @expected_lifecycle %{
    "google:gemini-3.1-flash-lite-preview" => "gemini-3.1-flash-lite",
    "google_vertex:gemini-3.1-flash-lite-preview" => "gemini-3.1-flash-lite"
  }

  test "local Gemini overrides codify the 2026-05-25 Flash Lite Preview retirement" do
    models = local_models()

    Enum.each(@expected_lifecycle, fn {model_key, replacement} ->
      model = Map.fetch!(models, model_key)

      assert model.lifecycle.status == "deprecated"
      assert model.lifecycle.deprecated_at == @deprecated_at
      assert model.lifecycle.retires_at == @retires_at
      assert model.lifecycle.replacement == replacement
      assert Model.lifecycle_status(model) == "deprecated"
      assert Model.effective_status(model, ~U[2026-05-24 23:59:59Z]) == "deprecated"
      assert Model.effective_status(model, ~U[2026-05-25 00:00:00Z]) == "retired"
    end)
  end

  defp local_models do
    {:ok, data} = Local.load(%{dir: @local_dir})

    data
    |> Map.values()
    |> Enum.flat_map(& &1.models)
    |> Normalize.normalize_models()
    |> Enum.map(&Model.new!/1)
    |> Map.new(&{"#{&1.provider}:#{&1.id}", &1})
  end
end
