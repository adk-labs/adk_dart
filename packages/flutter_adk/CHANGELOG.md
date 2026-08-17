# Changelog

## 2026.8.17+7

- Added `AdkStructuredDataView` widget for pretty-printing, inspecting, and copying JSON structured outputs.
- Added `AdkToolInspectorView` widget for visual tree inspection of registered agent tools and parameter schemas.
- Added `Structured Output` interactive recipe/profile extraction example to Flutter example app.

## 2026.8.17+6

- Added Local LLM (Ollama / LM Studio) interactive example and documentation.
- Enabled Web-safe `LiteLlm` runtime integration for Flutter without native `dart:io` constraints.

## 2026.8.17+5

- Updated default model baseline across ADK to `gemini-3.7-flash`.
- Added **`AdkDevStudioView`**: Flutter ADK Web developer studio with Playground, Live Logger, Agent Graph, and State tabs.
- Added **`AdkAgentLoggerView`**: Real-time agent I/O logger with filter categories, latency, token usage, and JSON export/copy.

## 2026.8.17+4

- Added complete Flutter AI Agent UI Kit:
  - `AdkPromptSuggestionsBar`: Quick-tap prompt suggestion chips.
  - `AdkToolCallCard`: Expandable tool call inspector with args, status, and results.
  - `AdkConfirmationBanner` & `AdkConfirmationDialog`: Human-in-the-loop (HITL) approval banner and dialog.
  - `AdkFloatingChatButton`: Floating AI assistant action button opening modal bottom sheets.
  - `AdkSessionDrawer`: Session history manager with create, switch, and delete operations.
  - `AdkAgentHierarchyBadge`: Multi-agent breadcrumb navigation badge.
  - `AdkWorkflowProgressIndicator`: Step-by-step workflow timeline progress tracker.
  - `AdkVoiceMicButton` & `AdkAudioWaveVisualizer`: Interactive mic button and animated waveform visualizer.
  - `AdkTokenUsageBadge`: Token usage counter with tooltip cost breakdown.
- Added suggestions and voice mic triggers directly to `AdkChatView`.

## 2026.8.17+3

- Added full-featured Flutter UI Kit: `AdkChatView`, `AdkChatController`, `AdkMessageBubble`, `AdkTypingIndicator`, and `AdkEventStreamBuilder`.
- Expose built-in turnkey AI agent chat interface for all Flutter mobile, web, and desktop platforms.

## 2026.8.17+2

## 2026.8.17+1

- Bumped package version to `2026.8.17+1` and dependency `adk_dart: ^2026.8.17`.
- Synced facade release with `adk_dart` `2026.8.17+1` rollout.

## 2026.8.17

- Bumped package version to `2026.8.17` and dependency `adk_dart: ^2026.8.17`.
- Exported new Web-safe parity symbols: `LlmCapabilities`, `GetUserChoiceTool` (`getUserChoice`), `StaleSessionError`, `SessionNotFoundError`, `ReflectAndRetryModelPlugin`, and `ReflectAndRetryToolPlugin`.
- Upgraded `web` and `plugin_platform_interface` dependencies to latest versions.

## 2026.7.30

- Bumped package version to `2026.7.30` and dependency `adk_dart: ^2026.7.30`.

## 2026.7.24

- Bumped package version to `2026.7.24`.
- Updated dependency alignment to `adk_dart: ^2026.7.24`.
- Synced facade release with `adk_dart` `2026.7.24` rollout.

## 2026.7.11

- Bumped package version to `2026.7.11`.
- Updated dependency alignment to `adk_dart: ^2026.7.11`.
- Synced facade release with `adk_dart` `2026.7.11`, including ADK 2.0
  Managed Agent support, Interactions API integration, and
  `RemoteMcpServer` for server-side tool execution.

## 2026.6.6

- Bumped package version to `2026.6.6`.
- Updated dependency alignment to `adk_dart: ^2026.6.6`.
- Synced facade release with `adk_dart` `2026.6.6`, including the `2.2.0` ADK baseline update and latest workflow/runtime parity work.
- Refreshed the Flutter example surface with updated localized README content, latest example registry entries, local path overrides, service wiring updates, and plugin smoke-test coverage.

## 2026.4.17

- Bumped package version to `2026.4.17`.
- Updated dependency alignment to `adk_dart: ^2026.4.17`.
- Synced facade release with `adk_dart` `2026.4.17`, including the `1.31.0` ADK baseline update and latest live/runtime parity fixes.

## 2026.3.21

- Bumped package version to `2026.3.21`.
- Updated dependency alignment to `adk_dart: ^2026.3.21`.
- Synced facade release with the latest `adk_dart` parity work, including session/storage parity, `SpannerAdminToolset`, `environment_simulation`, evaluation metric expansion, Slack/Agent Registry/IAM integration surfaces, and the latest A2A/Discovery Engine/skills compatibility updates.

## 2026.3.13

- Bumped package version to `2026.3.13`.
- Updated dependency alignment to `adk_dart: ^2026.3.13`.
- Synced facade release with the latest `adk_dart` parity work, including skills/API Registry/A2A runtime alignment, Anthropic and BigQuery parity updates, and CLI conformance/MCP schema improvements.

## 2026.3.6

- Bumped package version to `2026.3.6`.
- Updated dependency alignment to `adk_dart: ^2026.3.6`.
- Synced facade release with `adk_dart` `2026.3.6`, including the latest local session-path fix and March Python parity updates.

## 2026.3.2+4

- Bumped package version to `2026.3.2+4`.
- Synced facade release with `adk_dart` `2026.3.2+4`, including positional deploy target parity updates.

## 2026.3.2+3

- Bumped package version to `2026.3.2+3`.
- Synced facade release with `adk_dart` `2026.3.2+3`, including conformance live-mode execution support.

## 2026.3.2+2

- Bumped package version to `2026.3.2+2`.
- Synced facade release with `adk_dart` `2026.3.2+2`, including web/api_server project loading parity and `/run` auto session-create request behavior.

## 2026.3.2+1

- Bumped package version to `2026.3.2+1`.
- Updated release alignment with `adk_dart` `2026.3.2+1`, including latest CLI parity and runtime path-hardening changes from core.

## 2026.3.2

- Bumped package version to `2026.3.2`.
- Updated dependency alignment to `adk_dart: ^2026.3.2`.

## 2026.3.1

- Initial `flutter_adk` package scaffold added for Android, iOS, Web, Linux, macOS, and Windows.
- Re-exported `package:adk_dart/adk_core.dart` from `package:flutter_adk/flutter_adk.dart`.
- Added package metadata and release alignment with `adk_dart` version `2026.3.1`.
