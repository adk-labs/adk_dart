# Sessions Parity Work Unit (2026-03-01 09:42:33)

## Scope
- Dart target:
  - `lib/src/sessions/database_session_service.dart`
  - `lib/src/sessions/sqlite_session_service.dart`
  - `test/session_persistence_services_test.dart`
- Python reference:
  - `ref/adk-python/src/google/adk/sessions/database_session_service.py`
  - `ref/adk-python/src/google/adk/sessions/sqlite_session_service.py`
  - `ref/adk-python/tests/unittests/sessions/test_session_service.py`

## Parity gaps addressed
1. Database session stale append behavior mismatch.
   - Python DB service reloads stale session and still appends.
   - Dart delegated directly to sqlite path and failed on stale session.
2. SQLite URL parsing mismatch for SQLAlchemy convention.
   - Python treats `sqlite:///...` as relative path and `sqlite:////...` as absolute.
   - Dart treated a subset of triple-slash paths as absolute.
3. Query parameter preservation mismatch.
   - Python preserves sqlite URI query params (including invalid `mode`) and lets sqlite fail.
   - Dart silently filtered invalid `mode` values.
4. Legacy schema guard missing.
   - Python fails fast when old `events` schema lacks `event_data`.
   - Dart opened DB without migration-needed guard.

## Implemented changes
1. `DatabaseSessionService.appendEvent` stale reload/retry path.
   - Added stale-session error detection and bounded retry loop.
   - On stale detection: reload latest session from delegate, refresh state/events/timestamp, retry append.
2. SQLite URL path resolver alignment.
   - Updated `_resolveSqliteUriPath` to SQLAlchemy-style behavior:
     - `sqlite:///relative.db` -> `relative.db`
     - `sqlite:////absolute.db` -> `/absolute.db`
3. SQLite query passthrough.
   - Removed `mode` value whitelist filtering in `_buildSqliteConnectionQuery`.
   - Connection string now preserves caller-provided query values.
4. Legacy schema migration guard.
   - Added constructor-time `_ensureNotLegacySchema(...)` check.
   - If `events` table exists but `event_data` column is missing, throws migration-needed `StateError`.

## Tests added/updated
- `test/session_persistence_services_test.dart`
  - Updated triple-slash sqlite path expectation to relative semantics.
  - Updated invalid `mode` behavior to expect write failure.
  - Added stale-session append success test for `DatabaseSessionService`.
  - Added legacy-schema fail-fast test for sqlite service initialization.

## Validation
- `dart analyze` for modified sessions files/tests: passed.
- Targeted tests + related suites: passed.
