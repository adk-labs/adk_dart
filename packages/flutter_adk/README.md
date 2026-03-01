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
