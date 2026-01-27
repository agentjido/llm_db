defmodule LLMDB.PricingTest do
  use ExUnit.Case, async: true

  alias LLMDB.Pricing

  test "builds pricing components from cost when missing" do
    model = %LLMDB.Model{
      id: "m1",
      provider: :test,
      cost: %{input: 1.0, output: 2.0, cache_read: 0.5, cache_write: 0.8}
    }

    [updated] = Pricing.apply_cost_components([model])

    ids = Enum.map(updated.pricing.components, & &1.id) |> Enum.sort()

    assert ids == [
             "token.cache_read",
             "token.cache_write",
             "token.input",
             "token.output"
           ]
  end

  test "keeps explicit pricing component overrides over cost-derived components" do
    model = %LLMDB.Model{
      id: "m1",
      provider: :test,
      cost: %{input: 1.0, output: 2.0},
      pricing: %{
        components: [
          %{id: "token.output", kind: "token", unit: "token", per: 1_000_000, rate: 3.0}
        ]
      }
    }

    [updated] = Pricing.apply_cost_components([model])

    output =
      Enum.find(updated.pricing.components, fn component -> component.id == "token.output" end)

    assert output.rate == 3.0
  end

  test "applies provider defaults when model has no pricing" do
    provider = %LLMDB.Provider{
      id: :test,
      pricing_defaults: %{
        currency: "USD",
        components: [
          %{id: "token.input", kind: "token", unit: "token", per: 1_000_000, rate: 1.0}
        ]
      }
    }

    model = %LLMDB.Model{id: "m1", provider: :test, pricing: nil}

    [updated] = Pricing.apply_provider_defaults([provider], [model])
    assert updated.pricing.currency == "USD"
    assert [%{id: "token.input"}] = updated.pricing.components
  end

  test "merges provider defaults with model overrides by id" do
    provider = %LLMDB.Provider{
      id: :test,
      pricing_defaults: %{
        currency: "USD",
        components: [
          %{id: "token.input", kind: "token", unit: "token", per: 1_000_000, rate: 1.0},
          %{id: "token.output", kind: "token", unit: "token", per: 1_000_000, rate: 2.0}
        ]
      }
    }

    model = %LLMDB.Model{
      id: "m1",
      provider: :test,
      pricing: %{
        merge: "merge_by_id",
        components: [
          %{id: "token.output", kind: "token", unit: "token", per: 1_000_000, rate: 3.0}
        ]
      }
    }

    [updated] = Pricing.apply_provider_defaults([provider], [model])

    rates =
      updated.pricing.components
      |> Enum.map(fn c -> {c.id, c.rate} end)
      |> Map.new()

    assert rates["token.input"] == 1.0
    assert rates["token.output"] == 3.0
  end

  test "replace merge keeps only model pricing" do
    provider = %LLMDB.Provider{
      id: :test,
      pricing_defaults: %{
        currency: "USD",
        components: [
          %{id: "token.input", kind: "token", unit: "token", per: 1_000_000, rate: 1.0}
        ]
      }
    }

    model = %LLMDB.Model{
      id: "m1",
      provider: :test,
      pricing: %{
        merge: "replace",
        components: [
          %{id: "token.output", kind: "token", unit: "token", per: 1_000_000, rate: 3.0}
        ]
      }
    }

    [updated] = Pricing.apply_provider_defaults([provider], [model])

    assert [%{id: "token.output"}] = updated.pricing.components
  end
end
