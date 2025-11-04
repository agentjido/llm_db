# LLM_MODELS_PLAN.md

A focused, reusable Elixir package for LLM model metadata with a simple ETL pipeline, fast queries, and explicit refresh controls.

## 1) What this package is and why it exists

- **Package**: `llm_models`
- **Namespace**: `LlmModels`
- **Purpose**: Provide a standalone, fast, and explicit model catalog for Elixir AI libraries. It ships with a packaged snapshot, supports manual refresh from models.dev, and offers a minimal, capability-aware query API. It also owns canonical parsing of "provider:model" specs.
- **Why**: Centralize model metadata lifecycle (ingest → normalize → validate → enrich → index → publish) behind a simple, reusable library, decoupled from ReqLLM. Emphasize: stability (no magic), explicit updates only, fast lookup, and clear precedence rules.

## 2) Architectural principles

- Standalone package with packaged snapshot (no network by default)
- Manual refresh only via Mix tasks (`mix llm_models.pull`, `mix llm_models.activate`)
- Source precedence: packaged snapshot → config overrides → behaviour overrides (code)
- **persistent_term-backed read path** for O(1), lock-free queries
- **Compile-time parsing** of packaged snapshot when possible; runtime reload updates persistent_term atomically
- Simple allow/deny filtering, compiled once
- Capability-based selection, with minimal, explicit semantics
- **The package owns "provider:model" spec parsing and resolution**
- Simplicity-first: remove over-engineering and provenance complexity; focus on the 80% case

## 3) Public API (high level)

### Module: `LlmModels`

#### Lifecycle

- `load(opts \\ [])` → `{:ok, Snapshot.t()} | {:error, term()}`
  - Builds catalog from packaged snapshot + config overrides + behaviour overrides and publishes to persistent_term
- `reload()` → `:ok`
  - Re-runs load/0 using last-known options and swaps persistent_term atomically
- `snapshot()` → `Snapshot.t()`
  - Returns the current in-memory snapshot (persistent_term-backed)
- `epoch()` → `non_neg_integer()`
  - Monotonic version incremented on each publish

#### Lookup and listing

- `list_providers()` → `[provider_atom()]`
- `get_provider(provider :: atom())` → `{:ok, Provider.t()} | :error`
- `list_models(provider :: atom(), opts \\ [])` → `[Model.t()]`
  - Opts: `require: keyword(), forbid: keyword(), allow: patterns or nil`
- `get_model(provider :: atom(), model_id :: String.t())` → `{:ok, Model.t()} | :error`
- `capabilities({provider :: atom(), model_id :: String.t()})` → `Capabilities.t()`
- `allowed?({provider, model_id})` → `boolean()`

#### Selection

- `select(opts)` → `{:ok, {provider, model_id}} | {:error, :no_match}`
  - `opts.require`: keyword (e.g., `[chat: true, tools: true, json_native: true]`)
  - `opts.forbid`: keyword
  - `opts.prefer`: `[provider_atom()]`
  - `opts.scope`: `:all | provider_atom()`

#### Spec parsing and resolution (canonical)

- `parse_provider(binary)` → `{:ok, atom()} | {:error, :unknown_provider}`
- `parse_spec("provider:model")` → `{:ok, {atom(), String.t()}} | {:error, term()}`
- `resolve(binary_or_tuple)` → `{:ok, {provider :: atom(), model_id :: String.t(), Model.t()}} | {:error, term()}`
  - Accepts "provider:model", `{provider, model_id}`, or model ID scoped by `opts.scope`
  - Normalizes aliases and validates existence in the current catalog

### Example usage

```elixir
# Boot
{:ok, _} = LlmModels.load()

# Canonical spec parsing and resolution
{:ok, {:openai, "gpt-4o-mini"}} = LlmModels.parse_spec("openai:gpt-4o-mini")
{:ok, {prov, id, model}} = LlmModels.resolve("openai:gpt-4o-mini")

# Simple selection
LlmModels.select(
  require: [tools: true, json_native: true],
  prefer: [:openai, :anthropic]
)

# Retrieve capabilities
caps = LlmModels.capabilities({:openai, "gpt-4o-mini"})
caps.tools.enabled      # boolean
caps.tools.streaming    # boolean
```

## 4) Data model (validated with zoi)

No `typed_struct` or `NimbleOptions`. Use `zoi` for schema validation and to generate dialyzer specs.

### Schema modules

- `LlmModels.Schema.Provider`
- `LlmModels.Schema.Model`
- `LlmModels.Schema.Capabilities`
- `LlmModels.Schema.Limits`
- `LlmModels.Schema.Cost`

