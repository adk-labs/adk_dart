# adk_litertlm

[English](README.md) | [한국어](README.ko.md) | 日本語 | [中文](README.zh.md)

ADK Dart パッケージ用の LiteRT-LM モデル統合パッケージです。

このパッケージは、[LiteRT-LM](https://pub.dev/packages/litertlm) オンデバイスモデルを ADK Dart エージェントランタイムに接続する `LiteRtModel` 実装を提供し、完全なオフライン環境でのオンデバイス AI エージェントの実行を可能にします。

## 主な機能

- **オンデバイス推論**: LiteRT-LM モデルを使用し、完全にデバイス上でエージェントを実行します。
- **ADK ランタイム統合**: `LlmAgent` および全体の ADK パイプラインと互換性のあるドロップインの `BaseLlm` 実装を提供します。
- **ストリーミングサポート**: リアルタイムでトークン単位のストリーミング応答をサポートします。

## インストール

```bash
dart pub add adk_litertlm
```

または `pubspec.yaml`:

```yaml
dependencies:
  adk_litertlm: ^2026.8.17+1
```

## はじめに

```dart
import 'package:adk_litertlm/adk_litertlm.dart';

final model = LiteRtModel(modelPath: 'path/to/model.tflite');
final agent = LlmAgent(name: 'local-agent', model: model);
```

## ADK 2.0 互換性

このパッケージは ADK 2.0 と整合しており、v2 ワークフロー（宣言的なノードグラフスケジューリング）およびハイブリッドなオンデバイス + クラウド実行のための Managed Agent 連携に対応しています。
