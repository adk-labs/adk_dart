# 2026-03-01 Runtime Re-Audit (Post-Cleanup)

## Scope
- `lib/src/runners`
- `lib/src/tools`
- `lib/src/memory`
- `lib/src/sessions`
- `lib/src/plugins`
- `lib/src/skills`
- Reference: `ref/adk-python/src/google/adk/*`

## Method
- Re-ran file inventory parity checks between Python and Dart implementations.
- Re-checked known "not supported" behavior against Python source (to separate true missing features from parity-aligned limitations).
- Re-validated local analyzer state on touched code.

## Inventory Result (Python vs Dart)
- `memory`: 6 vs 6 (no missing module)
- `sessions`: 15 vs 17 (no missing module; Dart includes backend/runtime split helpers)
- `plugins`: 10 vs 10 (no missing module)
- `skills`: 3 vs 4 (no missing module; Dart has utility split)
- `tools`: 113 vs 129 (no missing module; Dart has additional runtime adapters/helpers)

## Parity Conclusions
- Module-level coverage for requested areas is aligned (no newly found unported module).
- `runners` core paths (`runAsync`, `runLive`, `rewindAsync`, plugin execution wrapping, resumable invocation routing) remain implemented and wired.
- Previously implemented runtime defaults remain in place:
  - BigQuery/Bigtable/Spanner default clients
  - Spanner default embedder runtime
  - Toolbox default HTTP delegate
  - GCS artifact live default providers

## "Unsupported" Items Rechecked Against Python
- OpenAPI external multi-file `$ref`: Python also rejects external refs (`External references not supported`).
- Spanner PostgreSQL ANN vector search: Python also raises `NotImplementedError` for ANN on PostgreSQL dialect.
- Audio transcription bootstrap: Python default path also needs explicit client/recognizer setup path in practice; Dart global/per-instance recognizer bootstrap is parity-aligned.

## Validation Notes
- `dart analyze` on target areas: no compile errors; one dead null-aware expression was fixed in `tool_auth_handler.dart`.
- Full `dart test` rerun in this sandbox is blocked by environment constraints:
  - `sqlite3` build hook attempts GitHub asset download (`Failed host lookup: github.com`) in network-restricted execution.
  - Dart telemetry file write outside writable root can fail unless home/env is redirected.

## Incremental Fix Applied During Re-Audit
- `lib/src/tools/openapi_tool/openapi_spec_parser/tool_auth_handler.dart`
  - Removed dead null-aware expression in `useIdToken` assignment.

