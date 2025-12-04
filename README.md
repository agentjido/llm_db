# LLM DB - A LLM Model Metadata Database

[![Hex.pm](https://img.shields.io/hexpm/v/llm_db.svg)](https://hex.pm/packages/llm_db)
[![License](https://img.shields.io/hexpm/l/llm_db.svg)](https://github.com/agentjido/llm_db/blob/main/LICENSE)

LLM model metadata catalog with fast, capability-aware lookups. Use simple `"provider:model"` or `"model@provider"` specs, get validated Provider/Model structs, and select models by capabilities. Ships with a packaged snapshot; no network required by default.

- **Primary interface**: `model_spec` — a string like `"openai:gpt-4o-mini"` or `"gpt-4o-mini@openai"` (filename-safe)
- **Fast O(1) reads** via `:persistent_term`
- **Minimal dependencies** 

## Installation

Model metadata is refreshed regularly, so versions follow [CalVer](https://calver.org/) (`YYYY.M.Patch` with no leading zeros):

```elixir
def deps do
  [
    {:llm_db, "~> 2025.11.0"}
  ]
end
```

## model_spec (the main interface)

A `model_spec` is a string in one of two formats:
- `"provider:model"` (e.g., `"openai:gpt-4o-mini"`) — traditional colon format
- `"model@provider"` (e.g., `"gpt-4o-mini@openai"`) — filename-safe format

Both formats are automatically recognized and work interchangeably. Use the `@` format when model specs appear in filenames, CI artifact names, or other filesystem contexts where colons are problematic.

Tuples `{:provider_atom, "id"}` also work, but prefer the string spec.

```elixir
{:ok, model} = LLMDB.model("openai:gpt-4o-mini")
#=> %LLMDB.Model{id: "gpt-4o-mini", provider: :openai, ...}

{:ok, model} = LLMDB.model("gpt-4o-mini@openai")
#=> %LLMDB.Model{id: "gpt-4o-mini", provider: :openai, ...}
```

## Quick Start

```elixir
# Get a model and read metadata
{:ok, model} = LLMDB.model("openai:gpt-4o-mini")
model.capabilities.tools.enabled  #=> true
model.cost.input                  #=> 0.15  (per 1M tokens)
model.limits.context              #=> 128_000

# Model aliases auto-resolve to canonical IDs
{:ok, model} = LLMDB.model("anthropic:claude-haiku-4.5")
model.id  #=> "claude-haiku-4-5-20251001" (canonical ID)

# Select a model by capabilities (returns {provider, id})
{:ok, {provider, id}} = LLMDB.select(
  require: [chat: true, tools: true, json_native: true],
  prefer:  [:openai, :anthropic]
)
{:ok, model} = LLMDB.model({provider, id})

# List providers
LLMDB.providers()
#=> [%LLMDB.Provider{id: :anthropic, ...}, %LLMDB.Provider{id: :openai, ...}]

# Check availability (allow/deny filters)
LLMDB.allowed?("openai:gpt-4o-mini") #=> true
```

## API Cheatsheet

- **`model/1`** — `"provider:model"`, `"model@provider"`, or `{:provider, id}` → `{:ok, %Model{}}` | `{:error, _}`
- **`model/2`** — `provider` atom + `id` → `{:ok, %Model{}}` | `{:error, _}`
- **`models/0`** — list all models → `[%Model{}]`
- **`models/1`** — list provider's models → `[%Model{}]`
- **`providers/0`** — list all providers → `[%Provider{}]`
- **`provider/1`** — get provider by ID → `{:ok, %Provider{}}` | `:error`
- **`select/1`** — pick first match by capabilities → `{:ok, {provider, id}}` | `{:error, :no_match}`
- **`candidates/1`** — get all matches by capabilities → `[{provider, id}]`
- **`capabilities/1`** — get capabilities map → `map()` | `nil`
- **`allowed?/1`** — check availability → `boolean()`
- **`parse/1,2`** — parse spec string (both formats) → `{:ok, {provider, id}}` | `{:error, _}`
- **`parse!/1,2`** — parse spec string, raising on error → `{provider, id}`
- **`format/1,2`** — format `{provider, id}` as string → `"provider:model"` or `"model@provider"`
- **`build/1,2`** — build spec string from input, converting between formats → `String.t()`
- **`load/1`**, **`load/0`** — load or reload snapshot with optional runtime overrides
- **`load_empty/1`** — load empty catalog (fallback when no snapshot available)
- **`epoch/0`**, **`snapshot/0`** — diagnostics

See the full function docs in [hexdocs](https://hexdocs.pm/llm_db).

## Data Structures

### Provider

```elixir
%LLMDB.Provider{
  id: :openai,
  name: "OpenAI",
  base_url: "https://api.openai.com",
  env: ["OPENAI_API_KEY"],
  doc: "https://platform.openai.com/docs",
  extra: %{}
}
```

### Model

```elixir
%LLMDB.Model{
  id: "gpt-4o-mini",
  provider: :openai,
  name: "GPT-4o mini",
  family: "gpt-4o",
  limits: %{context: 128_000, output: 16_384},
  cost: %{input: 0.15, output: 0.60},
  capabilities: %{
    chat: true,
    tools: %{enabled: true, streaming: true},
    json: %{native: true, schema: true},
    streaming: %{text: true, tool_calls: true}
  },
  tags: [],
  deprecated?: false,
  aliases: [],
  extra: %{}
}
```

## Configuration

The packaged snapshot loads automatically at app start. Optional runtime filters, preferences, and custom providers:

```elixir
# config/runtime.exs
config :llm_db,
  filter: %{
    allow: :all,                     # :all or %{provider => [patterns]}
    deny: %{openai: ["*-preview"]}   # deny patterns override allow
  },
  prefer: [:openai, :anthropic],     # provider preference order
  custom: %{
    local: [
      name: "Local Provider",
      base_url: "http://localhost:8080",
      models: %{
        "llama-3" => %{capabilities: %{chat: true}},
        "mistral-7b" => %{capabilities: %{chat: true, tools: %{enabled: true}}}
      }
    ]
  }
```

### Filter Examples

```elixir
# Allow all, deny preview/beta models
config :llm_db,
  filter: %{
    allow: :all,
    deny: %{openai: ["*-preview", "*-beta"]}
  }

# Allow only specific model families
config :llm_db,
  filter: %{
    allow: %{
      anthropic: ["claude-3-haiku-*", "claude-3.5-sonnet-*"],
      openrouter: ["anthropic/claude-*"]
    },
    deny: %{}
  }

# Runtime override (widen/narrow filters without rebuild)
{:ok, _snapshot} = LLMDB.load(
  allow: %{openai: ["gpt-4o-*"]},
  deny: %{}
)
```

**Important:** Filters match against **canonical model IDs only**, not aliases. Use canonical IDs (typically dated versions like `claude-haiku-4-5-20251001`) in filter patterns. Aliases are resolved during model lookup, after filtering is applied.

### Custom Providers

Add local or private models to the catalog:

```elixir
# config/runtime.exs
config :llm_db,
  custom: %{
    # Provider ID as key
    local: [
      name: "Local LLM Provider",
      base_url: "http://localhost:8080",
      env: ["LOCAL_API_KEY"],
      doc: "http://localhost:8080/docs",
      models: %{
        "llama-3-8b" => %{
          name: "Llama 3 8B",
          family: "llama-3",
          capabilities: %{chat: true, tools: %{enabled: true}},
          limits: %{context: 8192, output: 2048},
          cost: %{input: 0.0, output: 0.0}
        },
        "mistral-7b" => %{
          capabilities: %{chat: true}
        }
      }
    ],
    myprovider: [
      name: "My Custom Provider",
      models: %{
        "custom-model" => %{capabilities: %{chat: true}}
      }
    ]
  }

# Use custom models like any other
{:ok, model} = LLMDB.model("local:llama-3-8b")
{:ok, {provider, id}} = LLMDB.select(require: [chat: true], prefer: [:local, :openai])
```

**Filter Rules:**
- Provider keys: atoms or strings; patterns: `"*"` (glob) and `~r//` (Regex)
- Deny wins over allow
- Unknown providers are warned and ignored
- Empty allow map `%{}` behaves like `:all`
- `allow: %{provider: []}` blocks provider entirely

See [Runtime Filters guide](guides/runtime-filters.md) for details and troubleshooting.

## Updating Model Data

Snapshot is shipped with the library. To rebuild with fresh data:

```bash
# Fetch upstream data (optional)
mix llm_db.pull

# Run ETL and write snapshot.json
mix llm_db.build
```

See the [Sources & Engine](guides/sources-and-engine.md) guide for details.

## Using with ReqLLM

Designed to power [ReqLLM](https://github.com/agentjido/req_llm), but fully standalone. Use `model_spec` + `model/1` to retrieve metadata for API calls.

## Contributing

### Setup

```bash
mix setup  # Install dependencies and git hooks
```

### Git Hooks

This project uses [git_hooks](https://hex.pm/packages/git_hooks) to enforce code quality. Hooks install automatically on `mix compile` in dev:

| Hook | Action |
|------|--------|
| **commit-msg** | Validates [conventional commit](https://www.conventionalcommits.org/) format |
| **pre-commit** | Runs `mix format --check-formatted` |
| **pre-push** | Runs `mix quality` (format, compile warnings, dialyzer, credo) |

### Conventional Commits

All commits must follow conventional commit format:

```
type(scope): description

# Examples:
feat: add new provider support
fix: resolve model lookup edge case
docs: update API documentation
chore: update dependencies
```

Types: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, `revert`

## Docs & Guides

- [Using the Data](guides/using-the-data.md) — Runtime API and querying
- [Consumer Integration](guides/consumer-integration.md) — Best practices for libraries using llm_db
- [Runtime Filters](guides/runtime-filters.md) — Load-time and runtime filtering
- [Sources & Engine](guides/sources-and-engine.md) — ETL pipeline, data sources, precedence
- [Schema System](guides/schema-system.md) — Zoi validation and data structures
- [Release Process](guides/release-process.md) — Snapshot-based releases

## License

MIT License - see LICENSE file for details.
