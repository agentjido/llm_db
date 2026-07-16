defmodule LLMDB.Test.GitHistoryFixture do
  @moduledoc false

  @provider_path "priv/llm_db/providers/openai.json"
  @manifest_path "priv/llm_db/manifest.json"

  def create! do
    repo =
      Path.join(
        System.tmp_dir!(),
        "llm_db_git_history_#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(repo)
    File.mkdir_p!(repo)

    git!(repo, ["init", "--quiet", "--initial-branch=main"])
    git!(repo, ["config", "user.name", "LLMDB Test"])
    git!(repo, ["config", "user.email", "llm_db@example.test"])
    git!(repo, ["remote", "add", "origin", "https://example.test/llm_db.git"])

    commits = [
      commit!(repo, "2026-01-01T00:00:00Z", "add initial catalog", initial_provider()),
      commit!(repo, "2026-01-02T00:00:00Z", "update catalog", updated_provider()),
      commit!(repo, "2026-01-03T00:00:00Z", "rename model", renamed_provider())
    ]

    %{repo: repo, commits: commits}
  end

  def in_repo(repo, fun) when is_binary(repo) and is_function(fun, 0) do
    File.cd!(repo, fun)
  end

  def cleanup(%{repo: repo}), do: File.rm_rf!(repo)
  def cleanup(repo) when is_binary(repo), do: File.rm_rf!(repo)

  defp commit!(repo, captured_at, message, provider) do
    write_json!(Path.join(repo, @provider_path), provider)

    write_json!(Path.join(repo, @manifest_path), %{
      "version" => 2,
      "generated_at" => captured_at
    })

    git!(repo, ["add", @provider_path, @manifest_path])

    git!(repo, ["commit", "--quiet", "-m", message],
      env: [
        {"GIT_AUTHOR_DATE", captured_at},
        {"GIT_COMMITTER_DATE", captured_at}
      ]
    )

    repo
    |> git!(["rev-parse", "HEAD"])
    |> String.trim()
  end

  defp initial_provider do
    %{
      "id" => "openai",
      "name" => "OpenAI",
      "models" => %{
        "gpt-4o" => %{
          "id" => "gpt-4o",
          "provider" => "openai",
          "aliases" => ["gpt-4o-latest"],
          "limits" => %{"context" => 128_000}
        }
      }
    }
  end

  defp updated_provider do
    %{
      "id" => "openai",
      "name" => "OpenAI",
      "models" => %{
        "gpt-4o" => %{
          "id" => "gpt-4o",
          "provider" => "openai",
          "aliases" => ["gpt-4o-latest"],
          "limits" => %{"context" => 256_000}
        },
        "gpt-4o-mini" => %{
          "id" => "gpt-4o-mini",
          "provider" => "openai",
          "limits" => %{"context" => 128_000}
        }
      }
    }
  end

  defp renamed_provider do
    %{
      "id" => "openai",
      "name" => "OpenAI",
      "models" => %{
        "gpt-4.1" => %{
          "id" => "gpt-4.1",
          "provider" => "openai",
          "aliases" => ["gpt-4o", "gpt-4o-latest"],
          "limits" => %{"context" => 256_000}
        },
        "gpt-4o-mini" => %{
          "id" => "gpt-4o-mini",
          "provider" => "openai",
          "limits" => %{"context" => 128_000}
        }
      }
    }
  end

  defp write_json!(path, value) do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Jason.encode!(value, pretty: true))
  end

  defp git!(repo, args, opts \\ []) do
    opts = Keyword.merge([cd: repo, stderr_to_stdout: true], opts)

    case System.cmd("git", args, opts) do
      {output, 0} -> output
      {output, status} -> raise "git #{Enum.join(args, " ")} failed (#{status}): #{output}"
    end
  end
end
