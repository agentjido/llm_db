# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

<!-- changelog -->

## [Unreleased]

### Changed

- Updated model data from upstream sources (includes Gemini 3 Pro Preview)

## [2025.11.18-preview] - 2025-11-18

### Added

- New models available: GPT 5.1 (OpenAI) and Gemini 3 (Google)
- Provider alias system to enable single implementation handling models from multiple LLMDB providers
  - New `alias_of` field in Provider struct points aliased provider to primary implementation
  - `LLMDB.Store.models/1` now searches aliased providers when looking up by provider ID
  - `LLMDB.Store.model/2` normalizes provider field back to requested provider for aliased models
  - First implementation: `google_vertex_anthropic` aliases to `google_vertex` for Claude models on Vertex AI
- `provider_model_id` field for AWS Bedrock inference profile models that require API-specific identifiers
  - Enables models to use canonical IDs (e.g., `anthropic.claude-haiku-4-5-20251001-v1:0`) while making API calls with inference profile prefixes (e.g., `us.anthropic.claude-haiku-4-5-20251001-v1:0`)
  - Addresses AWS requirement: "Invocation of model ID [...] with on-demand throughput isn't supported. Retry your request with the ID or ARN of an inference profile"
  - Applied to: Claude Haiku 4.5, Claude Sonnet 4.5, Claude Opus 4.1, Llama 3.3 70B, Llama 3.2 3B
- `.env.example` file for environment variable configuration

### Changed

- Snapshot JSON is now pretty-printed for easier diffing
- Updated Zoi dependency to version 0.10.7
- Updated Dotenvy dependency to version 1.1
- ModelsDev transformer now auto-sets `streaming.tool_calls: true` when `tool_call: true`
  - Reflects reality: 99%+ of tool-capable models support streaming tool calls
  - Eliminates need for model-specific TOML overrides for common case
  - Rare exceptions can override with `streaming.tool_calls: false` in TOML

### Fixed

- Claude Opus 4.1: Changed `provider_model_id` from `global.` to `us.` prefix - Opus 4.1 is only available with `us.` inference profile on AWS Bedrock, not `global.` like Haiku and Sonnet
- Claude Haiku 4.5 and Sonnet 4.5: Override `tools.strict=false` to disable object generation hack - waiting for native Anthropic JSON support instead
- Model spec parsing now handles ambiguous formats (specs with both `:` and `@` separators) by attempting provider validation to determine the correct format
- Removed overly strict character validation that rejected `@` in model IDs when using colon format and `:` in model IDs when using @ format

## [2025.11.14-preview] - 2025-11-14

### Added

- `LLMDB.Model.format_spec/1` function for converting model struct to provider:model string format
- Zai Coder provider and GLM models support
- Enhanced cost schema with granular multimodal and reasoning pricing fields:
  - `reasoning`: Cost per 1M reasoning/thinking tokens for models like o1, Grok-4
  - `input_audio`/`output_audio`: Separate audio input/output costs (e.g., Gemini 2.5 Flash, Qwen-Omni)
  - `input_video`/`output_video`: Video input/output cost support for future models
- ModelsDev source transformer now captures all cost fields from models.dev data
- OpenRouter source transformer maps `internal_reasoning` field to `reasoning` cost

### Changed

- Updated Zoi dependency to version 0.10.6
- Refactored loader to use dynamic snapshot retrieval
- Disabled schema validation in snapshot.json and TOML source files

### Fixed

- Cleaned up code quality issues
- Fixed application startup crash (`ArgumentError: not an already existing atom`) caused by race condition between build task and snapshot loading
- Fixed flaky tests in `LLMDB.EngineOverrideTest` by ensuring test isolation from global config
