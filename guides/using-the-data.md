# Using the Data

Query, filter, and access LLM model metadata at runtime.

## Loading

### Initial Load

```elixir
# Defaults
{:ok, snapshot} = LLMDB.load()

# With filters and preferences
{:ok, snapshot} = LLMDB.load(
  allow: %{openai: :all, anthropic: ["claude-3*"]},
  deny: %{openai: ["*-deprecated"]},
  prefer: [:anthropic, :openai]
)

# With custom providers
{:ok, snapshot} = LLMDB.load(
  custom: %{
    local: [
      name: "Local Provider",
      base_url: "http://localhost:8080",
      models: %{
        "llama-3" => %{
          capabilities: %{chat: true, tools: %{enabled: true}},
          limits: %{context: 8192, output: 2048}
        }
      }
    ]
  }
)

# With local providers that use a port per model
{:ok, snapshot} = LLMDB.load(
  custom: %{
    vllm: [
      name: "VLLM Provider",
      models: %{
        "llama-3" => %{
          capabilities: %{chat: true, tools: %{enabled: true}},
          limits: %{context: 8192, output: 2048},
          base_url: "http://localhost:8000/v1"
        ,
        "SmolVLM-256M-Instruct" => %{
          capabilities: %{chat: true},
          modalities: %{
            "input" => ["text","image"],
            "output" => ["text"]
          },
          limits: %{context: 8192}
          base_url: "http://localhost:8001/v1"
        }
      }
    ]
  }
)
```

**Steps**:
1. Loads `LLMDB.Packaged.snapshot()` from `priv/llm_db/snapshot.json`
2. Normalizes IDs to atoms
3. Compiles filter patterns
4. Builds indexes (providers_by_id, models_by_key)
5. Applies runtime overrides
6. Stores in `:persistent_term` with epoch

### Reload

```elixir
# Reload with default configuration
{:ok, snapshot} = LLMDB.load()

# Reload with new runtime overrides
{:ok, snapshot} = LLMDB.load(runtime_overrides: %{filter: %{allow: :all, deny: %{}}})
```

### Storage

Stored in `:persistent_term` for O(1) lock-free reads, process-local caching, and epoch-based cache invalidation.

```elixir
LLMDB.epoch()           # => 1
LLMDB.snapshot()        # => %{providers: %{...}, ...}
```

## Listing and Lookup

### Providers

```elixir
# All providers
providers = LLMDB.providers()
# => [%LLMDB.Provider{id: :openai, ...}, ...]

# Specific provider
{:ok, provider} = LLMDB.provider(:openai)
LLMDB.provider(:unknown)  # => :error
```

### Models

```elixir
# All models
models = LLMDB.models()

# Models by provider
openai_models = LLMDB.models(:openai)

# Specific model
{:ok, model} = LLMDB.model(:openai, "gpt-4")
LLMDB.model(:openai, "unknown")  # => {:error, :not_found}

# From spec string
{:ok, model} = LLMDB.model("openai:gpt-4")
```

### Alias Resolution

Models can have multiple aliases that resolve to a single canonical model ID. This is useful for handling naming variations (dots vs dashes, dated vs undated versions, `-latest` shortcuts).

```elixir
# All of these resolve to the same canonical model
{:ok, model} = LLMDB.model(:anthropic, "claude-haiku-4-5-20251001")  # Canonical
{:ok, model} = LLMDB.model(:anthropic, "claude-haiku-4-5")            # Undated
{:ok, model} = LLMDB.model(:anthropic, "claude-haiku-4.5")            # Dot notation
# All return: %LLMDB.Model{id: "claude-haiku-4-5-20251001", ...}

# Aliases work in spec format too
{:ok, model} = LLMDB.model("anthropic:claude-haiku-4.5")
model.id  #=> "claude-haiku-4-5-20251001"

# Check the aliases for a model
model.aliases  #=> ["claude-haiku-4-5", "claude-haiku-4.5"]
```

**How Aliases Work:**
- Each model has ONE canonical `id` (stored in `model.id`)
- Additional naming variants are stored in `model.aliases`
- Lookups check both `id` and `aliases` - both resolve to the same model
- Canonical IDs are typically dated versions (e.g., `claude-haiku-4-5-20251001`)
- Aliases include undated versions, dot/dash variations, and `-latest` shortcuts

