# Upstream Multi-SDK Parity Sync & Enhancements (2026-10-16)

## Overview
Comprehensive synchronization across all upstream ADK repositories (`adk-python`, `adk-go`, `adk-java`, `adk-js`, `adk-kotlin`, `adk-web`) bringing `adk_dart` and `packages/adk` to complete parity.

---

## Unit 1: Core Runtime Updates
- **BaseAgent Artifact Delta Recording (`019387c62`)**:
  - In `lib/src/agents/base_agent.dart`: Updated callback event generation so `actions.artifactDelta` from `beforeAgentCallback` and `afterAgentCallback` produces an `Event` even when `state.hasDelta()` is false.
- **AgentTool RunConfig Forwarding (`6ed5dd08`)**:
  - In `lib/src/tools/agent_tool.dart`: Forwarded `runConfig: invocationContext.runConfig` when invoking `runner.runAsync(...)`, ensuring the model-call budget (`maxLlmCalls`) and runtime configuration bound sub-agent executions identically to the caller.
- **Memory Service `deleteMemory` API (`41e5c7b90`, `2416f660b`)**:
  - `BaseMemoryService`: Added `Future<void> deleteMemory({required String appName, required String userId, String? memoryId})`.
  - `InMemoryMemoryService`: Added `_deletedMemoryIdsByUserKey` tracking to purge deleted events and prevent re-ingestion from subsequent session additions. Added `id: event.id` to `MemoryEntry`.
  - `InvocationContext` and `Context`: Added `deleteMemory({String? memoryId})` delegation.
- **JSON Pointer `$ref` Dereferencing (`59fe93bd0`)**:
  - `lib/src/tools/_gemini_schema_util.dart`: Implemented `_resolveJsonPointer` with URI-fragment parsing, URI unquoting, token unescaping (`~1` -> `/`, `~0` -> `~`), array indexing, supporting both `definitions` and `$defs`, circular reference detection, and defs fallback.
