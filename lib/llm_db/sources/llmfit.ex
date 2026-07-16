defmodule LLMDB.Sources.Llmfit do
  @moduledoc """
  Sidecar source for llmfit open-weight metadata.

  This module is intentionally **not** a primary catalog source. It is used to:

  - `pull/1` fetch and cache llmfit's `hf_models.json`
  - `load_index/1` build a lookup index by Hugging Face repo ID for enrichment

  `load/1` returns an empty canonical map so this source can participate in
  generic source workflows without injecting non-canonical providers/models.
  """

  @behaviour LLMDB.Source

  alias LLMDB.Sources.Remote

  @default_url "https://raw.githubusercontent.com/AlexsJones/llmfit/main/llmfit-core/data/hf_models.json"
  @default_cache_dir "priv/llm_db/upstream"

  @valid_pipeline_tags MapSet.new([
                         "text-generation",
                         "image-text-to-text",
                         "feature-extraction"
                       ])

  # Keep enrichment data high-signal by rejecting obvious test/dummy repos.
  @noise_repo_pattern ~r/(?:peft-internal-testing|optimum-intel-internal-testing|nm-testing|tiny-random|unit-test|dummy)/i

  # 50M param floor avoids tiny random/unit-test artifacts.
  @min_parameters 50_000_000

  @impl true
  def pull(opts) do
    url = Map.get(opts, :url, @default_url)

    Remote.pull(url,
      cache_dir: get_cache_dir(),
      cache_key: "llmfit",
      req_opts: Map.get(opts, :req_opts, [])
    )
  end

  @impl true
  def load(_opts), do: {:ok, %{}}

  @doc """
  Load raw llmfit metadata list from cache.
  """
  @spec load_raw(map()) :: {:ok, [map()]} | {:error, term()}
  def load_raw(opts \\ %{}) do
    url = Map.get(opts, :url, @default_url)

    case Remote.load(url, cache_dir: get_cache_dir(), cache_key: "llmfit") do
      {:ok, decoded} when is_list(decoded) -> {:ok, decoded}
      {:ok, _other} -> {:error, :invalid_shape}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Build an enrichment index keyed by Hugging Face repo ID (`org/model`).
  """
  @spec load_index(map()) :: {:ok, %{optional(String.t()) => map()}} | {:error, term()}
  def load_index(opts \\ %{}) do
    with {:ok, rows} <- load_raw(opts) do
      {:ok, index_rows(rows)}
    end
  end

  # Private helpers

  defp get_cache_dir do
    Application.get_env(:llm_db, :llmfit_cache_dir, @default_cache_dir)
  end

  defp index_rows(rows) do
    Enum.reduce(rows, %{}, fn row, acc ->
      with true <- is_map(row),
           repo_id when is_binary(repo_id) <- Map.get(row, "name"),
           true <- eligible_row?(row),
           normalized <- normalize_row(row) do
        Map.put(acc, repo_id, normalized)
      else
        _ -> acc
      end
    end)
  end

  defp eligible_row?(row) do
    repo_id = Map.get(row, "name", "")
    params = Map.get(row, "parameters_raw", 0)
    pipeline = Map.get(row, "pipeline_tag")

    is_binary(repo_id) and
      not String.match?(repo_id, @noise_repo_pattern) and
      is_integer(params) and params >= @min_parameters and
      MapSet.member?(@valid_pipeline_tags, pipeline)
  end

  defp normalize_row(row) do
    memory =
      %{
        min_ram_gb: Map.get(row, "min_ram_gb"),
        recommended_ram_gb: Map.get(row, "recommended_ram_gb"),
        min_vram_gb: Map.get(row, "min_vram_gb")
      }
      |> drop_nil_values()

    moe =
      if Map.get(row, "is_moe") == true do
        %{
          is_moe: true,
          num_experts: Map.get(row, "num_experts"),
          active_experts: Map.get(row, "active_experts"),
          active_parameters: Map.get(row, "active_parameters")
        }
        |> drop_nil_values()
      else
        nil
      end

    gguf_sources =
      case Map.get(row, "gguf_sources") do
        sources when is_list(sources) ->
          Enum.map(sources, fn source ->
            %{
              repo: Map.get(source, "repo"),
              provider: Map.get(source, "provider")
            }
            |> drop_nil_values()
          end)

        _ ->
          []
      end

    %{
      source: "llmfit",
      model_id: Map.get(row, "name"),
      provider: Map.get(row, "provider"),
      parameter_count: Map.get(row, "parameter_count"),
      parameters_raw: Map.get(row, "parameters_raw"),
      quantization: Map.get(row, "quantization"),
      context_length: Map.get(row, "context_length"),
      use_case: Map.get(row, "use_case"),
      pipeline_tag: Map.get(row, "pipeline_tag"),
      architecture: Map.get(row, "architecture"),
      hf_downloads: Map.get(row, "hf_downloads"),
      hf_likes: Map.get(row, "hf_likes"),
      release_date: Map.get(row, "release_date"),
      discovered: Map.get(row, "_discovered") == true,
      memory: if(map_size(memory) > 0, do: memory, else: nil),
      gguf_sources: gguf_sources,
      moe: moe
    }
    |> drop_nil_values()
  end

  defp drop_nil_values(map) when is_map(map) do
    map
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end
end
