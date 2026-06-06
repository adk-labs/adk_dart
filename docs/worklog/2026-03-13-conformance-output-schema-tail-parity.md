# 2026-03-13 Conformance and Output Schema Tail Parity

## Scope

- update unreleased changelog entries after the March parity batches
- align `LiteLlm` output-schema-with-tools capability with Python
- align `adk conformance record` positional streaming-mode parsing with Python

## Changes

### 1. Unreleased changelog sync

- added post-`2026.3.6` parity summary entries to root and facade changelogs
- kept the updates under `Unreleased` so published `2026.3.6` notes stay stable

### 2. LiteLLM output schema compatibility

- `canUseOutputSchemaWithTools(...)` now returns `true` for `LiteLlm` instances
- this matches Python behavior where LiteLLM-backed models are allowed to use structured output with tools

### 3. Conformance positional streaming mode

- `adk conformance record <path> sse`
- `adk conformance record <path> none`

The CLI now recognizes trailing positional streaming modes when the explicit
flag form is not used.

## Verification

- `dart analyze` on changed files
- `dart test test/utils_content_variant_output_schema_test.dart`
- `dart test test/dev_cli_extended_commands_test.dart`
