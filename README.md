# LLMModels

[![Hex.pm](https://img.shields.io/hexpm/v/llm_models.svg)](https://hex.pm/packages/llm_models)
[![License](https://img.shields.io/hexpm/l/llm_models.svg)](https://github.com/yourorg/llm_models/blob/main/LICENSE)

Fast, persistent_term-backed LLM model metadata catalog with explicit refresh controls.

`llm_models` provides a standalone, capability-aware query API for LLM model metadata. It ships with a packaged snapshot, supports manual refresh from [models.dev](https://models.dev), and offers O(1) lock-free queries backed by `:persistent_term`.

## Overview

`llm_models` centralizes model metadata lifecycle (ingest → normalize → validate → enrich → index → publish) behind a simple, reusable library designed for Elixir AI applications like ReqLLM.

### Why LLMModels?

- **Packaged snapshot**: Ships with model data—no network required by default
- **Fast queries**: O(1), lock-free reads via `:persistent_term`
- **Explicit refresh**: Manual updates only via `mix llm_models.pull`
- **Capability-based selection**: Find models by features (tools, JSON mode, streaming, etc.)
- **Canonical spec parsing**: Owns "provider:model" format parsing and resolution
- **Flexible overrides**: Configure via `config.exs` or custom behaviour modules

### Key Features

- **No magic**: Stability-first design with explicit semantics
- **Simple allow/deny filtering**: Control which models are available
- **Precedence rules**: Packaged snapshot < config overrides < behaviour overrides
- **Forward compatible**: Unknown upstream keys pass through to `extra` field
- **Minimal dependencies**: Only `zoi` (validation) and `jason` (JSON)

## Installation

Add `llm_models` to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:llm_models, "~> 0.1.0"}
  ]
end
```

## Quick Start

```elixir
# Get all providers as structs (catalog loads automatically at startup)
providers = LLMModels.providers()
#=> [%LLMModels.Provider{id: :anthropic, ...}, ...]

# Get a specific model
{:ok, model} = LLMModels.model("openai:gpt-4o-mini")
#=> {:ok, %LLMModels.Model{id: "gpt-4o-mini", provider: :openai, ...}}

# Access model properties
model.capabilities.tools.enabled  #=> true
model.cost.input                  #=> 0.15
model.limits.context              #=> 128000

# Find models with specific capabilities
{:ok, {:openai, "gpt-4o-mini"}} = LLMModels.select(
  require: [chat: true, tools: true, json_native: true],
  prefer: [:openai, :anthropic]
)
```

## Data Structures

### Provider Struct

The `LLMModels.Provider` struct represents an LLM provider with Zoi validation:

```elixir
%LLMModels.Provider{
  id: :openai,
  name: "OpenAI",
  base_url: "https://api.openai.com",
  env: ["OPENAI_API_KEY"],
  doc: "https://platform.openai.com/docs",
  extra: %{}  # Additional provider-specific metadata
}
```

### Model Struct

The `LLMModels.Model` struct represents an LLM model with complete metadata:

```elixir
%LLMModels.Model{
  id: "gpt-4o-mini",
  provider: :openai,
  name: "GPT-4o mini",
  family: "gpt-4o",
  limits: %{context: 128000, output: 16384},
  cost: %{input: 0.15, output: 0.60},
  capabilities: %{
    chat: true,
    tools: %{enabled: true, streaming: true},
    json: %{native: true, schema: true},
    streaming: %{text: true, tool_calls: true}
  },
  tags: ["fast", "efficient"],
  deprecated?: false,
  aliases: ["gpt-4-mini"],
  extra: %{}
}
```

## Usage

### Loading the Catalog

The catalog loads automatically when your application starts. You can also reload it manually:

```elixir
# Reload with last-known options
:ok = LLMModels.reload()

# Get current snapshot
snapshot = LLMModels.snapshot()

# Get current epoch (increments on each load)
epoch = LLMModels.epoch()
```

### Querying Providers

```elixir
# Get all providers as structs
providers = LLMModels.providers()
#=> [%LLMModels.Provider{id: :anthropic, ...}, %LLMModels.Provider{id: :openai, ...}]

# Get a specific provider
{:ok, provider} = LLMModels.get_provider(:openai)
#=> {:ok, %LLMModels.Provider{...}}

provider.name        #=> "OpenAI"
provider.base_url    #=> "https://api.openai.com"
provider.env         #=> ["OPENAI_API_KEY"]

# List provider IDs only
provider_ids = LLMModels.list_providers()
#=> [:anthropic, :google_vertex, :openai]
```

### Querying Models

```elixir
# Get a model by spec string
{:ok, model} = LLMModels.model("openai:gpt-4o-mini")
#=> {:ok, %LLMModels.Model{...}}

# Or by provider and ID
{:ok, model} = LLMModels.get_model(:openai, "gpt-4o-mini")

# Access model properties
model.id                    #=> "gpt-4o-mini"
model.provider              #=> :openai
model.family                #=> "gpt-4o"
model.limits.context        #=> 128000
model.limits.output         #=> 16384
model.cost.input            #=> 0.15 (per 1M tokens)
model.cost.output           #=> 0.60 (per 1M tokens)
model.capabilities.tools.enabled  #=> true
model.capabilities.json.native    #=> true

# List all models for a provider (returns maps, not structs)
models = LLMModels.list_models(:openai)

# Filter by capabilities
models = LLMModels.list_models(:openai,
  require: [tools: true, json_native: true],
  forbid: [streaming_tool_calls: true]
)
```

### Model Selection

Find the best model matching your criteria:

```elixir
# Select with capability requirements
{:ok, {provider, model_id}} = LLMModels.select(
  require: [chat: true, tools: true, json_native: true],
  prefer: [:openai, :anthropic]
)

# Select from specific provider
{:ok, {provider, model_id}} = LLMModels.select(
  require: [tools: true],
  scope: :openai
)

# Select with forbidden capabilities
{:ok, {provider, model_id}} = LLMModels.select(
  require: [chat: true],
  forbid: [streaming_tool_calls: true],
  prefer: [:anthropic]
)

# Handle no match
case LLMModels.select(require: [impossible: true]) do
  {:ok, {provider, model_id}} -> # use model
  {:error, :no_match} -> # fallback
end
```

**Supported capability keys:**

- `:chat` - Chat completion support
- `:embeddings` - Embeddings support
- `:reasoning` - Extended reasoning capability
- `:tools` - Tool/function calling
- `:tools_streaming` - Streaming tool calls
- `:tools_strict` - Strict tool schemas
- `:tools_parallel` - Parallel tool execution
- `:json_native` - Native JSON mode
- `:json_schema` - JSON schema support
- `:json_strict` - Strict JSON mode
- `:streaming_text` - Text streaming
- `:streaming_tool_calls` - Tool call streaming

### Spec Parsing

Parse and resolve model specifications:

```elixir
# Parse "provider:model" spec and get Model struct
{:ok, model} = LLMModels.model("openai:gpt-4o-mini")
#=> {:ok, %LLMModels.Model{id: "gpt-4o-mini", provider: :openai, ...}}

# Also accepts tuples
{:ok, model} = LLMModels.model({:openai, "gpt-4o-mini"})

# Parse provider identifier
{:ok, :openai} = LLMModels.parse_provider("openai")
{:ok, :google_vertex} = LLMModels.parse_provider("google-vertex")
{:error, :unknown_provider} = LLMModels.parse_provider("invalid")

# Parse spec to tuple (for backwards compatibility)
{:ok, {:openai, "gpt-4o-mini"}} = LLMModels.parse_spec("openai:gpt-4o-mini")
{:error, :invalid_format} = LLMModels.parse_spec("no-colon")

# Resolve spec to full model record (returns map, not struct)
{:ok, {provider, id, model_map}} = LLMModels.resolve("openai:gpt-4o-mini")

# Handle aliases
{:ok, model} = LLMModels.model("openai:gpt-4-mini")
model.id  #=> "gpt-4o-mini" (canonical ID)
```

### Checking Availability

Use allow/deny filters to control model availability:

```elixir
# Check if a model is allowed
true = LLMModels.allowed?({:openai, "gpt-4o-mini"})
false = LLMModels.allowed?({:openai, "gpt-5-pro"})  # if denied

# Works with spec strings too
true = LLMModels.allowed?("openai:gpt-4o-mini")
```

## Configuration

Configure `llm_models` in your `config/config.exs`:

```elixir
config :llm_models,
  # Embed snapshot at compile time (default: false)
  compile_embed: false,

  # Provider and model overrides
  overrides: %{
    providers: [
      %{id: :openai, env: ["OPENAI_API_KEY"]},
      %{id: :anthropic, env: ["ANTHROPIC_API_KEY"]}
    ],
    models: [
      %{
        id: "gpt-4o-mini",
        provider: :openai,
        capabilities: %{
          tools: %{enabled: true, streaming: false},
          json: %{native: true}
        }
      }
    ],
    # Exclude specific models (supports glob patterns)
    exclude: %{
      openai: ["gpt-5-pro", "o3-*"],
      anthropic: ["claude-instant-*"]
    }
  },

  # Custom overrides module (see below)
  overrides_module: MyApp.LlmModelOverrides,

  # Global allow/deny filters
  allow: %{
    openai: :all,
    anthropic: ["claude-3-*", "claude-4-*"]
  },
  deny: %{
    openai: ["*-preview"]
  },

  # Provider preference order
  prefer: [:openai, :anthropic, :google_vertex]
```

### Precedence Rules

Sources are merged in this order (later wins):

1. **Packaged snapshot** (bundled in `priv/llm_models/snapshot.json`)
2. **Config overrides** (`:llm_models, :overrides`)
3. **Behaviour overrides** (`:llm_models, :overrides_module`)

For maps, fields are deep-merged. For lists, values are deduplicated. For scalars, higher precedence wins.

**Deny always wins over allow.**

## Custom Overrides

For more control, implement the `LLMModels.Overrides` behaviour:

```elixir
defmodule MyApp.LlmModelOverrides do
  use LLMModels.Overrides

  @impl true
  def providers do
    [
      %{id: :openai, env: ["OPENAI_API_KEY"], base_url: "https://api.openai.com"},
      %{id: :custom_provider, env: ["CUSTOM_API_KEY"], base_url: "https://custom.ai"}
    ]
  end

  @impl true
  def models do
    [
      %{
        id: "gpt-4o-mini",
        provider: :openai,
        capabilities: %{
          tools: %{enabled: true, streaming: false},
          json: %{native: true, schema: true}
        }
      },
      %{
        id: "custom-model",
        provider: :custom_provider,
        capabilities: %{chat: true}
      }
    ]
  end

  @impl true
  def excludes do
    %{
      openai: ["gpt-5-pro", "o3-*"],
      anthropic: ["claude-instant-*"]
    }
  end
end
```

Then configure the module:

```elixir
config :llm_models, overrides_module: MyApp.LlmModelOverrides
```

The `use LLMModels.Overrides` macro provides default implementations (empty lists/maps), so you only need to override what you need.

## Updating Model Data

Model data is packaged in the library. To update:

### Pull Latest Data

```bash
# Fetch from models.dev and regenerate snapshot
mix llm_models.pull

# Fetch from custom URL
mix llm_models.pull --url https://custom.source/api.json
```

This downloads upstream data from models.dev (or custom URL), transforms it, validates it, merges with your config overrides, and writes:

- `priv/llm_models/upstream.json` - Raw upstream data
- `priv/llm_models/snapshot.json` - Processed snapshot
- `lib/llm_models/generated/valid_providers.ex` - Generated provider atoms module

### Reload in Development

```elixir
# Reload catalog without recompiling
LLMModels.reload()
```

This re-reads the snapshot.json file and updates the `:persistent_term` storage.

## Architecture

### ETL Pipeline

The catalog is built through a seven-stage pipeline:

1. **Ingest** - Load from packaged snapshot, config overrides, behaviour overrides
2. **Normalize** - Convert provider IDs to atoms, standardize dates and formats
3. **Validate** - Validate via Zoi schemas, drop invalid entries
4. **Merge** - Apply precedence rules (deep merge maps, dedupe lists)
5. **Enrich** - Derive `family` from model ID, apply capability defaults
6. **Filter** - Apply global allow/deny patterns
7. **Index + Publish** - Build indexes and publish to `:persistent_term`

### Storage

- **Runtime loading**: `LLMModels.load/1` reads snapshot, merges with config overrides, and publishes to `:persistent_term`
- **Reads**: All queries use `:persistent_term.get(:llm_models_snapshot)` for O(1), lock-free access
- **No ETS**: Simpler and faster with `:persistent_term`
- **Optional compile-time embedding**: Set `compile_embed: true` to embed snapshot at compile time (default: false)

### Data Structures

Internally, the snapshot contains:

- `providers_by_id` - Map of provider atoms to provider metadata
- `models` - Map of provider atoms to lists of models
- `models_by_key` - Map of `{provider, id}` tuples to model records
- `aliases_by_key` - Map of `{provider, alias}` to canonical model IDs
- `filters` - Compiled allow/deny patterns

## Integration with ReqLLM

`llm_models` was designed to power ReqLLM but can be used standalone. The catalog loads automatically when your application starts.

In ReqLLM integration:

```elixir
# Get model struct
{:ok, model} = LLMModels.model("openai:gpt-4o-mini")

# Access model properties
model.capabilities.tools.enabled    #=> true
model.capabilities.streaming.text   #=> true
model.cost.input                    #=> 0.15

# Select best model for requirements
{:ok, {provider, id}} = LLMModels.select(
  require: [tools: true, streaming_text: true],
  prefer: [:openai]
)

# Then get the full model struct
{:ok, model} = LLMModels.model({provider, id})
```

## API Reference

### Main Module: `LLMModels`

**Lifecycle:**

- `load/1` - Load catalog and publish to persistent_term
- `reload/0` - Reload using last-known options
- `snapshot/0` - Get current snapshot
- `epoch/0` - Get current epoch

**Lookup and Listing:**

- `providers/0` - Get all providers as Provider structs
- `list_providers/0` - List provider IDs as atoms
- `get_provider/1` - Get provider as Provider struct
- `model/1` - Parse spec and get Model struct
- `get_model/2` - Get model by provider and ID as Model struct
- `list_models/2` - List models with filters (returns maps)
- `capabilities/1` - Get model capabilities map
- `allowed?/1` - Check if model passes filters

**Selection:**

- `select/1` - Select model by capability requirements

**Spec Parsing:**

- `parse_provider/1` - Parse provider identifier
- `model/1` - Parse "provider:model" spec
- `resolve/2` - Resolve spec to model record

### Behaviour: `LLMModels.Overrides`

**Callbacks:**

- `providers/0` - Return provider overrides
- `models/0` - Return model overrides
- `excludes/0` - Return exclusion patterns

### Mix Tasks

- `mix llm_models.pull` - Fetch latest data from models.dev and regenerate snapshot

## Design Principles

From the [design plan](LLM_MODELS_PLAN.md):

1. **Standalone with packaged snapshot** - No network required by default
2. **Manual refresh only** - Explicit updates via Mix tasks
3. **O(1) lock-free queries** - Fast reads via `:persistent_term`
4. **Simple allow/deny filtering** - Clear, compiled-once patterns
5. **Explicit semantics** - No magic, predictable behavior
6. **Stability first** - Remove over-engineering, focus on the 80% case

### Simplifications

- No per-field provenance in v1 (may add debug mode later)
- Dates stored as strings (`"YYYY-MM-DD"`)
- No DSL for overrides (use behaviour callbacks and plain maps)
- No schema version juggling (handled by code updates)
- Selection returns simple match or `:no_match`

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Add tests for new functionality
4. Ensure `mix test` passes
5. Submit a pull request

## License

MIT License. See [LICENSE](LICENSE) for details.

---

For detailed architectural information, see [LLM_MODELS_PLAN.md](LLM_MODELS_PLAN.md).
