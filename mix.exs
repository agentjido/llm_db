defmodule LLMModels.MixProject do
  use Mix.Project

  @version "2025.11.6"
  @source_url "https://github.com/agentjido/llm_models"

  def project do
    [
      app: :llm_models,
      version: @version,
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      description: description(),
      package: package(),
      elixirc_paths: elixirc_paths(Mix.env()),

      # Dialyzer configuration
      dialyzer: [
        plt_add_apps: [:mix]
      ],

      # Documentation
      name: "LLMModels",
      source_url: @source_url,
      homepage_url: @source_url,
      source_ref: "v#{@version}",
      docs: [
        main: "readme",
        extras: [
          "README.md",
          "guides/schema-system.md",
          "guides/sources-and-engine.md",
          "guides/using-the-data.md",
          "guides/release-process.md",
          "CHANGELOG.md"
        ],
        groups_for_extras: [
          Guides: ~r/guides\/.+\.md/
        ]
      ]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:zoi, "~> 0.8"},
      {:jason, "~> 1.4"},
      {:toml, "~> 0.7"},
      {:req, "~> 0.5"},
      {:deep_merge, "~> 1.0"},
      {:plug, "~> 1.16", only: :test},
      {:meck, "~> 0.9", only: :test},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:git_ops, "~> 2.6", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:usage_rules, "~> 0.1", only: :dev, runtime: false}
    ]
  end

  defp description do
    "Fast, persistent_term-backed LLM model metadata catalog with explicit refresh controls"
  end

  defp package do
    [
      description: "Fast, persistent_term-backed LLM model metadata catalog",
      licenses: ["MIT"],
      maintainers: ["Mike Hostetler"],
      links: %{
        "Changelog" => "https://hexdocs.pm/llm_models/changelog.html",
        "GitHub" => @source_url,
        "Agent Jido" => "https://agentjido.xyz"
      },
      files: ~w(lib priv mix.exs LICENSE README.md CHANGELOG.md AGENTS.md .formatter.exs)
    ]
  end

  defp aliases do
    [
      quality: [
        "format --check-formatted",
        "compile --warnings-as-errors",
        "dialyzer",
        "credo --strict"
      ],
      q: ["quality"]
    ]
  end
end
