# Agent Development Kit (ADK) for Dart

[English](README.md) | [한국어](README.ko.md) | 日本語 | [中文](README.zh.md)

[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)
[![pub package](https://img.shields.io/pub/v/adk_dart.svg)](https://pub.dev/packages/adk_dart)
[![Package Sync](https://github.com/adk-labs/adk_dart/actions/workflows/package-sync.yml/badge.svg)](https://github.com/adk-labs/adk_dart/actions/workflows/package-sync.yml)

ADK Dartは、モジュール型ランタイムプリミティブ、ツールオーケストレーション、MCP（Model Context Protocol）連携を備えた、AIエージェント構築・実行のためのオープンソースかつコードファースト（Code-First）なDartフレームワークです。

実用的なランタイム互換性と開発者エクスペリエンス（Ergonomics）に焦点を当てたADKアーキテクチャのDartポートです。

---

## 最新アップデート

- **ADK 2.0 ワークフローおよび Managed Agent サポート**: コアなADK 2.0機能をネイティブサポート:
  - **v2 ワークフロー**: `Workflow`, `BaseNode`, `JoinNode`等による宣言型ノードグラフスケジューリング、依存関係管理、条件分岐ルーティング、状態マージ。
  - **Managed Agents**: `ManagedAgent`および`RemoteMcpServer`設定を介したGCP Managed Agents Interactions APIとの直接連携。
- **MCP プロトコルコアパッケージ分離**: `packages/adk_mcp`を追加し、Streamable HTTP MCPトランスポートを独立パッケージとして提供。
- **MCP 仕様強化**: セッション復元、リクエストIDに基づくSSE応答マッチング、キャンセル通知、機能（Capability）認識RPCによる安定性向上。
- **互換性拡張**: セッション、ツールセット、モデル/ツール統合レイヤー全体にわたる広範なランタイム互換性を確保。

## 主な機能

- **コードファーストなエージェントランタイム**: `BaseAgent`, `LlmAgent`（`Agent`エイリアス）および明示的なコンテキストオブジェクトによる構築。
- **イベント駆動型実行**: `Runner` / `InMemoryRunner`による非同期実行と`Event`ストリーミング出力。
- **マルチエージェント構成**: `subAgents`による階層的エージェント連携とワークフローオーケストレーション。
- **豊富なツールエコシステム**: Functionツール、OpenAPIツール、Google APIツールセット、データツール（BigQuery/Bigtable/Spanner）、MCPツールセットを標準搭載。
- **MCP 統合**: `adk_mcp`を基盤とする`McpToolset`および`McpSessionManager`によりStreamable HTTPでリモートMCPサーバーと連携。
- **開発者 CLI + Web UI**: `adk` CLI（`create`, `run`, `web`, `api_server`）によるプロジェクト作成、対話型実行、Web UI機能。

## ADK Python 互換性ステータス

ADK Dartは、Dartのネイティブ型、非同期ストリーム、パッケージ構造、プラットフォーム制約を尊重しながら、`adk-python`と同様に動作するように設計されています。現在のリリースベースラインは`adk-python` `2.7.0`に準拠しています。

ステータス凡例:

- `✅` 実装済みかつ互換性/ランタイムテスト通過。
- `⚠️` プラットフォーム、認証情報、環境制約付きで実装済み。
- `🚧` 計画中 / 未実装。

| `adk-python` 領域 | Dart ステータス | Dart 実装サーフェス | 備考 |
| --- | --- | --- | --- |
| パッケージ/バージョン基準 | ✅ | `adkVersion`, パッケージバージョン | `adk_dart`, `adk`, `adk_mcp`, `flutter_adk` 最新アライメント完了; ADK基準は `2.7.0`。 |
| エージェントおよびランナー | ✅ | `BaseAgent`, `LlmAgent`/`Agent`, `SequentialAgent`, `ParallelAgent`, `LoopAgent`, `Runner`, `InMemoryRunner` | 呼び出し、フォールバック、巻き戻し（Rewind）、セッション状態、コールバック、Agent Transfer実装完了。 |
| LLM フロープロセッサ | ✅ | `flows/llm_flows` 配下の要求/応答プロセッサ | 指示、ID、コンテンツ、コンパクション、コンテキストキャッシュ、コード実行、出力スキーマ、ツール確認（HITL）、エージェント移行。 |
| ワークフローランタイム | ✅ | `Workflow`, `BaseNode`, 関数/ツール/LLMノード, `NodeTool`, ジョイン, ルーティング, 動的ノード, リプレイ | リトライ、タイムアウト、入力要求/HITL、並列ワーカー、リプレイ/再水和、グラフシリアライズ、DOT可視化。 |
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
| Flutter/Web-Safe API | ⚠️ | `adk_core`, `flutter_adk`, Flutter サンプルアプリ | Web-safe APIを公開、VM専用API（`dart:io`等）は安全に除外。 |

## どのパッケージを使うべきか？

| 開発環境 | 推奨パッケージ | 理由 |
| --- | --- | --- |
| Dart VM/CLI環境（サーバー、ツール、テスト、フルAPI） | `adk_dart` | フルランタイムサーフェスを提供するプライマリパッケージ |
| Dart VM/CLI環境で短いimportパスを好む場合 | `adk` | `adk_dart`を再エクスポートするファサードパッケージ（`package:adk/adk.dart`） |
| Flutterアプリ開発（Android/iOS/Web/Linux/macOS/Windows） | `flutter_adk` | `adk_core`ベースのWeb-safeサーフェスを単一importで提供 |

## インストール

### 最新安定版（推奨）

```bash
dart pub add adk_dart
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

## Gemini API キー設定

ADK Dartでは以下の環境変数を推奨します:

- `GOOGLE_API_KEY`（推奨）
- `GEMINI_API_KEY`（互換用エイリアス）

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

## Model Context Protocol (MCP)

ADK Dartは最新のMCP仕様を完全にサポートしており、プロトコルプリミティブを専用パッケージとして提供しています:

- `packages/adk_mcp`: Dart用MCPトランスポート/ライフサイクルコア
- `adk_dart` MCP層: ADKツール/ランタイム統合（`McpToolset`, `McpSessionManager`等）

## コード例

### 1. 単一エージェントの定義と実行

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

### 2. 開発 CLI および Web UI の実行

```bash
dart pub global activate adk_dart
adk create my_agent
cd my_agent
adk run .
adk web --port 8000 .
```

`adk web`コマンドにより、`http://127.0.0.1:8000`でローカル開発サーバーおよびWeb UIが起動します。

## テスト

```bash
dart test
dart analyze
```

## ライセンス

Apache 2.0 ライセンス（[LICENSE](LICENSE)）。