- **Tests**:
  - Added [test/unit1_core_parity_test.dart](file:///Users/jaichang/Documents/GitHub/adk-labs/adk-dart/adk_dart/test/unit1_core_parity_test.dart) covering JSON Pointer resolution and `InMemoryMemoryService.deleteMemory`.

---

## Unit 2: Live Ingress/Egress Models (`GeminiSTT` & `GeminiTTS`)
- **`GeminiSTT` Ingress Transform (`f78149a97`, `_gemini_stt.py`)**:
  - Created `lib/src/live/gemini_stt.dart` implementing `LiveIngress` (`Stream<InlineData> audio` -> `Stream<IngressEvent>`).
  - Added `_AudioBuffer` with `maxReplayMs` capping (default 10,000ms, 16kHz 16-bit mono) to preserve speech during session transitions.
  - Connects to Gemini Live API (`gemini-3.5-transcribe-live`) using `LiveConnectConfig(responseModalities: ['TEXT'], speechConfig: {'silenceDurationMs': silenceDurationMs, ...})`.
  - Dispatches `UserSpeechStarted`, `PartialTranscript`, and `UserTurnFinished` events upon transcription and turn completion (`resp.turnComplete == true`).
- **`GeminiTTS` Egress Transform (`f78149a97`, `_gemini_tts.py`)**:
  - Created `lib/src/live/gemini_tts.dart` implementing `LiveEgress` (`Stream<String> text` with `CancelSignal cancel` -> `Stream<EgressEvent>`).
  - Implemented sentence boundary regex `_sentenceEnd` and CJK clause detection `_cjkClauseEnd` with `minSegmentChars` (default 50) and `maxSegmentChars` (default 240) to synthesize natural audio chunks.
  - Generates `AudioChunk` blobs from model `Part.inlineData` and records `AgentSpokenOutput` text once audio synthesis completes.
  - Supports immediate cancellation and barge-in via `CancelSignal`.
- **`GenerateContentConfig` Modality & Speech Additions**:
  - Added `responseModalities` and `speechConfig` to `GenerateContentConfig` in `lib/src/models/llm_request.dart`, with overrides in `AnthropicGenerateContentConfig` in `lib/src/models/anthropic_llm.dart`.
  - Updated `_buildGenerationConfig` in `lib/src/models/google_llm.dart` to serialize `responseModalities` and `speechConfig`.
- **Exports**:
  - Exported `GeminiSTT` and `GeminiTTS` in `lib/src/live/live.dart`, which is re-exported by `lib/adk_dart.dart` and `lib/adk_core.dart`.
- **Tests**:
  - Added [test/unit2_gemini_speech_test.dart](file:///Users/jaichang/Documents/GitHub/adk-labs/adk-dart/adk_dart/test/unit2_gemini_speech_test.dart) covering `GeminiTTS` synthesis, segment splitting, barge-in cancellation, constructor validations, and `GeminiSTT` audio streaming and transcription events (100% pass).

---

## Unit 3: Plugins & Tools (`ForceEscalationPlugin` & `ModelConsultTool` Budget)
- **`ModelConsultTool` Turn and Session Budgeting (`08b53e839`, `_model_consult_tool.py`)**:
  - In `lib/src/tools/model_consult/model_consult_tool.dart`:
    - Added `sessionMaxUses` (and `maxUses` alias for `maxConsultationsPerInvocation`).
    - Added state key generators: `turnUsesStateKey({required String toolName, required String invocationId})` (`temp:model_consult:$toolName:$invocationId:uses`) and `sessionUsesStateKey({required String toolName})` (`model_consult:$toolName:session_uses`).
    - Added `hasRemainingBudget(Object context)`, `turnUses(Object context)`, and `sessionUses(Object context)`.
    - Enforced session and invocation caps during `run`, returning `SESSION_CONSULTATION_LIMIT_EXCEEDED` or `CONSULTATION_LIMIT_EXCEEDED` when exhausted, and recorded usage increments into `toolContext.state` upon success.
- **`ForceEscalationPlugin` (`a84d978e2`, `_force_escalation_plugin.py`)**:
  - Created `lib/src/tools/model_consult/force_escalation_plugin.dart` implementing `BasePlugin`.
  - Added deterministic escalation triggers:
    - `forceFirstConsult`: Requires consultation via `FunctionCallingConfig(mode: FunctionCallingConfigMode.any, allowedFunctionNames: [toolName])` on the first model turn.
    - `forceOnRepeat`: Detects looping calls with identical serialized arguments (`signature`) exceeding `forceOnRepeat` threshold, setting `pendingForce` for the subsequent model call.
    - `requireConsultBefore`: Refuses gated tools in `beforeToolCallback` with `status: 'consult_required'` until at least one consultation succeeds in the session, up to `maxRefusals`.
    - `maxForced` cap to prevent runaway advisor spend.
    - Lifecycle cleanup in `afterRunCallback` and `close`.
- **Exports**:
  - Exported `ForceEscalationPlugin` in `lib/adk_dart.dart`.
- **Tests**:
  - Added [test/unit3_force_escalation_plugin_test.dart](file:///Users/jaichang/Documents/GitHub/adk-labs/adk-dart/adk_dart/test/unit3_force_escalation_plugin_test.dart) covering turn and session budget tracking, first-consult forcing, tool refusal gating, repeat loop detection, and constructor argument validation (100% pass).

---

## Unit 4: Workflow EdgesBuilder & AgentEngineClient
- **`EdgesBuilder` Fluent Graph Builder (`47214918`, `EdgesBuilder.java`, `EdgesDsl.kt`)**:
  - Created `lib/src/workflow/edges_builder.dart`:
    - `EdgesBuilder`: `from(node)`, `fromStart()`, `fromGroup(nodes)`, `fromNodes(first, second, ...rest)`, `build()`, and `EdgesBuilder.buildEdges((g) { ... })`.
    - `EdgeChain`: `then(next)`, `thenGroup(targets)` / `thenAll(targets)`, `chain(nodes)`, and `route(definition)`.
    - `NodeGroupChain`: `joinTo(join)`.
    - `RouteMap`: `on(route)`, `onAny(routes)`, `otherwise(target, ...rest)`, and `anyOf(routes)`.
    - `RouteMapEntry`: `then(target, ...rest)`.
    - `RouteSet`: Groups multiple route keys into a single route trigger.
  - In `lib/src/workflow/workflow.dart`:
    - Added factory constructor `Workflow.build` with `required void Function(EdgesBuilder g) buildEdges` parameter.
- **`AgentEngineClient` Vertex AI Reasoning Engine / VMaaS Client (`0f28dc95`, `agent_engine_client.ts`)**:
  - Created `lib/src/integrations/vmaas/agent_engine_client.dart`:
    - `AgentEngineConfig`: Connection metadata (`project`, `location`, `reasoningEngineId`, `apiEndpoint`, `accessToken`).
    - `SessionConfig` & `QueryConfig`: JSON-serializable payloads for sessions and model queries.
    - `AgentExecutionError`: Structured exception for remote reasoning engine errors.
    - `AgentEngineClient`: Implements `createSession`, synchronous `query`, and streaming `streamQuery` with SSE chunk and `[DONE]` terminator parsing.
- **Exports**:
  - Exported `EdgesBuilder` in `lib/adk_dart.dart` and `lib/adk_core.dart`.
  - Exported `AgentEngineClient` in `lib/adk_dart.dart`.
- **Tests**:
  - Added [test/unit4_workflow_edges_builder_test.dart](file:///Users/jaichang/Documents/GitHub/adk-labs/adk-dart/adk_dart/test/unit4_workflow_edges_builder_test.dart) covering linear chains, multiple-node chaining, fan-out, fan-in `joinTo`, route maps (`on`, `onAny`, `otherwise`), route map validation errors, `Workflow.build` end-to-end execution, and `AgentEngineClient` session/query/stream execution (9/9 passed).

---

## Unit 5: Sub-package (packages/adk) Web Server & CLI Enhancements
- **Interrupts Indexing & Resolution (`23bc0bb79`, `_interrupts.py`, `cli.py`)**:
  - Created `lib/src/events/interrupts.dart`:
    - `OpenInterrupt`: Metadata class tracking event `author` and hierarchical `ancestorAuthors`.
    - `extractEventInterruptIds`: Extracts IDs from `event.longRunningToolIds` and fallback function calls (`adk_request_input`, `adk_request_credential`, `adk_request_confirmation`).
    - `isInterruptEvent`: Boolean predicate for interrupt events.
    - `indexOpenInterrupts`: Indexes open interrupts across the event sequence, correctly closing answered interrupts when user `FunctionResponse` arrives or when a sub-branch finishes with matching `runId`.
  - In `lib/src/events/node_path_builder.dart`:
    - Added `orderedRunIds` getter to `BranchPath` to extract run IDs embedded in `segment@run_id`.
  - In `packages/adk/lib/src/dev/cli.dart`:
    - Integrated `indexOpenInterrupts` to detect active unanswered interrupts during `adk run`, logging auto-resume messages and forwarding inputs appropriately without mistaking answered pauses for open interrupts.
- **Initial State Seeding from `initial_state.json` (`3c8c63e41`, `dev_server.py`)**:
  - In `packages/adk/lib/src/dev/web_server.dart`:
    - Added `getAgentDir(String appName)` helper to `_AdkDevWebContext`.
    - Added `_loadInitialState(_AdkDevWebContext context, String appName)` to read the optional `initial_state.json` file located next to the agent directory.
    - Updated `_handleLegacyCreateSession`, `_handleCreateSession`, and `_handleCreateSessionWithId` to seed session state with `initial_state.json`, while allowing caller-provided state to override file values key by key.
- **Exports**:
  - Exported `interrupts.dart` in `lib/adk_dart.dart` and `lib/adk_core.dart`.
- **Tests**:
  - Added [test/unit5_interrupts_and_initial_state_test.dart](file:///Users/jaichang/Documents/GitHub/adk-labs/adk-dart/adk_dart/test/unit5_interrupts_and_initial_state_test.dart) covering open interrupt tracking, user response resolution, sub-branch runId resolution, fallback function call extraction, and `initial_state.json` state merge semantics (4/4 passed).

---

---

## Unit 7: Environment Parsing, Eval CLI Exit Code & Live Artifact History Filtering
- **Truthy Environment Variable Parsing & GenAI Strict Mode (`95d621523`, `adk-python`)**:
  - In `lib/src/utils/env_utils.dart`:
    - Updated `isEnvEnabled` to trim whitespace and accept `{'1', 'true', 'yes', 'on'}` case-insensitively, unifying truthy environment variable checks.
    - Added `_isGenaiEnvEnabled` implementing Google GenAI SDK's strict boolean parsing (`['true', '1']` without whitespace trimming or `yes`/`on`) for `GOOGLE_GENAI_USE_ENTERPRISE` and `GOOGLE_GENAI_USE_VERTEXAI`.
- **Eval CLI Exit Code CI Gate (`c2ff63480`, `adk-python`)**:
  - In `packages/adk/lib/src/dev/cli.dart`:
    - Updated `_runEvalCliCommand` to compute `totalFailed` across `summaryByEvalSet`.
    - Returns `(totalFailed > 0 || summaryByEvalSet.isEmpty) ? 1 : 0`, ensuring CI/CD gates fail when test assertions fail or when an empty eval set produces no results.
- **Live Artifact History Exclusion (`29694fa8`, `adk-kotlin` & `content_utils.py`)**:
  - In `lib/src/utils/content_utils.dart`:
    - Added `isAdkLiveArtifactPart(Part part)` to identify internal `artifact://.../_adk_live/...` recordings.
    - Added `filterMediaParts(Content content)` removing audio parts and internal `_adk_live` artifacts while preserving text, images, and documents.
  - In `lib/src/models/gemini_llm_connection.dart`:
    - Used `filterMediaParts` when seeding history to the live session.
  - In `lib/src/flows/llm_flows/contents.dart`:
    - In `getContents`: removed `isAdkLiveArtifactPart` parts before sending contents to LLMs.
    - In `_isPartInvisible`: treated `isAdkLiveArtifactPart` as invisible, while honoring `thoughtSignature`.
    - In `_formatEventForOtherAgent`: skipped `isAdkLiveArtifactPart` when narrating other agent tool results.
- **Tests**:
  - Added [test/unit7_env_and_eval_exit_code_test.dart](file:///Users/jaichang/Documents/GitHub/adk-labs/adk-dart/adk_dart/test/unit7_env_and_eval_exit_code_test.dart) (4/4 passed).

---

## Final Verification & Parity Audit Summary
- **Static Analysis**:
  - `dart analyze` across `adk_dart`: **0 errors, 0 warnings, 0 infos**.
  - `dart analyze` across `packages/adk`: **0 errors, 0 warnings, 0 infos**.
  - `dart analyze` across `packages/adk_litertlm`, `packages/adk_mcp`, `packages/flutter_adk`: **0 errors, 0 warnings, 0 infos**.
- **Test Suite Results**:
  - `test/unit1_core_parity_test.dart`: 2/2 passed.
  - `test/unit2_gemini_speech_test.dart`: 5/5 passed.
  - `test/unit3_force_escalation_plugin_test.dart`: 5/5 passed.
  - `test/unit4_workflow_edges_builder_test.dart`: 9/9 passed.
  - `test/unit5_interrupts_and_initial_state_test.dart`: 4/4 passed.
  - `test/unit7_env_and_eval_exit_code_test.dart`: 4/4 passed.
  - **Total**: 29/29 unit tests passed (100% pass rate).
- **Git Commit Log (Incremental Work Units)**:
  1. `4ded41b`: `feat(core): sync upstream core runtime updates (artifact delta, deleteMemory, JSON Pointer $ref, RunConfig forwarding)`
  2. `cf87870`: `feat(live): add GeminiSTT and GeminiTTS speech transforms for CascadeLive`
  3. `0295d4e`: `feat(plugins): add ForceEscalationPlugin and ModelConsultTool budget tracking`
  4. `99ac06e`: `feat(workflow): add EdgesBuilder fluent graph edge construction and AgentEngineClient`
  5. `572c974`: `feat(cli): support indexOpenInterrupts auto-resume and initial_state.json session seeding`
  6. `68ff677`: `docs(parity): complete upstream parity audit worklog for units 1-5`
  7. `[pending]`: `fix(parity): align truthy env parsing, eval CLI exit code, and live artifact history exclusion`



