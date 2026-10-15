# 2026-10-15 Upstream Parity, Full Documentation & Release `2026.10.15` Worklog

## Overview
This worklog documents the `2026-10-15` release (`v2026.10.15`), achieving 100% multi-repo parity across `adk-python` (v2.12.0+, `156f007ce`), `adk-go` (v2.6.0, `9a43519e`), `adk-java` (v1.12.0, `bad4f4c3`), `adk-js` (v2.3.0, `0f3e5f22`), and `adk-kotlin` (v1.4.0, `d93eb795`), completing 100% Effective Dart API documentation comments and runnable examples, and publishing all 5 packages to pub.dev.

---

## 1. Upstream Multi-SDK Parity Features

### Classifiers & Workflow Routing (`lib/src/labs/classifiers/`, `workflow.dart`)
- **`BaseClassifier` & `ClassifierNode`**:
  - Implemented typed question models (`Choice`, `Binary`, `Score`) and answer distributions (`ChoiceAnswer`, `BinaryAnswer`, `ScoreAnswer`, `ClassifierResponse`).
  - Added route evaluation (`routeFor`), threshold validation for binary questions, and state mutation recording (`answerKey`).
- **Workflow Engine Hardening**:
  - Added out-of-order parallel branch completion buffering in `ReplaySequenceBarrier`.
  - Added `validateOutgoingEdges` on `BaseNode` and static graph edge verification.
  - Implemented `requireConfirmation` HITL gate and resume handling on `FunctionNode`.
  - Added retry pruning of non-completed dynamic child nodes and filtered thought parts from input tool arguments.

### Live Barge-in & Realtime Caching (`lib/src/live/`, `lib/src/flows/llm_flows/`)
- **`CascadeLiveConnection` Barge-in**:
  - Implemented full barge-in interruption detection (`_CascadeState`, `_pcmDurationMs`, `_extractHeardSentences`), emitting `LlmResponse(interrupted: true)` on user speech during thinking or speaking.
- **`RealtimeCacheManager`**:
  - Renamed `AudioCacheManager` to `RealtimeCacheManager` with backward-compatible typedefs.
  - Added `activeBackgroundTools` tracking in `InvocationContext` and cancellation cleanup in `functions.dart`.

### Model Router & Multi-Provider Enhancements (`lib/src/models/`, `lib/src/a2a/`)
- **`RoutedLlm` (`lib/src/models/routed_llm.dart`)**:
  - Added model router with custom fallback routing functions and automatic failure recovery failover (`adk-js` parity).
- **Claude & Gemma 4 Features**:
  - Honored `outputSchema` on `AnthropicLlm` without tools, and added adaptive thinking and effort configs.
  - Added Gemma 4 native function calling and system instructions on `GemmaLlm`.
  - Supported `tool_call` and `tool_response` in A2A part converter, namespaced context IDs in `RemoteA2aAgent`, and added `A2aTaskState.rejected` / `unknown`.

### Tools, Sandboxes & Environments (`lib/src/tools/`, `lib/src/integrations/`)
- **`ToolSearchToolset` (`lib/src/tools/toolsearch/`)**:
  - Ported `adk-go` dynamic tool discovery and activation toolset with BM25 ranking and regex pattern searching.
- **`ModelConsultTool` (`lib/src/tools/model_consult/`)**:
  - Ported advisor consultation toolset with advisor client label attribution.
- **`OpenSandboxEnvironment` & `AgentEngineEnvironment`**:
  - Added OpenSandbox and Vertex AI VMaaS execution environments.
- **Modern Computer Use**:
  - Implemented Gemini 3.x browser action schemas, coordinate normalization (`_normalizeX`, `_normalizeY`), private network blocking, and execution serialization.
- **OpenAPI & Bigtable**:
  - Disambiguated truncated OpenAPI tool names, prioritized operation-level parameters, and preserved `false` / `0` in query serialization.
  - Added parameterized view execution in `BigtableToolset`.
  - Surfaced unresolved long-running tool calls as errors in `AgentTool`.

---

## 2. 100% Effective Dart API Documentation & Examples
- Added `///` doc comments for all public declarations across:
  - `adk_dart`: Core agents, workflows, models, tools, auth, sessions, memory, telemetry, evaluation.
  - `packages/adk`: CLI commands, web server, service registry, built-in agents.
  - `packages/adk_mcp`: Stdio and remote MCP client primitives.
  - `packages/adk_litertlm`: LiteRT-LM models and conversation controllers.
  - `packages/flutter_adk`: 10+ UI Kit widgets, controllers, models, and themes.
- Added runnable `/// ```dart` code examples to all primary entrypoint classes.
- Created canonical `example/example.dart` quickstart in `adk_dart`.
- `dart analyze` across all packages: **0 issues found**.

---

## 3. Published Packages on pub.dev (`2026.10.15`)

| Package | Version | Pub.dev Link |
|---|---|---|
| `adk_mcp` | `2026.10.15` | https://pub.dev/packages/adk_mcp/versions/2026.10.15 |
| `adk_dart` | `2026.10.15` | https://pub.dev/packages/adk_dart/versions/2026.10.15 |
| `adk` | `2026.10.15` | https://pub.dev/packages/adk/versions/2026.10.15 |
| `adk_litertlm` | `2026.10.15` | https://pub.dev/packages/adk_litertlm/versions/2026.10.15 |
| `flutter_adk` | `2026.10.15` | https://pub.dev/packages/flutter_adk/versions/2026.10.15 |

Git Release Tag: `v2026.10.15` (commit `0042019`).
