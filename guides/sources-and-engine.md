# Sources and Engine

The Engine runs a build-time ETL pipeline that loads data from sources, normalizes, validates, merges, enriches, and indexes it, then writes `priv/llm_models/snapshot.json`. Runtime only loads the snapshot.

## Source Behaviour

All sources implement the `LLMModels.Source` behaviour:

```elixir
@callback load(opts :: map()) :: {:ok, data :: map()} | {:error, term()}
@callback pull(opts :: map()) :: :ok | {:error, term()}  # Optional
```

### Canonical Format

```elixir
%{
  "providers" => %{
    openai: %{
      "id" => :openai,
      "name" => "OpenAI",
      "base_url" => "https://api.openai.com/v1",
      # ...
    }
  },
  "models" => [
    %{
      "id" => "gpt-4",
      "provider" => :openai,
      "name" => "GPT-4",
      # ...
    },
    # ...
  ]
}
```

Outer map uses string keys; provider keys are atoms; model IDs are strings. Use `LLMModels.Source.assert_canonical!/1` for validation.

## Built-in Sources

### ModelsDev (Remote)

```elixir
{LLMModels.Sources.ModelsDev, %{
  url: "https://models.dev/api/models",
  cache_path: "priv/llm_models/cache/models_dev.json"
}}
```

`pull/1` downloads and caches via Req. `load/1` loads from cache. Transforms models.dev schema to canonical format (`limit` → `limits`, modality strings → atoms, unmapped → `:extra`).

### Local (TOML)

```elixir
{LLMModels.Sources.Local, %{dir: "priv/llm_models"}}
```

Structure: `provider.toml` + `models/{provider}/*.toml`. Atomizes keys, injects `:provider` from directory name.

### Config

```elixir
{LLMModels.Sources.Config, %{
  overrides: %{
    openai: %{
      "base_url" => "https://custom.endpoint",
      "models" => %{"gpt-4" => %{"cost" => %{"input" => 4.5}}}
    }
  }
}}
```

Provider-level and per-model overrides with deep merge.

## Configuring Sources

```elixir
config :llm_models,
  sources: [
    {LLMModels.Sources.ModelsDev, %{}},
    {LLMModels.Sources.Local, %{dir: "priv/llm_models"}},
    {LLMModels.Sources.Config, %{overrides: %{...}}}
  ]
```

Sources processed in order. Later sources override earlier ones.

## ETL Pipeline

`LLMModels.Engine.run/1` executes 7 stages:

1. **Ingest**: Load sources, validate canonical format, flatten nested provider data
2. **Normalize**: Convert provider IDs to atoms, normalize modalities to atoms, parse dates
3. **Validate**: Zoi validation via `LLMModels.Validate`, drop invalid, log warnings
4. **Merge**: Last-wins precedence; `:aliases` are unioned, other lists replaced, maps deep merged
5. **Filter**: Compile allow/deny patterns (deny wins, globs supported)
6. **Enrich**: Derive `:family`, fill `:provider_model_id`, apply capability defaults
7. **Index**: Build `providers_by_id`, `models_by_key`, `models_by_provider`, `aliases_by_key`, then v2 snapshot

Final check warns if zero providers/models.

## Mix Tasks

- `mix llm_models.pull` - Fetch and cache remote sources
- `mix llm_models.build` - Run ETL, write `priv/llm_models/snapshot.json` and `lib/llm_models/generated/valid_providers.ex`

## Custom Source Example

```elixir
defmodule MyApp.InternalModels do
  @behaviour LLMModels.Source

  @impl true
  def load(_opts) do
    {:ok, %{
      "providers" => %{internal: %{"id" => :internal, "name" => "Internal"}},
      "models" => [%{"id" => "custom-gpt", "provider" => :internal, "capabilities" => %{"chat" => true}}]
    }}
  end
end

# config.exs
config :llm_models, sources: [{MyApp.InternalModels, %{}}]
```
