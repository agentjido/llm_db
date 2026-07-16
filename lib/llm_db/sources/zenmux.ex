defmodule LLMDB.Sources.Zenmux do
  @moduledoc """
  Remote source for Zenmux models (https://zenmux.ai/api/v1/models).

  - `pull/1` fetches data from Zenmux API and caches locally
  - `load/1` reads from cached file (no network call)

  ## Options

  - `:url` - API endpoint (default: "https://zenmux.ai/api/v1/models")
  - `:api_key` - Zenmux API key (required, or set `ZENMUX_API_KEY` env var)
  - `:req_opts` - Additional Req options for testing

  ## Configuration

  Cache directory can be configured in application config:

      config :llm_db,
        zenmux_cache_dir: "priv/llm_db/remote"

  Default: `"priv/llm_db/remote"`

  ## Usage

      # Pull remote data and cache (requires API key)
      mix llm_db.pull --source zenmux

      # Load from cache
      {:ok, data} = Zenmux.load(%{})
  """

  @behaviour LLMDB.Source

  alias LLMDB.Sources.Remote

  @default_url "https://zenmux.ai/api/v1/models"
  @default_cache_dir "priv/llm_db/remote"

  @impl true
  def pull(opts) do
    api_key = get_api_key(opts)

    if is_nil(api_key) or api_key == "" do
      {:error, :no_api_key}
    else
      do_pull(opts, api_key)
    end
  end

  defp do_pull(opts, api_key) do
    url = Map.get(opts, :url, @default_url)

    Remote.pull(url,
      cache_dir: get_cache_dir(),
      cache_key: "zenmux",
      headers: build_headers(api_key),
      req_opts: Map.get(opts, :req_opts, [])
    )
  end

  @impl true
  def load(opts) do
    url = Map.get(opts, :url, @default_url)

    case Remote.load(url, cache_dir: get_cache_dir(), cache_key: "zenmux") do
      {:ok, decoded} -> {:ok, transform(decoded)}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Transforms Zenmux API response to canonical Zoi format.
  Zenmux is OpenAI compatible, so the structure mirrors OpenAI's.

  ## Input Format (Expected)

  ```json
  {
    "object": "list",
    "data": [
      {
        "id": "gpt-4",
        "object": "model",
        "created": 1686935002,
        "owned_by": "openai"
      }
    ]
  }
  ```

  ## Output Format (Canonical Zoi)

  ```elixir
  %{
    "zenmux" => %{
      id: :zenmux,
      name: "Zenmux",
      models: [
        %{
          id: "gpt-4",
          provider: :zenmux,
          extra: %{
            created: 1686935002,
            owned_by: "openai"
          }
        }
      ]
    }
  }
  ```
  """
  def transform(content) when is_map(content) do
    models_list =
      content
      |> Map.get("data", [])
      |> Enum.map(&transform_model/1)

    %{
      "zenmux" => %{
        id: :zenmux,
        name: "Zenmux",
        models: models_list
      }
    }
  end

  defp transform_model(model) do
    id = model["id"]

    %{
      id: id,
      provider: :zenmux,
      # Zenmux/OpenAI list often uses ID as name
      name: id,
      extra: %{
        created: model["created"],
        owned_by: model["owned_by"]
      }
    }
    |> map_capabilities(id)
    |> map_modalities(id)
    |> trim_nil_extra()
  end

  defp map_capabilities(model, id) do
    capabilities = %{}

    # Prompt Caching Inference
    capabilities =
      cond do
        String.contains?(id, ["claude", "qwen"]) ->
          Map.put(capabilities, :caching, %{type: "explicit"})

        String.contains?(id, ["gpt", "gemini", "deepseek", "grok"]) ->
          Map.put(capabilities, :caching, %{type: "implicit"})

        true ->
          capabilities
      end

    if map_size(capabilities) > 0 do
      Map.put(model, :capabilities, capabilities)
    else
      model
    end
  end

  defp map_modalities(model, id) do
    cond do
      # Image generation models
      String.contains?(id, ["image-preview", "flash-image"]) ->
        Map.put(model, :modalities, %{
          input: [:text],
          output: [:image]
        })

      # Vision capable models (simplified inference)
      String.contains?(id, ["gpt-4o", "claude-3", "gemini", "vision"]) ->
        Map.put(model, :modalities, %{
          input: [:text, :image],
          output: [:text]
        })

      # Default text models
      true ->
        Map.put(model, :modalities, %{
          input: [:text],
          output: [:text]
        })
    end
  end

  defp trim_nil_extra(model) do
    extra =
      model.extra
      |> Enum.reject(fn {_, v} -> is_nil(v) end)
      |> Map.new()

    if map_size(extra) == 0 do
      Map.drop(model, [:extra])
    else
      Map.put(model, :extra, extra)
    end
  end

  defp get_api_key(opts) do
    Map.get(opts, :api_key) || System.get_env("ZENMUX_API_KEY")
  end

  defp get_cache_dir do
    Application.get_env(:llm_db, :zenmux_cache_dir, @default_cache_dir)
  end

  defp build_headers(api_key) do
    [{"authorization", "Bearer #{api_key}"}]
  end
end
