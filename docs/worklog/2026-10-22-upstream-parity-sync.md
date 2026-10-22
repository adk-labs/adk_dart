# 2026-10-22 Upstream ADK Parity Sync

## Overview
Synchronized `adk_dart` and `packages/adk` with the latest upstream commits pulled across all 5 ADK reference repositories (`2026-10-16` through `2026-10-22`):
- `adk-python`: `783848821..facd7ddaf`
- `adk-go`: `1d2f5456..889816b7`
- `adk-java`: `97f22a28..aab51efa`
- `adk-js`: `0f28dc95..934d6bf9`
- `adk-kotlin`: `29694fa8..0ee2f30b`

---

## Key Features & Parity Updates

### 1. Features & Warning Suppression (`ea298d4bd`, `b592dee0a`, `ed76f9450`)
- Promoted 12 mature features from `FeatureStage.experimental` to `FeatureStage.stable` (`defaultOn: true`) in `lib/src/features/_feature_registry.dart`: `agentConfig`, `agentState`, `authenticatedFunctionTool`, `baseAuthenticatedTool`, `googleCredentialsConfig`, `googleTool`, `jsonSchemaForFuncDecl`, `mcpGracefulErrorHandling`, `progressiveSseStreaming`, `toolConfig`, `toolConfirmation`, and `pluggableAuth`.
- Added `FeatureName.toolArgsMatcher` (`TOOL_ARGS_MATCHER`, `FeatureStage.experimental`, `defaultOn: false`).
- Added `ADK_SUPPRESS_EXPERIMENTAL_FEATURE_WARNINGS` support via `experimentalWarningSuppressionEnvVar` and `isExperimentalWarningSuppressed()` across `lib/src/utils/env_utils.dart`, `lib/src/features/_feature_registry.dart`, and `lib/src/utils/feature_decorator.dart`.

### 2. Classifiers (`772b5773b`, `ddf8c55eb`)
- Created `lib/src/labs/classifiers/llm_classifier.dart` (`LlmClassifier extends BaseClassifier`) to evaluate `Choice`, `Binary`, and `Score` questions via structured JSON output and normalize probability distributions.
- Created `lib/src/integrations/typesafe/typesafe_classifier.dart` (`TypesafeClassifier extends BaseClassifier`) for TypeSafe Jev models (`/v1/systemone`) with automatic retry on HTTP `429`/`529`.

### 3. Extensible Tool Argument Matcher & Model Consult Observability (`ed76f9450`, `f02b89c39`)
- Created `lib/src/tools/tool_args_matcher/tool_args_matcher.dart` with `ArgMatchResult`, `ToolArgsMatchResult`, `BaseArgMatcher`, `ExactArgMatcher`, `CasefoldArgMatcher`, `NumericArgMatcher`, `ContainsArgMatcher`, `IgnoreArgMatcher`, `registerArgMatcher`, and `ToolArgsMatcher`.
- Created `lib/src/tools/model_consult/observability_plugin.dart` with `ModelConsultUsage`, `ModelConsultStats`, `ModelConsultReport`, and `ModelConsultObservabilityPlugin` to measure primary and advisor model calls, escalations, token usage, and estimated USD cost.

### 4. Isolation Scope, Compaction & State (`8d7445d99`, `dd9ca6fc1`, `2a28c3ede`, `626bd2071`, `662b0175a`)
- Keyed finished isolation scopes by `(scope, invocationId)` and skipped compaction events in `Runner._findActiveTaskScope`.
- Scoped token estimation and sliding-window/token-threshold compaction by `isolationScope`, optimized compaction range subsumption/filtering to $O(N \log N)$ via `_getCompactionRanges` and merged-interval binary search, and paired compacted `FunctionCall`/`FunctionResponse` events by event identity + `callId` so repeated tool call IDs recover the matching turn's call.
- Updated `State.recordNestedWrites()` to skip nested container mutations that do not round-trip through JSON unchanged.

