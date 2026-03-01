# Sessions Parity Unit: SQLite Migration Runtime

## Scope
- Target: `lib/src/sessions/migration/*` parity with `ref/adk-python/src/google/adk/sessions/migration/*`.
- Goal: replace JSON-file migration behavior with real SQLite schema detection and v0->v1 migration.

## Gaps Found
- Dart migration utilities were operating on JSON files instead of SQLite DBs.
- `migrate_from_sqlalchemy_sqlite.dart` was a thin passthrough and did not reflect Python migration semantics.
- `migration_runner.dart` created intermediate `.json` files for DB migration flow.
- `schema_check_utils.dart` detected schema from decoded JSON rather than DB tables/columns.

## Implementation
- Added migration SQLite runtime:
  - `lib/src/sessions/migration/sqlite_db.dart`
  - Includes SQLite URL resolution, native sqlite3 FFI open/query/execute/transaction, table/column inspection.
- Reworked `schema_check_utils.dart`:
  - `getDbSchemaVersion(...)` now opens SQLite DB and inspects:
    - `adk_internal_metadata` (`schema_version`)
    - fallback v0 signature: `events.actions` exists and `events.event_data` does not.
  - kept `toSyncUrl(...)` and `getDbSchemaVersionFromDecoded(...)` for compatibility.
- Reimplemented `migrate_from_sqlalchemy_pickle.dart`:
  - Source/destination are real SQLite URLs/paths.
  - Creates destination v1 tables (`adk_internal_metadata`, `app_states`, `user_states`, `sessions`, `events`).
  - Migrates `app_states`, `user_states`, `sessions`, `events` row-by-row with resilient parsing.
  - Converts legacy `events` rows into `event_data` JSON payloads.
  - Writes schema version metadata to `adk_internal_metadata`.
- Updated `migrate_from_sqlalchemy_sqlite.dart`:
  - Normalizes destination path handling (`:memory:` and sqlite URL/path).
- Updated `migration_runner.dart`:
  - Intermediate migration artifacts changed from `.json` to `.db`.

## Sessions Utility Parity Touch-ups
- `lib/src/sessions/session_util.dart`:
  - Added `decodeModel<T>(...)` helper for typed map decoding.
- `lib/src/sessions/state.dart`:
  - Added parity-oriented helpers: `setDefault`, `getValue`, `updateFromDelta`, `toDict`.

## Tests Updated
- Rewrote `test/session_migration_parity_test.dart` to use real SQLite source/destination DB fixtures:
  - schema detection on legacy v0/v1 metadata-backed DBs
  - v0/v1 event conversion roundtrip
  - migration payload verification (`event_data` and metadata)
  - migration runner upgrade flow

## Validation
- `dart analyze lib/src/sessions/migration lib/src/sessions/session_util.dart lib/src/sessions/state.dart test/session_migration_parity_test.dart`
- `dart test test/session_migration_parity_test.dart`
- `dart test test/session_persistence_services_test.dart`
- `dart test test/memory_service_test.dart test/vertex_memory_services_parity_test.dart test/plugin_manager_test.dart test/debug_logging_plugin_test.dart test/context_filter_plugin_test.dart test/global_instruction_plugin_test.dart test/multimodal_tool_results_plugin_test.dart test/reflect_retry_tool_plugin_test.dart test/save_files_as_artifacts_plugin_test.dart test/skills_models_test.dart test/skills_utils_test.dart test/skills_prompt_test.dart test/skill_toolset_parity_test.dart`
