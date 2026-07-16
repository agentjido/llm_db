defmodule LLMDB.Sources.OpenAI do
  @moduledoc """
  Remote source for OpenAI models (https://api.openai.com/v1/models).

  - `pull/1` fetches data from OpenAI API and caches locally
  - `load/1` reads from cached file (no network call)

  ## Options

  - `:url` - API endpoint (default: "https://api.openai.com/v1/models")
  - `:api_key` - OpenAI API key (required, or set `OPENAI_API_KEY` env var)
  - `:organization` - Optional OpenAI organization ID
  - `:project` - Optional OpenAI project ID
  - `:req_opts` - Additional Req options for testing

  ## Configuration

  Cache directory can be configured in application config:

      config :llm_db,
        openai_cache_dir: "priv/llm_db/remote"

  Default: `"priv/llm_db/remote"`

  ## Usage

      # Pull remote data and cache (requires API key)
      mix llm_db.pull --source openai

      # Load from cache
      {:ok, data} = OpenAI.load(%{})
  """

  @behaviour LLMDB.Source

  alias LLMDB.Sources.Remote

  @default_url "https://api.openai.com/v1/models"
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
      cache_key: "openai",
      headers: build_headers(api_key, opts),
      req_opts: Map.get(opts, :req_opts, [])
    )
  end

  @impl true
  def load(opts) do
    url = Map.get(opts, :url, @default_url)

    case Remote.load(url, cache_dir: get_cache_dir(), cache_key: "openai") do
      {:ok, decoded} -> {:ok, transform(decoded)}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Transforms OpenAI API response to canonical Zoi format.

  ## Input Format (OpenAI)

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
    "openai" => %{
      id: :openai,
      name: "OpenAI",
      models: [
        %{
          id: "gpt-4",
          provider: :openai,
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
      "openai" => %{
        id: :openai,
        name: "OpenAI",
        models: models_list
      }
    }
  end

  defp transform_model(model) do
    %{
      id: model["id"],
      provider: :openai,
      extra: %{
        created: model["created"],
        owned_by: model["owned_by"]
      }
    }
  end

  defp get_api_key(opts) do
    Map.get(opts, :api_key) || System.get_env("OPENAI_API_KEY")
  end

  defp get_cache_dir do
    Application.get_env(:llm_db, :openai_cache_dir, @default_cache_dir)
  end

  defp build_headers(api_key, opts) do
    headers = [{"authorization", "Bearer #{api_key}"}]

    headers =
      case Map.get(opts, :organization) do
        nil -> headers
        org -> [{"openai-organization", org} | headers]
      end

    case Map.get(opts, :project) do
      nil -> headers
      project -> [{"openai-project", project} | headers]
    end
  end
end
