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

## プラットフォーム対応マトリクス (Current)

ステータス:

- `✅` Supported
- `⚠️` Partial / environment dependent
- `❌` Not supported

| Feature / Surface | Dart VM / CLI | Flutter (Android/iOS/Linux/macOS/Windows) | Flutter Web | Notes |
| --- | --- | --- | --- | --- |
| Full API via `package:adk_dart/adk_dart.dart` | ✅ | ⚠️ | ❌ | Includes `dart:io`/`dart:ffi`/`dart:mirrors` paths |
| Web-safe API via `package:adk_dart/adk_core.dart` | ✅ | ✅ | ✅ | Excludes IO/FFI/mirrors-only APIs |
| Agent runtime (`Agent`, `Runner`, workflows) | ✅ | ✅ | ✅ | In-memory path is cross-platform |
| MCP Streamable HTTP | ✅ | ✅ | ✅ | Web may require CORS-ready MCP server |
| MCP stdio (`StdioConnectionParams`) | ✅ | ⚠️ | ❌ | Requires local process execution |
| Inline Skills (`Skill`, `SkillToolset`) | ✅ | ✅ | ✅ | Web-safe usage |
| Directory skill loading (`loadSkillFromDir`) | ✅ | ⚠️ | ❌ | Throws `UnsupportedError` on Web |
| CLI (`adk create/run/web/api_server/deploy`) | ✅ | ❌ | ❌ | VM/terminal only |
| Dev web server + A2A endpoints | ✅ | ❌ | ❌ | Server runtime path |
| DB/file-backed services | ✅ | ⚠️ | ❌ | Depends on IO/network/filesystem constraints |

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
