defmodule LLMDB.Dotenv do
  @moduledoc """
  Deprecated compatibility facade for maintainer dotenv loading.

  Dotenv loading belongs exclusively to `mix llm_db.pull`; runtime startup,
  loading, and queries never call this module. Direct calls remain functional
  for this minor release and can be removed no earlier than the next major
  release, together with the core `Dotenvy` dependency.
  """

  @deprecated "dotenv loading is owned by the mix llm_db.pull maintainer task"
  def load!(opts \\ []) do
    if Application.get_env(:llm_db, :load_dotenv, true) do
      env_path = Keyword.get(opts, :path, Path.join(File.cwd!(), ".env"))

      override? =
        Keyword.get(opts, :override, Application.get_env(:llm_db, :dotenv_override, false))

      if File.exists?(env_path) and not File.dir?(env_path) do
        env_path
        |> Dotenvy.source!()
        |> Enum.each(fn {key, value} ->
          if override? or System.get_env(key) == nil do
            System.put_env(key, value)
          end
        end)
      end
    end

    :ok
  end
end
