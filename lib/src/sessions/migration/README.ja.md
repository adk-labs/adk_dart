# Session Migration (Dart)

[English](README.md) | [한국어](README.ko.md) | 日本語 | [中文](README.zh.md)

このディレクトリは、Python ADK セッションスキーマ移行の parity を実現するための Dart ヘルパー群です。

- `sqlite_db.dart`: SQLite URL 解析と sqlite3 ランタイム補助
- `schema_check_utils.dart`: DB ベースのスキーマ版数判定と URL 正規化
- `migrate_from_sqlalchemy_pickle.dart`: 旧 v0 SQLAlchemy/SQLite 行を v1 JSON `event_data` へ移行
- `migrate_from_sqlalchemy_sqlite.dart`: SQLite 移行エントリーポイント
- `migration_runner.dart`: マイグレーションマップと一時 `.db` を使う段階的アップグレード実行

現在の最新スキーマバージョンは `1` です。
