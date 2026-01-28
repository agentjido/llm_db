defmodule LLMDB.Packaged do
  @moduledoc """
  Provides access to the packaged base snapshot.

  This is NOT a Source - it returns the pre-processed, version-stable snapshot
  that ships with each release. The snapshot has already been through the full
  ETL pipeline (normalize → validate → merge → enrich → filter → index).

  Sources (ModelsDev, Local, Config) provide raw data that gets merged ON TOP
  of this base snapshot.

  ## Loading Strategy

  Behavior controlled by `:compile_embed` configuration option:
  - `true` - Snapshot embedded at compile-time (zero runtime IO, recommended for production)
  - `false` - Snapshot loaded at runtime from priv directory with integrity checking

  ## Security

  Production deployments should use `compile_embed: true` to eliminate runtime atom
  creation and file I/O. Runtime mode includes SHA-256 integrity verification to
  prevent tampering with the snapshot file.

  ### Integrity Policy

  The `:integrity_policy` config option controls integrity check behavior:
  - `:strict` (default) - Fail on hash mismatch, treating it as tampering
  - `:warn` - Log warning and continue, useful in dev when snapshot regenerates frequently
  - `:off` - Skip mismatch warnings entirely

  In development, use `:warn` mode. The snapshot file is marked as an `@external_resource`,
  so Mix automatically recompiles the module when it changes, refreshing the hash.
  """

  require Logger

  @manifest_filename "priv/llm_db/manifest.json"
  @providers_dir "priv/llm_db/providers"
  @manifest_compile_path Path.join([Application.app_dir(:llm_db), @manifest_filename])

  # Always mark manifest as external resource so Mix recompiles when it changes
  @external_resource @manifest_compile_path

  # Compile-time integrity hash (computed only if file exists at compile time)
  # Note: Used conditionally in verify_integrity/1 macro - compiler may not detect usage
  @manifest_sha (if File.exists?(@manifest_compile_path) do
                   @manifest_compile_path
                   |> File.read!()
                   |> then(&:crypto.hash(:sha256, &1))
                   |> Base.encode16(case: :lower)
                 else
                   nil
                 end)

  @doc """
  Returns the absolute path to the packaged manifest file.

  ## Returns

  String path to `priv/llm_db/manifest.json` within the application directory.
  """
  @spec manifest_path() :: String.t()
  def manifest_path do
    Application.app_dir(:llm_db, @manifest_filename)
  end

  @doc """
  Returns the absolute path to the providers directory.

  ## Returns

  String path to `priv/llm_db/providers/` within the application directory.
  """
  @spec providers_dir() :: String.t()
  def providers_dir do
    Application.app_dir(:llm_db, @providers_dir)
  end

  if Application.compile_env(:llm_db, :compile_embed, false) do
    # Read manifest at compile time
    manifest_content = File.read!(@manifest_compile_path)
    manifest_data = Jason.decode!(manifest_content, keys: :atoms)

    # Load all provider files at compile time
    providers_compile_dir = Application.app_dir(:llm_db, @providers_dir)

    providers_map =
      manifest_data.providers
      |> Enum.map(fn provider_id ->
        provider_path = Path.join(providers_compile_dir, "#{provider_id}.json")
        @external_resource provider_path

        provider_content = File.read!(provider_path)
        provider_data = Jason.decode!(provider_content, keys: :atoms)
        {String.to_atom(provider_id), provider_data}
      end)
      |> Map.new()

    @snapshot %{
      version: manifest_data.version,
      generated_at: manifest_data.generated_at,
      providers: providers_map
    }

    @doc """
    Returns the packaged base snapshot (compile-time embedded).

    This snapshot is the pre-processed output of the ETL pipeline and serves
    as the stable foundation for this package version.

    ## Returns

    Fully indexed snapshot map with providers, models, and indexes, or `nil` if not available.
    """
    @spec snapshot() :: map() | nil
    def snapshot, do: @snapshot
  else
    @doc """
    Returns the packaged base snapshot (runtime loaded with integrity check).

    This snapshot is the pre-processed output of the ETL pipeline and serves
    as the stable foundation for this package version.

    Includes SHA-256 integrity verification to prevent tampering.

    ## Returns

    Fully indexed snapshot map with providers, models, and indexes, or `nil` if not available.
    """
    @spec snapshot() :: map() | nil
    def snapshot do
      # Defensive: ensure provider atoms exist even if Application.start wasn’t run
      _ = Code.ensure_loaded?(LLMDB.Generated.ValidProviders)
      _ = LLMDB.Generated.ValidProviders.list()

      with {:ok, manifest_content} <- File.read(manifest_path()),
           :ok <- verify_integrity(manifest_content),
           manifest <- Jason.decode!(manifest_content, keys: :atoms),
           {:ok, providers_map} <- load_provider_files(manifest.providers) do
        snapshot = %{
          version: manifest.version,
          generated_at: manifest.generated_at,
          providers: providers_map
        }

        validate_schema(snapshot)
        snapshot
      else
        {:error, :tampered} ->
          Logger.error(
            "llm_db: manifest integrity check failed - file may have been tampered with. " <>
              "Refusing to load potentially malicious snapshot."
          )

          nil

        {:error, :enoent} ->
          # Manifest doesn't exist yet (e.g., during build process)
          nil

        {:error, reason} ->
          Logger.warning("llm_db: failed to load snapshot: #{inspect(reason)}")
          nil
      end
    end

    defp load_provider_files(provider_ids) do
      providers_map =
        provider_ids
        |> Enum.map(fn provider_id ->
          provider_path = Path.join(providers_dir(), "#{provider_id}.json")

          case File.read(provider_path) do
            {:ok, content} ->
              provider_data = Jason.decode!(content, keys: :atoms)
              # Provider ID is already an atom in the decoded data
              provider_atom =
                case provider_data[:id] do
                  id when is_atom(id) -> id
                  id when is_binary(id) -> String.to_existing_atom(id)
                end

              {provider_atom, provider_data}

            {:error, reason} ->
              Logger.warning("llm_db: failed to load provider #{provider_id}: #{inspect(reason)}")
              nil
          end
        end)
        |> Enum.reject(&is_nil/1)
        |> Map.new()

      {:ok, providers_map}
    end

    defp integrity_policy do
      Application.get_env(:llm_db, :integrity_policy, :strict)
    end

    if is_nil(@manifest_sha) do
      defp verify_integrity(_content), do: :ok
    else
      @expected_hash @manifest_sha
      defp verify_integrity(content) do
        computed_hash =
          content
          |> then(&:crypto.hash(:sha256, &1))
          |> Base.encode16(case: :lower)

        cond do
          secure_compare(@expected_hash, computed_hash) ->
            :ok

          integrity_policy() in [:warn, :off] ->
            Logger.warning(
              "llm_db: manifest integrity mismatch (expected #{String.slice(@expected_hash, 0..7)}..., got #{String.slice(computed_hash, 0..7)}...). " <>
                "Treating as stale in #{integrity_policy()} mode. If you just ran `mix llm_db.build`, " <>
                "this is expected; the module will auto-recompile on next build."
            )

            :ok

          true ->
            {:error, :tampered}
        end
      end

      # Constant-time string comparison to prevent timing attacks
      defp secure_compare(a, b) when byte_size(a) == byte_size(b) do
        import Bitwise
        a_bytes = :binary.bin_to_list(a)
        b_bytes = :binary.bin_to_list(b)

        result =
          Enum.zip(a_bytes, b_bytes)
          |> Enum.reduce(0, fn {x, y}, acc -> acc ||| bxor(x, y) end)

        result == 0
      end

      defp secure_compare(_, _), do: false
    end

    defp validate_schema(%{providers: providers} = _snapshot)
         when is_map(providers) do
      # Lightweight schema checks to prevent atom/memory exhaustion
      provider_count = map_size(providers)

      if provider_count > 1000 do
        Logger.warning(
          "llm_db: snapshot contains unusually large number of providers: #{provider_count}. " <>
            "Expected < 1000. Potential DoS attempt."
        )
      end

      # Check provider IDs match safe regex
      Enum.each(providers, fn {provider_id, _data} ->
        unless is_atom(provider_id) and
                 Atom.to_string(provider_id) =~ ~r/^[a-z0-9][a-z0-9_:-]{0,63}$/ do
          Logger.warning(
            "llm_db: snapshot contains suspicious provider ID: #{inspect(provider_id)}"
          )
        end
      end)

      :ok
    end
  end
end
