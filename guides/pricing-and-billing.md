# Pricing and Billing

Query and manage pricing data for LLM models, including token costs, tool usage, and storage fees.

## Overview

LLMDB provides a flexible pricing system that supports:

- **Token-based pricing** - Input, output, cache, and reasoning tokens
- **Tool pricing** - Per-call fees for web search, code interpreter, file search, etc.
- **Storage pricing** - Per-GB-day fees for file storage
- **Image/media pricing** - Per-image or per-token fees for multimodal content

The pricing system has two layers:

1. **Legacy `cost` field** - Simple per-million-token pricing (input, output, cache, reasoning)
2. **New `pricing` field** - Component-based pricing with full flexibility

Legacy `cost` data is automatically converted to `pricing.components` at load time, ensuring backward compatibility.

## Pricing Components

Each pricing component describes a single billable item with the following fields:

```elixir
%{
  id: "token.input",           # Unique identifier
  kind: "token",               # Category: token, tool, image, storage, request, other
  unit: "token",               # Unit type: token, call, query, session, gb_day, image, source, other
  per: 1_000_000,              # Rate denominator (e.g., per 1M tokens)
  rate: 3.0,                   # Cost in currency units
  meter: "input_tokens",       # Optional: billing meter name
  tool: "web_search",          # Optional: tool name (for kind: "tool")
  size_class: "1024x1024",     # Optional: size variant (for images)
  notes: "Cached tokens"       # Optional: human-readable notes
}
```

### Component Kinds

| Kind | Description | Common Units |
|------|-------------|--------------|
| `token` | Token-based billing | `token` |
| `tool` | Tool/feature usage | `call`, `query`, `session` |
| `image` | Image generation/processing | `image` |
| `storage` | Data storage fees | `gb_day` |
| `request` | Per-request fees | `call` |
| `other` | Custom billing types | varies |

### Standard Component IDs

Token components use the `token.*` prefix:

- `token.input` - Input tokens
- `token.output` - Output tokens
- `token.cache_read` - Cached input tokens (read)
- `token.cache_write` - Tokens written to cache
- `token.reasoning` - Reasoning/thinking tokens

Tool components use the `tool.*` prefix:

- `tool.web_search` - Web search calls
- `tool.file_search` - File search calls
- `tool.code_interpreter` - Code interpreter sessions

## Provider Defaults

Providers can define default pricing for tools and features that apply to all their models. This avoids duplicating tool pricing across every model definition.

### TOML Configuration

```toml
# priv/llm_db/local/openai/provider.toml
[pricing_defaults]
currency = "USD"

[[pricing_defaults.components]]
id = "tool.web_search"
kind = "tool"
tool = "web_search"
unit = "call"
per = 1000
rate = 10.0

[[pricing_defaults.components]]
id = "tool.file_search"
kind = "tool"
tool = "file_search"
unit = "call"
per = 1000
rate = 2.5

[[pricing_defaults.components]]
id = "storage.file_search"
kind = "storage"
unit = "gb_day"
per = 1
rate = 0.10
meter = "file_search_storage_gb_day"

[[pricing_defaults.components]]
id = "tool.code_interpreter"
kind = "tool"
tool = "code_interpreter"
unit = "session"
per = 1
rate = 0.03
```

### Built-in Provider Defaults

| Provider | Tools | Notes |
|----------|-------|-------|
| OpenAI | `web_search`, `web_search_preview`, `file_search`, `code_interpreter` | Plus file search storage |
| Anthropic | `web_search` | $10/1000 calls |
| Google | `web_search` | $35/1000 calls |
| xAI | `web_search`, `x_search`, `code_execution`, `document_search`, `collections_search` | Various rates |

### How Defaults Are Applied

Provider defaults are merged with model pricing at load time:

1. Models without `pricing` inherit the full provider defaults
2. Models with `pricing` merge components by ID (default) or replace entirely

```
Provider defaults + Model overrides = Final model.pricing
```

## Merge Strategies

When a model defines its own `pricing`, you can control how it combines with provider defaults using the `merge` field.

### merge_by_id (Default)

Merges components by their `id`. Model components override matching defaults; non-matching defaults are preserved.

```elixir
# Provider default
%{id: "tool.web_search", rate: 10.0}

# Model override
%{pricing: %{
  merge: "merge_by_id",
  components: [%{id: "tool.web_search", rate: 5.0}]  # Override rate
}}

# Result: web_search at $5/1000, other provider defaults preserved
```

### replace

Completely replaces provider defaults with model-specific pricing.

```elixir
# Model with custom pricing only
%{pricing: %{
  merge: "replace",
  components: [
    %{id: "token.input", kind: "token", unit: "token", per: 1_000_000, rate: 1.0}
  ]
}}

# Result: Only token.input component, no provider defaults
```

### TOML Example

```toml
# Model with discounted web search
[pricing]
merge = "merge_by_id"

[[pricing.components]]
id = "tool.web_search"
kind = "tool"
tool = "web_search"
unit = "call"
per = 1000
rate = 5.0  # 50% discount from provider default
```

## Querying Pricing Data

### Access Model Pricing

