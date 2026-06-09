defmodule LLMDB.Sources.Anthropic do
  @moduledoc """
  Remote source for Anthropic models (https://api.anthropic.com/v1/models).

  - `pull/1` fetches data from Anthropic API and caches locally
  - `load/1` reads from cached file (no network call)

  ## Options

  - `:url` - API endpoint (default: "https://api.anthropic.com/v1/models")
  - `:api_key` - Anthropic API key (required, or set `ANTHROPIC_API_KEY` env var)
  - `:anthropic_version` - API version (default: "2023-06-01")
  - `:beta` - Optional beta versions list
  - `:limit` - Items per page (1-1000, default: 1000 to fetch all)
  - `:req_opts` - Additional Req options for testing

  ## Configuration

  Cache directory can be configured in application config:

      config :llm_db,
        anthropic_cache_dir: "priv/llm_db/remote"

  Default: `"priv/llm_db/remote"`

  ## Usage

      # Pull remote data and cache (requires API key)
      mix llm_db.pull --source anthropic

      # Load from cache
      {:ok, data} = Anthropic.load(%{})
  """

  @behaviour LLMDB.Source

  @default_url "https://api.anthropic.com/v1/models"
  @default_cache_dir "priv/llm_db/remote"
  @default_version "2023-06-01"

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
    cache_dir = get_cache_dir()
    cache_path = cache_path(url, cache_dir)
    manifest_path = manifest_path(url, cache_dir)
    req_opts = Map.get(opts, :req_opts, [])

    headers = build_headers(api_key, opts)
    headers = headers ++ Keyword.get(req_opts, :headers, [])
    req_opts = Keyword.put(req_opts, :headers, headers)

    limit = Map.get(opts, :limit, 1000)
    all_models = fetch_all_pages(url, req_opts, limit, [])

    case all_models do
      {:ok, models} ->
        response = %{"data" => models}
        bin = Jason.encode!(response, pretty: true)
        write_cache(cache_path, manifest_path, bin, url, [])
        {:ok, cache_path}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def load(opts) do
    url = Map.get(opts, :url, @default_url)
    cache_dir = get_cache_dir()
    cache_path = cache_path(url, cache_dir)

    case File.read(cache_path) do
      {:ok, bin} ->
        case Jason.decode(bin) do
          {:ok, decoded} -> {:ok, transform(decoded)}
          {:error, err} -> {:error, {:json_error, err}}
        end

      {:error, :enoent} ->
        {:error, :no_cache}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Transforms Anthropic API response to canonical Zoi format.

  ## Input Format (Anthropic)

  ```json
  {
    "data": [
      {
        "id": "claude-sonnet-4-20250514",
        "type": "model",
        "display_name": "Claude Sonnet 4",
        "created_at": "2025-02-19T00:00:00Z"
      }
    ]
  }
  ```

  ## Output Format (Canonical Zoi)

  ```elixir
  %{
    "anthropic" => %{
      id: :anthropic,
      name: "Anthropic",
      models: [
        %{
          id: "claude-sonnet-4-20250514",
          provider: :anthropic,
          name: "Claude Sonnet 4",
          limits: %{
            context: 200000,
            output: 64000
          },
          modalities: %{
            input: [:text, :image, :pdf],
            output: [:text]
          },
          extra: %{
            type: "model",
            created_at: "2025-02-19T00:00:00Z"
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
      "anthropic" => %{
        id: :anthropic,
        name: "Anthropic",
        models: models_list
      }
    }
  end

  defp transform_model(model) do
    base = %{
      id: model["id"],
      provider: :anthropic
    }

    base =
      if display_name = model["display_name"] do
        Map.put(base, :name, display_name)
      else
        base
      end

    base =
      base
      |> map_limits(model)
      |> map_modalities(model["capabilities"])
      |> map_capabilities(model["capabilities"])

    extra =
      model
      |> Map.drop(["id", "display_name", "max_input_tokens", "max_tokens"])
      |> Enum.reduce(%{}, fn {k, v}, acc -> Map.put(acc, String.to_atom(k), v) end)

    if map_size(extra) > 0 do
      Map.put(base, :extra, extra)
    else
      base
    end
  end

  defp map_limits(model, source_model) do
    limits =
      %{}
      |> put_if_valid_limit(:context, source_model["max_input_tokens"])
      |> put_if_valid_limit(:output, source_model["max_tokens"])

    if map_size(limits) > 0 do
      Map.put(model, :limits, limits)
    else
      model
    end
  end

  defp map_modalities(model, capabilities) when is_map(capabilities) do
    input =
      [:text]
      |> maybe_append(:image, supported?(capabilities, "image_input"))
      |> maybe_append(:pdf, supported?(capabilities, "pdf_input"))

    Map.put(model, :modalities, %{input: input, output: [:text]})
  end

  defp map_modalities(model, _capabilities), do: model

  defp map_capabilities(model, capabilities) when is_map(capabilities) do
    canonical =
      %{}
      |> put_if_true(:reasoning, %{enabled: true}, supported?(capabilities, "thinking"))
      |> put_if_true(
        :json,
        %{native: false, schema: true, strict: false},
        supported?(capabilities, "structured_outputs")
      )

    if map_size(canonical) > 0 do
      Map.put(model, :capabilities, canonical)
    else
      model
    end
  end

  defp map_capabilities(model, _capabilities), do: model

  defp supported?(capabilities, key) do
    case get_in(capabilities, [key, "supported"]) do
      true -> true
      _other -> false
    end
  end

  defp maybe_append(list, value, true), do: list ++ [value]
  defp maybe_append(list, _value, _supported?), do: list

  defp put_if_true(map, key, value, true), do: Map.put(map, key, value)
  defp put_if_true(map, _key, _value, _flag), do: map

  defp put_if_valid_limit(map, key, value) when is_integer(value) and value > 0 do
    Map.put(map, key, value)
  end

  defp put_if_valid_limit(map, _key, _value), do: map

  defp fetch_all_pages(url, req_opts, limit, acc) do
    params = [limit: limit]

    params =
      case acc do
        [] -> params
        [%{"id" => last_id} | _] -> [{:after_id, last_id} | params]
      end

    req_opts = Keyword.put(req_opts, :params, params)

    case Req.get(url, req_opts) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        data = Map.get(body, "data", [])
        has_more = Map.get(body, "has_more", false)
        new_acc = acc ++ data

        if has_more and not Enum.empty?(data) do
          fetch_all_pages(url, req_opts, limit, new_acc)
        else
          {:ok, new_acc}
        end

      {:ok, %Req.Response{status: status}} when status >= 400 ->
        {:error, {:http_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp get_api_key(opts) do
    Map.get(opts, :api_key) || System.get_env("ANTHROPIC_API_KEY")
  end

  defp get_cache_dir do
    Application.get_env(:llm_db, :anthropic_cache_dir, @default_cache_dir)
  end

  defp cache_path(url, cache_dir) do
    hash = :crypto.hash(:sha256, url) |> Base.encode16(case: :lower) |> binary_part(0, 8)
    Path.join(cache_dir, "anthropic-#{hash}.json")
  end

  defp manifest_path(url, cache_dir) do
    hash = :crypto.hash(:sha256, url) |> Base.encode16(case: :lower) |> binary_part(0, 8)
    Path.join(cache_dir, "anthropic-#{hash}.manifest.json")
  end

  defp build_headers(api_key, opts) do
    version = Map.get(opts, :anthropic_version, @default_version)
    headers = [{"x-api-key", api_key}, {"anthropic-version", version}]

    case Map.get(opts, :beta) do
      nil ->
        headers

      beta when is_list(beta) ->
        beta_value = Enum.join(beta, ",")
        [{"anthropic-beta", beta_value} | headers]

      beta when is_binary(beta) ->
        [{"anthropic-beta", beta} | headers]
    end
  end

  defp write_cache(cache_path, manifest_path, content, url, _headers) do
    File.mkdir_p!(Path.dirname(cache_path))
    File.write!(cache_path, content)

    manifest = %{
      source_url: url,
      sha256: :crypto.hash(:sha256, content) |> Base.encode16(case: :lower),
      size_bytes: byte_size(content),
      downloaded_at: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    File.write!(manifest_path, Jason.encode!(manifest, pretty: true))
  end
end
