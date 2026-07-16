defmodule LLMDB.CatalogBenchmark do
  @moduledoc false

  def run do
    measure("cold load", 3, fn ->
      LLMDB.Store.clear!()
      {:ok, _snapshot} = LLMDB.load()
    end)

    measure("no-op reload", 5, fn ->
      {:ok, _snapshot} = LLMDB.load()
    end)

    measure("warm lookup", 100_000, fn ->
      {:ok, _model} = LLMDB.model(:openai, "gpt-4o-mini")
    end)
  end

  defp measure(label, iterations, fun) do
    {microseconds, _result} = :timer.tc(fn -> Enum.each(1..iterations, fn _ -> fun.() end) end)
    average = microseconds / iterations
    IO.puts("#{label}: #{Float.round(average, 2)} µs/op (#{iterations} iterations)")
  end
end

LLMDB.CatalogBenchmark.run()
