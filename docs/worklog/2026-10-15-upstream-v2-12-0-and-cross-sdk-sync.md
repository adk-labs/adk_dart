# 2026-10-15 Upstream ADK v2.12.0+ & Cross-SDK Parity Sync Worklog

## Overview
This worklog documents the end-to-end synchronization of `adk_dart` and `packages/adk` against the latest upstream releases across all language SDKs in `ref/`:
- `adk-python` (`15486dbb2..156f007ce`, v2.12.0+)
- `adk-go` (`987c7bc0..9a43519e`, v2.6.0)
- `adk-java` (`189d463a..bad4f4c3`, v1.12.0)
- `adk-js` (`86d1cfef..0f3e5f22`, v2.3.0)
- `adk-kotlin` (`89c796cd..d93eb795`, v1.4.0)
- `adk-web` (built SPA assets verification in `packages/adk`)

---

## 1. Work Unit 1: Core, Workflow, Classifiers, Live, Models & Sessions

### 1.1 Classifiers & Routing Nodes (`lib/src/labs/classifiers/`)
- Created `types.dart`: `ClassifierQuestion` (sealed base), `Choice` (validating `criteria.length >= 2`), `Binary`, `Score` (validating `criteria.length >= 2`), `ClassifierAnswer` (sealed base), `ChoiceAnswer`, `BinaryAnswer`, `ScoreAnswer`, and `ClassifierResponse`.
- Created `base_classifier.dart`: `abstract class BaseClassifier` with feature gate check for `FeatureName.classifier`.
- Created `classifier_node.dart`: `class ClassifierNode extends BaseNode` supporting `Choice` and `Binary` questions, route resolution (`routeFor`), and outgoing edge validation (`validateOutgoingEdges`).
- Exported in `lib/src/labs/classifiers/classifiers.dart`, `lib/adk_dart.dart`, and `lib/adk_core.dart`.

### 1.2 Workflow Engine Enhancements (`lib/src/workflow/workflow.dart`)
- `ReplaySequenceBarrier`: Added `_completed` buffer for out-of-order completions in parallel branches to prevent stalls (`a4ba81372`).
- `BaseNode.validateOutgoingEdges`: Validates declared routes and edges during static graph validation (`e8c4bacdf`).
- `FunctionNode.requireConfirmation`: Added HITL confirmation flow via `wf_tool_confirmation:${nodeContext.nodePath}` interrupt and auto-defaulting `rerunOnResume: true` (`988fd1a73`).
- Rerun & Interrupt Disambiguation: Handled multi-interrupt partial resolution and dynamic child state pruning during retries (`ed81e1b26`, `5ee5cf853`, `2b8b6d535`).
- Thought filtering in `_toolArgsFromInput` and parallel worker batch interrupt handling (`2d4370170`, `531a86a19`).

### 1.3 Live & Realtime Caching (`lib/src/live/`, `lib/src/flows/llm_flows/`)
- Barge-in support in `CascadeLiveConnection`: Added `_CascadeState`, audio duration tracking, sentence extraction, and playback interruption triggering `LlmResponse(interrupted: true)` (`2e7ef926c`).
- Renamed `AudioCacheManager` to `RealtimeCacheManager` with backward-compatible typedef aliases (`e8b019239`).
- Added `activeBackgroundTools` tracking in `InvocationContext` and cancellation cleanup in `functions.dart` (`cf4ec9399`, `7d3658ef1`, `156f007ce`).

### 1.4 Runner, Agents & Sessions (`lib/src/runners/`, `lib/src/agents/`, `lib/src/sessions/`)
- `Runner._findAgentToRun`: Added task delegator resolution, error event skipping, and sticky routing for unfinished `transfer_to_agent` actions (`bb353c8dd`, `c5ee35e33`).
- Isolated cleanup blocks in `Runner.close` (`e342a14ec`) and full session rehydration in `Runner.rewindAsync` (`8431830c7`).
- `State.recordNestedWrites()`: Deeply tracks mutations to handed-out nested `Map` and `List` objects and merges them into `_delta` (`ce2fdc5aa`).
- Added `cascadeDelete` to database session services and purge events before deleting session rows (`3b2b949c4`).

