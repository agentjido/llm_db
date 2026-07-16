defmodule LLMDB.Generated.ProviderRegistry do
  @moduledoc false

  @snapshot_path Path.expand("../../../priv/llm_db/snapshot.json", __DIR__)
  @external_resource @snapshot_path

  # Provider atoms are created while compiling the trusted package artifact,
  # never from a runtime snapshot. This preserves the atom-based public API
  # without allowing untrusted JSON to grow the VM atom table.
  @providers (case File.read(@snapshot_path) do
                {:ok, content} ->
                  case Jason.decode(content) do
                    {:ok, %{"providers" => providers}} when is_map(providers) ->
                      providers
                      |> Map.keys()
                      |> Enum.sort()
                      |> Enum.map(fn provider_id ->
                        {provider_id, String.to_atom(provider_id)}
                      end)

                    _other ->
                      []
                  end

                {:error, _reason} ->
                  []
              end)

  @providers_by_name Map.new(@providers)

  @spec fetch(String.t()) :: {:ok, atom()} | :error
  def fetch(provider_id) when is_binary(provider_id) do
    Map.fetch(@providers_by_name, provider_id)
  end

  @spec list() :: [atom()]
  def list, do: Enum.map(@providers, &elem(&1, 1))
end
