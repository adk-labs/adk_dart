# flutter_adk

English | [한국어](README.ko.md) | [日本語](README.ja.md) | [中文](README.zh.md)

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

## When To Use `flutter_adk`

Use `flutter_adk` when:

- You are building a Flutter app and want one import that works across mobile,
  desktop, and web.
- You want the web-safe ADK runtime surface (`adk_core`) without pulling in
  VM-only APIs by default.

Use another package when:

- You are building VM/CLI agents, tools, or servers: use `adk_dart` (or `adk`
  for shorter imports).

Design intent:

- `flutter_adk` is not just a wrapper name; it is the Flutter-oriented
  compatibility layer.
- It prioritizes consistent multi-platform behavior in Flutter by exposing the
  web-safe runtime surface (`adk_core`) instead of the full VM-only API set.

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

- `Y` Supported
- `Partial` Supported with caveats
- `N` Not supported

| Feature | Android | iOS | Web | Linux | macOS | Windows | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `flutter_adk` single import (`package:flutter_adk/flutter_adk.dart`) | Y | Y | Y | Y | Y | Y | Re-exports the Web-safe `adk_core` surface. |
| Agent runtime (`Agent`, `Runner`, workflows) | Y | Y | Y | Y | Y | Y | In-memory orchestration path is cross-platform. |
| `Gemini` model usage | Y | Y | Partial | Y | Y | Y | Web requires BYOK/CORS/security policy consideration. |
| MCP Toolset via Streamable HTTP | Y | Y | Y | Y | Y | Y | Works with remote MCP HTTP servers. |
| MCP Toolset via stdio (`StdioConnectionParams`) | Partial | Partial | N | Y | Y | Y | Web cannot spawn local processes; mobile runtime support can depend on sandbox/process policy. |
| Skills (`Skill`, `SkillToolset`) with inline definitions | Y | Y | Y | Y | Y | Y | Inline skills are platform-agnostic. |
| Directory-based skill loading (`loadSkillFromDir`) | Y | Y | N | Y | Y | Y | Web throws `UnsupportedError` for filesystem-based loading. |
| Plugin channel helper (`FlutterAdk().getPlatformVersion()`) | Y | Y | Y | Y | Y | Y | Uses platform channel / browser user-agent path. |
| VM/CLI tooling (`adk` executable, dev server, CLI deploy path) | N | N | N | N | N | N | Not part of the Flutter package surface. |

Reference matrix and rollout notes:
- `knowledge/2026-03-01_18-20-00_flutter_adk_platform_support_matrix.md`

## Limitations
- Features requiring `dart:io`, `dart:ffi`, or `dart:mirrors` are outside the current `flutter_adk` surface.
- MCP stdio transport (`StdioConnectionParams`) is not supported on Web.
- Directory-based skill loading (`loadSkillFromDir`) is not supported on Web. Use inline `Skill` definitions.
- For browser BYOK (user-entered API key), document security risks before production rollout.
