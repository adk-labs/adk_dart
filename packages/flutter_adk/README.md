# flutter_adk

Flutter facade package for ADK Dart core runtime.

## What This Package Provides
- Re-exports `package:adk_dart/adk_core.dart` so Flutter apps can use the Web-safe ADK surface through `package:flutter_adk/flutter_adk.dart`.
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
- `flutter_adk` currently re-exports `adk_core` only.
- This means `Agent/LlmAgent`, `Runner`, and model adapters like `Gemini` are not yet exposed through `flutter_adk`.
- Platform support and limitations are tracked in:
  - `knowledge/2026-03-01_18-20-00_flutter_adk_platform_support_matrix.md`

## Limitations
- Features requiring `dart:io`, `dart:ffi`, or `dart:mirrors` are outside the current `flutter_adk` surface.
- Web support currently targets the `adk_core` subset only.
- For browser BYOK (user-entered API key), document security risks before production rollout.
