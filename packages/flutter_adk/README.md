# flutter_adk

English | [한국어](README.ko.md) | [日本語](README.ja.md) | [中文](README.zh.md)

Flutter facade package and turnkey UI Kit for the ADK Dart core runtime.

[![pub package](https://img.shields.io/pub/v/flutter_adk.svg)](https://pub.dev/packages/flutter_adk)
[![WASM Ready](https://img.shields.io/badge/Flutter%20Web-WASM%20100%25-brightgreen.svg)](https://flutter.dev/to/wasm)

## What This Package Provides
- **Single Import Facade**: Re-exports `package:adk_dart/adk_core.dart` with Web-safe APIs for seamless use across iOS, Android, macOS, Windows, Linux, and **Flutter Web (WASM / dart2wasm)**.
- **Turnkey UI Kit**: Complete suite of AI chat, developer studio, logger, tool inspectors, workflow progress bars, and voice interaction widgets.
- **Pluggable Persistence**: 2-line storage adapters (`AdkStorageSessionService`) for `SharedPreferences`, `FlutterSecureStorage`, SQLite, and Hive.
- **Core Runtime**:
  - `Agent` / `LlmAgent` (Default: `gemini-3.7-flash`, local `LiteLlm` Ollama/LM Studio)
  - Workflows: `SequentialAgent`, `ParallelAgent`, `LoopAgent`, `ManagedAgent`
  - Tools: `FunctionTool`, `AgentTool`, `McpToolset` (Streamable HTTP), `SkillToolset`
  - Retrieval: `UrlContextTool`, `VertexAiSearchTool`, `VertexRagRetrievalTool`

---

## Installation

```bash
flutter pub add flutter_adk
```

Or add to your `pubspec.yaml`:

```yaml
dependencies:
  flutter_adk: ^2026.8.17+7
```

---

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

---

## Local LLM Quickstart (Ollama / LM Studio)

Run AI agents completely offline on local models without cloud API keys:

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

---

# 📚 Widget & API Specification

### 1. Turnkey Views & Developer Tools

| Widget | Description | Key Parameters |
|---|---|---|
| **`AdkChatView`** | Full-featured chat UI with autoscroll, input box, suggestions bar, and tool cards. | `agent`, `controller`, `suggestions`, `showVoiceButton`, `customBubbleBuilder`, `inputPlaceholder` |
| **`AdkDevStudioView`** | Embedded ADK Web developer studio with Playground, Live Logger, Agent Graph, and Session State tabs. | `agent`, `controller`, `initialTab`, `showLogs` |
| **`AdkAgentLoggerView`** | Real-time I/O & telemetry inspector for prompts, model completions, tool calls, latencies, and token counts. | `logs`, `onClearLogs`, `showHeader`, `title` |
| **`AdkToolInspectorView`** | Visual registry inspector detailing all available tools and their JSON parameter schemas. | `tools`, `title`, `showHeader` |
| **`AdkStructuredDataView`** | Pretty-printer and syntax-styled viewer for JSON objects and `outputSchema` structured outputs. | `data`, `title`, `allowCopy`, `initialExpanded` |

---

### 2. State Controller & Storage Services

#### `AdkChatController`
ChangeNotifier-based controller managing conversation history, streaming responses, tool executions, and storage synchronization.

#### `AdkWorkflowController`
Reactive controller for executing, pausing (HITL approval), resuming, and tracking step progress in multi-agent workflows and pipelines.

```dart
final wfCtrl = AdkWorkflowController(workflowAgent: mySequentialPipeline, initialSteps: steps);
await wfCtrl.execute();
wfCtrl.approveAndResume(stepId: 'step_2', input: {'approved': true});
```

#### `AdkVoiceController`
Reactive controller for managing real-time microphone recording, audio levels (decibels), speech transcripts, and speaking states.

```dart
final voiceCtrl = AdkVoiceController();
await voiceCtrl.startListening();
voiceCtrl.toggleMute();
await voiceCtrl.stopListening();
```

#### `AdkSessionController`
Dedicated multi-session controller for loading, creating, switching, renaming, deleting, and searching chat sessions with Key-Value storage sync.

```dart
final sessionCtrl = AdkSessionController(storage: storage);
await sessionCtrl.loadAllSessions();
await sessionCtrl.createNewSession(title: 'New Chat');
sessionCtrl.switchSession('session_123');
```

#### `AdkSmartFormController`
Reactive controller for conversational form filling, field auto-extraction from tool arguments, required field validation, and submission.

```dart
final formCtrl = AdkSmartFormController(initialFields: fields, onSubmitted: (data) => ...);
formCtrl.populateFromMap({'user_name': 'Alice', 'date': '2026-08-20'});
await formCtrl.submit();
```

#### `AdkAgentLoggerController`
Telemetry and I/O logging controller for buffering agent events, filtering by category/search, and exporting logs to formatted JSON.

```dart
final loggerCtrl = AdkAgentLoggerController(maxLogEntries: 500);
loggerCtrl.setCategory(AdkLogCategory.toolCall);
final String jsonLogs = loggerCtrl.exportJson();
```

#### `AdkAgentManagerController` (Central Agent Fleet Manager)
Central registry controller for registering, toggling (ON/OFF), hot-swapping prompts, and tracking cumulative token and latency telemetry across all agents.

```dart
final managerCtrl = AdkAgentManagerController();
managerCtrl.registerAgent(researchAgent, id: 'researcher', tags: ['research', 'web']);
managerCtrl.toggleAgent('researcher', true);
print('Avg Latency: ${managerCtrl.getAgent("researcher")?.metrics.avgLatencyMs}');
```

#### `AdkStorageSessionService`
Plug-and-play session persistence backed by any key-value store (e.g. `shared_preferences`, `flutter_secure_storage`).

```dart
// 2-line SharedPreferences integration:
final sessionService = AdkStorageSessionService.custom(
  read: (key) => prefs.getString(key),
  write: (key, value) => prefs.setString(key, value),
  delete: (key) => prefs.remove(key),
  getKeys: ({prefix = ''}) => prefs.getKeys().where((k) => k.startsWith(prefix)).toList(),
);
```

#### `AdkTheme` & `AdkChatThemeData` (Theming System)
Wrap your app or screen with `AdkTheme` to customize colors, corner radiuses, paddings, and font styles across all widgets:

```dart
AdkTheme(
  data: const AdkChatThemeData(
    userBubbleColor: Colors.deepPurple,
    modelBubbleColor: Color(0xFFF1F5F9),
    userTextColor: Colors.white,
    modelTextColor: Colors.black87,
    borderRadius: BorderRadius.all(Radius.circular(20.0)),
    inputBackgroundColor: Colors.white,
    sendButtonColor: Colors.deepPurple,
    showTimestamp: true,
    showAvatars: true,
  ),
  child: AdkChatView(agent: myAgent),
)
```

---

### 3. Interactive UI Components & Builder Slots

| Component | Description | Usage Example |
|---|---|---|
| **`showAdkChatBottomSheet`** | Turnkey modal draggable bottom sheet hosting an interactive AI assistant. | `showAdkChatBottomSheet(context: context, agent: myAgent);` |
| **`AdkAgentManagementView`** | Administrative fleet dashboard for toggling agents, inspecting prompts, and monitoring telemetry. | `AdkAgentManagementView(controller: managerCtrl);` |
| **`AdkSplitPaneView`** | Adaptive split-pane layout (Chat on left, Live Logger & Tools on right) for Web/Desktop/Tablet. | `AdkSplitPaneView(agent: myAgent, splitRatio: 0.55);` |
| **`AdkReasoningExpander`** | Collapsible accordion for viewing Gemini 3.7 Thinking and reasoning steps. | `AdkReasoningExpander(thought: msg.thought!, durationMs: 1200);` |
| **`AdkAgentPersonaSelector`** | Responsive Grid/Carousel card selector for multi-agent persona switching. | `AdkAgentPersonaSelector(personas: [...], onPersonaSelected: (p) => ...);` |
| **`AdkInlineAssistantBar`** | Copilot-style inline toolbar for one-click Grammar, Polish, Summary, and Translate. | `AdkInlineAssistantBar(agent: copyAgent, targetController: textCtrl);` |
| **`AdkSmartFormView`** | Conversational form filling view that auto-populates fields through dialogue. | `AdkSmartFormView(agent: formAgent, fields: [...], onSubmit: (data) => ...);` |
| **`AdkConfirmationBanner`** | Human-in-the-Loop (HITL) inline banner and modal dialog for sensitive tool approvals. | `AdkConfirmationBanner.showAsDialog(context, title: 'Approve Tool', description: '...');` |
| **`AdkSessionDrawer`** | Sidebar drawer for switching, creating (`+`), and deleting conversation sessions. | `AdkSessionDrawer(sessions: sessions, activeSessionId: id, onSessionSelected: (s) => ...);` |
| **`AdkFloatingChatButton`** | Floating Action Button (FAB) that opens an AI assistant modal bottom sheet. | `AdkFloatingChatButton(agent: myAgent);` |
| **`AdkPromptSuggestionsBar`** | Horizontally scrollable bar with quick-tap prompt chips. | `AdkPromptSuggestionsBar(suggestions: [...], onSelected: (s) => ...);` |
| **`AdkToolCallCard`** | Accordion card displaying tool name, arguments, execution status, and return values. | `AdkToolCallCard(toolName: 'search', arguments: {...}, result: {...});` |
| **`AdkWorkflowProgressIndicator`**| Step-by-step timeline progress bar tracking workflow node statuses. | `AdkWorkflowProgressIndicator(steps: workflowSteps);` |
| **`AdkAgentHierarchyBadge`** | Breadcrumb badge indicating the active sub-agent in a multi-agent tree. | `AdkAgentHierarchyBadge(agentPath: ['Supervisor', 'Researcher']);` |
| **`AdkTokenUsageBadge`** | Compact badge showing prompt and completion token counts. | `AdkTokenUsageBadge(promptTokens: 120, completionTokens: 80);` |
| **`AdkVoiceMicButton` & `AdkAudioWaveVisualizer`** | Voice interaction button and reactive audio waveform animation. | `AdkVoiceMicButton(isListening: true, onPressed: () => ...);` |
| **`AdkMessageBubble`** | Material 3 chat bubble supporting user, model, tool, reasoning, and error roles. | `AdkMessageBubble(message: chatMessage);` |
| **`AdkTypingIndicator`** | Smooth pulsing animated dots displayed during AI generation. | `AdkTypingIndicator();` |
| **`AdkEventStreamBuilder`** | Reactive widget builder for listening directly to `Stream<Event>`. | `AdkEventStreamBuilder(stream: runner.runAsync(...), builder: (ctx, events) => ...);` |

---

### 4. UI Data Models (`package:flutter_adk/flutter_adk.dart`)

- **`AdkChatMessage`**: Immutable chat message (`isUser`, `isModel`, `isTool`, `isSystem`, `isStreaming`, `thought`, `toolArgs`, `toolResult`, `metadata`).
- **`AdkToolCallInfo`**: Tool execution state model (`callId`, `toolName`, `arguments`, `result`, `status`, `durationMs`).
- **`AdkWorkflowStep`**: Workflow step model (`id`, `label`, `description`, `status`, `durationMs`, `output`).
- **`AdkSessionInfo`**: Session history model (`id`, `title`, `messageCount`, `lastMessagePreview`, `updatedAt`).
- **`AdkPromptSuggestion`**: Suggestion model (`text`, `label`, `icon`, `category`).
- **`AdkTokenUsage`**: Token telemetry model (`promptTokens`, `completionTokens`, `totalTokens`, `formattedTotal`).
- **`AdkVoiceState`**: Real-time voice state model (`status`, `decibels`, `isMuted`, `isActive`).

---

## Platform Support Matrix

| Feature | Android | iOS | Web (WASM) | Linux | macOS | Windows | Notes |
| --- | :---: | :---: | :---: | :---: | :---: | :---: | --- |
| `flutter_adk` single import | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | Re-exports Web-safe `adk_core` |
| Turnkey UI Kit (14+ Widgets) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | 100% Flutter Material 3 |
| Agent runtime (`LlmAgent`, workflows) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | Pure Dart async stream orchestration |
| `Gemini` (3.7 / 2.0) & `LiteLlm` (Local) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | Cross-platform REST & WebSocket |
| MCP Toolset (Streamable HTTP) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | Remote MCP server connections |
| Storage Services (`AdkStorageSessionService`)| ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | Works with any key-value store |

---

## License

Apache License 2.0. Developed with ❤️ by Deepmind & ADK Labs.