### 5. Agents, Workflow & Live Flow (`6031bb1d7`, `486ef302c`, `6727f8f56`, `7c53386ad`, `3b3de80f1`, `b0e59521d`, `13dde39b6`, `e2dbc0f55`, `a6ed85905`, `4fdca1959`, `17d8a5aea`, `8fbcd42e1`, `da121d7bd`, `c6b8393d`)
- Updated `BaseAgent._validateSubAgentUniqueNames()` to detect duplicate agent names across full sibling subtrees and against the root agent name.
- Ignored `finish_task` when called in the same turn as a task delegation, routed the turn after a paused `single_turn` sub-agent to its delegator, and traversed `Workflow` nodes in `Runner._collectToolsets`.
- Preserved dynamic node `route` and retried failed dynamic runs during replay interception, reserved static ancestor `runId` counters on resume, cloned `FunctionNode` inputs per retry attempt, restored dynamic child run counters on parent retry, required fresh predecessor arrivals for `JoinNode` in loops, and sealed `RouteMap` after `Edges.route()`.
- Created `lib/src/live/visual_frames.dart` (`VisualFrame`, `packVisualFrames`, `unpackVisualFrames`) using uncompressed `ZIP_STORED` archives, skipped `output_schema` request/response processors in live flow, and forwarded `turnComplete`/`interrupted` events after flushing live audio blobs.

### 6. Auth, Models, A2A, Memory, Plugins, Telemetry, Tools & Dev Server (`d32474464`, `7fca46f11`, `cd72afa4f`, `dd80f8f75`, `557743c44`, `8ff99419f`, `5d408696d`, `77a74f020`, `b138b5a6a`, `a4b8ee94c`, `6a77d48cc`, `5762ef81f`, `d5c87a66c`, `bd3853581`, `ead208a47`, `81311b7ab`, `20a5a0cd4`, `30726eaf0`, `57e8bc67f`, `f82aa222f`, `17fb8afc1`, `2802834eb`, `aa9af7bfb`, `52cc2d82a`, `287b7e9a1`, `019b2b21f`, `1def14ba8`, `a468d5a5b`, `b01c5fff5`, `c08225da0`, `18a41a543`, `fa622652`, `36b6f91c`, `d89b915e`, `c240664f`)
- Added `credentialFromString` supporting `apiKey`, `http` bearer (rejecting `basic`), `oauth2`, and `openIdConnect`, and prevented persisting unredeemed OAuth2 auth codes in `CredentialManager`.
- Mapped Anthropic `model_context_window_exceeded` to `MAX_TOKENS`, supported `ThinkingConfig` and streamed `thoughtSignature` preservation in `LiteLlm`, and rejected native `outputSchema` with tools on `gemini-1.*`.
- Shared deterministic UUIDv5 event IDs across streamed A2A artifact chunks and emitted intermediate appended chunks with `partial: !update.lastChunk`.
- Deep-copied `Part` fields in `InMemoryMemoryService` and excluded `thought` parts from memory indexing, `PreloadMemoryTool`, and `ExampleTool` via `extractTextFromContent`.
- Created `lib/src/plugins/callback_helpers.dart` (`ToolResultClassification`, `ToolResultClassifier`, `classifyToolResultError`, `isDurableNodeError`) and integrated across `LoggingPlugin`, `DebugLoggingPlugin`, and `BigQueryAgentAnalyticsPlugin` (plus `evalViewMode`, 403/404/stream error classification, and suffix-based credential redaction), and tracked declined HITL calls in `ReflectAndRetryToolPlugin`.
- Added experimental grounding span attributes (`adk.experimental.grounding.*`) and preserved streaming token usage in `lib/src/telemetry/`.
- Added SSRF protection (`allowPrivateNetworkAccess: false`) to `RestApiTool`, `viewParameters` and trusted `ToolContext` resolution to `BigtableToolset`, MCP auth header precedence & session reaping, `AgentRegistry` runtime reference URI resolution, custom `name`/`description` on `VertexAiSearchTool`, isolated `Random` instances in `AgentSimulatorEngine`, sandbox state verification in `AgentEngineEnvironment`, 300s timeout in `UnsafeLocalCodeExecutor`, lowercase MIME canonicalization in `load_artifacts_tool.dart`, and `/rewind` endpoint + loopback host check in `packages/adk/lib/src/dev/web_server.dart`.

---

## Verification
- `dart analyze` (`adk_dart` & `packages/adk`): **0 issues**
- `dart test` (`adk_dart`): **1,613 passed, 0 failed**
- `dart test` (`packages/adk`): **396 passed, 0 failed**
