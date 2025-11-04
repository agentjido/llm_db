# LlmModels Test Suite

## Overview

Comprehensive test coverage for the `llm_models` package, including compile-time parsing, upstream data integration, and runtime behavior.

## Test Structure

### Core Tests
- **`llm_models_test.exs`** - Main API integration tests covering full lifecycle
- **`llm_models/packaged_test.exs`** - Compile-time snapshot loading tests
- **`llm_models/engine_test.exs`** - ETL pipeline and indexing tests

### Mix Task Tests
- **`mix/tasks/llm_models.pull_test.exs`** - Tests for pulling upstream data from models.dev
- **`mix/tasks/llm_models.activate_test.exs`** - Tests for activating/processing upstream data

## Running Tests

### All Tests (Excluding External)
```bash
mix test --exclude external
```

### External Tests (Requires Network)
```bash
mix test --only external
```

These tests actually fetch from `https://models.dev/api.json` to verify:
- Upstream data structure
- Major providers are present (OpenAI, Anthropic, Google Vertex, Mistral)
- Model data integrity
- Manifest generation

### Fast Tests Only
```bash
mix test --exclude external --exclude slow
```

## Test Configuration

The test suite uses:
- **`capture_log: true`** - Suppresses log output during tests (configured in `test_helper.exs`)
- **`:external` tag** - Marks tests requiring network access
- **`:async` mode** - Most tests run concurrently for speed

## Key Test Scenarios

### 1. Compile-Time Data Loading
Tests verify that packaged snapshot data is loaded at compile-time with:
- Atomized keys for providers
- Proper JSON structure validation
- Path resolution

### 2. Upstream Data Integration
External tests validate:
- Fetching from models.dev
- SHA256 manifest generation
- Data normalization (e.g., "google-vertex" → `:google_vertex`)
- Provider and model structure validation

### 3. ETL Pipeline
Engine tests cover all 8 stages:
1. **Ingest** - Load from packaged/config/behaviour sources
2. **Normalize** - Provider IDs, dates, structure
3. **Validate** - Schema validation with Zoi
4. **Merge** - Precedence-based merging
5. **Enrich** - Derived fields
6. **Filter** - Allow/deny patterns
7. **Index** - Build lookup maps
8. **Ensure Viable** - Non-empty catalog check

### 4. Runtime Queries
Comprehensive coverage of:
- Provider listing and lookup
- Model filtering by capabilities
- Alias resolution
- Spec parsing (`"provider:model"` format)
- `select/1` with preferences
- Capability predicates

## Test Data

Tests use:
1. **Packaged snapshot** from `priv/llm_models/snapshot.json`
2. **Upstream data** from `priv/llm_models/upstream.json` (if available)
3. **Synthetic test data** for unit tests

## External Test Notes

External tests (`@tag :external`) require:
- Active internet connection
- Access to `https://models.dev/api.json`
- May be slower due to network latency

**Note**: Due to OTP-28 compatibility issues with `:http_util`, external tests may fail on OTP-28. This is a known Erlang stdlib issue and doesn't affect runtime functionality.

## Coverage Areas

✅ **Compile-time parsing**  
✅ **Upstream data fetching from models.dev**  
✅ **JSON to Elixir map conversion with atom keys**  
✅ **Provider/model normalization**  
✅ **Schema validation**  
✅ **Allow/deny filtering**  
✅ **Alias resolution**  
✅ **Capability matching**  
✅ **Preference ordering**  
✅ **Error handling**  

## CI/CD Recommendations

For CI pipelines:
```bash
# Fast feedback - skip external tests
mix test --exclude external

# Full validation (including network tests)
mix test
```
