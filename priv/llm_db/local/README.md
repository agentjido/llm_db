# Local TOML Model Definitions

This directory contains example TOML files for defining custom LLM providers and models using the **canonical schema format**.

## Directory Structure

```
priv/llm_db/local/
├── openai/
│   ├── provider.toml         # Provider definition
│   ├── gpt-4o.toml           # Model
│   └── gpt-4o-mini.toml      # Model
├── anthropic/
│   ├── provider.toml
│   └── claude-3-5-sonnet.toml
└── custom/
    ├── provider.toml
    └── my-model.toml
```

## File Naming Convention

- **Provider files**: Must be named `provider.toml`
- **Model files**: Can be any name ending in `.toml` (e.g., `gpt-4o.toml`)

## Provider TOML Schema

```toml
id = "provider-id"           # Required: atom-compatible string
name = "Provider Name"       # Optional: display name
base_url = "https://..."     # Optional: API base URL
doc = "https://..."          # Optional: documentation URL
env = ["API_KEY_VAR"]        # Optional: environment variable names

[extra]                      # Optional: custom fields
custom_field = "value"
```

## Model TOML Schema (Canonical Format)

**IMPORTANT**: Local TOML files must use the canonical schema format exactly as defined in `lib/llm_db/schema/model.ex`. No transformation is applied - fields are used as-is after atomizing keys.

```toml
# Required Fields
id = "model-id"                      # Required: unique model identifier

# Optional Identity Fields
provider_model_id = "api-model-id"   # Optional: provider's API model ID
name = "Model Display Name"          # Optional: human-readable name
family = "model-family"              # Optional: model family/series
release_date = "2024-01-15"         # Optional: ISO date
last_updated = "2024-02-20"         # Optional: last update date
knowledge = "2024-01"               # Optional: knowledge cutoff date
tags = ["tag1", "tag2"]             # Optional: categorization tags
aliases = ["alias1"]                # Optional: alternative model names
deprecated = false                  # Optional: deprecation status (default: false)

# Limits (all values must be integers >= 1)
[limits]
context = 128000                    # Optional: max context window tokens
output = 4096                       # Optional: max output tokens

# Cost (per 1M tokens, floating point)
[cost]
input = 1.00                        # Optional: input cost per 1M tokens
output = 2.00                       # Optional: output cost per 1M tokens
cache_read = 0.10                   # Optional: cache read cost per 1M tokens
cache_write = 1.25                  # Optional: cache write cost per 1M tokens
training = 5.00                     # Optional: training cost
image = 0.50                        # Optional: image processing cost
audio = 0.25                        # Optional: audio processing cost

# Modalities (arrays of strings - converted to atoms)
[modalities]
input = ["text", "image", "audio"]  # Optional: input modalities
output = ["text"]                   # Optional: output modalities
# Valid modalities: text, image, audio, video, code, document, embedding, pdf

# Capabilities (nested structure with defaults from schema)
[capabilities.reasoning]
enabled = true                      # Optional: reasoning capability
token_budget = 10000               # Optional: reasoning token budget

[capabilities.tools]
enabled = true                      # Optional: tool/function calling
streaming = false                   # Optional: streaming tool calls
strict = false                      # Optional: strict schema enforcement
parallel = false                    # Optional: parallel tool execution

[capabilities.json]
native = false                      # Optional: native JSON mode
schema = false                      # Optional: JSON schema support
strict = false                      # Optional: strict JSON validation

[capabilities.streaming]
text = true                         # Optional: text streaming (default: true)
tool_calls = false                  # Optional: tool call streaming

# Note: capabilities.chat and capabilities.embeddings have defaults (true/false)
# and can be omitted unless you need to override them

# Extra Fields (arbitrary nested data preserved as-is)
[extra]
deployment_id = "prod-001"
custom_metadata = "value"

# Wire Protocol Selection (for API client libraries)
[extra.wire]
protocol = "openai_responses"    # openai_chat | openai_responses | anthropic

# Parameter Constraints (for API client libraries)
[extra.constraints]
token_limit_key = "max_completion_tokens"  # max_tokens | max_completion_tokens
temperature = "unsupported"                # any | unsupported | fixed_1
reasoning_effort = "supported"             # unsupported | supported | required
min_output_tokens = 16                     # integer minimum for output tokens
```

## Field Mapping Reference

The Local source uses the **canonical schema** directly (after atomizing keys). Field names must match the schema exactly:

### Limits
- ✅ Use: `limits.context` and `limits.output`
- ❌ Not: `max_input_tokens`, `max_output_tokens`
- Values must be integers >= 1 (0 is invalid)

### Cost
- ✅ Use: `cost.input`, `cost.output`, `cost.cache_read`, `cost.cache_write`
- ❌ Not: `input_per_1m`, `output_per_1m`
- Values are floating point numbers (cost per 1M tokens)

### Capabilities
- Use nested TOML tables for capability groups
- Example: `[capabilities.tools]` with `enabled = true`
- All capability fields have schema defaults (can be omitted)

### Modalities
- String arrays that get converted to atom arrays during load
- Valid values: `text`, `image`, `audio`, `video`, `code`, `document`, `embedding`, `pdf`

## Usage

1. Create a directory named after your provider ID
2. Add a `provider.toml` file with provider metadata
3. Add model TOML files for each model
4. Configure the Local source in your application:

```elixir
config :llm_db,
  sources: [
    {LLMDB.Sources.Local, %{dir: "priv/llm_db/local"}},
    # ... other sources
  ]
```

5. Run `mix llm_db.build` to generate the snapshot

## Examples

See the example files in this directory:
- `openai/` - OpenAI provider with GPT-4o models
- `anthropic/` - Anthropic provider with Claude 3.5 Sonnet
- `custom/` - Custom provider template

## Wire Protocol & Constraints (API Client Integration)

These `extra.*` fields enable metadata-driven API clients like ReqLlmNext to handle
model-specific requirements without hardcoded model-name heuristics.

### Wire Protocol

Use `extra.wire.protocol` to specify which API format a model uses:

| Value | Description |
|-------|-------------|
| `openai_chat` | Standard OpenAI Chat Completions API (default for OpenAI) |
| `openai_responses` | OpenAI Responses API (o-series, GPT-5) |
| `anthropic` | Anthropic Messages API (default for Anthropic) |

When absent, clients should use provider defaults.

### Constraints

Use `extra.constraints.*` to specify parameter handling requirements:

| Field | Values | Description |
|-------|--------|-------------|
| `token_limit_key` | `max_tokens`, `max_completion_tokens` | Which key to use for output tokens |
| `temperature` | `any`, `unsupported`, `fixed_1` | Temperature parameter support |
| `reasoning_effort` | `unsupported`, `supported`, `required` | Reasoning effort parameter handling |
| `min_output_tokens` | integer | Minimum output tokens floor |

Example for a reasoning model:
```toml
id = "o3-mini"

[extra.wire]
protocol = "openai_responses"

[extra.constraints]
token_limit_key = "max_completion_tokens"
temperature = "unsupported"
reasoning_effort = "supported"
```

## Notes

- All IDs should be lowercase with hyphens or underscores (e.g., `my-provider` or `my_provider`)
- The `provider` field is automatically set from the directory name (you can omit it from TOML)
- String keys in TOML are automatically converted to atoms during load
- Values are used as-is (no transformation) - must match canonical schema
- Parse errors in individual files are logged but don't stop processing
- Invalid models (that fail schema validation) are logged and dropped