### 1.5 Models & Multi-Provider Interop (`lib/src/models/`, `lib/src/a2a/`)
- Created `RoutedLlm` (`lib/src/models/routed_llm.dart`) with configurable router functions and automatic failure recovery failover (`adk-js` parity).
- `AnthropicLlm`: Honored output schema on Claude without tools (`97af1ff62`), and added adaptive thinking & effort parameter support (`201bb98d9`).
- `GemmaLlm`: Added validation and Gemma 4 native function calling and system instruction support (`608ce2dd5`, `b778323f3`).
- `InteractionsUtils`: Added detailed token usage breakdown (`cachedContentTokenCount`, `cacheTokensDetails`, etc.) and generation config forwarding (`d57f0cb0c`, `0df007036`).
- A2A Protocol: Added `tool_call` and `tool_response` in `part_converter.dart`, namespaced context IDs in `remote_a2a_agent.dart`, and added `A2aTaskState.rejected` and `unknown` (`a334bacaa`, `c213adf02`).

---

## 2. Work Unit 2: Tools, Sandboxes, Integrations, Eval & CLI

### 2.1 Tool Execution & Search (`lib/src/tools/`)
- `AgentTool`: Added tracking for `lastErrorMessage` and `pendingToolIds`, surfacing unresolved long-running tool calls as errors without swallowing them (`9a5510e09`).
- `NodeTool`: Aligned input schema resolution and tool argument validation (`4ec4af195`, `d0c8454ed`).
- `ComputerUseToolset`: Added Gemini 3.x modern action tool shims (`click`, `move`, `type`, `scroll`, `take_screenshot`, `press_key`, `hotkey`), coordinate normalization, private network blocking, and execution serialization (`b90e4a5ee`).
- `OpenAPIToolset`: Truncated tool name deduplication (`_2`, `_3`), operation-level parameter precedence, and query param truthiness preserving `false` and `0` (`b310c3080`, `6563a09ed`, `b4cf70ca6`).
- `BigtableToolset`: Added `viewParameterNames` and parameterized view execution (`3893d7fa3`).
- `ToolSearchToolset` (`lib/src/tools/toolsearch/`): Implemented dynamic tool discovery and catalog indexing with BM25 and Regex ranking (`adk-go` parity).
- `ModelConsultTool` (`lib/src/tools/model_consult/`): Implemented secondary advisor model consultation with context truncation and client label attribution (`adk-python` `068610f27`).

### 2.2 Sandboxes & Environments (`lib/src/integrations/`)
- `OpenSandboxEnvironment` (`lib/src/integrations/opensandbox/`): Remote and in-memory execution environment with HTTP client (`69d1c901b`).
- `AgentEngineEnvironment` (`lib/src/integrations/vmaas/`): Vertex AI Agent Engine sandbox execution environment with shell-backed command execution and file transfer (`3800f0689`).

### 2.3 Evaluation & Optimization (`lib/src/evaluation/`, `lib/src/optimization/`)
- Supported `BaseLlm` instances in `JudgeModelOptions` and user simulation (`cb48b9198`).
- Honored metric-level `evalStatus` and split invocation duration into model, tool, and framework time (`5bf7f12ef`, `e3797a496`).
- Surfaced Vertex rubric verdicts/explanations and handled zero scores (`bc220d2ef`).
- Rejected empty train eval cases and drive-qualified path segments (`d9fe639c0`, `29bb0532c`).

### 2.4 CLI & Web Server (`packages/adk/`)
- Added screencast WebSocket endpoint (`/apps/{appName}/screencast`) in `web_server.dart`.
- Handled nested workflow nodes in graph serialization (`agent_graph.dart`).
- Added `A2aTaskState.rejected` and `unknown` wire mappings.
- Returned 404 for missing eval results or sessions (`c2dcb75af`).

---

## 3. Verification & Quality Assurance
- `dart analyze` on `adk_dart`: **0 issues found** (clean).
- `dart analyze` on `packages/adk`: **0 issues found** (clean).
- New unit test suites created:
  - `test/routed_llm_test.dart`: 3/3 passing.
  - `test/classifiers_test.dart`: 5/5 passing.
  - `test/tool_search_test.dart`: 3/3 passing.
  - `test/model_consult_test.dart`: 2/2 passing.
  - `test/environments_parity_test.dart`: 2/2 passing.
- Daily upstream report generated at `reports/adk-python/2026-10-15.md` (and `reports/adk-python/latest.md`).
