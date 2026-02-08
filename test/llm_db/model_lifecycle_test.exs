defmodule LLMDB.ModelLifecycleTest do
  use ExUnit.Case, async: true

  alias LLMDB.Model

  describe "lifecycle_status/1" do
    test "returns status from lifecycle field" do
      {:ok, model} =
        Model.new(%{
          id: "model",
          provider: :openai,
          lifecycle: %{status: "deprecated"}
        })

      assert Model.lifecycle_status(model) == "deprecated"
    end

    test "returns nil when no lifecycle" do
      {:ok, model} =
        Model.new(%{
          id: "model",
          provider: :openai
        })

      assert Model.lifecycle_status(model) == nil
    end

    test "returns nil when lifecycle has no status" do
      {:ok, model} =
        Model.new(%{
          id: "model",
          provider: :openai,
          lifecycle: %{replacement: "new-model"}
        })

      assert Model.lifecycle_status(model) == nil
    end
  end

  describe "effective_status/2" do
    test "returns declared status when no dates" do
      {:ok, model} =
        Model.new(%{
          id: "model",
          provider: :openai,
          lifecycle: %{status: "deprecated"}
        })

      assert Model.effective_status(model) == "deprecated"
    end

    test "returns 'active' for model with no lifecycle" do
      {:ok, model} =
        Model.new(%{
          id: "model",
          provider: :openai
        })

      assert Model.effective_status(model) == "active"
    end

    test "auto-advances to deprecated based on deprecated_at date" do
      {:ok, model} =
        Model.new(%{
          id: "model",
          provider: :openai,
          lifecycle: %{status: "active", deprecated_at: "2025-01-01T00:00:00Z"}
        })

      before_deprecation = ~U[2024-12-01 00:00:00Z]
      after_deprecation = ~U[2025-02-01 00:00:00Z]

      assert Model.effective_status(model, before_deprecation) == "active"
      assert Model.effective_status(model, after_deprecation) == "deprecated"
    end

    test "auto-advances to retired based on retires_at date" do
      {:ok, model} =
        Model.new(%{
          id: "model",
          provider: :openai,
          lifecycle: %{
            status: "active",
            deprecated_at: "2025-01-01T00:00:00Z",
            retires_at: "2025-06-01T00:00:00Z"
          }
        })

      before_all = ~U[2024-12-01 00:00:00Z]
      after_deprecation = ~U[2025-03-01 00:00:00Z]
      after_retirement = ~U[2025-07-01 00:00:00Z]

      assert Model.effective_status(model, before_all) == "active"
      assert Model.effective_status(model, after_deprecation) == "deprecated"
      assert Model.effective_status(model, after_retirement) == "retired"
    end

    test "declared 'retired' status takes precedence over dates" do
      {:ok, model} =
        Model.new(%{
          id: "model",
          provider: :openai,
          lifecycle: %{status: "retired"}
        })

      assert Model.effective_status(model, ~U[2020-01-01 00:00:00Z]) == "retired"
    end

    test "handles date-only strings (without time)" do
      {:ok, model} =
        Model.new(%{
          id: "model",
          provider: :openai,
          lifecycle: %{deprecated_at: "2025-01-01"}
        })

      assert Model.effective_status(model, ~U[2025-02-01 00:00:00Z]) == "deprecated"
    end

    test "falls back to deprecated boolean when no lifecycle" do
      {:ok, model} =
        Model.new(%{
          id: "model",
          provider: :openai,
          deprecated: true
        })

      assert Model.effective_status(model) == "deprecated"
    end

    test "falls back to retired boolean when no lifecycle" do
      {:ok, model} =
        Model.new(%{
          id: "model",
          provider: :openai,
          retired: true
        })

      assert Model.effective_status(model) == "retired"
    end

    test "retired boolean takes precedence over deprecated boolean" do
      {:ok, model} =
        Model.new(%{
          id: "model",
          provider: :openai,
          deprecated: true,
          retired: true
        })

      assert Model.effective_status(model) == "retired"
    end

    test "real-world scenario: dall-e-3 lifecycle progression" do
      {:ok, model} =
        Model.new(%{
          id: "dall-e-3",
          provider: :openai,
          lifecycle: %{
            status: "deprecated",
            deprecated_at: "2025-05-12",
            retires_at: "2026-05-12",
            replacement: "gpt-image-1.5"
          }
        })

      assert Model.effective_status(model, ~U[2025-06-01 00:00:00Z]) == "deprecated"
      assert Model.effective_status(model, ~U[2026-06-01 00:00:00Z]) == "retired"
      assert Model.deprecated?(model, ~U[2025-06-01 00:00:00Z]) == true
      assert Model.retired?(model, ~U[2025-06-01 00:00:00Z]) == false
      assert Model.retired?(model, ~U[2026-06-01 00:00:00Z]) == true
    end
  end

  describe "deprecated?/2" do
    test "returns true for deprecated status" do
      {:ok, model} =
        Model.new(%{
          id: "model",
          provider: :openai,
          lifecycle: %{status: "deprecated"}
        })

      assert Model.deprecated?(model) == true
    end

    test "returns true for retired status (retired implies deprecated)" do
      {:ok, model} =
        Model.new(%{
          id: "model",
          provider: :openai,
          lifecycle: %{status: "retired"}
        })

      assert Model.deprecated?(model) == true
    end

    test "returns false for active status" do
      {:ok, model} =
        Model.new(%{
          id: "model",
          provider: :openai,
          lifecycle: %{status: "active"}
        })

      assert Model.deprecated?(model) == false
    end

    test "respects deprecated_at date" do
      {:ok, model} =
        Model.new(%{
          id: "model",
          provider: :openai,
          lifecycle: %{deprecated_at: "2025-06-01T00:00:00Z"}
        })

      assert Model.deprecated?(model, ~U[2025-05-01 00:00:00Z]) == false
      assert Model.deprecated?(model, ~U[2025-07-01 00:00:00Z]) == true
    end

    test "returns true for boolean-only deprecated model (no lifecycle)" do
      {:ok, model} =
        Model.new(%{
          id: "model",
          provider: :openai,
          deprecated: true
        })

      assert Model.deprecated?(model) == true
    end
  end

  describe "retired?/2" do
    test "returns true for retired status" do
      {:ok, model} =
        Model.new(%{
          id: "model",
          provider: :openai,
          lifecycle: %{status: "retired"}
        })

      assert Model.retired?(model) == true
    end

    test "returns false for deprecated status" do
      {:ok, model} =
        Model.new(%{
          id: "model",
          provider: :openai,
          lifecycle: %{status: "deprecated"}
        })

      assert Model.retired?(model) == false
    end

    test "respects retires_at date" do
      {:ok, model} =
        Model.new(%{
          id: "model",
          provider: :openai,
          lifecycle: %{retires_at: "2025-06-01T00:00:00Z"}
        })

      assert Model.retired?(model, ~U[2025-05-01 00:00:00Z]) == false
      assert Model.retired?(model, ~U[2025-07-01 00:00:00Z]) == true
    end

    test "returns true for boolean-only retired model (no lifecycle)" do
      {:ok, model} =
        Model.new(%{
          id: "model",
          provider: :openai,
          retired: true
        })

      assert Model.retired?(model) == true
    end
  end

  describe "lifecycle schema validation" do
    test "accepts all lifecycle fields" do
      {:ok, model} =
        Model.new(%{
          id: "model",
          provider: :openai,
          lifecycle: %{
            status: "deprecated",
            deprecated_at: "2025-01-01",
            retires_at: "2025-06-01",
            replacement: "new-model"
          }
        })

      assert model.lifecycle.status == "deprecated"
      assert model.lifecycle.deprecated_at == "2025-01-01"
      assert model.lifecycle.retires_at == "2025-06-01"
      assert model.lifecycle.replacement == "new-model"
    end

    test "rejects invalid status" do
      assert {:error, _} =
               Model.new(%{
                 id: "model",
                 provider: :openai,
                 lifecycle: %{status: "invalid"}
               })
    end
  end

  describe "retired field" do
    test "retired defaults to false" do
      {:ok, model} =
        Model.new(%{
          id: "model",
          provider: :openai
        })

      assert model.retired == false
    end

    test "can set retired explicitly" do
      {:ok, model} =
        Model.new(%{
          id: "model",
          provider: :openai,
          retired: true
        })

      assert model.retired == true
    end
  end
end