**Notes**:
- Use `Zoi.parse/2` for validation and defaulting
- Dates are stored as strings `"YYYY-MM-DD"` for simplicity; convert to `Date` only at call sites that need it
- `extra` passes through unknown upstream keys for forward compatibility

### Zoi schemas

#### Provider

```elixir
defmodule LlmModels.Schema.Provider do
  @schema Zoi.object(%{
    id: Zoi.atom(),
    name: Zoi.string() |> Zoi.optional(),
    base_url: Zoi.string() |> Zoi.optional(),
    env: Zoi.array(Zoi.string()) |> Zoi.optional(),
    doc: Zoi.string() |> Zoi.optional(),
    extra: Zoi.map() |> Zoi.optional()
  })
  @type t :: unquote(Zoi.type_spec(@schema))
  def schema, do: @schema
end
```

#### Limits

```elixir
defmodule LlmModels.Schema.Limits do
  @schema Zoi.object(%{
    context: Zoi.integer() |> Zoi.min(1) |> Zoi.optional(),
    output: Zoi.integer() |> Zoi.min(1) |> Zoi.optional()
  })
  @type t :: unquote(Zoi.type_spec(@schema))
  def schema, do: @schema
end
```

#### Cost (per 1M tokens)

```elixir
defmodule LlmModels.Schema.Cost do
  @schema Zoi.object(%{
    input: Zoi.number() |> Zoi.optional(),
    output: Zoi.number() |> Zoi.optional(),
    cache_read: Zoi.number() |> Zoi.optional(),
    cache_write: Zoi.number() |> Zoi.optional(),
    training: Zoi.number() |> Zoi.optional(),
    image: Zoi.number() |> Zoi.optional(),
    audio: Zoi.number() |> Zoi.optional()
  })
  @type t :: unquote(Zoi.type_spec(@schema))
  def schema, do: @schema
end
```

#### Capabilities (minimal but covers transport vs feature)

```elixir
defmodule LlmModels.Schema.Capabilities do
  @schema Zoi.object(%{
    chat: Zoi.boolean() |> Zoi.default(true),
    embeddings: Zoi.boolean() |> Zoi.default(false),
    reasoning: Zoi.object(%{
      enabled: Zoi.boolean() |> Zoi.default(false),
      token_budget: Zoi.integer() |> Zoi.min(0) |> Zoi.optional()
    }) |> Zoi.default(%{}),
    tools: Zoi.object(%{
      enabled: Zoi.boolean() |> Zoi.default(false),
      streaming: Zoi.boolean() |> Zoi.default(false),
      strict: Zoi.boolean() |> Zoi.default(false),
      parallel: Zoi.boolean() |> Zoi.default(false)
    }) |> Zoi.default(%{}),
    json: Zoi.object(%{
      native: Zoi.boolean() |> Zoi.default(false),
      schema: Zoi.boolean() |> Zoi.default(false),
      strict: Zoi.boolean() |> Zoi.default(false)
    }) |> Zoi.default(%{}),
    streaming: Zoi.object(%{
      text: Zoi.boolean() |> Zoi.default(true),
      tool_calls: Zoi.boolean() |> Zoi.default(false)
    }) |> Zoi.default(%{})
  })
  @type t :: unquote(Zoi.type_spec(@schema))
  def schema, do: @schema
end
```

#### Model

```elixir
defmodule LlmModels.Schema.Model do
  @schema Zoi.object(%{
    id: Zoi.string(),
    provider: Zoi.atom(),
    provider_model_id: Zoi.string() |> Zoi.optional(),
    name: Zoi.string() |> Zoi.optional(),
    family: Zoi.string() |> Zoi.optional(),
    release_date: Zoi.string() |> Zoi.optional(),
    last_updated: Zoi.string() |> Zoi.optional(),
    knowledge: Zoi.string() |> Zoi.optional(),
    limits: LlmModels.Schema.Limits.schema() |> Zoi.optional(),
    cost: LlmModels.Schema.Cost.schema() |> Zoi.optional(),
    modalities: Zoi.object(%{
      input: Zoi.array(Zoi.atom()) |> Zoi.optional(),
      output: Zoi.array(Zoi.atom()) |> Zoi.optional()
    }) |> Zoi.optional(),
    capabilities: LlmModels.Schema.Capabilities.schema() |> Zoi.optional(),
    tags: Zoi.array(Zoi.string()) |> Zoi.optional(),
    deprecated?: Zoi.boolean() |> Zoi.default(false),
    aliases: Zoi.array(Zoi.string()) |> Zoi.default([]),
    extra: Zoi.map() |> Zoi.optional()
  })
  @type t :: unquote(Zoi.type_spec(@schema))
  def schema, do: @schema
end
```

