# Runtime Remaining Work Checklist (Re-Audit)

Last updated: 2026-03-01 (post-runtime default cloud client + toolbox/embedder wiring)
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
- [x] Provider default cloud client implementations are now bundled for core data tools:
  - BigQuery default client factory (REST)
  - Bigtable admin/data default client factories (REST)
  - Spanner default client factory (REST)
  - Default token lookup supports explicit oauth token, env token, gcloud ADC token, and metadata server token
- [x] Spanner default embedder runtime is now bundled:
  - Vertex AI `predict` call path is available by default for embedding models
  - full model resource path and project/location env fallbacks are supported
  - if runtime prerequisites are missing, error guidance remains explicit (`setSpannerEmbedders()`)
- [x] Toolbox default runtime delegate is now bundled:
  - native toolbox HTTP endpoints are supported without extra delegate wiring:
    - `GET /api/toolset/{name}`
    - `POST /api/tool/{tool}/invoke`
  - custom delegate/factory registration still works for advanced integrations
- [x] `GcsArtifactService` live mode now has built-in HTTP/auth providers:
  - default auth header resolution uses Google access token discovery
  - custom providers are still supported for tests and custom transports

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
  - Note: provider defaults are now bundled, and bootstrap remains useful for custom enterprise adapters/mocks.

## Recommended execution order
1. P3 hardening: add live integration tests for default BigQuery/Bigtable/Spanner/GCS/Toolbox runtimes (env-gated, non-blocking by default).
2. P3 parity closure: continue endpoint-level behavior diff tests against `ref/adk-python` for non-core optional integrations.
