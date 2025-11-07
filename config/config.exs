import Config

# LLM Models configuration
config :llm_db,
  # Default sources for loading model metadata (first = lowest precedence, last = highest)
  sources: [
    {LLMDb.Sources.ModelsDev, %{}},
    {LLMDb.Sources.Local, %{dir: "priv/llm_db/local"}},
    {LLMDb.Sources.Config, %{overrides: Application.compile_env(:llm_db, :overrides, %{})}}
  ],

  # Cache directory for remote sources
  models_dev_cache_dir: "priv/llm_db/upstream",
  upstream_cache_dir: "priv/llm_db/upstream"

if Mix.env() == :dev do
  config :git_ops,
    mix_project: LLMDb.MixProject,
    changelog_file: "CHANGELOG.md",
    repository_url: "https://github.com/agentjido/llm_db",
    manage_mix_version?: false,
    manage_readme_version: false,
    version_tag_prefix: "v"
end

# Import environment-specific config
if File.exists?("config/#{Mix.env()}.exs") do
  import_config "#{Mix.env()}.exs"
end