## 5) ETL pipeline (core only)

### Stages

1. **Ingest**
   - Sources (in order of precedence):
     - a) Packaged snapshot (bundled JSON in `:llm_models` priv), compile-time parsed when `compile_embed: true`
     - b) Config overrides (Elixir map/keyword; our schema, not models.dev)
     - c) Behaviour overrides (`MyApp.LlmModelOverrides` callbacks)
   - No HTTP by default. models.dev fetch is handled by Mix tasks only

2. **Normalize**
   - Provider IDs to atoms (e.g., `"google-vertex"` → `:google_vertex`)
   - Ensure provider/model identity as `{provider_atom, model_id}` tuples
   - Normalize date strings to `"YYYY-MM-DD"` format; money to numeric per-1M token fields if present

3. **Validate**
   - Validate providers and models via Zoi schemas
   - Drop invalid records (log count). Fail hard only if no models survive

4. **Merge with precedence**
   - Map fields: deep merge
   - Lists: de-dup by value (for aliases/tags)
   - Scalars: higher precedence source wins
   - Excludes: allow `:exclude` entries (config/behaviour) to remove models (by exact id or glob)

5. **Enrich** (lightweight, deterministic)
   - `family` from id prefix (e.g., `"gpt-4o-mini"` → `"gpt-4o"`)
   - capabilities defaults as above (`streaming.text` default true; `tool_calls` default false)
   - `provider_model_id` defaults to `id` if missing

6. **Filter**
   - Apply global allow/deny (deny wins). Compile patterns to regex once

7. **Index + Publish**
   - Build in-memory indexes:
     - `models_by_provider: %{provider => [Model.t()]}`
     - `model_lookup: %{{provider, id} => Model.t()}`
     - `providers: %{provider => Provider.t()}`
   - Publish as Snapshot to persistent_term; store epoch for atomic swaps

### Data structures

**Snapshot** (internal struct; not exposed as dependency):
- `providers :: map()`
- `models_by_provider :: map()`
- `model_lookup :: map()`
- `allow :: map()`
- `deny :: map()`
- `epoch :: non_neg_integer()`

## 6) Storage and loading architecture

- **Compile-time embedding**:
  - `LlmModels.Packaged` reads `priv/llm_models/snapshot.json` at compile time, decodes it to a term, and stores it in a module attribute (using `@external_resource` to trigger recompilation on file changes)
  - Controlled by `config :llm_models, compile_embed: true` (default true)
- **Runtime loading**:
  - `LlmModels.load/1` merges: packaged term → config overrides → behaviour overrides, then validates/enriches and publishes to persistent_term
  - `LlmModels.reload/0` rebuilds with last-known options and atomically swaps the `:llm_models_snapshot` key via `:persistent_term.put/2`
- **Reads**:
  - All read APIs fetch from `:persistent_term.get(:llm_models_snapshot)`; no ETS

## 7) Flexible overrides (config.exs)

Do not force models.dev schema. Use a simple, Elixir-native shape:

```elixir
config :llm_models,
  compile_embed: true,
  overrides: %{
    providers: [
      %{id: :openai, env: ["OPENAI_API_KEY"], base_url: "https://api.openai.com"}
    ],
    models: [
      %{
        id: "gpt-4o-mini",
        provider: :openai,
        capabilities: %{tools: %{enabled: true, streaming: false}}
      },
      %{
        id: "claude-3-7-sonnet",
        provider: :anthropic,
        capabilities: %{json: %{native: true}}
      }
    ],
    exclude: %{openai: ["gpt-5-pro", "o3-*"]},
    allow: %{anthropic: :all}
  },
  prefer: [:openai, :anthropic]
```

- All keys are optional; unknown keys pass through to `extra`
- Overrides are validated with the same Zoi schemas as packaged data

## 8) LlmModelOverrides behaviour and use macro

Provide a behaviour that applications can implement and a `use` macro that injects defaults and docs:

```elixir
defmodule LlmModels.Overrides do
  @callback providers() :: [map()]
  @callback models() :: [map()]
  @callback excludes() :: map()

  defmacro __using__(_opts) do
    quote do
      @behaviour LlmModels.Overrides
      @impl true def providers, do: []
      @impl true def models, do: []
      @impl true def excludes, do: %{}
      defoverridable providers: 0, models: 0, excludes: 0
    end
  end
end
```

