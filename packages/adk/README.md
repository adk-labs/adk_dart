# Agent Development Kit (ADK) for Dart (`adk`)

English | [한국어](README.ko.md) | [日本語](README.ja.md) | [中文](README.zh.md)

[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)
[![pub package](https://img.shields.io/pub/v/adk.svg)](https://pub.dev/packages/adk)

`adk` is the short-name facade package for ADK Dart.

It re-exports `adk_dart` so you can use a shorter import path:
`package:adk/adk.dart`.

---

## What's New

- **Facade Package for ADK Dart**: Keeps the full ADK Dart API while providing
  a shorter package/import name.
- **CLI Exposure**: Ships the same `adk` executable entrypoint for local and
  global usage.
- **MCP-Ready API Surface**: Includes MCP-enabled types via the upstream
  `adk_dart` export surface.

## Key Features

- **Short Import Path**: `import 'package:adk/adk.dart';`
- **Full API Re-Export**: Access the same agent/runtime/tool APIs from
  `adk_dart`.
- **CLI Included**: Use `adk create`, `adk run`, `adk web`, `adk api_server`.

## When To Use `adk`

Use `adk` when:

- You are on Dart VM/CLI and want a shorter import path:
  `package:adk/adk.dart`.
- You want the same runtime behavior as `adk_dart` with package-name
  ergonomics.

Use another package when:

- You are writing Flutter app code (especially Web): use `flutter_adk`.
- You prefer explicit core package naming: use `adk_dart`.

Design intent:

- `adk` exists for naming ergonomics, not runtime divergence.
- If you need the same VM-first runtime surface as `adk_dart` with a shorter
  import, `adk` is the right choice.

## Platform Support Matrix (Current)

Status legend:

- `Y` Supported
- `Partial` Partially supported / environment dependent
- `N` Not supported

| Feature / Surface | Dart VM / CLI | Flutter (Android/iOS/Linux/macOS/Windows) | Flutter Web | Notes |
| --- | --- | --- | --- | --- |
| Import via `package:adk/adk.dart` (facade to `adk_dart`) | Y | Partial | N | Re-exports `package:adk_dart/adk_dart.dart` (full VM-first surface). |
| `adk` CLI executable | Y | N | N | Terminal/VM-only command entrypoint. |
| Runtime/tool features through facade (`MCP`, skills, sessions, etc.) | Y | Partial | N | Behavior follows `adk_dart` full API surface and its platform constraints. |
| Web-safe entrypoint from this package | N | N | N | `adk` does not provide `adk_core`; use `flutter_adk` or `adk_dart/adk_core.dart` directly for Web-safe surface. |

## Feature Support Matrix (Current)

This package is a facade. Runtime behavior comes from `adk_dart`, and this
package mainly provides short import/CLI ergonomics.

Status legend:

- `Y` Supported
- `Partial` Partial / integration required
- `N` Not supported yet

### Supported / Working

| Area | Feature | Status | Notes |
| --- | --- | --- | --- |
| Package role | Short import path (`package:adk/adk.dart`) | Y | Primary purpose of this package. |
| API surface | Re-export of `adk_dart` runtime/tooling APIs | Y | Uses upstream API surface directly. |
| CLI | `adk` executable entrypoint forwarding | Y | `bin/adk.dart` forwards to upstream CLI. |
| Runtime parity | Feature behavior aligned with `adk_dart` | Y | Same implementation path as upstream package. |

### Partial / Not Yet Supported

| Area | Feature | Status | Notes |
| --- | --- | --- | --- |
| Runtime implementation | Independent runtime implementation in this package | N | `adk` does not implement runtime itself; it delegates to `adk_dart`. |
| Feature divergence | Separate feature set different from `adk_dart` | N | Feature availability follows upstream `adk_dart` status. |
| Release decoupling | Independent publishability from upstream core | Partial | Depends on availability of matching `adk_dart` hosted versions. |

## Installation

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

## Gemini API Key Setup

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

## Import

```dart
import 'package:adk/adk.dart';
```

## Feature Highlight

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

## CLI

Global:

```bash
dart pub global activate adk
adk --help
```

Local package execution:

```bash
dart run adk:adk --help
```

## Related Package

- Core implementation package: <https://pub.dev/packages/adk_dart>
- Repository: <https://github.com/adk-labs/adk_dart>

## License

This project is licensed under Apache 2.0. See [LICENSE](LICENSE).
