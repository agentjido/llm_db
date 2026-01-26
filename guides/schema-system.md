# Schema System

Provider and Model schemas are defined using [Zoi](https://hexdocs.pm/zoi). Validation occurs at build time (ETL pipeline via `LLMDB.Validate`) and runtime (struct construction via `new/1`).

## Provider Schema

### Fields

- `:id` (atom, required) - Unique provider identifier (e.g., `:openai`)
- `:name` (string, required) - Display name
- `:base_url` (string, optional) - Base API URL (supports template variables)
- `:env` (list of strings, optional) - Environment variable names for credentials
- `:config_schema` (list of maps, optional) - Runtime configuration field definitions
- `:doc` (string, optional) - Documentation URL
- `:extra` (map, optional) - Additional provider-specific data

#### Base URL Templates

The `:base_url` field supports template variables in the format `{variable_name}`. These are typically substituted at runtime by client libraries based on configuration:

```elixir
"base_url" => "https://bedrock-runtime.{region}.amazonaws.com"
```

Common template variables:

- `{region}` - Cloud provider region (e.g., AWS: "us-east-1", GCP: "us-central1")
- `{project_id}` - Project identifier (e.g., Google Cloud project ID)

#### Runtime Configuration Schema

The `:config_schema` field documents what runtime configuration parameters the provider accepts beyond credentials. Each entry defines a configuration field:

```elixir
%{
  "name" => "region",           # Field name
  "type" => "string",           # Data type
  "required" => false,          # Whether required
  "default" => "us-east-1",     # Default value (optional)
  "doc" => "AWS region..."      # Description (optional)
}
```

This metadata helps client libraries validate configuration and generate documentation.

### Construction

```elixir
provider_data = %{
  "id" => :openai,
  "name" => "OpenAI",
  "base_url" => "https://api.openai.com/v1",
  "env" => ["OPENAI_API_KEY"],
  "doc" => "https://platform.openai.com/docs"
}

{:ok, provider} = LLMDB.Provider.new(provider_data)
provider = LLMDB.Provider.new!(provider_data)
```

### Example: AWS Bedrock

```elixir
%{
  "id" => :amazon_bedrock,
  "name" => "Amazon Bedrock",
  "base_url" => "https://bedrock-runtime.{region}.amazonaws.com",
  "env" => ["AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY"],
  "config_schema" => [
    %{
      "name" => "region",
      "type" => "string",
      "required" => false,
      "default" => "us-east-1",
      "doc" => "AWS region where Bedrock is available"
    },
    %{
      "name" => "api_key",
      "type" => "string",
      "required" => false,
      "doc" => "Bedrock API key for simplified authentication"
    }
  ],
  "extra" => %{
    "auth_patterns" => ["bearer_token", "sigv4"]
  }
}
```

See `LLMDB.Schema.Provider` and `LLMDB.Provider` for details.

## Model Schema

### Core Fields

- `:id` (string, required) - Canonical model identifier (e.g., "gpt-4")
- `:provider` (atom, required) - Provider atom (e.g., `:openai`)
- `:provider_model_id` (string, optional) - Provider's internal ID (defaults to `:id`)
- `:name` (string, required) - Display name
- `:family` (string, optional) - Model family (e.g., "gpt-4")
- `:release_date` (date, optional) - Release date
- `:last_updated` (date, optional) - Last update date
- `:knowledge` (date, optional) - Knowledge cutoff date
- `:deprecated` (boolean, default: `false`) - Deprecation status
- `:aliases` (list of strings, default: `[]`) - Alternative identifiers (see below)
- `:base_url` (date, optional) - Model specific base_url.  Typically used for local models that are deployed to different port numbers.
- `:tags` (list of strings, optional) - Categorization tags
- `:extra` (map, optional) - Additional model-specific data

#### Model Aliases

The `:aliases` field allows a single model entry to be referenced by multiple identifiers. This enables model consolidation and supports naming variations.

**Canonical ID Strategy:**
- Each unique model has ONE canonical `id` (typically the dated version)
- All naming variants are stored in the `aliases` array
- Lookups check both `id` and `aliases` - both resolve to the same model

**Common Use Cases:**

1. **Naming Variants** - Dot vs dash notation, dated vs undated:

   ```elixir
   %{
     "id" => "claude-haiku-4-5-20251001",  # Canonical (dated, dash notation)
     "aliases" => [
       "claude-haiku-4-5",                  # Undated version
       "claude-haiku-4.5",                  # Dot notation
       "claude-haiku-4.5-20251001"          # Dot + date variant
     ]
   }
   ```

2. **Version Shortcuts** - Latest/stable aliases:

   ```elixir
   %{
     "id" => "claude-3-5-haiku-20241022",
     "aliases" => [
       "claude-3-5-haiku-latest",           # Latest version pointer
       "claude-3.5-haiku",                  # Dot notation
       "claude-3.5-haiku-20241022"          # Dot + date
     ]
   }
   ```

3. **Provider-specific Routing** - AWS Bedrock region prefixes:

   ```elixir
   %{
     "id" => "anthropic.claude-opus-4-1-20250805-v1:0",  # Canonical ID
     "aliases" => [
       "us.anthropic.claude-opus-4-1-20250805-v1:0",     # US routing
       "eu.anthropic.claude-opus-4-1-20250805-v1:0",     # EU routing
       "global.anthropic.claude-opus-4-1-20250805-v1:0"  # Global routing
     ]
   }
   ```

4. **Legacy Compatibility** - Support deprecated identifiers:

   ```elixir
   %{
     "id" => "gpt-4o-2024-11-20",
     "aliases" => [
       "gpt-4o",                             # Undated version
       "gpt-4o-latest",                      # Latest pointer
       "chatgpt-4o-latest"                   # Legacy name
     ]
   }
   ```

**Canonicalization Rules:**

When consolidating models with multiple naming variants:
1. **Prefer dated versions** - Dated IDs are immutable and map to a single release
2. **Use dash notation** - `4-5` over `4.5` (dashes are the standard separator)
3. **Full date format** - `YYYYMMDD` when available
4. **Exclude from upstream** - Add non-canonical IDs to provider's `exclude_models`
5. **Document aliases** - Create local TOML override with canonical ID and aliases

**Example Consolidation:**

```toml
# llm_db/priv/llm_db/local/anthropic/claude-haiku-4-5-20251001.toml
id = "claude-haiku-4-5-20251001"

aliases = [
  "claude-haiku-4-5",
  "claude-haiku-4.5"
]
```

```toml
# llm_db/priv/llm_db/local/anthropic/provider.toml
exclude_models = [
  "claude-haiku-4-5",      # Now an alias
  "claude-haiku-4.5"       # Now an alias
]
```

**Resolution Behavior:**

Client libraries should:
1. Accept any variant (canonical ID or alias) in user input
2. Resolve to canonical model via `LLMDB.model/1` or `LLMDB.model/2`
3. Use `model.id` (canonical ID) for internal operations, fixtures, and cache keys
4. Use `model.provider_model_id` (if set) for API requests

**Important for Filtering:**

Allow/deny filters match against **canonical IDs only**, not aliases. Always use canonical IDs in filter patterns:

```elixir
# ✓ Correct
config :llm_db,
  filter: %{allow: %{anthropic: ["claude-haiku-4-5-20251001"]}}

# ✗ Incorrect (alias won't match)
config :llm_db,
  filter: %{allow: %{anthropic: ["claude-haiku-4.5"]}}
```

See [Consumer Integration Guide](consumer-integration.md) for detailed guidance on using aliases in your library.

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

{:ok, model} = LLMDB.Model.new(model_data)
```

See `LLMDB.Schema.Model` and `LLMDB.Model` for details.

## Nested Schemas

### Modalities

```elixir
%{
  "input" => [:text, :image, :audio],  # Atoms or strings (normalized to atoms)
  "output" => [:text, :image]
}
```

### Capabilities

The capabilities schema uses granular nested objects to accurately represent real-world provider limitations, moving beyond simple boolean flags.

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
    "streaming" => true,    # Can stream tool calls?
    "strict" => true,       # Supports strict schema validation?
    "parallel" => true      # Can invoke multiple tools in one turn?
  },
  "json" => %{
    "native" => true,       # Native JSON mode support?
    "schema" => true,       # Supports JSON schema?
    "strict" => true        # Strict schema enforcement?
  },
  "streaming" => %{
    "text" => true,
    "tool_calls" => true
  }
}
```

#### Granular Tool Capabilities

The `tools` capability object allows precise documentation of provider-specific limitations. For example, **AWS Bedrock's Llama 3.3 70B** supports tools but not in streaming mode:

```elixir
%{
  "tools" => %{
    "enabled" => true,
    "streaming" => false,  # ← Bedrock API restriction
    "strict" => false,
    "parallel" => false
  }
}
```

This granularity eliminates the need for client libraries to maintain provider-specific override lists, as the limitations are documented directly in the model metadata.

Defaults applied during Enrich stage: booleans default to `false`, optional values to `nil`. See `LLMDB.Schema.Capabilities`.

### Limits

```elixir
%{
  "context" => 128000,
  "output" => 4096
}
```

See `LLMDB.Schema.Limits`.

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
  "reasoning" => 10.0,     # Per 1M reasoning/thinking tokens
  "image" => 0.01,         # Per image
  "audio" => 0.001,        # Per second of audio (deprecated, use input_audio/output_audio)
  "input_audio" => 1.0,    # Per 1M input audio tokens
  "output_audio" => 2.5,   # Per 1M output audio tokens
  "input_video" => 3.0,    # Per 1M input video tokens
  "output_video" => 5.0    # Per 1M output video tokens
}
```

See `LLMDB.Schema.Cost`.

## Validation APIs

### Batch Validation

```elixir
# Returns {:ok, valid_providers, dropped_count}
{:ok, providers, dropped} = LLMDB.Validate.validate_providers(provider_list)

# Returns {:ok, valid_models, dropped_count}
{:ok, models, dropped} = LLMDB.Validate.validate_models(model_list)
```

Invalid entries are dropped and logged as warnings.

### Struct Construction

```elixir
# Returns {:ok, struct} or {:error, reason}
{:ok, provider} = LLMDB.Provider.new(provider_map)
{:ok, model} = LLMDB.Model.new(model_map)

# Raises on validation error
provider = LLMDB.Provider.new!(provider_map)
model = LLMDB.Model.new!(model_map)
```

## The `extra` Field

Unknown fields are preserved in `:extra` for forward compatibility. The ModelsDev source automatically moves unmapped fields into `:extra`:

```elixir
%{"id" => "gpt-4", "name" => "GPT-4", "vendor_field" => "custom"}
# Transforms to:
%{"id" => "gpt-4", "name" => "GPT-4", "extra" => %{"vendor_field" => "custom"}}
```