Preferred customization path:

```elixir
defmodule MyApp.LlmModelOverrides do
  use LlmModels.Overrides

  @impl true
  def providers do
    [%{id: :openai, env: ["OPENAI_API_KEY"]}]
  end

  @impl true
  def models do
    [
      %{id: "gpt-4o-mini", provider: :openai,
        capabilities: %{tools: %{enabled: true, streaming: false}}}
    ]
  end

  @impl true
  def excludes do
    %{openai: ["gpt-5-pro"]}
  end
end

config :llm_models, overrides_module: MyApp.LlmModelOverrides
```

During `load/1`, the engine reads `overrides_module` and merges its callbacks after config overrides.

## 9) Mix tasks

### `mix llm_models.pull`

- Fetches models.dev to a local file cache (no runtime network)
- Options:
  - `--url https://models.dev/api.json` (default maintained by task)
  - `--out priv/llm_models/upstream.json`
- Writes:
  - `priv/llm_models/upstream.json`
  - `priv/llm_models/.manifest.json` (SHA256 and file list)

### `mix llm_models.activate [--from priv/llm_models/upstream.json]`

- Validates and normalizes the given file(s), merges with existing local overrides, and writes a packaged-like snapshot file: `priv/llm_models/snapshot.json`
- If `compile_embed: true`, changing this file marks it as `@external_resource` so recompile picks up the new term; otherwise call `LlmModels.reload/0` in dev to swap persistent_term
- Production: prefer explicit `LlmModels.reload/0` after activation

**Notes**:
- Mix tasks do not mutate persistent_term directly
- Keep tasks simple: move all merge/validation to the runtime ETL engine so behavior is consistent

## 10) Selection and filtering (semantics)

### `allowed?/1`

- Uses compiled allow/deny patterns. deny wins
- If allow is `:all` and deny is empty, everything is allowed

### `select/1` behavior

- Filter models by required/forbid capabilities
- If prefer is provided, iterate providers in order; else iterate all providers
- Choose the first allowed model matching criteria
- Return `:no_match` if nothing fits

**Examples**:

```elixir
LlmModels.list_models(:openai,
  require: [tools: true],
  forbid: [streaming_tool_calls: true]
)

LlmModels.select(
  require: [chat: true, tools: true, json_native: true],
  prefer: [:openai, :anthropic]
)
```

## 11) Integration points for ReqLLM

Replace JSON file path lookups with `LlmModels` API calls:

- **ReqLLM.Provider.Registry**
  - Initialize from `LlmModels.snapshot/0`
  - Use `LlmModels.parse_provider/1` and `LlmModels.parse_spec/1` for canonical parsing
- **ReqLLM.Model.from/1**
  - Use `LlmModels.resolve/1` then `LlmModels.get_model/2`
- **ReqLLM.Capability**
  - Use `LlmModels.capabilities/1`

**Startup path**:

```elixir
{:ok, _} = LlmModels.load()
ReqLLM.Provider.Registry.initialize_from(LlmModels.snapshot())
```

## 12) Minimal module map (llm_models)

- `lib/llm_models.ex` - Public API (load/reload/snapshot/list/get/select/capabilities/allowed?/parse_x/resolve)
- `lib/llm_models/config.ex` - Reads and normalizes `:llm_models` env; compiles allow/deny patterns
- `lib/llm_models/engine.ex` - ETL pipeline runner. Accepts sources, returns Snapshot
- `lib/llm_models/packaged.ex` - Compile-time reader/holder of packaged snapshot term
- `lib/llm_models/normalize.ex` - Provider/model id normalization, date/money normalization
- `lib/llm_models/validate.ex` - Validates with Zoi; logs dropped entries
- `lib/llm_models/merge.ex` - Precedence-aware deep merge, list de-dup, excludes
- `lib/llm_models/enrich.ex` - Family derivation and capability defaults
- `lib/llm_models/store.ex` - persistent_term get/put and epoch; atomic swap
- `lib/llm_models/spec.ex` - "provider:model" parsing and resolution helpers
- `lib/llm_models/schema/*.ex` - Zoi schemas
- `lib/llm_models/overrides.ex` - Behaviour + `use` macro
- Mix tasks:
  - `lib/mix/tasks/llm_models.pull.ex`
  - `lib/mix/tasks/llm_models.activate.ex`

## 13) Implementation checklist

### Core (S–M)

