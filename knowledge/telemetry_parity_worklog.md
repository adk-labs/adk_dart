# Telemetry Python 1:1 Port Worklog

Date: 2026-03-01
Reference: `ref/adk-python/src/google/adk/telemetry`
Target: `lib/src/telemetry`

## Work Unit 1 - Gap Audit

### Compared files
- `setup.py` <-> `setup.dart`
- `google_cloud.py` <-> `google_cloud.dart`
- `sqlite_span_exporter.py` <-> `sqlite_span_exporter.dart`
- `tracing.py` <-> `tracing.dart`
- `_experimental_semconv.py` <-> missing in Dart (new file required)

### Audit result
- `setup` / `google_cloud` / `sqlite_span_exporter`: mostly ported, but provider overwrite behavior needed parity adjustment.
- `tracing`: core helpers existed, but Python parity gaps found.

### Missing or mismatched items found
1. Missing `trace_agent_invocation` equivalent.
2. Missing inference-span API family:
- `use_generate_content_span`
- `use_inference_span`
- `GenerateContentSpan`
- `trace_generate_content_result`
- `trace_inference_result`
3. Missing full experimental semconv implementation from `_experimental_semconv.py`.
4. `trace_call_llm` missing request attributes parity (`gen_ai.request.top_p`, `gen_ai.request.max_tokens`).
5. `setup` behavior mismatch: should not override already-set providers.

### Planned implementation units
- Work Unit 2: Implement missing telemetry APIs and semconv behavior.
- Work Unit 3: Add parity tests and validate behavior.

## Work Unit 2 - Missing Feature Implementation

### Implemented files
- `lib/src/telemetry/tracing.dart`
- `lib/src/telemetry/_experimental_semconv.dart` (new)
- `lib/src/telemetry/setup.dart`
- `lib/src/telemetry/google_cloud.dart`

### Implemented parity items
1. Added `traceAgentInvocation` to match Python `trace_agent_invocation`.
2. Added inference-span API parity:
- `useGenerateContentSpan` (deprecated parity helper)
- `useInferenceSpan`
- `GenerateContentSpan`
- `traceGenerateContentResult` (deprecated parity helper)
- `traceInferenceResult`
3. Ported experimental semconv behavior into new `_experimental_semconv.dart`:
- experimental opt-in detection (`OTEL_SEMCONV_STABILITY_OPT_IN`)
- capturing mode logic (`OTEL_INSTRUMENTATION_GENAI_CAPTURE_MESSAGE_CONTENT`)
- request/response operation-detail attribute builders
- completion-details log emission and span-attribute serialization
4. Updated `traceCallLlm` parity fields:
- `gen_ai.request.top_p`
- `gen_ai.request.max_tokens`
5. Updated `maybeSetOtelProviders` to avoid overriding pre-existing providers.
6. Added warning log on missing GCP project in `getGcpExporters`.

## Work Unit 3 - Validation and Regression Tests

### Updated test file
- `test/features_telemetry_parity_test.dart`

### Added coverage
1. Provider override prevention behavior in `maybeSetOtelProviders`.
2. `traceCallLlm` attribute parity for:
- `gen_ai.request.top_p`
- `gen_ai.request.max_tokens`
3. `traceAgentInvocation` attribute behavior.
4. `useInferenceSpan` + `traceInferenceResult` experimental semconv path:
- completion-details event emission
- span operation-details attribute persistence

### Validation commands and result
- `dart analyze lib/src/telemetry test/features_telemetry_parity_test.dart` -> passed.
- `mcp__dart__run_tests` on:
  - `test/features_telemetry_parity_test.dart`
  - `test/telemetry_test.dart`
  -> passed (`14 tests passed`).
