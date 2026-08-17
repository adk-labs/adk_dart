# Agent Development Kit (ADK) for Dart (`adk`)

English | [한국어](README.ko.md) | [日本語](README.ja.md) | [中文](README.zh.md)

[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)
[![pub package](https://img.shields.io/pub/v/adk.svg)](https://pub.dev/packages/adk)

`adk` is the command-line interface (CLI) toolchain and unified entrypoint for the Agent Development Kit (ADK) in Dart.

It bundles the `adk` command-line executable (`adk create`, `adk run`, `adk web`, `adk api_server`, `adk deploy`, `adk eval`) and provides top-level access to the full ADK Dart runtime via `package:adk/adk.dart`.

---

## What's New

- **ADK 2.0 Workflows & Managed Agent**: Fully exposes upstream ADK 2.0 v2 Workflows and GCP Managed Agent APIs.
- **Unified CLI Toolchain**: Ships the `adk` executable entrypoint for global activation (`dart pub global activate adk`) and local package workflows.
- **Unified SDK Entrypoint**: Full ADK Dart agent, runner, workflow, and tool APIs accessible through a clean, top-level package namespace.
- **MCP-Ready API Surface**: Includes MCP-enabled types and toolsets via upstream `adk_dart`.

## Key Features

- **Global & Local CLI Toolchain**: Run `adk create`, `adk run`, `adk web`, `adk api_server`, `adk deploy`, `adk eval`.
- **Complete ADK Runtime**: Seamlessly construct Agents, Sequential/Parallel/Loop workflows, LLM providers, and Tools.
- **Top-Level Package Namespace**: Direct import via `import 'package:adk/adk.dart';`.

## Ecosystem Packages & Roles

- **`adk`** (this package): CLI toolchain executable and top-level unified entrypoint for Dart VM and server environments.
- **`adk_dart`**: Core SDK runtime library providing the fundamental agent primitives, engine, and multi-agent coordination.
- **`flutter_adk`**: Flutter-specific multi-platform plugin providing platform channels, Web-safe runtime surfaces, and UI components.
- **`adk_mcp`**: Dedicated MCP (Model Context Protocol) integration package for client and server capabilities.
- **`adk_litertlm`**: On-device LLM acceleration package for LiteRT and Gemini Nano runtime on edge devices.

## When To Use `adk`

Use `adk` when:

- You want to use the `adk` CLI tool in your terminal (`dart pub global activate adk`).
- You are developing backend, server-side, or VM Dart applications and want the unified ADK entrypoint.

Use other packages when:

- You are writing Flutter client applications (Mobile/Desktop/Web): use `flutter_adk`.
- You are building internal modular extensions against the low-level SDK: use `adk_dart`.

## Package Links

- [adk](https://pub.dev/packages/adk): Short-name facade package that exports
  the ADK Dart API with `package:adk/adk.dart`.
- [adk_dart](https://pub.dev/packages/adk_dart): Core runtime package that
  provides the full ADK Dart VM/CLI surface.
- [flutter_adk](https://pub.dev/packages/flutter_adk): Flutter-focused package
  for web-safe multi-platform Flutter integration.

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
  adk: ^2026.8.17+1
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

Runnable feature-highlight sample (Google Search single agent + coordinator
multi-agent):

- `example/feature_highlight_agents.dart`

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
dart run adk --help
```

## Related Package

- Core implementation package: <https://pub.dev/packages/adk_dart>
- Repository: <https://github.com/adk-labs/adk_dart>

## License

This project is licensed under Apache 2.0. See [LICENSE](LICENSE).