- [ ] Create schema modules with Zoi for Provider, Model, Capabilities, Limits, Cost; add simple unit tests with `Zoi.example()/parse()`
- [ ] Implement `normalize.ex` (provider atoms, family derivation, date strings)
- [ ] Implement `validate.ex` (Zoi.parse per provider/model; collect errors; drop invalid)
- [ ] Implement `merge.ex` with precedence rules and exclude handling (compile globs once)
- [ ] Implement `enrich.ex` (capability defaults, provider_model_id fallback)
- [ ] Implement `packaged.ex` (compile-time snapshot reader using `@external_resource`)
- [ ] Implement `store.ex` (persistent_term key + epoch; atomic swap)

### API and parsing (S)

- [ ] Implement public API in `LlmModels` (load/reload/snapshot/list/get/allowed?/capabilities/select)
- [ ] Implement `spec.ex` with `parse_provider/1`, `parse_spec/1`, `resolve/1`

### Overrides (S)

- [ ] Implement `overrides.ex` behaviour + `use` macro (providers/0, models/0, excludes/0)
- [ ] Wire `config :llm_models, overrides` and `overrides_module` into engine precedence

### Mix tasks (S)

- [ ] `mix llm_models.pull` to fetch models.dev and write upstream.json + .manifest.json
- [ ] `mix llm_models.activate` to build snapshot.json (using runtime engine for consistency)
- [ ] Ensure snapshot.json is marked as `@external_resource` to trigger recompilation when `compile_embed: true`

### Integration (ReqLLM) (M)

- [ ] Provider.Registry: read from `LlmModels.snapshot/0`; safe spec parsing via `LlmModels.parse_provider/1` and `parse_spec/1`
- [ ] Model.from/1 resolves via `LlmModels.resolve/1` → `get_model/2`
- [ ] Capability predicates read from `LlmModels.capabilities/1`
- [ ] Remove direct JSON reads and replace with `LlmModels` calls

### Docs and config (S)

- [ ] README for llm_models; document compile-time embedding, config overrides, and behaviour overrides
- [ ] Provide examples for list/select/allowed?/parse_spec/resolve

### Effort estimate

- Core library: M to L (1–2 days)
- Mix tasks: S (<1h each)
- ReqLLM integration: M (1–3h), assuming straightforward substitutions

## 14) Design simplifications (explicitly chosen)

- No per-field provenance/traces in v1; if needed later, add a debug-only module to report which source selected the final record
- Dates kept as strings for simplicity; convert to `Date` at call sites if needed
- No DSL for overrides; use behaviour callbacks and plain maps to reduce surface area and cognitive load
- No schema version juggling in v1; changes handled by code updates and Zoi schemas
- Selection returns a simple match or `:no_match`; no elaborate fallback trace until required

## 15) Guardrails and defaults

- If sources/overrides are not configured, package boots from packaged snapshot only (no network)
- If `load/0` produces 0 models, return `{:error, :empty_catalog}` rather than publishing an empty catalog
- Deny always wins over allow
- persistent_term writes are single-writer; all reads are lock-free
- All merges deterministic; higher precedence source wins on scalar keys
- Minimize reload frequency to reduce persistent_term update costs; track `epoch`

## 16) Dependency list

- `:zoi ~> 0.8` (validation and type specs)
- `:jason` (JSON decode/encode)

No `NimbleOptions`, no `typed_struct`.

## 17) Appendix: Minimal examples

### Config with overrides and preference

```elixir
config :llm_models,
  compile_embed: true,
  overrides: %{
    providers: [%{id: :openai, env: ["OPENAI_API_KEY"]}],
    models: [
      %{id: "gpt-4o-mini", provider: :openai, capabilities: %{tools: %{enabled: true}}}
    ],
    exclude: %{openai: ["gpt-5-pro"]}
  },
  overrides_module: MyApp.LlmModelOverrides,
  prefer: [:openai, :anthropic]
```

### Spec parsing and resolution

```elixir
{:ok, {:openai, "gpt-4o-mini"}} = LlmModels.parse_spec("openai:gpt-4o-mini")
{:ok, {p, m, model}} = LlmModels.resolve({:openai, "gpt-4o-mini"})
```

### Listing models with filters

```elixir
LlmModels.list_models(:openai,
  require: [tools: true],
  forbid: [streaming_tool_calls: true]
)
```

---

This plan yields a small, focused `llm_models` package with a crisp ETL pipeline, stable defaults, explicit update path via Mix tasks, and a minimal public API suitable for ReqLLM and other Elixir AI libraries.