**Important for Filtering:**
- Allow/deny filters match against **canonical IDs only**, not aliases
- Alias resolution happens AFTER filtering during model lookup
- Always use canonical IDs in filter patterns (see example below)

```elixir
# ✓ Correct - filter by canonical ID
{:ok, _} = LLMDB.load(
  allow: %{anthropic: ["claude-haiku-4-5-20251001"]},
  deny: %{}
)

# ✗ Incorrect - alias won't match filter
{:ok, _} = LLMDB.load(
  allow: %{anthropic: ["claude-haiku-4.5"]},  # Won't work!
  deny: %{}
)
# This will eliminate all models because "claude-haiku-4.5" is an alias, not a canonical ID
```

## Capabilities

Get capabilities map for a model:

```elixir
{:ok, model} = LLMDB.model("openai:gpt-4o-mini")
LLMDB.capabilities(model)
# => %{chat: true, tools: %{enabled: true, ...}, json: %{native: true, ...}, ...}

LLMDB.capabilities({:openai, "gpt-4o-mini"})
# => %{chat: true, tools: %{enabled: true, ...}, ...}

LLMDB.capabilities("openai:gpt-4o-mini")
# => %{chat: true, ...}
```

## Model Selection

Select models by capability requirements:

```elixir
# Select first match
{:ok, {provider, id}} = LLMDB.select(require: [tools: true])

{:ok, {provider, id}} = LLMDB.select(
  require: [json_native: true, chat: true]
)

# Get all matches
specs = LLMDB.candidates(require: [tools: true])
# => [{:openai, "gpt-4o"}, {:openai, "gpt-4o-mini"}, ...]

# Forbid capabilities
{:ok, {provider, id}} = LLMDB.select(
  require: [tools: true],
  forbid: [streaming_tool_calls: true]
)

# Provider preference (uses configured prefer as default, or override)
{:ok, {provider, id}} = LLMDB.select(
  require: [chat: true],
  prefer: [:anthropic, :openai]
)

# Scope to provider
{:ok, {provider, id}} = LLMDB.select(
  require: [tools: true],
  scope: :openai
)

# Combined - select first match
{:ok, {provider, id}} = LLMDB.select(
  require: [chat: true, json_native: true, tools: true],
  forbid: [streaming_tool_calls: true],
  prefer: [:openai, :anthropic],
  scope: :all
)

# Combined - get all matches
specs = LLMDB.candidates(
  require: [chat: true, json_native: true, tools: true],
  forbid: [streaming_tool_calls: true],
  prefer: [:openai, :anthropic],
  scope: :all
)
```

## Allow/Deny Filters

### Runtime Filters

```elixir
{:ok, _} = LLMDB.load(
  runtime_overrides: %{
    filter: %{
      allow: %{
        openai: ["gpt-4*", "gpt-3.5*"],  # Globs
        anthropic: :all
      },
      deny: %{
        openai: ["*-deprecated"]
      }
    }
  }
)
```

**Rules**:
- Deny wins over allow
- Empty allow map `%{}` behaves like `:all` (allows all)
- `:all` allows all models from provider
- Patterns: exact strings, globs with `*`, or Regex `~r//`
- Unknown providers in filters are warned and ignored

### Check Availability

```elixir
LLMDB.allowed?("openai:gpt-4")               # => true
LLMDB.allowed?({:openai, "gpt-4"})           # => true
LLMDB.allowed?("openai:gpt-4-deprecated")    # => false

{:ok, model} = LLMDB.model("openai:gpt-4")
LLMDB.allowed?(model)                        # => true
```

## Spec Parsing

