# adk_core API Matrix (v2)

Date: 2026-03-01
Related plans:
- `knowledge/2026-02-28_21-44-13_adk_core_split_plan.md`
- `knowledge/2026-03-01_16-59-24_flutter_adk_all_platform_plan.md`

## Scope
- Entrypoint: `lib/adk_core.dart`
- Goal: Flutter/Web-safe import path that compiles on Web.

## Included (v1)

### Agents/App runtime primitives
- `src/agents/agent_state.dart`
- `src/agents/base_agent.dart`
- `src/agents/callback_context.dart`
- `src/agents/context.dart`
- `src/agents/invocation_context.dart`
- `src/agents/live_request_queue.dart`
- `src/agents/run_config.dart`
- `src/apps/app.dart`

### Data model / event / session / memory
- `src/events/event.dart`
- `src/events/event_actions.dart`
- `src/types/content.dart`
- `src/models/llm_request.dart`
- `src/models/llm_response.dart`
- `src/sessions/base_session_service.dart`
- `src/sessions/in_memory_session_service.dart`
- `src/sessions/session.dart`
- `src/sessions/state.dart`
- `src/memory/base_memory_service.dart`
- `src/memory/in_memory_memory_service.dart`
- `src/memory/memory_entry.dart`

### Plugin / tool / artifact / telemetry base
- `src/plugins/base_plugin.dart`
- `src/plugins/plugin_manager.dart`
- `src/tools/base_tool.dart`
- `src/tools/tool_context.dart`
- `src/artifacts/base_artifact_service.dart`
- `src/artifacts/in_memory_artifact_service.dart`
- `src/telemetry/base_telemetry_service.dart`
- `src/telemetry/in_memory_telemetry_service.dart`

### Common errors
- `src/errors/already_exists_error.dart`
- `src/errors/input_validation_error.dart`
- `src/errors/not_found_error.dart`

## Excluded (initial policy)

### Exclude rule
- Any API depending on one or more of:
  - `dart:io`
  - `dart:ffi`
  - `dart:mirrors`
  - Local process execution (`Process.*`)
  - Local filesystem / server runtime assumptions

### Key excluded groups
- CLI stack (`src/cli/**`, `src/dev/**`)
- FFI-backed/session migration stack (`src/sessions/sqlite_session_service.dart`, `src/sessions/migration/sqlite_db.dart`)
- Network/database local runtime services requiring VM-only deps
- Tools with direct IO/process dependencies (`src/tools/**` subset)
- VM-only telemetry exporters (`src/telemetry/sqlite_span_exporter.dart`, cloud exporter path)

## Validation Gate
- Smoke file: `tool/smoke/adk_core_web_smoke.dart`
- Gate script: `tool/check_adk_core_web_compile.sh`
- Command:
  - `dart compile js tool/smoke/adk_core_web_smoke.dart -o /tmp/adk_core_smoke.js`

## Web Compile Blockers Resolved
- `lib/src/agents/run_config.dart`
  - `sys.maxsize` sentinel을 `BigInt.parse` 기반 비교로 변경
- `lib/src/auth/auth_tool.dart`
  - FNV64 로직을 `BigInt` signed-int64 래핑으로 변경
- `lib/src/tools/openapi_tool/openapi_spec_parser/tool_auth_handler.dart`
  - 동일 FNV64 로직 정렬
- `lib/src/models/gemini_context_cache_manager.dart`
  - 동일 FNV64 로직 정렬

## Notes
- `adk_dart.dart` remains full VM/CLI export for backward compatibility.
- `adk_core.dart` is additive and intentionally narrower.
