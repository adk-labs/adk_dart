---
name: flutter-adk-ui-builder
description: >-
  Builds cross-platform Flutter AI chat, developer studio, workflow, voice, and
  evaluation UIs using package:flutter_adk/flutter_adk.dart (iOS, Android,
  Web/WASM, macOS, Windows, Linux). Covers turnkey views (AdkChatView,
  AdkDevStudioView, AdkSplitPaneView, AdkAgentManagementView, AdkSmartFormView,
  showAdkChatBottomSheet), 7 reactive controllers (AdkChatController,
  AdkWorkflowController, AdkVoiceController, AdkSessionController,
  AdkSmartFormController, AdkAgentLoggerController, AdkAgentManagerController),
  specialized tool/usage/eval cards (AdkUsageMonitorCard,
  AdkContextWindowMeter, AdkSkillToolCard, AdkFileEditCard,
  AdkShellCommandCard, AdkWebPageCard, AdkComputerActionCard,
  AdkCompactionSummaryCard, AdkReflectRetryBanner, AdkMultiRunEvalCard),
  AdkTheme & AdkCardStyle customization, AdkStorageSessionService, and UI
  utilities (AdkFormatters, AdkEventStreamUtils). Use when building or
  customizing Flutter AI agent UIs.
---

# Flutter ADK UI Builder (`flutter_adk`)

Checked against `flutter_adk` `2026.11.9` (100% Flutter Web / `dart2wasm` compatible).

Single import for both the Web-safe ADK runtime (`adk_core`) and all 43+ Material 3 UI components:

```dart
import 'package:flutter_adk/flutter_adk.dart';
```

---

## 1. Turnkey Views & Quick Start

```dart
import 'package:flutter/material.dart';
import 'package:flutter_adk/flutter_adk.dart';

class AgentChatScreen extends StatelessWidget {
  const AgentChatScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final Agent agent = LlmAgent(
      name: 'assistant',
      model: 'gemini-2.5-flash',
      instruction: 'You are a helpful Flutter assistant.',
    );

    return Scaffold(
      appBar: AppBar(title: const Text('AI Assistant')),
      body: AdkChatView(
        agent: agent,
        inputPlaceholder: 'Ask anything...',
        showContextWindowMeter: true,
        showTokenUsage: true,
        useSpecializedToolCards: true,
        suggestions: const <String>[
          'Summarize today\'s tasks',
          'Show available tools',
        ],
      ),
    );
  }
}
```

### Turnkey Full-Screen & Modal Views
- **`AdkChatView`**: Complete chat screen with autoscroll, streaming bubbles, thinking accordion, specialized tool cards, context window meter, and token usage badges.
- **`AdkDevStudioView`**: Embedded ADK Web developer studio (Playground, Live Logger, Agent Graph, and Session State tabs).
- **`AdkSplitPaneView`**: Responsive desktop/tablet/web split view (Chat on left, Live Logger & Tool Inspector on right).
- **`AdkAgentManagementView`**: Fleet dashboard for toggling agents ON/OFF, hot-swapping instructions, and viewing latency/token metrics.
- **`AdkSmartFormView`**: Conversational form-filling view that auto-populates form fields from dialogue and tool calls.
- **`showAdkChatBottomSheet(context: context, agent: agent)`** / **`AdkFloatingChatButton(agent: agent)`**: One-line modal assistant overlay.

---

## 2. Reactive State Controllers

| Controller | Role & Key Methods |
| --- | --- |
| **`AdkChatController`** | Manages chat messages, SSE streaming, tool call states, `sessionTokenUsage`, and storage sync (`sendMessage`, `loadSession`, `clearMessages`, `stopGeneration`, `rewindBeforeInvocation`, `exportTranscriptJson`, `resetTokenUsage`). |
| **`AdkWorkflowController`** | Runs multi-step workflows, tracks `AdkWorkflowStep` statuses, and handles HITL pause/resume (`execute`, `approveAndResume`, `setStepStatus`, `cancel`, `reset`). |
| **`AdkSessionController`** | Manages multi-session creation, switching, renaming, deletion, and search (`loadAllSessions`, `createNewSession`, `switchSession`, `updateSessionTitle`, `deleteSession`, `clearAllSessions`, `setSearchQuery`). |
| **`AdkVoiceController`** | Manages microphone recording state, decibels, transcripts, and barge-in (`startListening`, `stopListening`, `startSpeaking`, `stopSpeaking`, `interrupt`, `toggleMute`). |
| **`AdkSmartFormController`** | Extracts form values from tool args and validates required fields (`updateFieldValue`, `populateFromMap`, `validate`, `getFormData`, `submit`, `reset`). |
| **`AdkAgentLoggerController`** | Buffers real-time I/O and telemetry logs with category filtering and JSON export (`addLog`, `recordEvent`, `setCategory`, `setSearchQuery`, `exportJson`, `clearLogs`). |
| **`AdkAgentManagerController`** | Central fleet registry for toggling agents and aggregating latency/token telemetry (`registerAgent`, `unregisterAgent`, `toggleAgent`, `setActiveAgent`, `updateInstruction`, `recordInvocation`). |

