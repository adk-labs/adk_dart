# March 11-12 Parity Batch

- Date: 2026-03-13
- Sources:
  - `reports/adk-python/2026-03-11.md`
  - `reports/adk-python/2026-03-12.md`
  - `ref/adk-python` commit ranges:
    - `ffe97ec5..0ad4de73`
    - `0ad4de73..c9109615`

## Work Unit 1: Gemini Live Grounding Metadata Parity

- Added `groundingMetadata` to `GeminiServerContentPayload`.
- `GeminiLlmConnection` now forwards grounding metadata for:
  - standalone server-content grounding payloads
  - model content payloads carrying grounding metadata
  - tool-call followed by grounded live content
- Added live regression coverage mirroring the Python intent around
  grounded live responses.

## Work Unit 2: SkillToolset Additional Toolset Support

- `SkillToolset.additionalTools` now accepts both:
  - `BaseTool`
  - `BaseToolset`
- Dynamic `adk_additional_tools` resolution now aggregates candidate tools from
  provided toolsets via `getToolsWithPrefix(...)` before matching by name.
- Added regression coverage for activated skill resolution through a provided
  toolset.

## Work Unit 3: LiteLLM Thought Signature Parity

- Added LiteLLM tool-call thought-signature extraction from:
  - `extra_content.google.thought_signature`
  - `provider_specific_fields.thought_signature`
  - nested function `provider_specific_fields`
  - `__thought__` suffix embedded in tool call ids
- Outbound LiteLLM tool-call payloads now preserve `Part.thoughtSignature`
  using both metadata paths expected by Gemini-compatible providers.
- Added round-trip regression coverage for function-call thought signatures.

## Work Unit 4: Anthropic Nested Schema Type Normalization

- `AnthropicLlm.functionDeclarationToToolParam(...)` now deep-copies and
  recursively lowercases nested schema `type` values.
- Covers nested object properties and JSON-schema combinators / containers such
  as:
  - `properties`
  - `additionalProperties`
  - `items`
  - `allOf` / `anyOf` / `oneOf`
  - `not`
  - `$defs`
- Added regression coverage for nested and combinator-heavy tool schemas.

## Work Unit 5: Conformance SSE Streaming Mode Support

- Added conformance streaming mode support for `none` and `sse`.
- `adk conformance record` can now emit mode-specific fixtures:
  - `generated-session.yaml`
  - `generated-recordings.yaml`
  - `generated-session-sse.yaml`
  - `generated-recordings-sse.yaml`
- `adk conformance test` now runs both supported streaming modes by default,
  or a single mode when `--streaming_mode` / `--streaming-mode` is provided.
- Replay and record state-delta payloads now include `streaming_mode`.
- Markdown reporting now summarizes results per streaming mode and emits a
  matrix-style results table.
- Added CLI regression coverage for live-mode dual-run output and SSE fixture
  generation.

## Notes

- Python commit `31174462` (Agent Engine tracking headers) was not ported
  directly.
- Reason: the Python change targets Vertex AI client initialization headers,
  while the current Dart deploy path shells out to `gcloud` and does not own a
  comparable Agent Engine HTTP client surface in `cli_deploy.dart`.
- Workflow-only, sample-only, and Python test-environment changes from these
  reports were also intentionally excluded from Dart parity scope.

## Verification

- `dart analyze` on changed files: clean
- Passed:
  - `test/models_parity_batch2_test.dart`
  - `test/skill_toolset_parity_test.dart`
  - `test/dev_cli_extended_commands_test.dart`
