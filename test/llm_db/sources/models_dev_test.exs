defmodule LLMDB.Sources.ModelsDevTest do
  use ExUnit.Case, async: false

  alias LLMDB.Sources.ModelsDev

  setup do
    # Clean up test cache directory
    File.rm_rf!("tmp/test/upstream")

    on_exit(fn ->
      File.rm_rf!("tmp/test/upstream")
    end)

    :ok
  end

  # Test plug that returns mocked responses
  defp make_plug(fun) do
    fn conn ->
      fun.(conn)
    end
  end

  describe "pull/1" do
    test "fetches and caches data on 200 response" do
      test_url = "https://test.example.com/api.json"

      # models.dev format: providers as top-level keys with nested models
      body = %{
        "openai" => %{
          "api" => "https://api.openai.example/v1",
          "id" => "openai",
          "name" => "OpenAI",
          "models" => %{
            "gpt-4o" => %{"id" => "gpt-4o"}
          }
        }
      }

      plug =
        make_plug(fn conn ->
          conn
          |> Plug.Conn.put_resp_header("etag", "abc123")
          |> Plug.Conn.put_resp_header("last-modified", "Mon, 01 Jan 2024")
          |> Plug.Conn.send_resp(200, Jason.encode!(body))
        end)

      assert {:ok, cache_path} = ModelsDev.pull(%{url: test_url, req_opts: [plug: plug]})

      # Verify cache file created
      assert File.exists?(cache_path)
      {:ok, cached} = File.read(cache_path)
      decoded = Jason.decode!(cached)
      assert decoded["openai"]
      assert decoded["openai"]["models"]

      # Verify manifest created
      manifest_path = String.replace_suffix(cache_path, ".json", ".manifest.json")
      assert File.exists?(manifest_path)
      {:ok, manifest_bin} = File.read(manifest_path)
      manifest = Jason.decode!(manifest_bin)
      assert manifest["etag"] == "abc123"
      assert manifest["last_modified"] == "Mon, 01 Jan 2024"
      assert manifest["sha256"]
      assert manifest["downloaded_at"]
    end

    test "returns :noop on 304 not modified" do
      plug = make_plug(fn conn -> Plug.Conn.send_resp(conn, 304, "") end)
      assert :noop = ModelsDev.pull(%{req_opts: [plug: plug]})
    end

    test "returns error on non-200/304 status" do
      plug = make_plug(fn conn -> Plug.Conn.send_resp(conn, 404, "Not Found") end)
      assert {:error, {:http_status, 404}} = ModelsDev.pull(%{req_opts: [plug: plug]})
    end

    test "sends conditional headers from manifest on subsequent pulls" do
      test_url = "https://test.example.com/api.json"
      body = %{"providers" => [], "models" => []}

      # First pull - create manifest
      plug_first =
        make_plug(fn conn ->
          conn
          |> Plug.Conn.put_resp_header("etag", "tag1")
          |> Plug.Conn.put_resp_header("last-modified", "Mon, 01 Jan 2024")
          |> Plug.Conn.send_resp(200, Jason.encode!(body))
        end)

      ModelsDev.pull(%{url: test_url, req_opts: [plug: plug_first]})

      # Second pull - should send conditional headers and get 304
      plug_second =
        make_plug(fn conn ->
          headers = Enum.into(conn.req_headers, %{})
          assert headers["if-none-match"] == "tag1"
          assert headers["if-modified-since"] == "Mon, 01 Jan 2024"

          Plug.Conn.send_resp(conn, 304, "")
        end)

      assert :noop = ModelsDev.pull(%{url: test_url, req_opts: [plug: plug_second]})
    end
  end

  describe "load/1" do
    test "loads and normalizes cached data" do
      test_url = "https://test.example.com/api.json"

      # Create cache file in models.dev format
      cache_data = %{
        "openai" => %{
          "api" => "https://api.openai.example/v1",
          "id" => "openai",
          "name" => "OpenAI",
          "models" => %{
            "gpt-4o" => %{"id" => "gpt-4o"}
          }
        }
      }

      # Determine cache path from URL
      hash = :crypto.hash(:sha256, test_url) |> Base.encode16(case: :lower) |> binary_part(0, 8)
      cache_path = "tmp/test/upstream/models-dev-#{hash}.json"

      File.mkdir_p!(Path.dirname(cache_path))
      File.write!(cache_path, Jason.encode!(cache_data))

      {:ok, data} = ModelsDev.load(%{url: test_url})

      # Should be in nested format with models as list
      assert is_map(data)
      assert Map.has_key?(data, "openai")

      provider = data["openai"]
      assert provider[:id] == "openai"
      assert provider[:name] == "OpenAI"
      assert provider[:base_url] == "https://api.openai.example/v1"
      assert is_list(provider[:models])
      assert length(provider[:models]) == 1
      assert hd(provider[:models])[:id] == "gpt-4o"
      assert hd(provider[:models])[:provider] == "openai"
    end

    test "returns error when cache file missing" do
      test_url = "https://missing.example.com/api.json"
      assert {:error, :no_cache} = ModelsDev.load(%{url: test_url})
    end

    test "returns error on invalid JSON" do
      test_url = "https://invalid.example.com/api.json"
      hash = :crypto.hash(:sha256, test_url) |> Base.encode16(case: :lower) |> binary_part(0, 8)
      cache_path = "tmp/test/upstream/models-dev-#{hash}.json"

      File.mkdir_p!(Path.dirname(cache_path))
      File.write!(cache_path, "not json")

      assert {:error, {:json_error, _}} = ModelsDev.load(%{url: test_url})
    end
  end

  describe "integration" do
    test "pull then load workflow" do
      test_url = "https://integration.example.com/api.json"

      # models.dev format
      body = %{
        "test" => %{
          "id" => "test",
          "name" => "Test",
          "models" => %{
            "model-1" => %{"id" => "model-1"}
          }
        }
      }

      plug = make_plug(fn conn -> Plug.Conn.send_resp(conn, 200, Jason.encode!(body)) end)

      # Pull
      assert {:ok, _} = ModelsDev.pull(%{url: test_url, req_opts: [plug: plug]})

      # Load
      assert {:ok, data} = ModelsDev.load(%{url: test_url})
      assert Map.has_key?(data, "test")
      assert data["test"][:name] == "Test"
      assert length(data["test"][:models]) == 1
      assert hd(data["test"][:models])[:provider] == "test"
    end
  end
end
