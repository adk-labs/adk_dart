# flutter_adk

[English](README.md) | [한국어](README.ko.md) | 日本語 | [中文](README.zh.md)

Flutter で ADK Dart の Web-safe コアランタイムを使うためのファサードパッケージです。

## 提供内容

- `package:adk_dart/adk_core.dart` re-export
- Single Flutter import: `package:flutter_adk/flutter_adk.dart`
- Latest Web-safe ADK surface such as `AgentTool`, `UrlContextTool`, and Vertex
  retrieval tools
- Plugin registration for Android/iOS/Web/Linux/macOS/Windows

## `flutter_adk` を使うべきケース

`flutter_adk` を選ぶとよい場合:

- Flutter アプリでモバイル/デスクトップ/Web を単一 import で扱いたい
- VM 専用 API を既定で含めず、Web-safe な `adk_core` 表面を使いたい

別パッケージを選ぶ場合:

- VM/CLI のエージェント・ツール・サーバー開発: `adk_dart`
  （短い import が必要なら `adk`）

Design intent:

- `flutter_adk` は単なる名前ラッパーではなく、Flutter 向け互換レイヤーです。
- フル VM API をそのまま公開するのではなく、Web-safe な `adk_core` 表面を
  優先し、Flutter マルチプラットフォームでの一貫動作を重視します。

## パッケージリンク

- [flutter_adk](https://pub.dev/packages/flutter_adk): Flutter
  マルチプラットフォームで使う Web-safe ADK 表面を提供します。
- [adk_dart](https://pub.dev/packages/adk_dart): ADK Dart の VM/CLI
  フルランタイム API を提供するコアパッケージです。
- [adk](https://pub.dev/packages/adk): `adk_dart` を短い名前で再公開する
  ファサードパッケージです。

## ADK 2.0 互換性

このパッケージは ADK 2.0 と整合しており、v2 ワークフロー（宣言的なノードグラフスケジューリング、条件付きルーティング、および状態マージ）と GCP Managed Agents（`ManagedAgent` および `RemoteMcpServer` 設定マッピングを含む）によるハイブリッドオンデバイス + クラウド実行をサポートしています。

## Platform Support Matrix (Current)

Status legend:

- `Y` Supported
- `Partial` Supported with caveats
- `N` Not supported

| Feature | Android | iOS | Web | Linux | macOS | Windows | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Single import (`package:flutter_adk/flutter_adk.dart`) | Y | Y | Y | Y | Y | Y | Re-exports web-safe `adk_core` |
| Agent runtime (`Agent`, `Runner`, workflows) | Y | Y | Y | Y | Y | Y | In-memory path is cross-platform |
| `Gemini` model usage | Y | Y | Partial | Y | Y | Y | Consider BYOK/CORS/security on Web |
| Built-in model tools (`UrlContextTool`, Vertex retrieval) | Y | Y | Y | Y | Y | Y | Tool execution is handled by Gemini/Vertex backends |
| MCP Toolset (Streamable HTTP) | Y | Y | Y | Y | Y | Y | Remote MCP HTTP servers |
| MCP Toolset (stdio) | Partial | Partial | N | Y | Y | Y | Web cannot spawn local processes |
| Skills (inline) | Y | Y | Y | Y | Y | Y | Inline skills are platform-agnostic |
| Directory skill loading (`loadSkillFromDir`) | Y | Y | N | Y | Y | Y | Web throws `UnsupportedError` |
| Plugin helper (`getPlatformVersion`) | Y | Y | Y | Y | Y | Y | Platform channel / browser user-agent |
| VM/CLI tooling (`adk`, dev server, deploy path) | N | N | N | N | N | N | Out of Flutter package scope |

## Install

```bash
flutter pub add flutter_adk
```

または `pubspec.yaml`:

```yaml
dependencies:
  flutter_adk: ^2026.8.17+3
```

## クイックスタート (ターンキーチャットUI)

わずか数行のコードでFlutterアプリに対話型AIエージェントチャット画面を即座に導入できます:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_adk/flutter_adk.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final agent = LlmAgent(
      name: 'assistant',
      model: 'gemini-2.5-flash',
      instruction: '親切で役立つFlutterアシスタントです。',
    );

    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('ADK Flutter Chat')),
        body: AdkChatView(
          agent: agent,
          inputPlaceholder: '質問を入力してください...',
        ),
      ),
    );
  }
}
```

## Links

- Full details: [README.md](README.md)
- Deep matrix notes: `knowledge/2026-03-01_18-20-00_flutter_adk_platform_support_matrix.md`
