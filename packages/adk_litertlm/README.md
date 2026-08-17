# adk_litertlm

English | [한국어](README.ko.md) | [日本語](README.ja.md) | [中文](README.zh.md)

LiteRT-LM model integration for ADK Dart packages.

This package provides a `LiteRtModel` implementation that connects [LiteRT-LM](https://pub.dev/packages/litertlm) on-device models to the ADK Dart agent runtime, enabling fully offline, on-device AI agent execution.

## Features

- **On-device inference**: Run agents entirely on-device using LiteRT-LM models.
- **ADK runtime integration**: Drop-in `BaseLlm` implementation compatible with `LlmAgent` and the full ADK pipeline.
- **Streaming support**: Real-time token-by-token streaming responses.

## Installation

```bash
dart pub add adk_litertlm
```

Or add to your `pubspec.yaml`:

```yaml
dependencies:
  adk_litertlm: ^2026.8.17+1
```

## Getting Started

```dart
import 'package:adk_litertlm/adk_litertlm.dart';

final model = LiteRtModel(modelPath: 'path/to/model.tflite');
final agent = LlmAgent(name: 'local-agent', model: model);
```

## ADK 2.0 Compatibility

This package is aligned with ADK 2.0, supporting v2 Workflows (declarative node-graph scheduling) and Managed Agent integration for hybrid on-device + cloud execution.
