# adk_litertlm

[English](README.md) | [한국어](README.ko.md) | [日本語](README.ja.md) | 中文

适用于 ADK Dart 包的 LiteRT-LM 模型集成包。

本包提供了 `LiteRtModel` 实现，可将 [LiteRT-LM](https://pub.dev/packages/litertlm) 设备端模型连接到 ADK Dart Agent 运行时，从而实现完全离线的设备端 AI Agent 运行。

## 主要特性

- **设备端推理**: 使用 LiteRT-LM 模型完全在设备本地运行 Agent。
- **ADK 运行时集成**: 提供即插即用的 `BaseLlm` 实现，兼容 `LlmAgent` 和整个 ADK 流水线。
- **支持流式传输**: 实时按 Token 的流式响应。

## 安装

```bash
dart pub add adk_litertlm
```

或在 `pubspec.yaml` 中配置：

```yaml
dependencies:
  adk_litertlm: ^2026.8.17+1
```

## 快速上手

```dart
import 'package:adk_litertlm/adk_litertlm.dart';

final model = LiteRtModel(modelPath: 'path/to/model.tflite');
final agent = LlmAgent(name: 'local-agent', model: model);
```

## ADK 2.0 兼容性

本包与 ADK 2.0 保持一致，支持 v2 工作流（声明式节点图调度）以及适用于设备端 + 云端混合执行的 Managed Agent 集成。
