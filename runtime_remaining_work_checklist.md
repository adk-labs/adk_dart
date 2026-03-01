# Runtime Remaining Work Checklist (Re-Audit)

Last updated: 2026-03-01 (post-A2A push delivery hardening + live DB integration test pass)
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
- [x] A2A runtime route parity expanded beyond minimal RPC:
  - `tasks/resubscribe` streaming replay
  - `tasks/pushNotificationConfig/set`
  - `tasks/pushNotificationConfig/get`
  - best-effort outbound push callback dispatch (`tasks/pushNotification`)
  - SSE behavior for `message/stream`
  - REST-style task routes under `/a2a/{app}/v1/tasks/{task_id}*` (get/subscribe/push config)
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
- [x] `SqliteSpanExporter` now uses real SQLite persistence (sqlite3 package), and debug trace endpoints read persisted spans (`event_id`, `session_id`).
- [x] `--extra_plugins` now supports runtime dynamic class loading from spec strings:
  - explicit class spec: `package:pkg/path/plugin.dart:PluginClass`
  - explicit file spec: `/abs/path/plugin.dart:PluginClass`
  - dotted path: `pkg.module.path.PluginClass`
  - still supports built-ins + registered factories.
- [x] A2A push callback delivery now has runtime resilience:
  - SQLite-backed persistent queue (`.adk/a2a_push_delivery.db`)
  - retry/backoff policy parsing from push config
  - startup/background drain loop with at-least-once callback delivery behavior
  - dead-letter capture when max retries are exhausted
- [x] Live DB integration test coverage added for network session backends:
  - PostgreSQL roundtrip test gated by `ADK_TEST_POSTGRES_URL`
  - MySQL roundtrip test gated by `ADK_TEST_MYSQL_URL`
  - tests are skipped (not failed) when env/ports are unavailable

## P2 - Runtime integration completion (production readiness)
- [x] Provide officially shipped runtime bootstrap wiring for cloud/service clients that fail fast without injection.
  - Added unified registration/reset API:
    - `configureToolRuntimeBootstrap(...)`
    - `resetToolRuntimeBootstrap(...)`
  - Covers bootstrap hooks for:
    - BigQuery client factory
    - Bigtable admin/data factories
    - Spanner client + embedders
    - Toolbox delegate factory
    - global audio recognizer (`AudioTranscriber.registerDefaultRecognizer`)
  - Note: concrete provider-specific clients are still integration-specific and may require user/project dependency wiring.

## Recommended execution order
1. P3 provider-specific default client implementations (optional), e.g. concrete BigQuery/Bigtable/Spanner adapters if "zero-injection" runtime is required.
