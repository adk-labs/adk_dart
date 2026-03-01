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
