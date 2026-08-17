# Agent Development Kit (ADK) for Dart

[English](README.md) | [한국어](README.ko.md) | 日本語 | [中文](README.zh.md)

[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)
[![pub package](https://img.shields.io/pub/v/adk_dart.svg)](https://pub.dev/packages/adk_dart)
[![Package Sync](https://github.com/adk-labs/adk_dart/actions/workflows/package-sync.yml/badge.svg)](https://github.com/adk-labs/adk_dart/actions/workflows/package-sync.yml)

ADK Dartは、モジュール型ランタイムプリミティブ、ツールオーケストレーション、MCP（Model Context Protocol）連携を備えた、自律型AIエージェント構築および実行のためのオープンソースかつコードファースト（Code-First）なDartエンジニアリングフレームワークです。

実用的なランタイム互換性、非同期パイプラインの完全性、および優れた開発者体験（DX）と直感的な使いやすさに焦点を当てたGoogle ADKアーキテクチャのDartネイティブポートです。

---

## 最新アップデート

- **ADK 2.0 ワークフローおよび Managed Agent サポート**: コアなADK 2.0アーキテクチャを完全サポート:
  - **v2 ワークフロー**: `Workflow`, `BaseNode`, `JoinNode`等による宣言型DAGノードグラフスケジューリング、依存関係管理、条件分岐ルーティング、状態マージ。
  - **Managed Agents**: `ManagedAgent`および`RemoteMcpServer`設定を介したGCP Vertex AI Managed Agents Interactions APIとの直接RPC連携。
- **MCP プロトコルコアパッケージ分離**: `packages/adk_mcp`を追加し、Streamable HTTP MCPトランスポート層を独立パッケージとしてモジュール化。
- **MCP 仕様強化**: セッション復元、リクエストIDに基づくSSE応答マッチング、キャンセ�## ADK Python 互換性ステータス

ADK Dartは、Dartの静的型システム、非同期ストリーム（`Stream<Event>`）、パッケージ構造、プラットフォーム制約を尊重しながら、`adk-python`と同様に動作するように設計されています。現在のリリースベースラインは`adk-python` `2.2.0`に準拠しています。

ステータス凡例:

- `✅` 実装済みかつ互換性/ランタイムテスト通過。
- `⚠️` プラットフォーム、認証情報、環境制約付きで実装済み。
- `🚧` 計画中 / 未実装。

| `adk-python` 領域 | Dart ステータス | Dart 実装 API およびインターフェース | 備考 |
| --- | --- | --- | --- |
| パッケージ/バージョン基準 | ✅ | `adkVersion`, パッケージバージョン | `adk_dart`, `adk`, `adk_mcp`, `flutter_adk`, `adk_litertlm` 最新アライメント完了; ADK基準は `2.2.0`。 |
| エージェントおよびランナー | ✅ | `BaseAgent`, `LlmAgent`/`Agent`, `SequentialAgent`, `ParallelAgent`, `LoopAgent`, `Runner`, `InMemoryRunner` | 呼び出し、フォールバック、セッションロールバック/リワインド（Rewind）、セッション状態、コールバック、Agent Transfer実装完了。 |
| LLM フロープロセッサ | ✅ | `flows/llm_flows` 配下の要求/応答プロセッサ | 指示、ID、コンテンツ、トークンコンパクション、コンテキストキャッシュ、コード実行、出力スキーマ、ツール確認（HITL）、エージェント移行。 |
| ワークフローランタイム | ✅ | `Workflow`, `BaseNode`, 関数/ツール/LLMノード, `NodeTool`, ジョイン, ルーティング, 動的ノード, リプレイ | リトライ、タイムアウト、入力要求/HITL、並列ワーカー、ワークフローリプレイおよび状態復元 (State Restoration)、グラフシリアライズ、DOT可視化。 |
| イベントおよびコンテンツ変換 | ✅ | `Event`, `EventActions`, コンテンツ/パートモデル, ノードパスヘルパー | 構造化イベントアクション、ノードパス構築、関数/ツール応答変換、A2Aメタデータ保持。 |
| セッションおよび状態 | ✅ | In-Memory, SQLite, Database, Vertex AI セッションサービス, 移行ヘルパー | ローカルおよびリモートセッションAPI実装完了。 |
| メモリおよびアーティファクト | ✅ | In-Memoryメモリ, Vertex AI メモリ/RAG, In-Memory/ファイル/GCSアーティファクト | GCS/Vertexパスは環境設定およびクレデンシャルに依存。 |
| ツールおよびツールセット | ✅ | 関数ツール, エージェントツール, OpenAPIツール, Google APIツール, 検索/RAGツール, データツール | Google検索、URL Context、コード実行、Computer Use、Google Maps、Vertex AI Search、Vertex RAG対応。 |
| MCP 統合 | ⚠️ | `adk_mcp`, `McpToolset`, `McpSessionManager`, `StreamableHTTPConnectionParams`, `StdioConnectionParams` | Streamable HTTPはVM/Flutter/Webで動作。Stdioはプロセス実行が必要なためVM専用。 |
| モデル/プロバイダ | ✅ | Gemini REST/Live SSE, Anthropic Claude (`AnthropicLlm`), LiteLLM/OpenAI (`LiteLlm` - GPT-4o, o3-mini, Ollama, DeepSeek, Groq), Gemma, Apigee, Chat Completions, `LLMRegistry` | 全プロバイダでSSEリアルタイムトークンストリーミングおよび動的モデルルーティングを提供。 |
| 認証およびクレデンシャル | ✅ | 認証スキーム, クレデンシャルマネージャ, OAuth2交換/更新, サービスアカウントフック | ツール認証、OAuthディスカバリ、トークン交換/更新、セッション状態でのクレデンシャル保存対応。 |
| 評価およびシミュレーション | ✅ | 評価マネージャ/サービス, メトリクス評価器, LLM-as-a-judge, ユーザーシミュレータ | 軌跡/最終応答/ルーブリック/安全性メトリクス、シミュレータ生成を実装。 |
| プラグインおよびテレメトリ | ✅ | プラグインマネージャ, デバッグ/グローバル/リフレクション/アーティファクト保存, OpenTelemetry/SQLite | SQLiteトレース永続化、メトリクス計測、自動トレース、プラグインライフサイクルフック。 |
| CLI, 開発サーバー, デプロイ | ✅ | `adk create/run/web/api_server/deploy/eval/eval_set/conformance/migrate` | Dart CLI環境向けに移植完了。 |
| A2A プロトコル | ✅ | A2Aコンバータ, エグゼキュータ, エージェントカード, JSON-RPC/RESTタスクルート, リモートA2Aエージェント | ストリーミング、タスク再開/キャンセル/再購読、プッシュ通知設定、SQLite永続プッシュキュー。 |
| コード実行 | ⚠️ | ローカルプロセス, コンテナ/Docker, GKE, Vertex AI, Cloud Runサンドボックス | 実行ロジック実装済み。実環境のDocker/K8s/Vertex/Cloud Runに依存。 |
| データ/クラウド統合 | ⚠️ | BigQuery, Bigtable, Spanner, Pub/Sub, Secret Manager, Agent Registry, Slack, Toolbox | ランタイムクライアントおよびファサード実装済み。 |
| スキル (Skills) | ✅ | `Skill`, `SkillToolset`, インメモリ/GCSスキルソース, スキルプロンプト整形 | インラインおよびディレクトリ読み込み対応（ファイルシステムはFlutter Web未対応）。 |
| Flutter/Web-Safe API & UI Kit | ✅ | `adk_core`, `flutter_adk`, 20+ Turnkey M3 ウィジェット, 6種のリアクティブコントローラ, `AdkTheme`, WASM対応 | Flutter Web/WASM コンパイル検証済み (`flutter build web --wasm`)。`AdkChatView`, `AdkDevStudioView`, `AdkAgentManagementView`, 6種のコントローラ, SSEストリーミングを標準提供。 |
| OpenAPI 外部参照 | 🚧 | OpenAPI パーサー/ツールセット | インライン/ローカル仕様対応済み。外部マルチファイル `$ref` 解決は対応予定。 |
| Spanner PostgreSQL ANN | 🚧 | Spanner ベクトルツール | Spanner/Vectorコアパス対応済み。PostgreSQL ANN 動作は今後対応予定。 |
| 音声テキスト変換ランタイム | ⚠️ | オーディオ音声認識(STT) ランタイム | 音声認識(STT) オーケストレーション提供。認識器のインスタンス登録が必要。 |
| Python サンプルツリー網羅 | 🚧 | サンプルコード, `flutter_adk/example`, ドキュメント | 代表的なDart/Flutterサンプルを提供。Python全サンプルツリーは順次拡充中。 |

## どのパッケージを使うべきか？

| 開発環境 | 推奨パッケージ | 理由 |
| --- | --- | --- |
| Dart VM/CLI環境（サーバー、ツール、テスト、フルAPI） | [`adk_dart`](https://pub.dev/packages/adk_dart) | フルランタイムAPIインターフェースを提供するプライマリパッケージ |
| Dart VM/CLI環境で短いimportパスを好む場合 | [`adk`](https://pub.dev/packages/adk) | `adk_dart`を再エクスポートするファサードパッケージ（`package:adk/adk.dart`） |
| Flutterアプリ開発（Android/iOS/Web/WASM/Linux/macOS/Windows） | [`flutter_adk`](https://pub.dev/packages/flutter_adk) | 20+ ウィジェット、6種コントローラ、`AdkTheme`、WASM/SSE完全対応のUI Kit |
| MCP(Model Context Protocol) クライアント/サーバー統合 | [`adk_mcp`](https://pub.dev/packages/adk_mcp) | 独立型標準MCPプロトコルトランスポートパッケージ |
| オンデバイスエッジAI (Gemini Nano / LiteRT) | [`adk_litertlm`](https://pub.dev/packages/adk_litertlm) | オンデバイスLLMアクセラレータ統合パッケージ |パッケージ | 理由 |
| --- | --- | --- |
| Dart VM/CLI環境（サーバー、ツール、テスト、フルAPI） | [`adk_dart`](https://pub.dev/packages/adk_dart) | フルランタイムAPIインターフェースを提供するプライマリパッケージ |
| Dart VM/CLI環境で短いimportパスを好む場合 | [`adk`](https://pub.dev/packages/adk) | `adk_dart`を再エクスポートするファサードパッケージ（`package:adk/adk.dart`） |
| Flutterアプリ開発（Android/iOS/Web/WASM/Linux/macOS/Windows） | [`flutter_adk`](https://pub.dev/packages/flutter_adk) | 20+ ウィジェット、6種コントローラ、`AdkTheme`、WASM/SSE完全対応のUI Kit | (State Restoration)、グラフシリアライズ、DOT可視化。 |
| イベントおよびコンテンツ変換 | ✅ | `Event`, `EventActions`, コンテンツ/パートモデル, ノードパスヘルパー | 構造化イベントアクション、ノードパス構築、関数/ツール応答変換、A2Aメタデータ保持。 |
| セッションおよび状態 | ✅ | In-Memory, SQLite, Database, Vertex AI セッションサービス, 移行ヘルパー | ローカルおよびリモートセッションAPI実装完了。 |
| メモリおよびアーティファクト | ✅ | In-Memoryメモリ, Vertex AI メモリ/RAG, In-Memory/ファイル/GCSアーティファクト | GCS/Vertexパスは環境設定およびクレデンシャルに依存。 |
| ツールおよびツールセット | ✅ | 関数ツール, エージェントツール, OpenAPIツール, Google APIツール, 検索/RAGツール, データツール | Google検索、URL Context、コード実行、Computer Use、Google Maps、Vertex AI Search、Vertex RAG対応。 |
| MCP 統合 | ⚠️ | `adk_mcp`, `McpToolset`, `McpSessionManager`, `StreamableHTTPConnectionParams`, `StdioConnectionParams` | Streamable HTTPはVM/Flutter/Webで動作。Stdioはプロセス実行が必要なためVM専用。 |
| モデル/プロバイダ | ✅ | Gemini REST/Live, Anthropic, LiteLLM, Gemma, Apigee, Chat Completions, OpenAI labs | プラガブルなトランスポートで移植完了。APIキー設定が必要。 |
| 認証およびクレデンシャル | ✅ | 認証スキーム, クレデンシャルマネージャ, OAuth2交換/更新, サービスアカウントフック | ツール認証、OAuthディスカバリ、トークン交換/更新、セッション状態でのクレデンシャル保存対応。 |
| 評価およびシミュレーション | ✅ | 評価マネージャ/サービス, メトリクス評価器, LLM-as-a-judge, ユーザーシミュレータ | 軌跡/最終応答/ルーブリック/安全性メトリクス、シミュレータ生成を実装。 |
| プラグインおよびテレメトリ | ✅ | プラグインマネージャ, デバッグ/グローバル/リフレクション/アーティファクト保存, OpenTelemetry/SQLite | SQLiteトレース永続化、メトリクス計測、自動トレース、プラグインライフサイクルフック。 |
| CLI, 開発サーバー, デプロイ | ✅ | `adk create/run/web/api_server/deploy/eval/eval_set/conformance/migrate` | Dart CLI環境向けに移植完了。 |
| A2A プロトコル | ✅ | A2Aコンバータ, エグゼキュータ, エージェントカード, JSON-RPC/RESTタスクルート, リモートA2Aエージェント | ストリーミング、タスク再開/キャンセル/再購読、プッシュ通知設定、SQLite永続プッシュキュー。 |
| コード実行 | ⚠️ | ローカルプロセス, コンテナ/Docker, GKE, Vertex AI, Cloud Runサンドボックス | 実行ロジック実装済み。実環境のDocker/K8s/Vertex/Cloud Runに依存。 |
| データ/クラウド統合 | ⚠️ | BigQuery, Bigtable, Spanner, Pub/Sub, Secret Manager, Agent Registry, Slack, Toolbox | ランタイムクライアントおよびファサード実装済み。 |
| スキル (Skills) | ✅ | `Skill`, `SkillToolset`, インメモリ/GCSスキルソース, スキルプロンプト整形 | インラインおよびディレクトリ読み込み対応（ファイルシステムはFlutter Web未対応）。 |
| Flutter/Web-Safe API | ⚠️ | `adk_core`, `flutter_adk`, Flutter サンプルアプリ | Web-safe APIインターフェースを公開、VM専用API（`dart:io`等）は安全に分離。 |

## どのパッケージを使うべきか？

| 開発環境 | 推奨パッケージ | 理由 |
| --- | --- | --- |
| Dart VM/CLI環境（サーバー、ツール、テスト、フルAPI） | `adk_dart` | フルランタイムAPIインターフェースを提供するプライマリパッケージ |
| Dart VM/CLI環境で短いimportパスを好む場合 | `adk` | `adk_dart`を再エクスポートするファサードパッケージ（`package:adk/adk.dart`） |
| Flutterアプリ開発（Android/iOS/Web/Linux/macOS/Windows） | `flutter_adk` | `adk_core`ベースのWeb-safe APIインターフェースを単一importで提供 |

## プラットフォームサポートマトリクス

| 機能 / サーフェス | Dart VM / CLI | Flutter (Android/iOS/Linux/macOS/Windows) | Flutter Web | 備考 |
| --- | --- | --- | --- | --- |
| `package:adk_dart/adk_dart.dart` フルAPI | Y | Partial | N | `dart:io`, `dart:ffi`, `dart:mirrors` 等のVM専用パスを含むためWeb直接利用不可。 |
| `package:adk_dart/adk_core.dart` Web-safe API | Y | Y | Y | `adk_core` はIO/FFI依存を安全に除外。 |
| エージェントランタイム (`Agent`, `Runner`, Workflows) | Y | Y | Y | インメモリオーケストレーションは完全なクロスプラットフォーム。 |
| MCP over Streamable HTTP (`StreamableHTTPConnectionParams`) | Y | Y | Y | HTTPアクセス可能な環境で動作（WebはCORS設定が必要な場合あり）。 |
| MCP over stdio (`StdioConnectionParams`) | Y | Partial | N | `dart:io` `Process` によるローカルプロセス実行が必要。 |
| インラインスキル (`Skill` + `SkillToolset`) | Y | Y | Y | インラインスキル定義はWeb-safe。 |
| ディレクトリベーススキル読み込み (`loadSkillFromDir`) | Y | Partial | N | ファイルシステムAPIを使用（Webでは `UnsupportedError`）。 |
| CLI (`adk create/run/web/api_server/deploy`) | Y | N | N | CLIはVM/ターミナル専用。 |
| 開発Webサーバー + A2Aサービスエンドポイント | Y | N | N | サーバーホスティングはVM専用。 |
| DB/ファイルベースサービス (SQLite/Postgres/MySQL, ファイルアーティファクト) | Y | Partial | N | IO/ネットワークプリミティブに依存。 |

## インストール

### 最新安定版（推奨）

```bash
dart pub add adk_dart
```

または `pubspec.yaml`:

```yaml
dependencies:
  adk_dart: ^2026.8.17+1
  # または統合CLIファサードパッケージ:
  # adk: ^2026.8.17+1
```

短いimportパッケージ（`adk`）を使用する場合:

```bash
dart pub add adk
```

### 開発版（Git参照）

```yaml
dependencies:
  adk_dart:
    git:
      url: https://github.com/adk-labs/adk_dart.git
      ref: main
```

```bash
dart pub get
```

## Gemini API 環境変数の設定

ADK Dartは以下の環境変数名を推奨します:

- `GOOGLE_API_KEY`（推奨）

互換性のため `GEMINI_API_KEY` エイリアスもサポートしています。

### オプション A: Gemini API モード（デフォルト）

```env
GOOGLE_GENAI_USE_VERTEXAI=0
GOOGLE_API_KEY=your_google_api_key
```

### オプション B: Vertex AI モード

```env
GOOGLE_GENAI_USE_VERTEXAI=1
GOOGLE_CLOUD_PROJECT=your-gcp-project-id
GOOGLE_CLOUD_LOCATION=us-central1
GOOGLE_API_KEY=your_google_api_key
```

## MCP (Model Context Protocol)

ADK DartはMCPサポートを標準内蔵し、プロトコルプリミティブを専用パッケージとして提供します:

- `packages/adk_mcp`: Dart用MCPトランスポート/ライフサイクルコア
- `adk_dart` MCP層: ADKツール/ランタイム統合 (`McpToolset`, `McpSessionManager`, `LoadMcpResourceTool`, `McpInstructionProvider`)

## 機能ハイライトコード例

### 単一エージェントの定義

```dart
import 'package:adk_dart/adk_dart.dart';

class EchoModel extends BaseLlm {
  EchoModel() : super(model: 'echo');

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    final String userText = request.contents.isEmpty
        ? ''
        : request.contents.last.parts
              .where((Part part) => part.text != null)
              .map((Part part) => part.text!)
              .join(' ');

    yield LlmResponse(content: Content.modelText('echo: $userText'));
  }
}

Future<void> main() async {
  final Agent agent = Agent(name: 'echo_agent', model: EchoModel());
  final InMemoryRunner runner = InMemoryRunner(agent: agent);

  final Session session = await runner.sessionService.createSession(
    appName: runner.appName,
    userId: 'user_1',
    sessionId: 'session_1',
  );

  await for (final Event event in runner.runAsync(
    userId: 'user_1',
    sessionId: session.id,
    newMessage: Content.userText('hello'),
  )) {
    print(event.content?.parts.first.text ?? '');
  }
}
```

### マルチエージェントシステムの構成

```dart
import 'package:adk_dart/adk_dart.dart';

class StubModel extends BaseLlm {
  StubModel() : super(model: 'stub');

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    yield LlmResponse(content: Content.modelText('done'));
  }
}

void main() {
  final Agent greeter = Agent(
    name: 'greeter',
    model: StubModel(),
    instruction: 'Handle greetings.',
  );

  final Agent worker = Agent(
    name: 'worker',
    model: StubModel(),
    instruction: 'Handle execution tasks.',
  );

  final Agent coordinator = Agent(
    name: 'coordinator',
    model: StubModel(),
    instruction: 'Route requests to sub-agents.',
    subAgents: <BaseAgent>[greeter, worker],
  );

  print('Coordinator configured: ${coordinator.name}');
}
```

### 開発用 CLI および Web UI

```bash
dart pub global activate adk_dart
adk create my_agent
cd my_agent
adk run .
adk web --port 8000 .
```

`adk web` コマンドは `http://127.0.0.1:8000` でローカル開発サーバーと対話型デバッグUIを起動します。

## テスト

```bash
dart test
dart analyze
```

## ライセンス

本プロジェクトは Apache 2.0 ライセンスの下で配布されています。詳細は [LICENSE](LICENSE) ファイルをご参照ください。


## プラットフォーム機能、制限および環境要件 (Platform Matrix & Limitations)

| 機能領域 | Dart VM (Server/CLI/Desktop) | Flutter Mobile (iOS/Android) | Flutter Web / WASM | 制限事項および環境要件 |
| :--- | :---: | :---: | :---: | :--- |
| **マルチエージェント & ワークフロー 2.0** | ✅ 完全対応 | ✅ 完全対応 | ✅ 完全対応 | DAGグラフ、順次/並列/ループエージェント、HITL一時停止の全環境動作。 |
| **Multi-LLM & SSE リアルタイムストリーミング** | ✅ 完全対応 | ✅ 完全対応 | ✅ 完全対応 | Gemini, Claude, OpenAI, Ollama, Groq トークン単位リアルタイムストリーミング。 |
| **OpenAPI 仕様 & 外部 `$ref` 解決** | ✅ 完全対応 | ✅ 完全対応 | ✅ 完全対応 | インライン、相対パス、リモートHTTP/HTTPS `$ref` スキーマ解決と循環参照防止。 |
| **Gemini 内蔵コード実行 (`BuiltIn`)** | ✅ 完全対応 | ✅ 完全対応 | ✅ 完全対応 | Google クラウドサンドボックスで実行。ローカルインフラ不要。 |
| **ローカルコード実行 (`UnsafeLocal`)** | ✅ 完全対応 | ⚠️ 権限制限 | ❌ ブラウザ制限 | Dart, Python, Node, Shell サブプロセス実行。ブラウザのプロセス生成制限に準拠。 |
| **コンテナ / K8s / Cloud Run サンドボックス** | ⚠️ インフラ要 | ⚠️ インフラ要 | ⚠️ インフラ要 | ホストの Docker デーモン、Kubernetes クラスタ、GCP 認証/IAM 権限が必要。 |
| **MCP 連携 (Streamable HTTP)** | ✅ 完全対応 | ✅ 完全対応 | ✅ 完全対応 | 標準 HTTP/SSE ベース JSON-RPC 通信 (Web はサーバーの CORS 許可が必要)。 |
| **MCP 連携 (Stdio パイプ)** | ✅ 完全対応 | ❌ プロセス制限 | ❌ サンドボックス制限 | `dart:io` `Process` パイプ通信 (Dart VM / Desktop / Server 専用)。 |
| **GCP データ連携 (Spanner/BQ 等)** | ⚠️ 認証要 | ⚠️ 認証要 | ⚠️ 認証要 | クライアント SDK 実装完了。呼出時にサービスアカウント JSON または ADC が必要。 |
| **音声会話 (STT / TTS)** | 🔌 デリゲート | 🔌 デリゲート | 🔌 デリゲート | 状態制御と波形 UI 完備。端末固有 STT (`speech_to_text`, Web Speech API) を注入。 |
