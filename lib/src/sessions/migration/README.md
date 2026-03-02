# Session Migration (Dart)

English | [한국어](README.ko.md) | [日本語](README.ja.md) | [中文](README.zh.md)

This directory provides parity helpers for Python ADK session-schema migration.

- `sqlite_db.dart`: SQLite URL parsing and native sqlite3 runtime helpers used by migration.
- `schema_check_utils.dart`: DB-backed schema-version detection and URL normalization.
- `migrate_from_sqlalchemy_pickle.dart`: migrates legacy v0 SQLAlchemy/SQLite schema rows into v1 JSON `event_data`.
- `migrate_from_sqlalchemy_sqlite.dart`: SQLite migration entrypoint wrapper.
- `migration_runner.dart`: multi-step upgrade runner using the configured migration map and temporary `.db` intermediates.

The current latest schema version is `1`.