---

## 3. Specialized Tool, Telemetry & Evaluation Cards

When `useSpecializedToolCards: true` is enabled on `AdkChatView` (or when rendered standalone), `flutter_adk` provides dedicated Material 3 cards:

- **Tool Execution Cards**:
  - `AdkToolCallCard`: General accordion card displaying `call.effectiveTitle` (`displayTitle ?? toolName`), arguments, status, and result.
  - `AdkSkillToolCard`: Renders `SkillToolset` calls (`list_skills`, `load_skill`, `load_skill_resource`) and parses `<available_skills>` XML.
  - `AdkFileEditCard`: Renders `EnvironmentToolset` file operations (`EditFile`, `WriteFile`, `ReadFile`) with LCS line-by-line unified diff highlighting.
  - `AdkShellCommandCard`: Dark terminal card for `Execute` / `run_skill_script` with ANSI code stripping, `stdout`/`stderr`, and exit code badge.
  - `AdkWebPageCard`: Preview card for `load_web_page` / `fetch_web_page` with domain badge and collapsible body.
  - `AdkComputerActionCard`: Coordinate badge and screenshot viewer for `ComputerUseToolset` (`click_at`, `type_text_at`, `scroll_at`).
- **Context, Usage & Retry Widgets**:
  - `AdkUsageMonitorCard`: Stacked token bar (`promptTokens`, `completionTokens`, `thoughtTokens`, `cachedTokens`, `cacheCreationTokens`), cache hit ratio, latency, and USD cost estimator.
  - `AdkContextWindowMeter`: Progress bar (`usedTokens / maxContextTokens`) with compaction threshold marker.
  - `AdkCompactionSummaryCard`: Collapsible timeline card for `EventActions.compaction`.
  - `AdkReflectRetryBanner`: Self-healing retry status banner (`Attempt N/M`) for `ReflectAndRetryToolPlugin`.
- **Evaluation & HITL Widgets**:
  - `AdkMultiRunEvalCard`: Displays `MultiRunCaseResult` pass rate, average score, std dev, **`pass@k` / `pass^k` chips**, and **`[INFO]` informational metric badges** (`AdkMultiRunEvalCard.fromCoreResults(...)`).
  - `AdkConfirmationBanner`, `AdkInterruptBanner`, `AdkInterruptCard`: Human-in-the-loop approval and input cards.
  - `AdkArtifactViewer`: Renders text, markdown, JSON, HTML, CSV, and image artifacts (with UTF-8 `data:` URL decoding and URL-encoded download paths).

---

## 4. Theming (`AdkTheme` & `AdkCardStyle`) & Persistence

```dart
// 1. 2-Line Key-Value Session Persistence (SharedPreferences / Hive / SecureStorage)
final AdkStorageSessionService sessionService = AdkStorageSessionService.custom(
  read: (String key) async => prefs.getString(key),
  write: (String key, String value) async => prefs.setString(key, value),
  delete: (String key) async => prefs.remove(key),
  getKeys: ({String prefix = ''}) async =>
      prefs.getKeys().where((String k) => k.startsWith(prefix)).toList(),
);

// 2. Unified Theme & Card Styling
AdkTheme(
  data: const AdkChatThemeData(
    userBubbleColor: Colors.indigo,
    cardStyle: AdkCardStyle(
      borderRadius: BorderRadius.all(Radius.circular(14)),
      accentColor: Colors.indigo,
    ),
  ),
  child: AdkChatView(agent: myAgent),
)
```

---

## 5. Built-in UI Utilities (`AdkFormatters` & `AdkEventStreamUtils`)

- **`AdkFormatters`**:
  - `formatTokens(int, {bool compact = false})`, `formatDuration(Duration)`, `formatBytes(int)`, `formatJson(Object?)`
  - `decodeDataUrlTextUtf8(String? dataUrl)`: Decodes base64 or percent-encoded `data:` URLs using UTF-8 (preserving Korean/CJK/emoji characters).
  - `encodeArtifactFilename(String artifactName)`: Percent-encodes special characters (`#`, `?`, `%`, spaces) for safe artifact URLs.
- **`AdkEventStreamUtils`**:
  - `extractToolCalls(Event)` (automatically maps `adk:tool_display_names` to `AdkToolCallInfo.displayTitle`)
  - `extractTokenUsage(Event)` (maps `cacheCreationTokens`, `cachedTokens`, `thoughtTokens`)
  - `extractVisibleText(Event)` (concatenates non-thought text parts)
  - `isAbortedEvent(Event)` (detects invocation abort / cancellation events)
  - `detectSystemInstructionChangesByAgent(Iterable<({Event event, String? systemInstruction})>)` (tracks system instruction changes scoped per agent author)

For full widget parameter tables and copy-paste recipes, see:
- [`packages/flutter_adk/docs/WIDGET_CATALOG.md`](../../../packages/flutter_adk/docs/WIDGET_CATALOG.md)
- [`packages/flutter_adk/docs/WIDGET_SPECIFICATION.md`](../../../packages/flutter_adk/docs/WIDGET_SPECIFICATION.md)
