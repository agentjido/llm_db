defmodule LLMDB.Sources.RemoteTest do
  use ExUnit.Case, async: false

  alias LLMDB.Sources.Remote

  @url "https://example.test/models.json"
  @remote_opts [cache_dir: "tmp/test/remote", cache_key: "provider"]

  setup do
    File.rm_rf!(Keyword.fetch!(@remote_opts, :cache_dir))
    on_exit(fn -> File.rm_rf!(Keyword.fetch!(@remote_opts, :cache_dir)) end)
  end

  test "writes compatible cache and provenance metadata for a 200 response" do
    request = fn url, opts ->
      send(self(), {:request, url, opts})

      {:ok,
       %Req.Response{
         status: 200,
         body: ~s({"models":[{"id":"model-1"}]}),
         headers: %{"etag" => ["tag-1"], "last-modified" => ["Mon, 01 Jan 2024"]}
       }}
    end

    assert {:ok, cache_path} = Remote.pull(@url, @remote_opts ++ [request: request])
    assert_receive {:request, @url, request_opts}
    assert request_opts[:decode_body] == false

    assert {:ok, %{"models" => [%{"id" => "model-1"}]}} =
             Remote.load(@url, @remote_opts)

    content = File.read!(cache_path)
    manifest = cache_path |> manifest_path() |> File.read!() |> Jason.decode!()

    assert manifest["source_url"] == @url
    assert manifest["etag"] == "tag-1"
    assert manifest["last_modified"] == "Mon, 01 Jan 2024"
    assert manifest["size_bytes"] == byte_size(content)
    assert manifest["sha256"] == sha256(content)
    assert is_binary(manifest["downloaded_at"])
  end

  test "returns noop for a 304 response" do
    request = fn _url, _opts -> {:ok, %Req.Response{status: 304}} end
    assert :noop = Remote.pull(@url, @remote_opts ++ [request: request])
  end

  test "returns transport errors when there is no usable cache" do
    request = fn _url, _opts -> {:error, :timeout} end
    assert {:error, :timeout} = Remote.pull(@url, @remote_opts ++ [request: request])
  end

  test "keeps a valid stale cache on timeout and invalid JSON" do
    cache_path = seed_cache!()
    original = File.read!(cache_path)

    timeout = fn _url, _opts -> {:error, :timeout} end
    assert {:ok, ^cache_path} = Remote.pull(@url, @remote_opts ++ [request: timeout])

    invalid_json = fn _url, _opts ->
      {:ok, %Req.Response{status: 200, body: "not-json", headers: %{}}}
    end

    assert {:ok, ^cache_path} = Remote.pull(@url, @remote_opts ++ [request: invalid_json])
    assert File.read!(cache_path) == original
  end

  test "reports invalid JSON when there is no stale cache" do
    request = fn _url, _opts ->
      {:ok, %Req.Response{status: 200, body: "not-json", headers: %{}}}
    end

    assert {:error, {:json_error, %Jason.DecodeError{}}} =
             Remote.pull(@url, @remote_opts ++ [request: request])
  end

  test "ignores a corrupt manifest and refreshes without conditional headers" do
    cache_path = seed_cache!()
    File.write!(manifest_path(cache_path), "not-json")

    request = fn _url, opts ->
      refute List.keymember?(opts[:headers], "if-none-match", 0)
      refute List.keymember?(opts[:headers], "if-modified-since", 0)

      {:ok, %Req.Response{status: 200, body: ~s({"version":2}), headers: %{}}}
    end

    assert {:ok, ^cache_path} = Remote.pull(@url, @remote_opts ++ [request: request])
    assert {:ok, %{"version" => 2}} = Remote.load(@url, @remote_opts)
  end

  test "adds conditional headers from a valid manifest" do
    cache_path = seed_cache!()

    manifest =
      cache_path
      |> manifest_path()
      |> File.read!()
      |> Jason.decode!()
      |> Map.merge(%{"etag" => "tag-1", "last_modified" => "Mon, 01 Jan 2024"})

    File.write!(manifest_path(cache_path), Jason.encode!(manifest))

    request = fn _url, opts ->
      assert {"if-none-match", "tag-1"} in opts[:headers]
      assert {"if-modified-since", "Mon, 01 Jan 2024"} in opts[:headers]
      {:ok, %Req.Response{status: 304}}
    end

    assert :noop = Remote.pull(@url, @remote_opts ++ [request: request])
  end

  defp seed_cache! do
    request = fn _url, _opts ->
      {:ok, %Req.Response{status: 200, body: ~s({"version":1}), headers: %{}}}
    end

    {:ok, cache_path} = Remote.pull(@url, @remote_opts ++ [request: request])
    cache_path
  end

  defp manifest_path(cache_path),
    do: String.replace_suffix(cache_path, ".json", ".manifest.json")

  defp sha256(content) do
    content
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end
end
