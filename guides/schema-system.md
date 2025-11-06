# Schema System

Provider and Model schemas are defined using [Zoi](https://hexdocs.pm/zoi). Validation occurs at build time (ETL pipeline via `LLMModels.Validate`) and runtime (struct construction via `new/1`).

## Provider Schema

### Fields

- `:id` (atom, required) - Unique provider identifier (e.g., `:openai`)
- `:name` (string, required) - Display name
- `:base_url` (string, optional) - Base API URL
- `:env` (map, optional) - Environment variable mappings
- `:doc` (string, optional) - Documentation URL
- `:extra` (map, optional) - Additional provider-specific data

### Construction

```elixir
provider_data = %{
  "id" => :openai,
  "name" => "OpenAI",
  "base_url" => "https://api.openai.com/v1",
  "env" => %{"api_key" => "OPENAI_API_KEY"},
  "doc" => "https://platform.openai.com/docs"
}

{:ok, provider} = LLMModels.Provider.new(provider_data)
provider = LLMModels.Provider.new!(provider_data)
```

See `LLMModels.Schema.Provider` and `LLMModels.Provider` for details.

## Model Schema

### Core Fields

- `:id` (string, required) - Model identifier (e.g., "gpt-4")
- `:provider` (atom, required) - Provider atom (e.g., `:openai`)
- `:provider_model_id` (string, optional) - Provider's internal ID (defaults to `:id`)
- `:name` (string, required) - Display name
- `:family` (string, optional) - Model family (e.g., "gpt-4")
- `:release_date` (date, optional) - Release date
- `:last_updated` (date, optional) - Last update date
- `:knowledge` (date, optional) - Knowledge cutoff date
- `:deprecated` (boolean, default: `false`) - Deprecation status
- `:aliases` (list of strings, default: `[]`) - Alternative names
- `:tags` (list of strings, optional) - Categorization tags
- `:extra` (map, optional) - Additional model-specific data

### Capability Fields

- `:modalities` (map, required) - Input/output modalities (see below)
- `:capabilities` (map, required) - Feature capabilities (see below)
- `:limits` (map, optional) - Context and output limits
- `:cost` (map, optional) - Pricing information

### Construction

```elixir
model_data = %{
  "id" => "gpt-4",
  "provider" => :openai,
  "name" => "GPT-4",
  "family" => "gpt-4",
  "modalities" => %{
    "input" => [:text],
    "output" => [:text]
  },
  "capabilities" => %{
    "chat" => true,
    "tools" => %{"enabled" => true, "streaming" => true}
  },
  "limits" => %{
    "context" => 8192,
    "output" => 4096
  }
}

{:ok, model} = LLMModels.Model.new(model_data)
```

See `LLMModels.Schema.Model` and `LLMModels.Model` for details.

## Nested Schemas

### Modalities

```elixir
%{
  "input" => [:text, :image, :audio],  # Atoms or strings (normalized to atoms)
  "output" => [:text, :image]
}
```

### Capabilities

```elixir
%{
  "chat" => true,
  "embeddings" => false,
  "reasoning" => %{
    "enabled" => true,
    "token_budget" => 10000
  },
  "tools" => %{
    "enabled" => true,
    "streaming" => true,
    "strict" => true,
    "parallel" => true
  },
  "json" => %{
    "native" => true,
    "schema" => true,
    "strict" => true
  },
  "streaming" => %{
    "text" => true,
    "tool_calls" => true
  }
}
```

Defaults applied during Enrich stage: booleans default to `false`, optional values to `nil`. See `LLMModels.Schema.Capabilities`.

### Limits

```elixir
%{
  "context" => 128000,
  "output" => 4096
}
```

See `LLMModels.Schema.Limits`.

### Cost

Pricing per million tokens (USD):

```elixir
%{
  "input" => 5.0,          # Per 1M input tokens
  "output" => 15.0,        # Per 1M output tokens
  "request" => 0.01,       # Per request (if applicable)
  "cache_read" => 0.5,     # Per 1M cached tokens read
  "cache_write" => 1.25,   # Per 1M tokens written to cache
  "training" => 25.0,      # Per 1M tokens for fine-tuning
  "image" => 0.01,         # Per image
  "audio" => 0.001         # Per second of audio
}
```

See `LLMModels.Schema.Cost`.

## Validation APIs

### Batch Validation

```elixir
# Returns {:ok, valid_providers, dropped_count}
{:ok, providers, dropped} = LLMModels.Validate.validate_providers(provider_list)

# Returns {:ok, valid_models, dropped_count}
{:ok, models, dropped} = LLMModels.Validate.validate_models(model_list)
```

Invalid entries are dropped and logged as warnings.

### Struct Construction

```elixir
# Returns {:ok, struct} or {:error, reason}
{:ok, provider} = LLMModels.Provider.new(provider_map)
{:ok, model} = LLMModels.Model.new(model_map)

# Raises on validation error
provider = LLMModels.Provider.new!(provider_map)
model = LLMModels.Model.new!(model_map)
```

## The `extra` Field

Unknown fields are preserved in `:extra` for forward compatibility. The ModelsDev source automatically moves unmapped fields into `:extra`:

```elixir
%{"id" => "gpt-4", "name" => "GPT-4", "vendor_field" => "custom"}
# Transforms to:
%{"id" => "gpt-4", "name" => "GPT-4", "extra" => %{"vendor_field" => "custom"}}
```
