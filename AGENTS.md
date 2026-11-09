# AGENTS.md

## Project Overview

The **Agent Development Kit (ADK) for Dart & Flutter** (`adk_dart`) is an open-source, code-first Dart and Flutter framework for building, evaluating, and deploying AI agents, multi-agent hierarchies, ADK 2.0 graph workflows, and turnkey Flutter AI interfaces. It tracks [adk-python](https://github.com/google/adk-python) (`v2.14.0` baseline) and `adk-web` as the upstream sources of truth for runtime behavior.

### Monorepo Packages

| Package | Path | Import Entrypoint | Target Environment & Role |
| --- | --- | --- | --- |
| **`adk_dart`** | `.` (root) | `package:adk_dart/adk_dart.dart` (VM) / `package:adk_dart/adk_core.dart` (Web-safe) | Core runtime SDK: agents, workflows, LLM flows, tools, sessions, evaluation, A2A, telemetry. Also ships 9 domain barrels (`agents.dart`, `workflow.dart`, `evaluation.dart`, `tools.dart`, `models.dart`, `sessions.dart`, `integrations.dart`, `a2a.dart`, `telemetry.dart`). |
| **`adk`** | `packages/adk` | `package:adk/adk.dart` | Official `adk` CLI executable (`create`, `run`, `web`, `api_server`, `eval`, `eval_set`, `optimize`, `generate_agent_card`, `deploy`, `conformance`, `migrate`, `telemetry`, `test`, `doctor`) and short-name VM facade. |
| **`flutter_adk`** | `packages/flutter_adk` | `package:flutter_adk/flutter_adk.dart` | Flutter multi-platform & Web/WASM-safe UI Kit: 43+ Material 3 widgets (`AdkChatView`, `AdkDevStudioView`, specialized tool/eval/usage cards), 7 reactive controllers, `AdkTheme`, and `AdkStorageSessionService`. |
| **`adk_mcp`** | `packages/adk_mcp` | `package:adk_mcp/adk_mcp.dart` | Standalone Model Context Protocol (MCP) client/transport primitives (Streamable HTTP & Stdio). |
| **`adk_litertlm`** | `packages/adk_litertlm` | `package:adk_litertlm/adk_litertlm.dart` | On-device LiteRT-LM / Gemini Nano model integration for edge devices. |

---

## Skills for AI Coding Agents

Skills for building with or contributing to ADK Dart & Flutter are located in `.agents/skills/` (also linked at `.claude/skills/`):

| Skill | Path | When to Use |
| --- | --- | --- |
| **`adk-dart-setup`** | [`.agents/skills/adk-dart-setup/SKILL.md`](.agents/skills/adk-dart-setup/SKILL.md) | Choosing between `adk`, `adk_dart`, and `flutter_adk`, configuring `pubspec.yaml` and domain barrels, setting API keys / Vertex AI env vars, running `adk` CLI commands, or running repo build/analyze/test checks. |
| **`adk-dart-agent-builder`** | [`.agents/skills/adk-dart-agent-builder/SKILL.md`](.agents/skills/adk-dart-agent-builder/SKILL.md) | Building `LlmAgent` (`Agent`), `FunctionTool` / `BaseTool` / `McpToolset` / `OpenAPIToolset` / `SkillToolset` / `ToolSearchToolset`, ADK 2.0 `Workflow` DAG graphs (`BaseNode`, `FunctionNode`, `JoinNode`, `WorkflowTool`, `NodeTool`, routed edges, HITL `RequestInput`), multi-agent systems (`SequentialAgent`, `ParallelAgent`, `LoopAgent`, `subAgents`, `RemoteA2aAgent`, `mode: 'task'`), sessions/state/artifacts/memory, callbacks/plugins, and evaluations (`pass@k`, `pass^k`). |
| **`flutter-adk-ui-builder`** | [`.agents/skills/flutter-adk-ui-builder/SKILL.md`](.agents/skills/flutter-adk-ui-builder/SKILL.md) | Building Flutter chat UIs, embedding `AdkChatView` / `AdkDevStudioView` / `AdkSplitPaneView`, wiring controllers (`AdkChatController`, `AdkWorkflowController`, `AdkSessionController`, `AdkAgentManagerController`), customizing `AdkTheme` & `AdkCardStyle`, or using `AdkFormatters` & `AdkEventStreamUtils`. |
| **`adk-dart-debug`** | [`.agents/skills/adk-dart-debug/SKILL.md`](.agents/skills/adk-dart-debug/SKILL.md) | Diagnosing misbehaving ADK Dart agents and workflows using `Event` stream inspection, `DebugLoggingPlugin`, `adk web` HTTP/SSE endpoints (`/run`, `/run_sse`, `/debug/trace`), and known ADK Dart failure modes. |
| **`adk-dart-architecture`** | [`.agents/skills/adk-dart-architecture/SKILL.md`](.agents/skills/adk-dart-architecture/SKILL.md) | Understanding or modifying `adk_dart` / `packages/adk` / `packages/flutter_adk` internals, `part` / `part of` modularized subsystems, Web-safe (`adk_core.dart`) vs VM (`adk_dart.dart`) platform boundaries, and `adk-python` / `adk-web` parity rules. |

---

## Key Runtime Invariants

Keep these rules in mind when writing or modifying ADK Dart code:

1. **Web / WASM Safety Boundary**:
   - `package:adk_dart/adk_core.dart` and `package:flutter_adk/flutter_adk.dart` MUST remain 100% free of `dart:io`, `dart:ffi`, and `dart:mirrors` so Flutter Web (`flutter build web --wasm`) compiles cleanly.
   - VM-only services (`SqliteSessionService`, `DatabaseSessionService`, `FileArtifactService`, `StdioConnectionParams`, `UnsafeLocalCodeExecutor`, CLI/dev server) belong in `package:adk_dart/adk_dart.dart` (or `package:adk/adk.dart`).
2. **Cold `Stream<Event>` Execution**:
   - `runner.runAsync(...)` returns a `Stream<Event>`. Nothing executes until the caller listens to (`await for` or `.listen`) the stream.
   - Partial streaming chunks have `event.partial == true` and are emitted for real-time UI updates but never persisted to session storage.
3. **Session State & `temp:` Keys**:
   - State mutations travel via `EventActions(stateDelta: ...)` or `toolContext.state[key] = value`.
   - Keys prefixed with `temp:` are visible to subsequent steps within the same invocation (and forwarded to `AgentTool` child runs except internal `temp:_adk*` keys), then stripped before storage persistence.
4. **Function Tools on AOT & Web**:
   - On Dart VM JIT, `FunctionTool(func: myFunction)` can introspect parameter metadata via `dart:mirrors`.
   - For Flutter AOT / Web compatibility, prefer passing explicit `name`, `description`, and `parametersSchema` (or a `Map<String, dynamic>`-accepting function / `BaseTool` subclass) when targeting `adk_core` / `flutter_adk`.
5. **Documentation & Analysis**:
   - Follow Effective Dart documentation guidelines (`///` doc comments, third-person verbs or noun phrases, `[Symbol]` references).
   - Always verify zero issues across packages (`dart analyze lib test` and `flutter analyze lib test`).
