# Using the Data

Query, filter, and access LLM model metadata at runtime.

## Loading

### Initial Load

```elixir
# Defaults
{:ok, snapshot} = LLMModels.load()

# Runtime overrides
{:ok, snapshot} = LLMModels.load(
  runtime_overrides: %{
    filters: %{
      allow: %{openai: :all, anthropic: ["claude-3*"]},
      deny: %{openai: ["*-deprecated"]}
    },
    prefer: [:anthropic, :openai]
  }
)
```

**Steps**:
1. Loads `LLMModels.Packaged.snapshot()` from `priv/llm_models/snapshot.json`
2. Normalizes IDs to atoms
3. Compiles filter patterns
4. Builds indexes (providers_by_id, models_by_key)
5. Applies runtime overrides
6. Stores in `:persistent_term` with epoch

### Reload

```elixir
{:ok, snapshot} = LLMModels.reload()
```

### Storage

Stored in `:persistent_term` for O(1) lock-free reads, process-local caching, and epoch-based cache invalidation.

```elixir
LLMModels.epoch()           # => 1
LLMModels.snapshot()        # => %{providers: %{...}, ...}
```

## Listing and Lookup

### Providers

```elixir
# All providers
providers = LLMModels.providers()
# => [%LLMModels.Provider{id: :openai, ...}, ...]

# Specific provider
{:ok, provider} = LLMModels.provider(:openai)
LLMModels.provider(:unknown)  # => :error
```

### Models

```elixir
# All models
models = LLMModels.models()

# Models by provider
openai_models = LLMModels.models(:openai)

# Specific model
{:ok, model} = LLMModels.model(:openai, "gpt-4")
LLMModels.model(:openai, "unknown")  # => {:error, :not_found}

# From spec string
{:ok, model} = LLMModels.model("openai:gpt-4")
```

### Alias Resolution

Aliases auto-resolve:

```elixir
{:ok, model} = LLMModels.model(:openai, "gpt4")
# => {:ok, %LLMModels.Model{id: "gpt-4", ...}}

{:ok, model} = LLMModels.model("openai:gpt4")
```

## Capabilities

Get capability keys for filtering:

```elixir
LLMModels.capabilities(model)
# => [:chat, :tools, :json_native, :streaming_text, ...]

LLMModels.capabilities({:openai, "gpt-4"})
LLMModels.capabilities("openai:gpt-4")
```

## Model Selection

Select models by requirements:

```elixir
# Basic requirements
models = LLMModels.select(require: [tools: true])

models = LLMModels.select(
  require: [json_native: true, chat: true]
)

# Forbid capabilities
models = LLMModels.select(
  require: [tools: true],
  forbid: [streaming_tool_calls: true]
)

# Provider preference
models = LLMModels.select(
  require: [chat: true],
  prefer: [:anthropic, :openai]
)

# Scope to provider
models = LLMModels.select(
  require: [tools: true],
  scope: :openai
)

# Combined
models = LLMModels.select(
  require: [chat: true, json_native: true, tools: true],
  forbid: [streaming_tool_calls: true],
  prefer: [:openai, :anthropic],
  scope: :all
)
```

## Allow/Deny Filters

### Runtime Filters

```elixir
{:ok, _} = LLMModels.load(
  runtime_overrides: %{
    filters: %{
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
- Empty allow map denies all unless explicitly allowed
- `:all` allows all models from provider
- Patterns: exact strings or globs with `*`

### Check Availability

```elixir
LLMModels.allowed?(:openai, "gpt-4")           # => true
LLMModels.allowed?(:openai, "gpt-4-deprecated") # => false
```

## Spec Parsing

```elixir
# Parse provider
{:ok, :openai} = LLMModels.Spec.parse_provider("openai")
LLMModels.Spec.parse_provider("unknown")  # => {:error, :unknown_provider}

# Parse spec
{:ok, {:openai, "gpt-4"}} = LLMModels.Spec.parse_spec("openai:gpt-4")
LLMModels.Spec.parse_spec("invalid")  # => {:error, :invalid_spec}

# Resolve (handles Bedrock inference profiles)
{:ok, {:openai, "gpt-4"}} = LLMModels.Spec.resolve("openai:gpt-4", snapshot)

{:ok, {:bedrock, "us.anthropic.claude-3-sonnet-20240229-v1:0"}} =
  LLMModels.Spec.resolve("bedrock:us.anthropic.claude-3-sonnet-20240229-v1:0", snapshot)
```

## Runtime Overrides

Runtime overrides **only** affect filters and preferences, not provider/model data.

```elixir
{:ok, _} = LLMModels.load(
  runtime_overrides: %{
    filters: %{allow: %{openai: ["gpt-4"]}, deny: %{}},
    prefer: [:openai]
  }
)
```

Triggers `LLMModels.Runtime.apply/2`:
1. Recompiles filter patterns
2. Rebuilds indexes (excludes filtered models)
3. Stores snapshot with epoch + 1

## Recipes

### Pick JSON-native model, prefer OpenAI, forbid streaming tool calls

```elixir
models = LLMModels.select(
  require: [json_native: true],
  forbid: [streaming_tool_calls: true],
  prefer: [:openai]
)
model = List.first(models)
```

### List Anthropic models with tools

```elixir
models = LLMModels.select(require: [tools: true], scope: :anthropic)
Enum.each(models, fn m -> IO.puts("#{m.id}: #{m.name}") end)
```

### Check spec availability

```elixir
case LLMModels.model("openai:gpt-4") do
  {:ok, model} ->
    if LLMModels.allowed?(model.provider, model.id) do
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
models = LLMModels.select(require: [chat: true, tools: true])

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
  LLMModels.models()
  |> Enum.filter(fn m -> :image in (m.modalities.input || []) end)
```

## Diagnostics

```elixir
LLMModels.epoch()                         # => 1
snapshot = LLMModels.snapshot()
LLMModels.providers() |> length()
LLMModels.models() |> length()
```

## Next Steps

- **[Schema System](schema-system.md)**: Data structures
- **[Release Process](release-process.md)**: Snapshot-based releases
