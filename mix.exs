defmodule LlmModels.MixProject do
  use Mix.Project

  def project do
    [
      app: :llm_models,
      version: "0.1.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:zoi, "~> 0.8"},
      {:jason, "~> 1.4"}
    ]
  end

  defp description do
    "Fast, persistent_term-backed LLM model metadata catalog with explicit refresh controls"
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{}
    ]
  end
end
