# Agent Development Kit (ADK) for Dart

[English](README.md) | [한국어](README.ko.md) | 日本語 | [中文](README.zh.md)

ADK Dart は、AI エージェントを構築・実行するためのコードファーストな Dart フレームワークです。
エージェント実行基盤、ツール連携、MCP 統合を提供します。

## 主な機能

- コードファーストなエージェントランタイム (`BaseAgent`, `LlmAgent`, `Runner`)
- イベントストリーミング実行
- マルチエージェント構成 (`Sequential`, `Parallel`, `Loop`)
- Function/OpenAPI/Google API/MCP ツール統合
- `adk` CLI (`create`, `run`, `web`, `api_server`, `deploy`)

## どのパッケージを使うべきか

| 利用ケース | 推奨パッケージ | 理由 |
| --- | --- | --- |
| Dart VM/CLI（サーバー、ツール、テスト、フルランタイム API）で開発 | `adk_dart` | ADK Dart のフルランタイム表面を提供する本体パッケージ |
| VM/CLI で短い import 名を使いたい | `adk` | `adk_dart` を再公開するファサード（`package:adk/adk.dart`） |
| Flutter アプリ（Android/iOS/Web/Linux/macOS/Windows）を開発 | `flutter_adk` | `adk_core` ベースの Flutter/Web-safe 表面を単一 import で提供 |

Quick rule:

- デフォルトは `adk_dart`
- 挙動は同じで import 名だけ短くしたいなら `adk`
- Flutter アプリコード（特に Web 対応）なら `flutter_adk`

## 設計思想

- `adk_dart` はランタイム parity を重視するコアパッケージです。
  ADK SDK の概念を維持しつつ、Dart VM 実行経路での機能実装を優先します。
- `adk` は使い勝手（命名）向けのファサードです。
  独自ランタイムは持たず、`adk_dart` を短い名前で再公開します。
- `flutter_adk` は Flutter のマルチプラットフォーム層です。
  Android/iOS/Web/Linux/macOS/Windows で一貫したコード経路を保つため、
  Web-safe な `adk_core` 表面を意図的に提供します。

用語メモ:

- 本 README の `VM/CLI` は Dart VM プロセス（CLI ツール、サーバープロセス、
  テスト、非 Flutter のデスクトップ Dart アプリ）を指します。
- Flutter デスクトップ UI アプリでは、既定の選択として `flutter_adk` を
  推奨します。

## プラットフォーム対応マトリクス (Current)

ステータス:

- `Y` Supported
- `Partial` Partial / environment dependent
- `N` Not supported

| Feature / Surface | Dart VM / CLI | Flutter (Android/iOS/Linux/macOS/Windows) | Flutter Web | Notes |
| --- | --- | --- | --- | --- |
| Full API via `package:adk_dart/adk_dart.dart` | Y | Partial | N | Includes `dart:io`/`dart:ffi`/`dart:mirrors` paths |
| Web-safe API via `package:adk_dart/adk_core.dart` | Y | Y | Y | Excludes IO/FFI/mirrors-only APIs |
| Agent runtime (`Agent`, `Runner`, workflows) | Y | Y | Y | In-memory path is cross-platform |
| MCP Streamable HTTP | Y | Y | Y | Web may require CORS-ready MCP server |
| MCP stdio (`StdioConnectionParams`) | Y | Partial | N | Requires local process execution |
| Inline Skills (`Skill`, `SkillToolset`) | Y | Y | Y | Web-safe usage |
| Directory skill loading (`loadSkillFromDir`) | Y | Partial | N | Throws `UnsupportedError` on Web |
| CLI (`adk create/run/web/api_server/deploy`) | Y | N | N | VM/terminal only |
| Dev web server + A2A endpoints | Y | N | N | Server runtime path |
| DB/file-backed services | Y | Partial | N | Depends on IO/network/filesystem constraints |

## Installation

```bash
dart pub add adk_dart
```

短い import パスを使う場合:

```bash
dart pub add adk
```

## Documentation

- 詳細な機能マトリクス/サンプル: [README.md](README.md)
- Repository: <https://github.com/adk-labs/adk_dart>
