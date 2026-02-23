# Session Migration (Dart)

This directory provides parity helpers for Python ADK session-schema migration.

- `schema_check_utils.dart`: schema-version detection and URL normalization.
- `migrate_from_sqlalchemy_pickle.dart`: v0-style event payload migration to v1 JSON event data.
- `migrate_from_sqlalchemy_sqlite.dart`: SQLite migration entrypoint.
- `migration_runner.dart`: multi-step upgrade runner using the configured migration map.

The current latest schema version is `1`.
