# Schema System

Provider and Model schemas are defined using [Zoi](https://hexdocs.pm/zoi). Validation occurs at build time (ETL pipeline via `LLMDb.Validate`) and runtime (struct construction via `new/1`).

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

{:ok, provider} = LLMDb.Provider.new(provider_data)
provider = LLMDb.Provider.new!(provider_data)
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

See `LLMDb.Schema.Provider` and `LLMDb.Provider` for details.

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
- `:tags` (list of strings, optional) - Categorization tags
- `:extra` (map, optional) - Additional model-specific data

#### Model Aliases

The `:aliases` field allows a single model entry to be referenced by multiple identifiers. This is particularly useful for:

1. **Provider-specific routing** - AWS Bedrock inference profiles prefix models with region identifiers:

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

2. **Version shortcuts** - Latest/stable version aliases:

   ```elixir
   %{
     "id" => "claude-haiku-4-5@20251001",
     "aliases" => ["claude-haiku-4-5@latest"]
   }
   ```

3. **Legacy compatibility** - Supporting deprecated identifiers during migrations

Client libraries should normalize model IDs before catalog lookup (e.g., strip region prefixes) and check both the `:id` and `:aliases` fields when resolving models.

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

{:ok, model} = LLMDb.Model.new(model_data)
```

See `LLMDb.Schema.Model` and `LLMDb.Model` for details.

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

Defaults applied during Enrich stage: booleans default to `false`, optional values to `nil`. See `LLMDb.Schema.Capabilities`.

### Limits

```elixir
%{
  "context" => 128000,
  "output" => 4096
}
```

See `LLMDb.Schema.Limits`.

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

See `LLMDb.Schema.Cost`.

## Validation APIs

### Batch Validation

```elixir
# Returns {:ok, valid_providers, dropped_count}
{:ok, providers, dropped} = LLMDb.Validate.validate_providers(provider_list)

# Returns {:ok, valid_models, dropped_count}
{:ok, models, dropped} = LLMDb.Validate.validate_models(model_list)
```

Invalid entries are dropped and logged as warnings.

### Struct Construction

```elixir
# Returns {:ok, struct} or {:error, reason}
{:ok, provider} = LLMDb.Provider.new(provider_map)
{:ok, model} = LLMDb.Model.new(model_map)

# Raises on validation error
provider = LLMDb.Provider.new!(provider_map)
model = LLMDb.Model.new!(model_map)
```

## The `extra` Field

Unknown fields are preserved in `:extra` for forward compatibility. The ModelsDev source automatically moves unmapped fields into `:extra`:

```elixir
%{"id" => "gpt-4", "name" => "GPT-4", "vendor_field" => "custom"}
# Transforms to:
%{"id" => "gpt-4", "name" => "GPT-4", "extra" => %{"vendor_field" => "custom"}}
```
