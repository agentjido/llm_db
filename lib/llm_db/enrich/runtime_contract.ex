defmodule LLMDB.Enrich.RuntimeContract do
  @moduledoc false

  alias LLMDB.ExecutionContract

  defdelegate enrich(providers, models), to: ExecutionContract
  defdelegate enrich_for_validation(providers, models), to: ExecutionContract
  defdelegate enrich_provider(provider), to: ExecutionContract
  defdelegate enrich_model(model, provider), to: ExecutionContract
  defdelegate publish_provider(provider), to: ExecutionContract
end
