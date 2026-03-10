defmodule LLMDB.Sources.LlmfitTest do
  use ExUnit.Case, async: false

  alias LLMDB.Sources.Llmfit

  setup do
    File.rm_rf!("tmp/test/upstream")

    on_exit(fn ->
      File.rm_rf!("tmp/test/upstream")
    end)

    :ok
  end

  defp make_plug(fun) do
    fn conn ->
      fun.(conn)
    end
  end

  describe "pull/1" do
    test "fetches and caches data on 200 response" do
      test_url = "https://test.example.com/llmfit.json"

      body = [
        %{
          "name" => "Qwen/Qwen2.5-7B-Instruct",
          "provider" => "Alibaba",
          "parameter_count" => "7.6B",
          "parameters_raw" => 7_600_000_000,
          "context_length" => 32_768,
          "pipeline_tag" => "text-generation",
          "min_ram_gb" => 8.1,
          "recommended_ram_gb" => 13.2,
          "min_vram_gb" => 7.0
        }
      ]

      plug =
        make_plug(fn conn ->
          conn
          |> Plug.Conn.put_resp_header("etag", "abc123")
          |> Plug.Conn.put_resp_header("last-modified", "Mon, 01 Jan 2024")
          |> Plug.Conn.send_resp(200, Jason.encode!(body))
        end)

      assert {:ok, cache_path} = Llmfit.pull(%{url: test_url, req_opts: [plug: plug]})
      assert File.exists?(cache_path)

      manifest_path = String.replace_suffix(cache_path, ".json", ".manifest.json")
      assert File.exists?(manifest_path)
    end

    test "returns :noop on 304 not modified" do
      plug = make_plug(fn conn -> Plug.Conn.send_resp(conn, 304, "") end)
      assert :noop = Llmfit.pull(%{req_opts: [plug: plug]})
    end

    test "returns error on non-200/304 status" do
      plug = make_plug(fn conn -> Plug.Conn.send_resp(conn, 404, "Not Found") end)
      assert {:error, {:http_status, 404}} = Llmfit.pull(%{req_opts: [plug: plug]})
    end
  end

  describe "load/1" do
    test "returns empty canonical map" do
      assert {:ok, %{}} = Llmfit.load(%{})
    end
  end

  describe "load_index/1" do
    test "returns error when cache file missing" do
      test_url = "https://missing.example.com/llmfit.json"
      assert {:error, :no_cache} = Llmfit.load_index(%{url: test_url})
    end

    test "loads and indexes eligible rows only" do
      test_url = "https://test.example.com/llmfit.json"
      hash = :crypto.hash(:sha256, test_url) |> Base.encode16(case: :lower) |> binary_part(0, 8)
      cache_path = "tmp/test/upstream/llmfit-#{hash}.json"

      rows = [
        %{
          "name" => "Qwen/Qwen2.5-7B-Instruct",
          "provider" => "Alibaba",
          "parameter_count" => "7.6B",
          "parameters_raw" => 7_600_000_000,
          "min_ram_gb" => 8.1,
          "recommended_ram_gb" => 13.2,
          "min_vram_gb" => 7.0,
          "quantization" => "Q4_K_M",
          "context_length" => 32_768,
          "use_case" => "Instruction following, chat",
          "pipeline_tag" => "text-generation",
          "architecture" => "qwen2",
          "hf_downloads" => 1_234_567,
          "hf_likes" => 42,
          "release_date" => "2024-09-01",
          "_discovered" => true
        },
        %{
          "name" => "peft-internal-testing/tiny-random-gpt2",
          "provider" => "peft-internal-testing",
          "parameter_count" => "120K",
          "parameters_raw" => 120_000,
          "pipeline_tag" => "text-generation"
        },
        %{
          "name" => "some-org/small-model",
          "provider" => "some-org",
          "parameter_count" => "25M",
          "parameters_raw" => 25_000_000,
          "pipeline_tag" => "text-generation"
        }
      ]

      File.mkdir_p!(Path.dirname(cache_path))
      File.write!(cache_path, Jason.encode!(rows))

      assert {:ok, index} = Llmfit.load_index(%{url: test_url})
      assert map_size(index) == 1

      metadata = index["Qwen/Qwen2.5-7B-Instruct"]
      assert metadata.source == "llmfit"
      assert metadata.parameters_raw == 7_600_000_000
      assert metadata.context_length == 32_768
      assert metadata.hf_downloads == 1_234_567
      assert metadata.discovered == true
      assert metadata.memory.min_ram_gb == 8.1
    end
  end
end
