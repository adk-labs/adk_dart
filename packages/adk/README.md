# adk

`adk` provides the ADK Dart API with a shorter package name.

## Install

Add the package dependency:

```bash
dart pub add adk
```

Or add it manually in `pubspec.yaml`:

```yaml
dependencies:
  adk: ^0.1.0
```

For local development in this repository, you can use a path dependency:

```yaml
dependencies:
  adk:
    path: packages/adk
```

Then run:

```bash
dart pub get
```

## Import

```dart
import 'package:adk/adk.dart';
```

All core ADK Dart types are available from this import.

## CLI

This package also exposes the `adk` CLI executable.

For global use:

```bash
dart pub global activate adk
adk --help
```

For local package execution:

```bash
dart run adk:adk --help
```

## Example

```dart
import 'package:adk/adk.dart';

class EchoModel extends BaseLlm {
  EchoModel() : super(model: 'echo');

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    yield LlmResponse(content: Content.modelText('hello from adk'));
  }
}
```