```elixir
# Parse spec string to {provider, id} tuple
{:ok, {:openai, "gpt-4"}} = LLMDB.parse("openai:gpt-4")
{:ok, {:anthropic, "claude-3-5-sonnet-20241022"}} = LLMDB.parse("anthropic:claude-3-5-sonnet-20241022")
LLMDB.parse("invalid")  # => {:error, :invalid_spec}

# Parse also accepts tuples (passthrough)
{:ok, {:openai, "gpt-4"}} = LLMDB.parse({:openai, "gpt-4"})

# Advanced: Use LLMDB.Spec for additional functionality
{:ok, :openai} = LLMDB.Spec.parse_provider("openai")
LLMDB.Spec.parse_provider("unknown")  # => {:error, :unknown_provider}

{:ok, {:openai, "gpt-4"}} = LLMDB.Spec.parse_spec("openai:gpt-4")
```

## Custom Providers

Add local or private models to the catalog at load time:

```elixir
{:ok, _} = LLMDB.load(
  custom: %{
    local: [
      name: "Local LLM Server",
      base_url: "http://localhost:8080",
      env: ["LOCAL_API_KEY"],
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
    openrouter: [
      name: "OpenRouter",
      base_url: "https://openrouter.ai/api/v1",
      models: %{
        "custom/model" => %{capabilities: %{chat: true}}
      }
    ]
  }
)

# Use custom models
{:ok, model} = LLMDB.model("local:llama-3-8b")
{:ok, {provider, id}} = LLMDB.select(require: [tools: true], prefer: [:local])
```

**Custom Provider Format:**
- Each provider is a top-level key under `:custom`
- Provider config is a keyword list with optional `:name`, `:base_url`, `:env`, `:doc`, `:extra`
- `:models` is required - a map where keys are model IDs and values are model configs
- Models inherit the provider ID automatically
- Custom providers/models merge with packaged data (last wins by ID)

## Load Options

All options passed to `LLMDB.load/1`:

```elixir
{:ok, _} = LLMDB.load(
  allow: %{openai: ["gpt-4*"]},
  deny: %{openai: ["*-preview"]},
  prefer: [:openai, :anthropic],
  custom: %{local: [models: %{"llama-3" => %{capabilities: %{chat: true}}}]}
)
```

These options override application config from `config :llm_db, ...` and trigger:
1. Filter pattern compilation
2. Custom provider/model merging
3. Filter application
4. Index rebuilding
5. Store update with epoch + 1

## Recipes

### Pick JSON-native model, prefer OpenAI, forbid streaming tool calls

```elixir
{:ok, {provider, id}} = LLMDB.select(
  require: [json_native: true],
  forbid: [streaming_tool_calls: true],
  prefer: [:openai]
)
{:ok, model} = LLMDB.model({provider, id})
```

### List Anthropic models with tools

```elixir
specs = LLMDB.candidates(require: [tools: true], scope: :anthropic)
Enum.each(specs, fn {provider, id} ->
  {:ok, model} = LLMDB.model({provider, id})
  IO.puts("#{model.id}: #{model.name}")
end)
```

### Check spec availability

```elixir
case LLMDB.model("openai:gpt-4") do
  {:ok, model} ->
    if LLMDB.allowed?(model) do
      IO.puts("✓ Available: #{model.name}")
    else
      IO.puts("✗ Filtered by allow/deny")
    end
  {:error, :not_found} ->
    IO.puts("✗ Not in catalog")
end
```

### Find cheapest model with capabilities

```elixir
specs = LLMDB.candidates(require: [chat: true, tools: true])

models = 
  for {provider, id} <- specs,
      {:ok, model} <- [LLMDB.model({provider, id})],
      do: model

cheapest = 
  models
  |> Enum.filter(& &1.cost != nil)
  |> Enum.min_by(& &1.cost.input + &1.cost.output, fn -> nil end)

if cheapest do
  IO.puts("#{cheapest.provider}:#{cheapest.id}")
  IO.puts("$#{cheapest.cost.input}/M in + $#{cheapest.cost.output}/M out")
end
```

### Get vision models

```elixir
models = 
  LLMDB.models()
  |> Enum.filter(fn m -> :image in (m.modalities.input || []) end)
```

## Diagnostics

```elixir
LLMDB.epoch()                         # => 1
snapshot = LLMDB.snapshot()
LLMDB.providers() |> length()
LLMDB.models() |> length()
```

## Next Steps

- **[Schema System](schema-system.md)**: Data structures
- **[Release Process](release-process.md)**: Snapshot-based releases
