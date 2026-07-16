defmodule LLMDB.Packaged do
  @moduledoc """
  Provides access to the packaged base snapshot.

  This is NOT a Source - it returns the pre-processed, version-stable snapshot
  that ships with each release. The snapshot has already been normalized,
  validated, merged, and enriched by the build-time ETL pipeline. Consumer
  filters and runtime indexes are applied later by `LLMDB.load/1`.

  Build-time sources produce future packaged snapshots through `LLMDB.Engine`.
  They are not contacted or merged automatically when consumers load this
  packaged snapshot at runtime.

  ## Loading Strategy

  Behavior controlled by `:compile_embed` configuration option:
  - `true` - Snapshot embedded at compile-time (zero runtime IO, recommended for production)
  - `false` - Snapshot loaded at runtime from priv directory with integrity checking

  ## Integrity and atom safety

  Production deployments can use `compile_embed: true` to eliminate runtime file
  I/O. Embedded and file-based documents pass through the same checksum,
  migration, structural-validation, and bounded atom-decoding contract.

  Snapshot IDs detect accidental corruption or content mismatch. They do not
  authenticate the snapshot or its publisher.

  ### Integrity Policy

  The `:integrity_policy` config option controls integrity check behavior:
  - `:strict` (default) - Fail on snapshot ID mismatch
  - `:warn` - Log warning and continue, useful in dev when snapshot regenerates frequently
  - `:off` - Skip mismatch warnings entirely

  In development, use `:warn` mode. The snapshot file is marked as an `@external_resource`,
  so Mix automatically recompiles the module when it changes, refreshing the hash.
  """

  require Logger
  alias LLMDB.Snapshot

  @snapshot_filename "priv/llm_db/snapshot.json"
  @snapshot_compile_path Path.join([Application.app_dir(:llm_db), @snapshot_filename])

  @external_resource @snapshot_compile_path

  @doc """
  Returns the absolute path to the packaged snapshot file.

  ## Returns

  String path to `priv/llm_db/snapshot.json` within the application directory.
  """
  @spec snapshot_path() :: String.t()
  def snapshot_path, do: Snapshot.packaged_path()

  if Application.compile_env(:llm_db, :compile_embed, false) do
    @snapshot if File.exists?(@snapshot_compile_path),
                do: Jason.decode!(File.read!(@snapshot_compile_path)),
                else: nil

    @doc false
    @spec load() :: {:ok, map()} | {:error, term()}
    def load do
      case @snapshot do
        nil -> {:error, :no_snapshot}
        snapshot -> Snapshot.prepare(snapshot, integrity_policy: integrity_policy())
      end
    end

    @doc """
    Returns the verified packaged base snapshot (compile-time embedded).

    This snapshot is the pre-processed output of the ETL pipeline and serves
    as the stable foundation for this package version.

    ## Returns

    Fully indexed snapshot map with providers, models, and indexes, or `nil` if not available.
    """
    @spec snapshot() :: map() | nil
    def snapshot, do: unwrap_snapshot(load())
  else
    @doc false
    @spec load() :: {:ok, map()} | {:error, term()}
    def load do
      Snapshot.read(snapshot_path(), integrity_policy: integrity_policy())
    end

    @doc """
    Returns the packaged base snapshot loaded from the runtime file.

    This snapshot is the pre-processed output of the ETL pipeline and serves
    as the stable foundation for this package version.

    The same checksum, migration, structural validation, and atom-safety
    boundary used by compile-time embedded snapshots is applied.

    ## Returns

    Fully indexed snapshot map with providers, models, and indexes, or `nil` if not available.
    """
    @spec snapshot() :: map() | nil
    def snapshot, do: unwrap_snapshot(load())
  end

  defp integrity_policy do
    Application.get_env(:llm_db, :integrity_policy, :strict)
  end

  defp unwrap_snapshot({:ok, snapshot}), do: snapshot
  defp unwrap_snapshot({:error, reason}) when reason in [:enoent, :no_snapshot], do: nil

  defp unwrap_snapshot({:error, reason}) do
    Logger.error("llm_db: refusing to load packaged snapshot: #{inspect(reason)}")
    nil
  end
end
