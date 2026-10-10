# 2026-09-11 Upstream `adk-python` v2.9.0 Parity & `flutter_adk` HITL/Artifact UI Worklog

## Overview
This worklog documents the `2026-09-11` commits (`2e00d2d`, `d22506b`, `752230c`, `daed006`) covering `adk-python` v2.9.0 parity, `adk-web` A2UI markdown bundle sync, new `flutter_adk` HITL and artifact viewer widgets, and the `2026.9.11` release.

---

## 1. Upstream `adk-python` v2.9.0 Runtime Parity (`d22506b`)
- **`LlmAgent` & `BaseNode` / `BaseAgent` Tool Interop**:
  - Automatically adapts `BaseNode` instances passed to `LlmAgent(tools: ...)` into `NodeTool(node: t, description: t.description)`.
  - Rejects `BaseAgent` instances in `tools` with an explicit `ArgumentError` directing users to `subAgents` or `AgentTool`.
  - Preserves list identity when no tool adaptation is needed.
- **`Workflow` & `NodeTool` Unwrapping and State Propagation**:
  - Unwraps `NodeTool` directly to its underlying `BaseNode` in `buildNode`.
  - Falls back to `invocationContext.session.state` for missing required parameters in `ToolNode.run` and merges `toolContext.actions.stateDelta` back into `session.state`.
- **`LoadArtifactsTool` Scope Guard & Namespace Resolution**:
  - Cross-checks requested artifact names against session-listed artifacts to prevent out-of-scope file access.
  - Automatically resolves `user:filename` vs `filename` namespaces while keeping the requested label in prompt feedback.
- **`Runner` State Delta on Resume & Workflow Failure Rehydration**:
  - Supports applying `stateDelta` when resuming an invocation by `invocationId` with `newMessage: null`.
  - Rehydrates failed workflow nodes without output as `NodeStatus.failed` and clears stale errors upon retry completion.
- **`BaseLlmFlow` Streaming Flag Inheritance & Orphaned Function Call Pruning**:
  - Added `_inheritUnsetStreamingFields` so `afterModelCallback` replacements inherit `partial` and `turnComplete` flags.
  - Added `_dropOrphanedFunctionCalls` in `contents.dart` to prune unanswered tool calls on interrupted turns while preserving `longRunningToolIds`.

## 2. `adk-web` A2UI Markdown Bundle Update (`2e00d2d`)
- Rebuilt and updated `packages/adk/lib/src/cli/browser/` with upstream `adk-web` commit `3693fda` adding A2UI markdown rendering support.

## 3. `flutter_adk` HITL & Artifact UI Widgets (`daed006`)
- **`AdkHumanInTheLoopCard`**: Interactive approval/rejection card for pending tool confirmations and user choice interruptions.
- **`AdkArtifactViewer`**: Multimodal artifact previewer supporting text, JSON, code, and binary artifact inspection.
- Enhanced `AdkToolCallCard` and `AdkToolInspectorView` with expandable metadata and execution status badges.

## 4. Verification & Release `2026.9.11` (`752230c`)
- Added `test/upstream_v2_9_parity_test.dart` (12 parity tests; 1,474 total passing tests).
- Bumped all workspace packages to `2026.9.11`.
