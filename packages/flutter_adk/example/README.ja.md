# flutter_adk_example

[English](README.md) | [한국어](README.ko.md) | 日本語 | [中文](README.zh.md)

`flutter_adk` のサンプルアプリです。

## 多言語 UI 対応

- 対応言語: English, 한국어, 日本語, 中文
- 上部の `Translate (🌐)` アイコンで即時切り替え
- 選択言語はローカルストレージに保存

## 含まれるサンプル

- `Basic Chatbot`: 単一 `Agent + FunctionTool`
- `Transfer Multi-Agent`: Coordinator/Dispatcher パターン
- `Workflow Combo`: `SequentialAgent + ParallelAgent + LoopAgent`
- `Sequential` / `Parallel` / `Loop`
- `Agent Team`
- `MCP Toolset` (remote HTTP)
- `Skills` (inline `Skill + SkillToolset`)

## Platform Support Matrix (Current)

Status legend:

- `✅` Supported
- `⚠️` Partial / caveat
- `❌` Not supported

| Feature | Android | iOS | Web | Linux | macOS | Windows | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Example app UI/routing/chat screen | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | Flutter shared UI layer |
| Basic/Transfer/Workflow/Team execution | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | In-memory runtime via `flutter_adk` `adk_core` |
| MCP Toolset (Streamable HTTP) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | Web may require server CORS setup |
| Skills (inline) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | No filesystem requirement |
| Settings persistence (`shared_preferences`) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | Web uses browser storage |
| Local-process MCP stdio example | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | Remote HTTP MCP only |
| Directory skill loading demo | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | Inline skills only |

## 実行

```bash
flutter pub get
flutter run
```

Web build:

```bash
flutter build web
```

## 使い方

1. 右上設定で Gemini API キーを入力・保存
2. MCP サンプル使用時は MCP Streamable HTTP URL（任意で Bearer Token）を入力
3. 上部のチップからサンプルを選択
4. メッセージ送信で動作確認

## 注意

- ブラウザ保存の API キーは露出リスクあり。プロダクションではサーバープロキシ推奨
- ローカル開発で最新ルートソースを参照するため `pubspec_overrides.yaml` を同梱
