# Release Process

## Snapshot-Based Model Data

LLMModels packages a pre-built snapshot at `priv/llm_models/snapshot.json`.

### Snapshot Structure

V2 schema uses nested providers with embedded models:

```json
{
  "version": 2,
  "generated_at": "2025-11-06T14:23:45.123456Z",
  "providers": {
    "openai": {
      "id": "openai",
      "name": "OpenAI",
      "base_url": "https://api.openai.com/v1",
      "models": {
        "gpt-4": {
          "id": "gpt-4",
          "provider": "openai",
          "name": "GPT-4",
          "capabilities": {...},
          "limits": {...},
          "cost": {...}
        }
      }
    }
  }
}
```

### Runtime Loading

```elixir
# Reads from priv/llm_models/snapshot.json
{:ok, _} = LLMModels.load()
```

Compile-time embed (zero runtime IO):

```elixir
# config/config.exs
config :llm_models, compile_embed: true
```

Snapshot is inlined into BEAM bytecode during compilation. Requires recompilation on snapshot changes.

## Updating Model Data

### 1. Pull Remote Sources

```bash
$ mix llm_models.pull
Pulling from configured sources...
✓ ModelsDev: 450 models cached at priv/llm_models/cache/models_dev.json
```

### 2. Build Snapshot

```bash
$ mix llm_models.build
Running ETL pipeline...
✓ Ingested 3 sources
✓ Validated 450 models (3 invalid dropped)
✓ Merged with precedence (last wins)
✓ Filtered to 400 models (50 excluded by filters)
✓ Enriched and indexed
✓ Snapshot written to priv/llm_models/snapshot.json
✓ Generated lib/llm_models/generated/valid_providers.ex

Summary:
  Providers: 12
  Models: 400
  Snapshot size: 1.2 MB
```

**Outputs**:

1. `priv/llm_models/snapshot.json` - V2 snapshot
2. `lib/llm_models/generated/valid_providers.ex` - Pre-existing provider atoms (prevents atom leaks)

### 3. Commit Changes

```bash
$ git add priv/llm_models/snapshot.json lib/llm_models/generated/valid_providers.ex
$ git commit -m "Update model snapshot"
```

## Versioning and Tagging

Date-based versioning: `YYYY.M.D`

### Update Version

```bash
$ mix llm_models.version
Updated version to 2025.11.6 in mix.exs
```

Updates `@version` in `mix.exs`.

### Generate Changelog and Tag

```bash
$ mix git_ops.release
Analyzing commits since last release...
Updating CHANGELOG.md...
Creating git tag v2025.11.6...
```

1. Parses conventional commits since last tag
2. Updates `CHANGELOG.md`
3. Creates git tag `v2025.11.6`

### Push Tag

```bash
$ git push && git push --tags
```

CI triggers on tag push: Hex.pm publish, GitHub release, HexDocs publish.

## Snapshot Format

### V2 Schema

```json
{
  "version": 2,
  "generated_at": "ISO8601 timestamp",
  "providers": {
    "provider_atom_as_string": {
      "id": "provider_atom_as_string",
      "name": "Provider Name",
      "base_url": "https://...",
      "env": {...},
      "doc": "https://...",
      "extra": {...},
      "models": {
        "model_id": {
          "id": "model_id",
          "provider": "provider_atom_as_string",
          "name": "Model Name",
          "capabilities": {...},
          "limits": {...},
          "cost": {...},
          "modalities": {...},
          "deprecated": false,
          "aliases": [...],
          "extra": {...}
        }
      }
    }
  }
}
```

**Runtime-only indexes** (rebuilt during `LLMModels.load/1`):
- `providers_by_id`
- `models_by_key`
- `models_by_provider`
- `aliases_by_key`

## Release Triggers

1. Upstream data changes (new models, pricing, capabilities)
2. Schema changes (new fields, modality types)
3. Provider additions
4. Taxonomy updates
5. Metadata corrections

## Release Checklist

- [ ] `mix llm_models.pull`
- [ ] `mix llm_models.build`
- [ ] `mix test`
- [ ] Review `git diff priv/llm_models/snapshot.json`
- [ ] Commit snapshot and generated files
- [ ] `mix llm_models.version`
- [ ] `mix git_ops.release`
- [ ] Review `CHANGELOG.md`
- [ ] `git push && git push --tags`

## Automated Release

```bash
$ mix llm_models.pull && \
  mix llm_models.build && \
  mix test && \
  mix llm_models.version && \
  mix git_ops.release && \
  git push && \
  git push --tags
```

Or via mix alias:

```elixir
defp aliases do
  [
    release: [
      "llm_models.pull",
      "llm_models.build",
      "test",
      "llm_models.version",
      "git_ops.release"
    ]
  ]
end
```

```bash
$ mix release
$ git push && git push --tags
```

## Snapshot Versions

- **v1**: Flat lists (deprecated)
- **v2**: Nested providers with models (current)

## Snapshot Size

Current: ~1.2 MB (400 models × 12 providers)

**Optimization options**:
1. Filter deprecated models at build time
2. gzip compression (transparent in BEAM)
3. Split by provider (on-demand load)
4. Remove `:extra` fields

## Schema Evolution Signals

- New capability types (e.g., "video generation")
- New cost models (e.g., "per-character")
- New modality types (e.g., "3d", "code")
- Provider-specific features becoming common

**Schema changes require updates to**:
1. Source adapters (ModelsDev transform)
2. Validation schemas (Zoi definitions)
3. Documentation (capability lists)

## Related Guides

- [Schema System](schema-system.md)
- [Sources and Engine](sources-and-engine.md)
- [Using the Data](using-the-data.md)
