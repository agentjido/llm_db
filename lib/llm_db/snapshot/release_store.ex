defmodule LLMDB.Snapshot.ReleaseStore do
  @moduledoc """
  GitHub Releases-backed snapshot artifact store.

  Runtime fetching uses public release asset URLs via Req. Publishing is handled
  with the `gh` CLI, intended for local maintainer workflows and GitHub Actions.
  """

  alias LLMDB.Snapshot

  @default_repo "agentjido/llm_db"
  @default_index_tag "catalog-index"
  @default_cache_dir Path.join(["tmp", "llm_db", "snapshot_cache"])

  @type config :: %{
          repo: String.t(),
          index_tag: String.t(),
          cache_dir: String.t()
        }

  @spec config(keyword() | map()) :: config()
  def config(overrides \\ []) do
    app_config =
      Application.get_env(:llm_db, :snapshot_store, [])
      |> Enum.into(%{})

    override_map =
      cond do
        is_map(overrides) -> overrides
        Keyword.keyword?(overrides) -> Enum.into(overrides, %{})
        true -> %{}
      end

    merged = Map.merge(app_config, override_map)

    %{
      repo: Map.get(merged, :repo, Map.get(merged, "repo", @default_repo)),
      index_tag: Map.get(merged, :index_tag, Map.get(merged, "index_tag", @default_index_tag)),
      cache_dir:
        Map.get(merged, :cache_dir, Map.get(merged, "cache_dir", @default_cache_dir))
        |> expand_path()
    }
  end

  @spec snapshot_tag(String.t()) :: String.t()
  def snapshot_tag(snapshot_id), do: "snapshot-#{snapshot_id}"

  @spec index_asset_url(String.t(), String.t() | nil, keyword() | map()) :: String.t()
  def index_asset_url(filename, store_file \\ nil, overrides \\ %{})

  def index_asset_url(filename, nil, overrides) do
    cfg = config(overrides)
    release_asset_url(cfg.repo, cfg.index_tag, filename)
  end

  def index_asset_url(_filename, store_file, overrides) do
    cfg = config(overrides)
    release_asset_url(cfg.repo, cfg.index_tag, store_file)
  end

  @spec snapshot_asset_url(String.t(), keyword() | map()) :: String.t()
  def snapshot_asset_url(snapshot_id, overrides \\ %{}) do
    cfg = config(overrides)
    release_asset_url(cfg.repo, snapshot_tag(snapshot_id), Snapshot.snapshot_filename())
  end

  @spec snapshot_meta_asset_url(String.t(), keyword() | map()) :: String.t()
  def snapshot_meta_asset_url(snapshot_id, overrides \\ %{}) do
    cfg = config(overrides)
    release_asset_url(cfg.repo, snapshot_tag(snapshot_id), Snapshot.snapshot_meta_filename())
  end

  @spec fetch_latest(keyword() | map()) :: {:ok, map()} | {:error, term()}
  def fetch_latest(overrides \\ %{}) do
    Snapshot.latest_filename()
    |> index_asset_url(nil, overrides)
    |> fetch_json()
  end

  @spec fetch_snapshot_index(keyword() | map()) :: {:ok, [map()]} | {:error, term()}
  def fetch_snapshot_index(overrides \\ %{}) do
    case Snapshot.snapshot_index_filename()
         |> index_asset_url(nil, overrides)
         |> fetch_json() do
      {:ok, %{"snapshots" => snapshots}} when is_list(snapshots) -> {:ok, snapshots}
      {:ok, snapshots} when is_list(snapshots) -> {:ok, snapshots}
      {:ok, other} -> {:error, {:invalid_snapshot_index, other}}
      error -> error
    end
  end

  @spec fetch_history_meta(keyword() | map()) :: {:ok, map()} | {:error, term()}
  def fetch_history_meta(overrides \\ %{}) do
    Snapshot.history_meta_filename()
    |> index_asset_url(nil, overrides)
    |> fetch_json()
  end

  @spec fetch_snapshot(:latest | String.t(), keyword() | map()) ::
          {:ok, %{snapshot: map(), snapshot_id: String.t(), path: String.t()}} | {:error, term()}
  def fetch_snapshot(ref, overrides \\ %{})

  def fetch_snapshot(:latest, overrides) do
    with {:ok, latest} <- fetch_latest(overrides),
         snapshot_id when is_binary(snapshot_id) <- latest["snapshot_id"] do
      fetch_snapshot(snapshot_id, overrides)
    else
      _ -> {:error, :invalid_latest_snapshot}
    end
  end

  def fetch_snapshot(snapshot_id, overrides) when is_binary(snapshot_id) do
    cfg = config(overrides)
    path = cached_snapshot_path(snapshot_id, cfg)

    with :ok <- File.mkdir_p(Path.dirname(path)),
         {:ok, snapshot} <- maybe_read_cached_snapshot(path, snapshot_id) do
      {:ok, %{snapshot: snapshot, snapshot_id: snapshot_id, path: path}}
    else
      {:error, :cache_miss} ->
        with {:ok, content} <- download(snapshot_asset_url(snapshot_id, cfg)),
             {:ok, snapshot} <- Snapshot.decode(content),
             ^snapshot_id <- snapshot["snapshot_id"] do
          File.write!(path, Snapshot.encode(snapshot))
          {:ok, %{snapshot: snapshot, snapshot_id: snapshot_id, path: path}}
        else
          mismatch when is_binary(mismatch) ->
            {:error, {:snapshot_id_mismatch, expected: snapshot_id, got: mismatch}}

          error ->
            error
        end

      error ->
        error
    end
  end

  @spec download_history_archive(String.t(), keyword() | map()) :: :ok | {:error, term()}
  def download_history_archive(destination, overrides \\ %{}) when is_binary(destination) do
    with {:ok, content} <-
           download(index_asset_url(Snapshot.history_archive_filename(), nil, overrides)) do
      destination
      |> Path.dirname()
      |> File.mkdir_p!()

      File.write!(destination, content)
      :ok
    end
  end

  @spec ensure_snapshot_release(String.t(), String.t(), String.t(), keyword() | map()) ::
          :ok | {:error, term()}
  def ensure_snapshot_release(snapshot_path, meta_path, snapshot_id, overrides \\ %{}) do
    cfg = config(overrides)
    tag = snapshot_tag(snapshot_id)

    with :ok <- ensure_gh_available(),
         :ok <- ensure_release(tag, cfg.repo, "Snapshot #{snapshot_id}"),
         :ok <- upload_assets(tag, cfg.repo, [snapshot_path, meta_path]) do
      :ok
    end
  end

  @spec publish_catalog_index([String.t()], keyword() | map()) :: :ok | {:error, term()}
  def publish_catalog_index(asset_paths, overrides \\ %{}) when is_list(asset_paths) do
    cfg = config(overrides)

    with :ok <- ensure_gh_available(),
         :ok <- ensure_release(cfg.index_tag, cfg.repo, "Catalog Index"),
         :ok <- upload_assets(cfg.index_tag, cfg.repo, asset_paths) do
      :ok
    end
  end

  defp maybe_read_cached_snapshot(path, expected_snapshot_id) do
    case Snapshot.read(path) do
      {:ok, %{"snapshot_id" => ^expected_snapshot_id} = snapshot} -> {:ok, snapshot}
      _ -> {:error, :cache_miss}
    end
  end

  defp cached_snapshot_path(snapshot_id, %{cache_dir: cache_dir}) do
    Path.join([cache_dir, "snapshots", "#{snapshot_id}.json"])
  end

  @spec fetch_json(String.t()) :: {:ok, term()} | {:error, term()}
  defp fetch_json(url) do
    with {:ok, content} <- download(url),
         {:ok, decoded} <- Jason.decode(content) do
      {:ok, decoded}
    end
  end

  @spec download(String.t()) :: {:ok, binary()} | {:error, term()}
  defp download(url) do
    :ok = ensure_http_started()

    case Req.get(url) do
      {:ok, %{status: status, body: body}} when status in 200..299 -> {:ok, body}
      {:ok, %{status: 404}} -> {:error, :not_found}
      {:ok, %{status: status, body: body}} -> {:error, {:http_status, status, body}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp release_asset_url(repo, tag, filename) do
    "https://github.com/#{repo}/releases/download/#{tag}/#{filename}"
  end

  defp ensure_gh_available do
    case System.find_executable("gh") do
      nil -> {:error, "gh CLI is required to publish snapshot artifacts"}
      _ -> :ok
    end
  end

  defp ensure_release(tag, repo, title) do
    case run_gh(["release", "view", tag, "--repo", repo]) do
      {:ok, _output} ->
        :ok

      {:error, _reason} ->
        run_gh(["release", "create", tag, "--repo", repo, "--title", title, "--notes", ""])
    end
  end

  defp upload_assets(tag, repo, asset_paths) do
    existing_assets =
      Enum.filter(asset_paths, &File.exists?/1)

    case existing_assets do
      [] ->
        :ok

      _ ->
        run_gh(["release", "upload", tag, "--repo", repo, "--clobber" | existing_assets])
    end
  end

  defp run_gh(args) do
    case System.cmd("gh", args, stderr_to_stdout: true) do
      {output, 0} -> {:ok, output}
      {output, _code} -> {:error, String.trim(output)}
    end
  end

  @spec ensure_http_started() :: :ok
  defp ensure_http_started do
    case Application.ensure_all_started(:req) do
      {:ok, _apps} -> :ok
      {:error, {:already_started, _app}} -> :ok
      {:error, reason} -> raise "failed to start req application: #{inspect(reason)}"
    end
  end

  defp expand_path(path) when is_binary(path) do
    if Path.type(path) == :absolute do
      path
    else
      Path.expand(path)
    end
  end
end
