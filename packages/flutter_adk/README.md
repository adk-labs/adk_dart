# flutter_adk

English | [한국어](README.ko.md) | [日本語](README.ja.md) | [中文](README.zh.md)

Flutter facade package for ADK Dart core runtime.

## What This Package Provides
- Re-exports `package:adk_dart/adk_core.dart` so Flutter apps can use the Web-safe ADK surface through `package:flutter_adk/flutter_adk.dart`.
- Exposes core runtime APIs needed for Flutter app usage:
  - `Agent` / `LlmAgent`
  - `SequentialAgent` / `ParallelAgent` / `LoopAgent`
  - `Runner` / `InMemoryRunner`
  - `FunctionTool`
  - `AgentTool`
  - `McpToolset` (remote MCP over Streamable HTTP)
  - `SkillToolset` + inline `Skill`
  - Gemini built-in retrieval tools: `UrlContextTool`, `VertexAiSearchTool`,
    `VertexRagRetrievalTool`
  - `Gemini` (BYOK-style key injection)
- Includes a Flutter plugin scaffold registered for all major Flutter platforms:
  - Android
  - iOS
  - Web
  - Linux
  - macOS
  - Windows

## When To Use `flutter_adk`

Use `flutter_adk` when:

- You are building a Flutter app and want one import that works across mobile,
  desktop, and web.
- You want the web-safe ADK runtime surface (`adk_core`) without pulling in
  VM-only APIs by default.

Use another package when:

- You are building VM/CLI agents, tools, or servers: use `adk_dart` (or `adk`
  for shorter imports).

Design intent:

- `flutter_adk` is not just a wrapper name; it is the Flutter-oriented
  compatibility layer.
- It prioritizes consistent multi-platform behavior in Flutter by exposing the
  web-safe runtime surface (`adk_core`) instead of the full VM-only API set.

## Package Links

- [flutter_adk](https://pub.dev/packages/flutter_adk): Flutter-focused package
  for web-safe ADK usage across Flutter platforms.
- [adk_dart](https://pub.dev/packages/adk_dart): Core runtime package with the
  full ADK Dart VM/CLI API surface.
- [adk](https://pub.dev/packages/adk): Short-name facade package that
  re-exports `adk_dart`.

## ADK 2.0 Compatibility

This package is fully aligned with ADK 2.0, supporting v2 Workflows (declarative node-graph scheduling, conditional routing, and state merging) and GCP Managed Agents (including `ManagedAgent` and `RemoteMcpServer` configuration mapping) for hybrid on-device and cloud execution.

## Installation

```bash
flutter pub add flutter_adk
```

Or add to your `pubspec.yaml`:

```yaml
dependencies:
  flutter_adk: ^2026.8.17+3
```

## Quick Start (Turnkey Chat UI)

Drop an interactive AI agent chat screen into your Flutter app with just a few lines of code:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_adk/flutter_adk.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // 1. Define your AI Agent (Default model is gemini-3.7-flash)
    final agent = LlmAgent(
      name: 'assistant',
      model: 'gemini-3.7-flash',
      instruction: 'You are a helpful and friendly Flutter assistant.',
    );

    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('ADK Flutter Chat')),
        // 2. Embed the turnkey chat view or use AdkDevStudioView(agent: agent)
        body: AdkChatView(
          agent: agent,
          inputPlaceholder: 'Ask anything...',
        ),
      ),
    );
  }
}
```

## Local LLM Quickstart (Ollama / LM Studio)

You can run AI agents completely offline on local models without any cloud API keys:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_adk/flutter_adk.dart';

void main() => runApp(const LocalAiApp());

class LocalAiApp extends StatelessWidget {
  const LocalAiApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Connect to local Ollama (http://localhost:11434/v1) or LM Studio (http://localhost:1234/v1)
    final localModel = LiteLlm(
      model: 'ollama_chat/gemma2:2b',
      baseUrl: 'http://localhost:11434/v1',
    );

    final agent = Agent(
      name: 'local_assistant',
      model: localModel,
      instruction: 'You are a fast, private offline AI assistant.',
    );

    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Offline Local LLM Assistant')),
        body: AdkChatView(agent: agent),
      ),
    );
  }
}
```

## Built-in UI Components & Controllers

