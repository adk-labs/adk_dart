# flutter_adk

[English](README.md) | [한국어](README.ko.md) | 日本語 | [中文](README.zh.md)

Flutter で ADK Dart の Web-safe コアランタイムを使うためのファサードパッケージです。

## 提供内容

- `package:adk_dart/adk_core.dart` re-export
- Single Flutter import: `package:flutter_adk/flutter_adk.dart`
- Plugin registration for Android/iOS/Web/Linux/macOS/Windows

## `flutter_adk` を使うべきケース

`flutter_adk` を選ぶとよい場合:

- Flutter アプリでモバイル/デスクトップ/Web を単一 import で扱いたい
- VM 専用 API を既定で含めず、Web-safe な `adk_core` 表面を使いたい

別パッケージを選ぶ場合:

- VM/CLI のエージェント・ツール・サーバー開発: `adk_dart`
  （短い import が必要なら `adk`）

Design intent:

- `flutter_adk` は単なる名前ラッパーではなく、Flutter 向け互換レイヤーです。
- フル VM API をそのまま公開するのではなく、Web-safe な `adk_core` 表面を
  優先し、Flutter マルチプラットフォームでの一貫動作を重視します。

## Platform Support Matrix (Current)

Status legend:

- `Y` Supported
- `Partial` Supported with caveats
- `N` Not supported

| Feature | Android | iOS | Web | Linux | macOS | Windows | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Single import (`package:flutter_adk/flutter_adk.dart`) | Y | Y | Y | Y | Y | Y | Re-exports web-safe `adk_core` |
| Agent runtime (`Agent`, `Runner`, workflows) | Y | Y | Y | Y | Y | Y | In-memory path is cross-platform |
| `Gemini` model usage | Y | Y | Partial | Y | Y | Y | Consider BYOK/CORS/security on Web |
| MCP Toolset (Streamable HTTP) | Y | Y | Y | Y | Y | Y | Remote MCP HTTP servers |
| MCP Toolset (stdio) | Partial | Partial | N | Y | Y | Y | Web cannot spawn local processes |
| Skills (inline) | Y | Y | Y | Y | Y | Y | Inline skills are platform-agnostic |
| Directory skill loading (`loadSkillFromDir`) | Y | Y | N | Y | Y | Y | Web throws `UnsupportedError` |
| Plugin helper (`getPlatformVersion`) | Y | Y | Y | Y | Y | Y | Platform channel / browser user-agent |
| VM/CLI tooling (`adk`, dev server, deploy path) | N | N | N | N | N | N | Out of Flutter package scope |

## Usage

```dart
import 'package:flutter_adk/flutter_adk.dart';
```

## Links

- Full details: [README.md](README.md)
- Deep matrix notes: `knowledge/2026-03-01_18-20-00_flutter_adk_platform_support_matrix.md`
