# Runtime Remaining Work Checklist (Fresh Audit)

Last updated: 2026-03-01
Scope: `adk_dart` runtime/CLI/web behavior parity vs `ref/adk-python` and actual runnable status.

## Audit method
- Re-audited live code paths under `lib/src` (not relying on old docs).
- Re-checked Python parity endpoints/CLI behavior from `ref/adk-python/src/google/adk/cli/*`.
- Re-ran core runtime tests:
  - `dart test test/session_persistence_services_test.dart test/dev_web_server_test.dart test/cli_adk_web_server_test.dart` (pass)

## Verified working (not remaining)
- SQLite session persistence/runtime behavior is working (create/get/list/update/delete/event persistence).
- Database URL dispatch now includes built-in PostgreSQL/MySQL path (`DatabaseSessionService` -> `NetworkDatabaseSessionService`).
- ADK web base routes are working (`/health`, `/version`, `/list-apps`, `/run`, `/run_sse`, legacy session routes).

## P0 - Must fix for real feature operation parity
- [x] Fix `gs://` artifact service runtime break in service registry. (2026-03-01)
  - Current: registry creates `GcsArtifactService(parsed.authority)` without required live providers.
  - Effect: `--artifact_service_uri=gs://...` fails immediately.
  - Evidence:
    - `lib/src/cli/service_registry.dart:192-195`
    - `lib/src/artifacts/gcs_artifact_service.dart:64-69`

- [x] Implement real `adk deploy` execution path (2026-03-01).
  - Current: command prints generated gcloud command and exits.
  - Effect: deploy command is non-functional.
  - Evidence:
    - `lib/src/cli/cli_tools_click.dart:28-47`
    - Python reference executes deploy command: `ref/adk-python/src/google/adk/cli/cli_deploy.py:760-800`

- [ ] Complete `--a2a` server behavior to include A2A RPC routes, not only agent card routes.
  - Current: only `/.well-known/agent.json`, `/a2a/agent-card`, and scoped agent-card URLs are served.
  - Effect: A2A protocol calls cannot run, only card discovery works.
  - Evidence:
    - `lib/src/dev/web_server.dart:413-429`
    - Python A2A route mounting: `ref/adk-python/src/google/adk/cli/fast_api.py:579-590`

## P1 - High priority parity gaps (web/debug/eval/plugin behavior)
- [ ] Add missing debug/eval/metrics/event-graph web APIs used by Python ADK web.
  - Missing families include:
    - `/debug/trace/{event_id}`
    - `/debug/trace/session/{session_id}`
    - `/apps/{app_name}/metrics-info`
    - `/apps/{app_name}/eval-*` and legacy `/eval_*`
    - `/apps/{app_name}/users/{user_id}/sessions/{session_id}/events/{event_id}/graph`
  - Evidence:
    - Dart route surface currently limited around: `lib/src/dev/web_server.dart:437-555`, `557-668`, `1013-1250`
    - Python endpoint definitions: `ref/adk-python/src/google/adk/cli/adk_web_server.py:794-1744`

- [ ] Wire `--eval_storage_uri` into actual runtime configuration.
  - Current: option is parsed then discarded.
  - Effect: eval storage backend cannot be configured from CLI.
  - Evidence:
    - `lib/src/dev/cli.dart:571-577`

- [ ] Make `--extra_plugins` load external plugins dynamically (module/class), not built-in-name mapping only.
  - Current: static normalization/switch supports only built-ins; unknown entries are ignored.
  - Effect: Python-style custom plugin loading path is unavailable.
  - Evidence:
    - `lib/src/dev/web_server.dart:2267-2325`
    - Python dynamic import path: `ref/adk-python/src/google/adk/cli/adk_web_server.py:569-603`

- [ ] Align `/run_sse` artifact delta streaming behavior with Python split-event semantics.
  - Current: streams one event as-is.
  - Python: may split into content event + artifact-only action event for web rendering consistency.
  - Evidence:
    - Dart: `lib/src/dev/web_server.dart:1331-1353`
    - Python: `ref/adk-python/src/google/adk/cli/adk_web_server.py:1703-1721`

## P2 - Integration completion / production readiness
- [ ] Replace JSON-file fallback in `SqliteSpanExporter` with real SQLite-backed exporter + wire into debug trace flow.
  - Current: writes/reads JSON array from `dbPath`, not sqlite DB.
  - Effect: telemetry persistence parity and tooling expectations diverge.
  - Evidence:
    - Dart: `lib/src/telemetry/sqlite_span_exporter.dart:66-82`, `185-192`
    - Python sqlite exporter: `ref/adk-python/src/google/adk/telemetry/sqlite_span_exporter.py:21-106`

- [ ] Provide default runtime integrations (or officially shipped adapters) for cloud DB/tool clients.
  - Current defaults throw until factory/delegate is injected:
    - BigQuery: `lib/src/tools/bigquery/client.dart:140-149`
    - Bigtable: `lib/src/tools/bigtable/client.dart:78-120`
    - Spanner: `lib/src/tools/spanner/client.dart:78-123`
    - Toolbox delegate: `lib/src/tools/toolbox_toolset.dart:85-91`
    - Vertex code interpreter client: `lib/src/code_executors/vertex_ai_code_executor.dart:152-155`
    - Audio transcriber recognizer: `lib/src/flows/llm_flows/audio_transcriber.dart:77-80`
  - Effect: feature surfaces exist but are not out-of-box runnable without custom wiring.

- [ ] Add real integration tests for network DB backends (PostgreSQL/MySQL) using running containers.
  - Current tests validate URL dispatch and guards but do not verify end-to-end CRUD against live DB servers.
  - Evidence:
    - `test/session_persistence_services_test.dart` (no live Postgres/MySQL round-trip)

## Suggested execution order
1. P0 blockers (`gs://` artifact, deploy execution, full A2A RPC).
2. P1 web parity APIs + eval storage wiring + dynamic plugin loading.
3. P2 telemetry sqlite + default client adapters + live DB integration tests.
