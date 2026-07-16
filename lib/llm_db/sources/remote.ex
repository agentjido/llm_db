defmodule LLMDB.Sources.Remote do
  @moduledoc false

  @type pull_result :: :noop | {:ok, String.t()} | {:error, term()}

  @spec pull(String.t(), keyword()) :: pull_result()
  def pull(url, opts) when is_binary(url) and is_list(opts) do
    {cache_path, manifest_path} = paths(url, opts)
    req_opts = request_options(manifest_path, opts)
    request = Keyword.get(opts, :request, &Req.get/2)

    url
    |> request.(req_opts)
    |> handle_response(url, cache_path, manifest_path)
    |> fallback_to_cache(cache_path)
  end

  @spec load(String.t(), keyword()) :: {:ok, term()} | {:error, term()}
  def load(url, opts) when is_binary(url) and is_list(opts) do
    {cache_path, _manifest_path} = paths(url, opts)

    case File.read(cache_path) do
      {:ok, content} -> decode(content)
      {:error, :enoent} -> {:error, :no_cache}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec store(String.t(), term(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def store(url, body, opts) when is_binary(url) and is_list(opts) do
    {cache_path, manifest_path} = paths(url, opts)
    headers = Keyword.get(opts, :response_headers, [])
    include_validators? = Keyword.get(opts, :include_validators, false)
    store_at(url, body, cache_path, manifest_path, headers, include_validators?)
  end

  @spec cache_path(String.t(), keyword()) :: String.t()
  def cache_path(url, opts) when is_binary(url) and is_list(opts) do
    {path, _manifest_path} = paths(url, opts)
    path
  end

  @spec request_json(String.t(), keyword()) :: {:ok, term()} | {:error, term()}
  def request_json(url, req_opts) when is_binary(url) and is_list(req_opts) do
    request = Keyword.get(req_opts, :request, &Req.get/2)
    req_opts = req_opts |> Keyword.delete(:request) |> Keyword.put(:decode_body, false)

    case request.(url, req_opts) do
      {:ok, %Req.Response{status: 200, body: body}} -> decode_body(body)
      {:ok, %Req.Response{status: status}} -> {:error, {:http_status, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp paths(url, opts) do
    cache_dir = Keyword.fetch!(opts, :cache_dir)
    cache_key = Keyword.fetch!(opts, :cache_key)
    hash = url |> sha256() |> binary_part(0, 8)
    basename = "#{cache_key}-#{hash}"

    {
      Path.join(cache_dir, "#{basename}.json"),
      Path.join(cache_dir, "#{basename}.manifest.json")
    }
  end

  defp request_options(manifest_path, opts) do
    req_opts = Keyword.get(opts, :req_opts, [])

    headers =
      conditional_headers(manifest_path) ++
        Keyword.get(opts, :headers, []) ++ Keyword.get(req_opts, :headers, [])

    req_opts
    |> Keyword.put(:headers, headers)
    |> Keyword.put(:decode_body, false)
  end

  defp handle_response({:ok, %Req.Response{status: 304}}, _url, _cache_path, _manifest_path),
    do: :noop

  defp handle_response(
         {:ok, %Req.Response{status: 200, body: body, headers: headers}},
         url,
         cache_path,
         manifest_path
       ) do
    store_at(url, body, cache_path, manifest_path, headers, true)
  end

  defp handle_response({:ok, %Req.Response{status: status}}, _url, _cache_path, _manifest_path),
    do: {:error, {:http_status, status}}

  defp handle_response({:error, reason}, _url, _cache_path, _manifest_path),
    do: {:error, reason}

  defp store_at(url, body, cache_path, manifest_path, headers, include_validators?) do
    with {:ok, decoded} <- decode_body(body),
         {:ok, content} <- Jason.encode(decoded, pretty: true),
         :ok <-
           write_cache(
             cache_path,
             manifest_path,
             content,
             url,
             headers,
             include_validators?
           ) do
      {:ok, cache_path}
    end
  end

  defp decode_body(body) when is_binary(body), do: decode(body)
  defp decode_body(body), do: {:ok, body}

  defp decode(content) do
    case Jason.decode(content) do
      {:ok, decoded} -> {:ok, decoded}
      {:error, reason} -> {:error, {:json_error, reason}}
    end
  end

  defp fallback_to_cache({:error, {:http_status, _status}} = error, _cache_path), do: error

  defp fallback_to_cache({:error, _reason} = error, cache_path) do
    case File.read(cache_path) do
      {:ok, content} -> if match?({:ok, _}, decode(content)), do: {:ok, cache_path}, else: error
      {:error, _reason} -> error
    end
  end

  defp fallback_to_cache(result, _cache_path), do: result

  defp write_cache(cache_path, manifest_path, content, url, headers, include_validators?) do
    manifest =
      %{
        source_url: url,
        sha256: sha256(content),
        size_bytes: byte_size(content),
        downloaded_at: DateTime.utc_now() |> DateTime.to_iso8601()
      }
      |> maybe_put_validators(headers, include_validators?)

    with :ok <- File.mkdir_p(Path.dirname(cache_path)),
         :ok <- atomic_write(cache_path, content),
         {:ok, encoded_manifest} <- Jason.encode(manifest, pretty: true),
         :ok <- atomic_write(manifest_path, encoded_manifest) do
      :ok
    end
  end

  defp maybe_put_validators(manifest, _headers, false), do: manifest

  defp maybe_put_validators(manifest, headers, true) do
    manifest
    |> Map.put(:etag, header(headers, "etag"))
    |> Map.put(:last_modified, header(headers, "last-modified"))
  end

  defp atomic_write(path, content) do
    temporary_path = "#{path}.tmp-#{System.unique_integer([:positive])}"

    with :ok <- File.write(temporary_path, content),
         :ok <- File.rename(temporary_path, path) do
      :ok
    else
      {:error, _reason} = error ->
        File.rm(temporary_path)
        error
    end
  end

  defp conditional_headers(manifest_path) do
    with {:ok, content} <- File.read(manifest_path),
         {:ok, manifest} when is_map(manifest) <- Jason.decode(content) do
      []
      |> maybe_header("if-none-match", Map.get(manifest, "etag"))
      |> maybe_header("if-modified-since", Map.get(manifest, "last_modified"))
    else
      _error -> []
    end
  end

  defp maybe_header(headers, _name, value) when not is_binary(value), do: headers
  defp maybe_header(headers, name, value), do: [{name, value} | headers]

  defp header(headers, name) do
    case Enum.find(headers, fn {key, _value} -> String.downcase(key) == name end) do
      {_key, [value | _rest]} when is_binary(value) -> value
      {_key, value} when is_binary(value) -> value
      _other -> nil
    end
  end

  defp sha256(value) do
    value
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end
end
