# Sources and Engine

The Engine runs a build-time ETL pipeline that loads data from sources, normalizes, validates, merges, enriches, and indexes it, then builds a canonical `snapshot.json` artifact. Runtime only loads the packaged or explicitly fetched snapshot.

## Source Behaviour

All sources implement the `LLMDB.Source` behaviour:

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

Outer map uses string keys; provider keys are atoms; model IDs are strings. Use `LLMDB.Source.assert_canonical!/1` for validation.

## Built-in Sources

### ModelsDev (Remote)

```elixir
{LLMDB.Sources.ModelsDev, %{
  url: "https://models.dev/api/models",
  cache_path: "priv/llm_db/cache/models_dev.json"
}}
```

`pull/1` downloads and caches via Req. `load/1` loads from cache. Transforms models.dev schema to canonical format (`limit` → `limits`, modality strings → atoms, unmapped → `:extra`).

### Local (TOML)

```elixir
{LLMDB.Sources.Local, %{dir: "priv/llm_db"}}
```

Structure: `provider.toml` + `models/{provider}/*.toml`. Atomizes keys, injects `:provider` from directory name.

## Configuring Sources

```elixir
config :llm_db,
  sources: [
    {LLMDB.Sources.ModelsDev, %{}},
    {LLMDB.Sources.Local, %{dir: "priv/llm_db"}}
  ]
```

Sources processed in order. Later sources override earlier ones.

## ETL Pipeline

`LLMDB.Engine.run/1` executes 7 stages:

1. **Ingest**: Load sources, validate canonical format, flatten nested provider data
2. **Normalize**: Convert provider IDs to atoms, normalize modalities to atoms, parse dates
3. **Validate**: Zoi validation via `LLMDB.Validate`, drop invalid, log warnings
4. **Merge**: Last-wins precedence; `:aliases` are unioned, other lists replaced, maps deep merged
5. **Filter**: Compile allow/deny patterns (deny wins, globs supported)
6. **Enrich**: Derive `:family`, fill `:provider_model_id`, apply capability defaults
7. **Index**: Build `providers_by_id`, `models_by_key`, `models_by_provider`, `aliases_by_key`, then v2 snapshot

Final check warns if zero providers/models.

## Mix Tasks

- `mix llm_db.pull` - Fetch and cache remote sources
- `mix llm_db.build` - Run ETL and build canonical snapshot artifacts
- `mix llm_db.snapshot.publish` - Publish an immutable content-addressed snapshot to GitHub Releases

## Custom Source Example

```elixir
defmodule MyApp.InternalModels do
  @behaviour LLMDB.Source

  @impl true
  def load(_opts) do
    {:ok, %{
      "providers" => %{internal: %{"id" => :internal, "name" => "Internal"}},
      "models" => [%{"id" => "custom-gpt", "provider" => :internal, "capabilities" => %{"chat" => true}}]
    }}
  end
end

# config.exs
config :llm_db, sources: [{MyApp.InternalModels, %{}}]
```
