# Session Migration (Dart)

[English](README.md) | [한국어](README.ko.md) | [日本語](README.ja.md) | 中文

该目录提供 Dart 侧的迁移辅助工具，用于与 Python ADK 会话 schema 迁移保持一致。

- `sqlite_db.dart`: SQLite URL 解析与原生 sqlite3 运行时辅助
- `schema_check_utils.dart`: 基于数据库的 schema 版本检测与 URL 规范化
- `migrate_from_sqlalchemy_pickle.dart`: 将旧版 v0 SQLAlchemy/SQLite 行迁移为 v1 JSON `event_data`
- `migrate_from_sqlalchemy_sqlite.dart`: SQLite 迁移入口封装
- `migration_runner.dart`: 基于迁移映射和临时 `.db` 的多阶段升级执行器

当前最新 schema 版本为 `1`。
