# flutter_adk

Flutter facade package for ADK Dart core runtime.

## What This Package Provides
- Re-exports `package:adk_dart/adk_core.dart` so Flutter apps can use the Web-safe ADK surface through `package:flutter_adk/flutter_adk.dart`.
- Exposes core runtime APIs needed for Flutter app usage:
  - `Agent` / `LlmAgent`
  - `SequentialAgent` / `ParallelAgent` / `LoopAgent`
  - `Runner` / `InMemoryRunner`
  - `FunctionTool`
  - `McpToolset` (remote MCP over Streamable HTTP)
  - `SkillToolset` + inline `Skill`
  - `Gemini` (BYOK-style key injection)
- Includes a Flutter plugin scaffold registered for all major Flutter platforms:
  - Android
  - iOS
  - Web
  - Linux
  - macOS
  - Windows

## Usage

```dart
import 'package:flutter_adk/flutter_adk.dart';

void main() {
  final Session session = Session(id: 's1', appName: 'app', userId: 'u1');
  final InMemorySessionService sessions = InMemorySessionService();
  print('${session.id}:${sessions.runtimeType}');
}
```

## Full Runtime Surface
- For VM/CLI-only APIs, import `package:adk_dart/adk_dart.dart`.

## Platform Scope (Current)
- `flutter_adk` is a Flutter-focused runtime surface built on top of `adk_core`.
- It targets single-import usage across Flutter platforms while leaving VM/CLI-only APIs outside this package.

Status legend:

- `✅` Supported
- `⚠️` Supported with caveats
- `❌` Not supported

| Feature | Android | iOS | Web | Linux | macOS | Windows | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `flutter_adk` single import (`package:flutter_adk/flutter_adk.dart`) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | Re-exports the Web-safe `adk_core` surface. |
| Agent runtime (`Agent`, `Runner`, workflows) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | In-memory orchestration path is cross-platform. |
| `Gemini` model usage | ✅ | ✅ | ⚠️ | ✅ | ✅ | ✅ | Web requires BYOK/CORS/security policy consideration. |
| MCP Toolset via Streamable HTTP | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | Works with remote MCP HTTP servers. |
| MCP Toolset via stdio (`StdioConnectionParams`) | ⚠️ | ⚠️ | ❌ | ✅ | ✅ | ✅ | Web cannot spawn local processes; mobile runtime support can depend on sandbox/process policy. |
| Skills (`Skill`, `SkillToolset`) with inline definitions | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | Inline skills are platform-agnostic. |
| Directory-based skill loading (`loadSkillFromDir`) | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | Web throws `UnsupportedError` for filesystem-based loading. |
| Plugin channel helper (`FlutterAdk().getPlatformVersion()`) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | Uses platform channel / browser user-agent path. |
| VM/CLI tooling (`adk` executable, dev server, CLI deploy path) | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | Not part of the Flutter package surface. |

Reference matrix and rollout notes:
- `knowledge/2026-03-01_18-20-00_flutter_adk_platform_support_matrix.md`

## Limitations
- Features requiring `dart:io`, `dart:ffi`, or `dart:mirrors` are outside the current `flutter_adk` surface.
- MCP stdio transport (`StdioConnectionParams`) is not supported on Web.
- Directory-based skill loading (`loadSkillFromDir`) is not supported on Web. Use inline `Skill` definitions.
- For browser BYOK (user-entered API key), document security risks before production rollout.