`flutter_adk` provides 12+ ready-to-use widgets and reactive controllers:
- **`AdkDevStudioView`**: Turnkey ADK Web / Dev Studio inspector in Flutter (Tabs for Playground, Live Logger, Agent Graph, and State).
- **`AdkAgentLoggerView`**: Real-time agent I/O logger (User inputs, LLM responses, Tool calls, State deltas, Latency, Token counts).
- **`AdkChatView`**: Full-featured chat UI with autoscroll, input bar, prompt suggestions, and voice triggers.
- **`AdkChatController`**: ChangeNotifier-based state controller for managing messages and streaming turns.
- **`AdkFloatingChatButton`**: Floating Action Button (FAB) that opens an AI assistant modal bottom sheet.
- **`AdkPromptSuggestionsBar`**: Horizontal scrollable bar with quick-tap prompt chips.
- **`AdkToolCallCard`**: Expandable card displaying tool name, execution status, JSON arguments, and results.
- **`AdkConfirmationBanner` & `AdkConfirmationDialog`**: Human-in-the-loop (HITL) approval banner and modal dialog.
- **`AdkSessionDrawer`**: Chat session history sidebar with create, switch, and delete actions.
- **`AdkAgentHierarchyBadge`**: Breadcrumb badge showing active agent in a multi-agent hierarchy.
- **`AdkWorkflowProgressIndicator`**: Step-by-step workflow timeline progress tracker.
- **`AdkVoiceMicButton` & `AdkAudioWaveVisualizer`**: Interactive voice input button and animated waveform visualizer.
- **`AdkTokenUsageBadge`**: Compact badge displaying prompt and completion token counts.
- **`AdkMessageBubble`**: Material 3 message bubble for user, model, and tool outputs.
- **`AdkTypingIndicator`**: Smooth pulsing typing indicator.
- **`AdkEventStreamBuilder`**: Reactive widget builder for listening directly to `Stream<Event>`.

## Full Runtime Surface
- For VM/CLI-only APIs, import `package:adk_dart/adk_dart.dart`.

## Platform Scope (Current)
- `flutter_adk` is a Flutter-focused runtime surface built on top of `adk_core`.
- It targets single-import usage across Flutter platforms while leaving VM/CLI-only APIs outside this package.

Status legend:

- `Y` Supported
- `Partial` Supported with caveats
- `N` Not supported

| Feature | Android | iOS | Web | Linux | macOS | Windows | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `flutter_adk` single import (`package:flutter_adk/flutter_adk.dart`) | Y | Y | Y | Y | Y | Y | Re-exports the Web-safe `adk_core` surface. |
| Agent runtime (`Agent`, `Runner`, workflows) | Y | Y | Y | Y | Y | Y | In-memory orchestration path is cross-platform. |
| `Gemini` model usage | Y | Y | Partial | Y | Y | Y | Web requires BYOK/CORS/security policy consideration. |
| Built-in model tools (`UrlContextTool`, Vertex retrieval) | Y | Y | Y | Y | Y | Y | Tool execution is handled by Gemini/Vertex backends. |
| MCP Toolset via Streamable HTTP | Y | Y | Y | Y | Y | Y | Works with remote MCP HTTP servers. |
| MCP Toolset via stdio (`StdioConnectionParams`) | Partial | Partial | N | Y | Y | Y | Web cannot spawn local processes; mobile runtime support can depend on sandbox/process policy. |
| Skills (`Skill`, `SkillToolset`) with inline definitions | Y | Y | Y | Y | Y | Y | Inline skills are platform-agnostic. |
| Directory-based skill loading (`loadSkillFromDir`) | Y | Y | N | Y | Y | Y | Web throws `UnsupportedError` for filesystem-based loading. |
| Plugin channel helper (`FlutterAdk().getPlatformVersion()`) | Y | Y | Y | Y | Y | Y | Uses platform channel / browser user-agent path. |
| VM/CLI tooling (`adk` executable, dev server, CLI deploy path) | N | N | N | N | N | N | Not part of the Flutter package surface. |

Reference matrix and rollout notes:
- `knowledge/2026-03-01_18-20-00_flutter_adk_platform_support_matrix.md`

## Limitations
- Features requiring `dart:io`, `dart:ffi`, or `dart:mirrors` are outside the current `flutter_adk` surface.
- MCP stdio transport (`StdioConnectionParams`) is not supported on Web.
- Directory-based skill loading (`loadSkillFromDir`) is not supported on Web. Use inline `Skill` definitions.
- For browser BYOK (user-entered API key), document security risks before production rollout.
