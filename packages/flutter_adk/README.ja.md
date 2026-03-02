# flutter_adk

[English](README.md) | [한국어](README.ko.md) | 日本語 | [中文](README.zh.md)

Flutter で ADK Dart の Web-safe コアランタイムを使うためのファサードパッケージです。

## 提供内容

- `package:adk_dart/adk_core.dart` re-export
- Single Flutter import: `package:flutter_adk/flutter_adk.dart`
- Plugin registration for Android/iOS/Web/Linux/macOS/Windows

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