```elixir
{:ok, model} = LLMDB.model("openai:gpt-4o")

# Full pricing structure
model.pricing
# => %{
#      currency: "USD",
#      components: [
#        %{id: "token.input", kind: "token", unit: "token", per: 1_000_000, rate: 2.5},
#        %{id: "token.output", kind: "token", unit: "token", per: 1_000_000, rate: 10.0},
#        %{id: "tool.web_search", kind: "tool", tool: "web_search", unit: "call", per: 1000, rate: 10.0},
#        ...
#      ]
#    }

# Legacy cost field (still available)
model.cost
# => %{input: 2.5, output: 10.0, ...}
```

### Find Specific Components

```elixir
# Get token input rate
input_component = Enum.find(model.pricing.components, & &1.id == "token.input")
input_component.rate  # => 2.5

# Get all tool pricing
tool_components = Enum.filter(model.pricing.components, & &1.kind == "tool")

# Check if model has web search pricing
has_web_search = Enum.any?(model.pricing.components, & &1.tool == "web_search")
```

### Calculate Costs

```elixir
defmodule CostCalculator do
  def token_cost(model, input_tokens, output_tokens) do
    components = model.pricing.components

    input_rate = get_rate(components, "token.input")
    output_rate = get_rate(components, "token.output")

    (input_tokens * input_rate / 1_000_000) + (output_tokens * output_rate / 1_000_000)
  end

  def tool_cost(model, tool_name, call_count) do
    component = Enum.find(model.pricing.components, & &1.tool == tool_name)

    if component do
      call_count * component.rate / component.per
    else
      0.0
    end
  end

  defp get_rate(components, id) do
    case Enum.find(components, & &1.id == id) do
      nil -> 0.0
      comp -> comp.rate
    end
  end
end

# Usage
{:ok, model} = LLMDB.model("openai:gpt-4o")
CostCalculator.token_cost(model, 1000, 500)      # => 0.0075
CostCalculator.tool_cost(model, "web_search", 5) # => 0.05
```

## Migration from Legacy Cost Format

The legacy `cost` field is automatically converted to `pricing.components` at load time by `LLMDB.Pricing.apply_cost_components/1`.

### Mapping

| Legacy Field | Component ID | Kind | Unit | Per |
|--------------|--------------|------|------|-----|
| `cost.input` | `token.input` | token | token | 1,000,000 |
| `cost.output` | `token.output` | token | token | 1,000,000 |
| `cost.cache_read` | `token.cache_read` | token | token | 1,000,000 |
| `cost.cache_write` | `token.cache_write` | token | token | 1,000,000 |
| `cost.reasoning` | `token.reasoning` | token | token | 1,000,000 |

### Example Conversion

```elixir
# Legacy format (in TOML or input data)
%{
  cost: %{input: 3.0, output: 15.0, cache_read: 0.3}
}

# Automatically becomes
%{
  cost: %{input: 3.0, output: 15.0, cache_read: 0.3},
  pricing: %{
    currency: "USD",
    components: [
      %{id: "token.input", kind: "token", unit: "token", per: 1_000_000, rate: 3.0},
      %{id: "token.output", kind: "token", unit: "token", per: 1_000_000, rate: 15.0},
      %{id: "token.cache_read", kind: "token", unit: "token", per: 1_000_000, rate: 0.3}
    ]
  }
}
```

The legacy `cost` field remains available for backward compatibility with existing code.

## Custom Providers with Pricing

When defining custom providers at runtime, you can include `pricing_defaults`:

```elixir
{:ok, _} = LLMDB.load(
  custom: %{
    my_provider: [
      name: "My Provider",
      base_url: "https://api.example.com/v1",
      pricing_defaults: %{
        currency: "USD",
        components: [
          %{id: "tool.custom_search", kind: "tool", tool: "custom_search", unit: "call", per: 1000, rate: 5.0},
          %{id: "storage.vectors", kind: "storage", unit: "gb_day", per: 1, rate: 0.05}
        ]
      },
      models: %{
        "my-model" => %{
          name: "My Model",
          capabilities: %{chat: true, tools: %{enabled: true}},
          cost: %{input: 1.0, output: 2.0}
        }
      }
    ]
  }
)

# The model inherits provider pricing_defaults
{:ok, model} = LLMDB.model("my_provider:my-model")
model.pricing.components
# => [
#   %{id: "token.input", ...},
#   %{id: "token.output", ...},
#   %{id: "tool.custom_search", ...},
#   %{id: "storage.vectors", ...}
# ]
```

### Model-Level Pricing Overrides

```elixir
{:ok, _} = LLMDB.load(
  custom: %{
    my_provider: [
      name: "My Provider",
      pricing_defaults: %{
        currency: "USD",
        components: [
          %{id: "tool.search", kind: "tool", tool: "search", unit: "call", per: 1000, rate: 10.0}
        ]
      },
      models: %{
        "basic-model" => %{
          capabilities: %{chat: true},
          cost: %{input: 1.0, output: 2.0}
          # Inherits tool.search at $10/1000
        },
        "premium-model" => %{
          capabilities: %{chat: true},
          cost: %{input: 5.0, output: 15.0},
          pricing: %{
            merge: "merge_by_id",
            components: [
              # Free search for premium tier
              %{id: "tool.search", kind: "tool", tool: "search", unit: "call", per: 1000, rate: 0.0}
            ]
          }
        }
      }
    ]
  }
)
```

## Next Steps

- **[Schema System](schema-system.md)**: Full schema definitions including pricing
- **[Using the Data](using-the-data.md)**: Runtime API and queries
