# Sessions Parity Unit: SQLite Entrypoint Alignment

## Scope
- Target: `migrate_from_sqlalchemy_sqlite.dart` parity with Python sqlite-specific migrator behavior.

## Gap Found
- Dart `migrateFromSqlalchemySqlite(...)` delegated to the pickle migrator and retained `adk_internal_metadata`.
- Python sqlite-specific migrator writes runtime tables only (no metadata table).

## Implementation
- Updated `lib/src/sessions/migration/migrate_from_sqlalchemy_sqlite.dart`:
  - Keep shared migration path via `migrateFromSqlalchemyPickle(...)`.
  - Post-step aligns sqlite-specific semantics by dropping `adk_internal_metadata`.
  - Handles destination URL normalization and opens destination DB via migration sqlite runtime helper.

## Tests
- Updated `test/session_migration_parity_test.dart`:
  - Added `sqlite-specific migration omits metadata table` test.
  - Verifies:
    - metadata table is absent
    - runtime tables are present
    - schema detector still reports latest (`1`) via `event_data` shape.

## Validation
- `dart analyze lib/src/sessions/migration/migrate_from_sqlalchemy_sqlite.dart test/session_migration_parity_test.dart`
- `dart test test/session_migration_parity_test.dart`
