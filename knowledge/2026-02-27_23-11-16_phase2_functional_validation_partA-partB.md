# Phase2 Functional Validation Briefing (Part A/B)

- Date: 2026-02-27 23:11:16
- Scope (4-folder x 2 parts):
  - Part A: `lib/src/apps`, `lib/src/cli`, `lib/src/code_executors`, `lib/src/evaluation`
  - Part B: `lib/src/flows`, `lib/src/models`, `lib/src/sessions`, `lib/src/utils`

## 1) Python 기준 동작 계약 확인

Reference inspected:
- `ref/adk-python/src/google/adk/apps/compaction.py`
- `ref/adk-python/src/google/adk/cli/cli_tools_click.py`
- `ref/adk-python/src/google/adk/cli/cli_deploy.py` (`_resolve_project` behavior)
- `ref/adk-python/src/google/adk/code_executors/agent_engine_sandbox_code_executor.py`
- `ref/adk-python/src/google/adk/evaluation/eval_metrics.py`, `eval_result.py`
- `ref/adk-python/src/google/adk/flows/llm_flows/basic.py`
- `ref/adk-python/src/google/adk/flows/llm_flows/_output_schema_processor.py`
- `ref/adk-python/src/google/adk/models/google_llm.py`
- `ref/adk-python/src/google/adk/sessions/database_session_service.py`
- `ref/adk-python/src/google/adk/utils/yaml_utils.py`

Contract highlights applied:
- Compaction: token-threshold compaction triggers should short-circuit sliding-window compaction in same pass.
- Agent Engine sandbox output: JSON stream fields prioritize `msg_out`/`msg_err`.
- Eval metric result JSON: support Python-style `metric_name`, `eval_status`, `details` while keeping legacy parsing compatibility.
- LLM flow output schema: allow native schema+tools for supported model/backend combinations; fallback tool (`set_model_response`) only when required.
- Gemini model: missing API key should fail fast instead of emitting synthetic mock content.
- DB session service: unsupported DB URLs should fail fast.
- YAML loader: literal block scalar (`|`, `|-`, `|+`) multiline parsing support.

## 2) Dart 구현 검수 및 수정

Implementation updates:
- `lib/src/apps/compaction.dart`
  - `runCompactionForSlidingWindow` now returns immediately when token-threshold compaction already ran.
- `lib/src/cli/cli_tools_click.dart`
  - CLI entry supports injected `environment` for deterministic deploy resolution and proper stderr+exit code on missing project.
- `lib/src/code_executors/agent_engine_sandbox_code_executor.dart`
  - JSON output parsing now prefers `msg_out`/`msg_err` with `stdout`/`stderr` fallback.
- `lib/src/evaluation/eval_result.dart`
  - Added Python metric JSON contract handling (`metric_name`, `eval_status`, `details`) plus tolerant legacy parsing.
- `lib/src/flows/llm_flows/basic.dart`
  - Output schema is set directly when model supports schema+tools parity path.
- `lib/src/flows/llm_flows/output_schema_processor.dart`
  - `set_model_response` injection only for unsupported schema+tools combinations.
- `lib/src/models/google_llm.dart`
  - Removed synthetic fallback response path; missing API key now throws `StateError`.
- `lib/src/sessions/database_session_service.dart`
  - Unsupported database URL now throws explicit `UnsupportedError`.
- `lib/src/utils/yaml_utils.dart`
  - Added block scalar parsing logic for map/list values with chomp indicator handling.

## 3) 테스트 추가/수정

Updated tests:
- `test/compaction_parity_test.dart`
  - Added token-first compaction short-circuit scenario.
- `test/cli_tools_click_parity_test.dart`
  - Added deploy env resolution success/failure cases.
- `test/code_execution_parity_test.dart`
  - Added `msg_out`/`msg_err` precedence assertion.
- `test/evaluation_surface_contracts_test.dart`
  - Added Python metric JSON contract assertions.
- `test/flow_processors_parity_test.dart`
  - Added Vertex Gemini2+ native schema+tools behavior assertion.
- `test/google_llm_rest_test.dart`
  - Added missing API key fail-fast test.
- `test/session_persistence_services_test.dart`
  - Added unsupported DB URL fail-fast test.
- `test/utils_batch_parity_test.dart`
  - Added YAML block-scalar parse test.

## 4) 검증 커맨드 결과

Executed in `adk_dart/`:
- `dart format .` (targeted files): success, no formatting changes required.
- `dart analyze`: success (info-level lints only, no errors).
- `dart test`: success (`640 passed`, `1 skipped` where Vertex env var is required).

## 5) 학습/운영 포인트

- Python parity at this stage benefits from fail-fast semantics (no mock fallback) for external integrations.
- Schema+tools handling must remain backend-aware (Vertex Gemini2+ native path vs fallback tool path).
- YAML literal block support materially reduces config mismatch risk in agent config/instruction files.
- Contract tests should encode both modern and legacy payloads to protect migration compatibility.
