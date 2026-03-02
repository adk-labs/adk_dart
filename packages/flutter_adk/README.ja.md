# flutter_adk

[English](README.md) | [한국어](README.ko.md) | 日本語 | [中文](README.zh.md)

Flutter で ADK Dart の Web-safe コアランタイムを使うためのファサードパッケージです。

## 提供内容

- `package:adk_dart/adk_core.dart` re-export
- Single Flutter import: `package:flutter_adk/flutter_adk.dart`
- Plugin registration for Android/iOS/Web/Linux/macOS/Windows

## ✅ `flutter_adk` を使うべきケース

`flutter_adk` を選ぶとよい場合:

- Flutter アプリでモバイル/デスクトップ/Web を単一 import で扱いたい
- VM 専用 API を既定で含めず、Web-safe な `adk_core` 表面を使いたい

別パッケージを選ぶ場合:

- VM/CLI のエージェント・ツール・サーバー開発: `adk_dart`
  （短い import が必要なら `adk`）

## Platform Support Matrix (Current)

Status legend:

- `✅` Supported
- `⚠️` Supported with caveats
- `❌` Not supported

| Feature | Android | iOS | Web | Linux | macOS | Windows | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Single import (`package:flutter_adk/flutter_adk.dart`) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | Re-exports web-safe `adk_core` |
| Agent runtime (`Agent`, `Runner`, workflows) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | In-memory path is cross-platform |
| `Gemini` model usage | ✅ | ✅ | ⚠️ | ✅ | ✅ | ✅ | Consider BYOK/CORS/security on Web |
| MCP Toolset (Streamable HTTP) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | Remote MCP HTTP servers |
| MCP Toolset (stdio) | ⚠️ | ⚠️ | ❌ | ✅ | ✅ | ✅ | Web cannot spawn local processes |
| Skills (inline) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | Inline skills are platform-agnostic |
| Directory skill loading (`loadSkillFromDir`) | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | Web throws `UnsupportedError` |
| Plugin helper (`getPlatformVersion`) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | Platform channel / browser user-agent |
| VM/CLI tooling (`adk`, dev server, deploy path) | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | Out of Flutter package scope |

## Usage

```dart
import 'package:flutter_adk/flutter_adk.dart';
```

## Links

- Full details: [README.md](README.md)
- Deep matrix notes: `knowledge/2026-03-01_18-20-00_flutter_adk_platform_support_matrix.md`
