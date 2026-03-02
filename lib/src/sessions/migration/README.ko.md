# Session Migration (Dart)

[English](README.md) | 한국어 | [日本語](README.ja.md) | [中文](README.zh.md)

이 디렉터리는 Python ADK 세션 스키마 마이그레이션 parity를 위한 Dart 헬퍼를 제공합니다.

- `sqlite_db.dart`: SQLite URL 파싱 및 네이티브 sqlite3 런타임 헬퍼
- `schema_check_utils.dart`: DB 기반 스키마 버전 감지 및 URL 정규화
- `migrate_from_sqlalchemy_pickle.dart`: 레거시 v0 SQLAlchemy/SQLite 행을 v1 JSON `event_data`로 마이그레이션
- `migrate_from_sqlalchemy_sqlite.dart`: SQLite 마이그레이션 엔트리포인트 래퍼
- `migration_runner.dart`: 마이그레이션 맵과 임시 `.db`를 사용하는 다단계 업그레이드 실행기

현재 최신 스키마 버전은 `1`입니다.
