# Agent Development Kit (ADK) for Dart (`adk`)

[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)
[![pub package](https://img.shields.io/pub/v/adk.svg)](https://pub.dev/packages/adk)

`adk` is the short-name facade package for ADK Dart.

It re-exports `adk_dart` so you can use a shorter import path:
`package:adk/adk.dart`.

---

## 🔥 What's New

- **Facade Package for ADK Dart**: Keeps the full ADK Dart API while providing
  a shorter package/import name.
- **CLI Exposure**: Ships the same `adk` executable entrypoint for local and
  global usage.
- **MCP-Ready API Surface**: Includes MCP-enabled types via the upstream
  `adk_dart` export surface.

## ✨ Key Features

- **Short Import Path**: `import 'package:adk/adk.dart';`
- **Full API Re-Export**: Access the same agent/runtime/tool APIs from
  `adk_dart`.
- **CLI Included**: Use `adk create`, `adk run`, `adk web`, `adk api_server`.

## 🚀 Installation

```bash
dart pub add adk
```

Or with `pubspec.yaml`:

```yaml
dependencies:
  adk: ^2026.2.28
```

For local repository development:

```yaml
dependencies:
  adk:
    path: packages/adk
```

Then:

```bash
dart pub get
```

## 🔐 Gemini API Key Setup

Use `GOOGLE_API_KEY` as the primary key environment variable.

```env
GOOGLE_GENAI_USE_VERTEXAI=0
GOOGLE_API_KEY=your_google_api_key
```

`adk_dart` also accepts `GEMINI_API_KEY` as a compatibility alias.

For Vertex AI usage:

```env
GOOGLE_GENAI_USE_VERTEXAI=1
GOOGLE_CLOUD_PROJECT=your-gcp-project-id
GOOGLE_CLOUD_LOCATION=us-central1
GOOGLE_API_KEY=your_google_api_key
```

Detailed runtime behavior and full setup guidance:
[adk_dart README](https://github.com/adk-labs/adk_dart/blob/main/README.md#-gemini-api-key-setup)

## 📦 Import

```dart
import 'package:adk/adk.dart';
```

## 🏁 Feature Highlight

### Define a single agent

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

## 🛠 CLI

Global:

```bash
dart pub global activate adk
adk --help
```

Local package execution:

```bash
dart run adk:adk --help
```

## 📚 Related Package

- Core implementation package: <https://pub.dev/packages/adk_dart>
- Repository: <https://github.com/adk-labs/adk_dart>

## 📄 License

This project is licensed under Apache 2.0. See [LICENSE](LICENSE).
