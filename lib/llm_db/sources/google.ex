defmodule LLMDB.Sources.Google do
  @moduledoc """
  Remote source for Google Gemini models (https://generativelanguage.googleapis.com/v1beta/models).

  - `pull/1` fetches data from Google Gemini API and caches locally
  - `load/1` reads from cached file (no network call)

  ## Options

  - `:url` - API endpoint (default: "https://generativelanguage.googleapis.com/v1beta/models")
  - `:api_key` - Google API key (required, or set `GOOGLE_API_KEY` or `GEMINI_API_KEY` env var)
  - `:page_size` - Items per page (1-1000, default: 1000 to fetch all)
  - `:req_opts` - Additional Req options for testing

  ## Configuration

  Cache directory can be configured in application config:

      config :llm_db,
        google_cache_dir: "priv/llm_db/remote"

  Default: `"priv/llm_db/remote"`

  ## Usage

      # Pull remote data and cache (requires API key)
      mix llm_db.pull --source google

      # Load from cache
      {:ok, data} = Google.load(%{})
  """

  @behaviour LLMDB.Source

  alias LLMDB.Sources.Remote

  @default_url "https://generativelanguage.googleapis.com/v1beta/models"
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
    req_opts = Map.get(opts, :req_opts, [])

    headers = build_headers(api_key)
    headers = headers ++ Keyword.get(req_opts, :headers, [])
    req_opts = Keyword.put(req_opts, :headers, headers)

    page_size = Map.get(opts, :page_size, 1000)
    all_models = fetch_all_pages(url, req_opts, page_size, [])

    case all_models do
      {:ok, models} ->
        Remote.store(url, %{"models" => models},
          cache_dir: get_cache_dir(),
          cache_key: "google"
        )

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def load(opts) do
    url = Map.get(opts, :url, @default_url)

    case Remote.load(url, cache_dir: get_cache_dir(), cache_key: "google") do
      {:ok, decoded} -> {:ok, transform(decoded)}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Transforms Google Gemini API response to canonical Zoi format.

  ## Input Format (Google)

  ```json
  {
    "models": [
      {
        "name": "models/gemini-2.0-flash-exp",
        "baseModelId": "models/gemini-2.0-flash",
        "version": "001",
        "displayName": "Gemini 2.0 Flash",
        "description": "...",
        "inputTokenLimit": 1048576,
        "outputTokenLimit": 8192,
        "supportedGenerationMethods": ["generateContent"],
        "thinking": false
      }
    ]
  }
  ```

  ## Output Format (Canonical Zoi)

  ```elixir
  %{
    "google" => %{
      id: :google,
      name: "Google",
      models: [
        %{
          id: "gemini-2.0-flash-exp",
          provider: :google,
          name: "Gemini 2.0 Flash",
          limits: %{
            context: 1048576,
            output: 8192
          },
          extra: %{
            base_model_id: "models/gemini-2.0-flash",
            version: "001",
            description: "...",
            supported_generation_methods: ["generateContent"],
            thinking: false
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
      |> Map.get("models", [])
      |> Enum.map(&transform_model/1)

    %{
      "google" => %{
        id: :google,
        name: "Google",
        models: models_list
      }
    }
  end

  defp transform_model(model) do
    model_id = extract_model_id(model["name"])

    base = %{
      id: model_id,
      provider: :google
    }

    base =
      if display_name = model["displayName"] do
        Map.put(base, :name, display_name)
      else
        base
      end

    base = map_limits(base, model)
    base = map_extra(base, model)

    base
  end

  defp extract_model_id(name) when is_binary(name) do
    case String.split(name, "/") do
      ["models", model_id] -> model_id
      _ -> name
    end
  end

  defp extract_model_id(name), do: name

  defp map_limits(model, source) do
    limits =
      %{}
      |> put_if_present(:context, source["inputTokenLimit"])
      |> put_if_present(:output, source["outputTokenLimit"])

    if map_size(limits) > 0 do
      Map.put(model, :limits, limits)
    else
      model
    end
  end

  defp map_extra(model, source) do
    extra =
      source
      |> Map.drop([
        "name",
        "displayName",
        "inputTokenLimit",
        "outputTokenLimit"
      ])
      |> Enum.reduce(%{}, fn {k, v}, acc ->
        atom_key =
          k
          |> Macro.underscore()
          |> String.to_atom()

        Map.put(acc, atom_key, v)
      end)

    if map_size(extra) > 0 do
      Map.put(model, :extra, extra)
    else
      model
    end
  end

  defp fetch_all_pages(url, req_opts, page_size, acc) do
    params = [pageSize: page_size]
    req_opts = Keyword.put(req_opts, :params, params)

    case Remote.request_json(url, req_opts) do
      {:ok, body} when is_map(body) ->
        models = Map.get(body, "models", [])
        next_page_token = Map.get(body, "nextPageToken")
        new_acc = acc ++ models

        if next_page_token && not Enum.empty?(models) do
          req_opts =
            Keyword.put(req_opts, :params, pageSize: page_size, pageToken: next_page_token)

          fetch_all_pages(url, req_opts, page_size, new_acc)
        else
          {:ok, new_acc}
        end

      {:ok, _body} ->
        {:error, :invalid_shape}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp put_if_present(map, _key, nil), do: map
  defp put_if_present(map, key, value), do: Map.put(map, key, value)

  defp get_api_key(opts) do
    Map.get(opts, :api_key) ||
      System.get_env("GOOGLE_API_KEY") ||
      System.get_env("GEMINI_API_KEY")
  end

  defp get_cache_dir do
    Application.get_env(:llm_db, :google_cache_dir, @default_cache_dir)
  end

  defp build_headers(api_key) do
    [{"x-goog-api-key", api_key}]
  end
end
