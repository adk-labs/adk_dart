# 2026-03-09 Python Parity Batch 2

Scope:
- Ref sync range reviewed: `adk-python` `6edcb975..9d155177`
- Reference inputs:
  - `reports/adk-python/2026-03-06.md`
  - `reports/adk-python/2026-03-07.md`
  - `reports/adk-python/2026-03-08.md`

This batch covers the upstream changes that were small enough to port directly
without opening a larger architecture refactor. The goal was functional parity
for runtime behavior, not just API surface alignment.

## Work Unit 1: BigQuery Config Guardrails

Reason:
- Python added stricter `job_labels` validation in `BigQueryToolConfig`.

Implemented:
- Reject more than 20 job labels.
- Reject reserved label keys starting with `adk-bigquery-`.

Files:
- `lib/src/tools/bigquery/config.dart`
- `test/bigquery_parity_test.dart`

## Work Unit 2: Skill Directory Listing Helper

Reason:
- Python added `_list_skills_in_dir()` for local skill discovery.

Implemented:
- Added `listSkillsInDir()` to enumerate valid local skills and skip invalid
  directories.
- Re-exported the helper from `src/skills/_utils.dart`.

Files:
- `lib/src/skills/skill.dart`
- `lib/src/skills/_utils.dart`
- `test/skills_utils_test.dart`

## Work Unit 3: Tool Execution Error Telemetry

Reason:
- Python added `ToolExecutionError` and started emitting semantic `error.type`
  on tool spans.

Implemented:
- Added `ToolErrorType` and `ToolExecutionError`.
- Extended `traceToolCall()` to accept an execution error and emit
  `error.type`.
- Exported the new error surface from `adk_dart` and `adk_core`.

Files:
- `lib/src/errors/tool_execution_error.dart`
- `lib/src/telemetry/tracing.dart`
- `lib/adk_dart.dart`
- `lib/adk_core.dart`
- `test/features_telemetry_parity_test.dart`

## Work Unit 4: Anthropic PDF Input Support

Reason:
- Python added inline PDF handling for Anthropic request conversion and skips
  PDF parts on assistant turns.

Implemented:
- Added PDF detection in `AnthropicLlm`.
- Mapped inline PDF parts to Anthropic `document` blocks.
- Skipped PDF payloads on non-user turns, matching the existing image rule.

Files:
- `lib/src/models/anthropic_llm.dart`
- `test/models_parity_batch2_test.dart`

## Work Unit 5: Platform Time and UUID Abstractions

Reason:
- Python introduced `platform/time.py` and `platform/uuid.py` to remove direct
  runtime dependence on wall-clock and random ID generation.

Implemented:
- Added `getTime()` / `getUtcNow()` with provider override hooks.
- Added `newUuid()` with provider override hooks.
- Routed event IDs, session IDs, timestamps, A2A synthetic IDs, and schema
  default timestamps through the new helpers.

Files:
- `lib/src/platform/time.dart`
- `lib/src/platform/uuid.dart`
- `lib/src/types/id.dart`
- `lib/src/events/event.dart`
- `lib/src/a2a/converters/event_converter.dart`
- `lib/src/a2a/executor/a2a_agent_executor.dart`
- `lib/src/agents/remote_a2a_agent.dart`
- `lib/src/sessions/in_memory_session_service.dart`
- `lib/src/sessions/sqlite_session_service.dart`
- `lib/src/sessions/network_database_session_service.dart`
- `lib/src/sessions/vertex_ai_session_service.dart`
- `lib/src/sessions/schemas/v0.dart`
- `lib/src/sessions/schemas/v1.dart`
- `test/features_telemetry_parity_test.dart`

## Work Unit 6: Simulator Null/Empty Chunk Regression

Reason:
- Python fixed an evaluation simulator path that could attempt to read from
  `None` streamed content.

Implemented:
- Added a regression test covering null content, empty parts, thought-only
  parts, and the eventual valid response.
- Runtime code already matched the intended behavior, so only the missing
  verification was added.

Files:
- `test/user_simulation_parity_test.dart`

## Verification

Static analysis:

```bash
dart analyze <changed files>
```

Result:
- No errors

Tests:

```bash
dart test \
  test/bigquery_parity_test.dart \
  test/skills_utils_test.dart \
  test/features_telemetry_parity_test.dart \
  test/models_parity_batch2_test.dart \
  test/user_simulation_parity_test.dart
```

Result:
- All tests passed

## Deferred Gaps

The following upstream areas were reviewed but intentionally left for later
because they require a larger feature batch:
- BigQuery catalog search / Dataplex integration
- Skill GCS loading and binary asset handling
- Dynamic skill tool activation via `adk_additional_tools`
- Larger A2A durable runtime parity
- Full Anthropic streaming/runtime parity beyond PDF request conversion
