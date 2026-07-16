defmodule LLMDB.Schema.Pricing do
  @moduledoc false

  @component Zoi.object(%{
               id: Zoi.string(),
               kind:
                 Zoi.enum([
                   "token",
                   "tool",
                   "image",
                   "storage",
                   "request",
                   "other"
                 ])
                 |> Zoi.nullish(),
               unit:
                 Zoi.enum([
                   "token",
                   "call",
                   "query",
                   "session",
                   "gb_day",
                   "image",
                   "source",
                   "other"
                 ])
                 |> Zoi.nullish(),
               per: Zoi.integer() |> Zoi.min(1) |> Zoi.nullish(),
               rate: Zoi.number() |> Zoi.nullish(),
               meter: Zoi.string() |> Zoi.nullish(),
               tool: Zoi.union([Zoi.atom(), Zoi.string()]) |> Zoi.nullish(),
               size_class: Zoi.string() |> Zoi.nullish(),
               multiplier: Zoi.number() |> Zoi.nullish(),
               derives_from: Zoi.string() |> Zoi.nullish(),
               applies_to: Zoi.array(Zoi.string()) |> Zoi.nullish(),
               applies_when: Zoi.map() |> Zoi.nullish(),
               excludes_when: Zoi.map() |> Zoi.nullish(),
               mode: Zoi.string() |> Zoi.nullish(),
               charge_scope: Zoi.string() |> Zoi.nullish(),
               source: Zoi.string() |> Zoi.nullish(),
               notes: Zoi.string() |> Zoi.nullish()
             })

  @base_fields %{
    currency: Zoi.string() |> Zoi.nullish(),
    components: Zoi.array(@component) |> Zoi.default([])
  }

  @doc false
  def schema(extra_fields \\ %{}) when is_map(extra_fields) do
    @base_fields
    |> Map.merge(extra_fields)
    |> Zoi.object()
  end
end
