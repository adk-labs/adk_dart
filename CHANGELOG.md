## Unreleased

- Hardened A2A push callback delivery with a persistent SQLite queue, retry/backoff policy handling, startup/background drain, and dead-letter capture.
- Added A2A delivery reliability coverage in `test/dev_web_server_test.dart`, including persisted queue replay after restart.
- Added live network backend integration tests for PostgreSQL/MySQL session services (env-gated via `ADK_TEST_POSTGRES_URL` / `ADK_TEST_MYSQL_URL`).
- Added unified runtime adapter bootstrap APIs: `configureToolRuntimeBootstrap(...)` and `resetToolRuntimeBootstrap(...)`.
- Added global default audio recognizer registration support via `AudioTranscriber.registerDefaultRecognizer(...)`.
- Refreshed runtime checklist and README feature matrix to reflect current implemented behavior.

## 2026.2.28

- Switched package versioning scheme to date-based `YYYY.M.D`.
- Expanded `adk web` / `adk api_server` parity surface with bundled `/dev-ui` serving and broader API route compatibility.
- Hardened MCP transport/session behavior through `adk_mcp` integration updates and related tests.
- Replaced deprecated `mysql1` runtime dependency with `mysql_client_plus` in network session backend wiring.
- Added MySQL secure-fallback connect behavior for auth plugins that require TLS (for example `caching_sha2_password`).
- Added MySQL TLS hardening options (`ssl_ca_file`, `ssl_cert_file`/`ssl_key_file`, `ssl_verify`) with fail-fast validation for invalid TLS file configuration.
- Added runtime gap audit document for remaining non-functional/default-unwired features.

## 0.1.2

- Added package topics metadata on pub.dev to improve discoverability.

## 0.1.1

- Expanded Python parity coverage across evaluator workflows and remote code executor paths.
- Added parity ports for model contracts and toolset stacks, including Google API, Pub/Sub, and OpenAPI integrations.
- Added Spanner, Bigtable, and BigQuery client/toolset parity layers with vector store and metadata/query support.
- Added session schema/migration utilities and missing shared utility modules.

## 0.1.0

- Bootstrap `adk_dart` package as an ADK core runtime port (based on `ref/adk-python`).
- Added core agent/session/event/tool/model abstractions and execution flow.
- Added `Runner` / `InMemoryRunner` with async invocation path.
- Added function-call orchestration in LLM flow.
- Added baseline tests for event behavior, session service, and runner flow.
