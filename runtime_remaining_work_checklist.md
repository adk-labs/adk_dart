# Runtime Remaining Work Checklist (Re-Audit)

Last updated: 2026-03-01 (post-P1 web parity implementation pass)
Scope: `adk_dart` runtime/CLI/web behavior parity vs `ref/adk-python` and actual runnable status.

## Audit method
- Re-audited current code paths under `lib/src` after latest commits.
- Re-checked Python parity endpoints/behavior from `ref/adk-python/src/google/adk/cli/*`.
- Re-ran core runtime tests:
  - `dart test test/session_persistence_services_test.dart` (pass)
  - `dart test test/dev_web_server_test.dart test/cli_adk_web_server_test.dart` (pass)

## Completed (confirmed)
- [x] `gs://` artifact service registry wiring is fixed and constructible in runtime.
- [x] `adk deploy` has real execution path (`--dry-run` + actual gcloud process execution).
- [x] `--a2a` dev web now serves agent card + JSON-RPC entry routes (`message/send`, `message/stream`, `tasks/get`, `tasks/cancel`).
- [x] SQLite session persistence path is operational and covered by tests.
- [x] PostgreSQL/MySQL URL dispatch is operational at service-selection level.
- [x] ADK web debug/eval/metrics/event-graph route families are now present in Dart web server:
  - `/debug/trace/{event_id}`
  - `/debug/trace/session/{session_id}`
  - `/apps/{app_name}/metrics-info`
  - `/apps/{app_name}/eval-*` and legacy `/eval_*`
  - `/apps/{app_name}/users/{user_id}/sessions/{session_id}/events/{event_id}/graph`
- [x] `--eval_storage_uri` is now wired end-to-end from CLI parse to web server eval manager selection.
- [x] `/run_sse` now applies Python-style split emission when content and `artifact_delta` co-exist.

## P1 - Remaining parity gaps (high priority)
- [ ] Implement Python-style dynamic plugin loading for `--extra_plugins`.
  - Current: registry-backed custom factory loading is implemented (`registerExtraPluginFactory`), but importlib-equivalent module/class runtime loading from arbitrary dotted path is not available.
  - Evidence:
    - `lib/src/dev/web_server.dart` uses built-in mapping + explicit factory registry.
    - Python still supports direct dotted import (`importlib.import_module`).

- [ ] Expand A2A server parity beyond minimal RPC surface.
  - Current: minimal JSON-RPC support is present, but advanced server behaviors from full A2A server stack are not implemented.
  - Evidence:
    - Dart routing maps only a small fixed set of operations in `web_server.dart`.
    - Python delegates to A2A server application stack (`A2AStarletteApplication` + default handlers/stores).

## P2 - Runtime integration completion (production readiness)
- [ ] Replace JSON-file storage in `SqliteSpanExporter` with real SQLite-backed exporter and wire it into debug trace endpoints.
  - Current: exporter persists JSON file at `dbPath`; no runtime debug route integration.
  - Evidence:
    - `lib/src/telemetry/sqlite_span_exporter.dart`.

- [ ] Provide default runtime adapters (or officially shipped bootstrap) for cloud/service clients that currently fail fast without injection.
  - Current examples:
    - BigQuery default client factory throws.
    - Bigtable/Spanner factories throw if not configured.
    - Toolbox delegate missing -> runtime error.
    - Vertex code interpreter/audio transcriber require injected clients.

- [ ] Add live DB integration tests (PostgreSQL/MySQL) against running containers.
  - Current: tests cover URL dispatch/guards, not real network CRUD roundtrip.
  - Evidence:
    - `test/session_persistence_services_test.dart`.

## Recommended execution order
1. P1 dynamic plugin dotted-path loading parity strategy finalization.
2. P1 A2A server parity expansion.
3. P2 telemetry SQLite exporter + debug trace linkage.
4. P2 live Postgres/MySQL integration tests and default adapter packaging policy.
