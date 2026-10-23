# 2026-10-23 Upstream ADK Parity Sync & Dependency Upgrade

## Overview
Synchronized `adk_dart` and `packages/adk` with the latest upstream commits pulled across all 5 ADK reference repositories (`2026-10-23`):
- `adk-python`: `facd7ddaf..7f3517e43`
- `adk-go`: `889816b7..4df7bdda`
- `adk-java`: `aab51efa..41aa2506`
- `adk-js`: `934d6bf9..bb9a49a5`
- `adk-kotlin`: `0ee2f30b..7d9248f6`

---

## Key Features & Parity Updates

### 1. MongoDB Session Service (`983383519`)
- Added `FeatureName.mongodbSessionService` (`MONGODB_SESSION_SERVICE`, `FeatureStage.experimental`, `defaultOn: true`) and `warnFeatureUse` in `lib/src/features/_feature_registry.dart`.
- Created `lib/src/sessions/mongodb_session_service.dart` (`MongoDbSessionService`, `MongoSessionStore`, `InMemoryMongoSessionStore`) storing sessions, events, `app_states`, and `user_states` in separate collections with `app:` / `user:` / `temp:` state prefix routing, stale session revision checks, and cascading delete.

### 2. Multi-Run Evaluation & Aggregation (`7f3517e43`)
- Created `lib/src/evaluation/multi_run_aggregation_methods.dart` (`MultiRunAggregationMethod`: `meanOverInvocations`, `meanOfRuns`, `minOverRuns`, `passRate`).
- Created `lib/src/evaluation/eval_case_result_multi_run_aggregator.dart` (`EvalCaseResultMultiRunAggregator`, `AggregatedMetricResult`, `MultiRunEvalCaseResult`, `MultiRunEvalSetResult`).
- Updated `EvalMetric`, `EvaluateConfig`, `LocalEvalService`, `AgentEvaluator`, and `packages/adk` CLI (`adk eval --num_runs`) to execute and aggregate multi-run evaluations.

### 3. Prompt Cache Creation Token Count & Anthropic MCP `is_error` (`b89dda409`, `37b1ab3c2`)
- Added `cacheCreationTokenCount` on `LlmResponse` and `Event`, persisted in session schema `v0`, and extracted from Anthropic `cache_creation_input_tokens` and LiteLLM `cache_creation_input_tokens`.
- Propagated MCP tool error flag (`result['isError'] == true`) to Anthropic `tool_result` blocks as `'is_error': true` in `AnthropicLlm`.

### 4. Gemini Client Options & Live Validation (`fb197fa39`)
- Added `clientKwargs`, `buildAdkHttpOptions`, and `withAdkHttpOptions` on `Gemini` in `lib/src/models/google_llm.dart`.
- Added validation in `Gemini.connect` rejecting `liveConnectConfig.httpOptions` with an `ArgumentError`.

### 5. Per-Session Compaction Lock, Isolated Scopes, Remote A2A & Workflow (`933163849`, `471341f28`, `6c672404e`, `a9714eceb`, `9a158552`)
- Added per-session compaction lock (`(appName, userId, sessionId)`) in `lib/src/apps/compaction.dart`.
- Treated `escalate` and error events as terminal outcomes for isolated task scopes in `Runner._findActiveTaskScope`.
- Added `mode` (`'chat'`, `'single_turn'`, `'task'`) to `RemoteA2aAgent` and emitted an error event when a remote A2A task ends in a non-completed state in `task` mode.
- Delegated `ParallelWorker` inner node `retryConfig` to per-item workers.
- Converted live input/output transcription events into conversation context on replay and preserved compaction summary author in `contents.dart`.

### 6. Cross-SDK Parity (`adk-go`, `adk-java`, `adk-js`, `adk-kotlin`)
- Added `handleFunctionCallsLive` (`lib/src/flows/llm_flows/functions.dart`) supporting live `Stream` tool execution, background `Event` forwarding, `stop_streaming` cancellation, and duplicate streaming tool call deduplication (`0355356e`, `0ee2f30b`, `3f1afd0c`).
- Added `BigQueryDropStats`, `exactlyOnceDelivery`, `gcsUploadTimeout` with cooldown window bypass, bounded completed-invocation trace cache for late callbacks, and `popTaskAgentSpan` in `BigQueryAgentAnalyticsPlugin` (`4df7bdda`, `03e41177`, `331c9c57`, `03a62c3f`, `f7db1f4a`).
- Added `Event.nodeName` getter (`52f2be71`), `allowSelfTransfer: true` in `_postprocessLive` (`f4d6de4c`), multi-trigger and `dynamicAuthConfig` schema filtering in `ApplicationIntegrationToolset` (`70944fe4`), `mcpReservedToolNames` filtering on cached tools in `McpToolset` (`509d69d6`), and client disconnect abort listener in `packages/adk/lib/src/dev/web_server.dart` (`1fbe9e034`).

### 7. Full `adk-python` Ecosystem Module Parity (`99301fd`)
- Added `SqliteMemoryService` (`lib/src/memory/sqlite_memory_service.dart`), `ToolCallIntegrityPlugin` (`lib/src/plugins/tool_call_integrity_plugin.dart`), `KmsEncryptor` (`lib/src/auth/kms_encryptor.dart`), `GEPARootAgentOptimizer` (`lib/src/optimization/gepa_root_agent_optimizer.dart`), `ScenarioGenerator` (`lib/src/evaluation/vertex_ai_scenario_generation_facade.dart`), `CloudTtsLlm` (`lib/src/evaluation/simulation/cloud_tts_llm.dart`), `A2aClientInterceptor` (`lib/src/a2a/interceptors.dart`), `AntigravityAgent` (`lib/src/labs/antigravity/`), and integrations for `Firestore`, `Redis`, `MongoDB`, `ModelArmor`, `AgentIdentity`, `ParameterManager`, `SecretManager`, `Gcs`, `E2B`, `LiveKit`, `OCI`, and `OpenAI`.

### 8. Dependency Upgrades & Version Bump (`2026.10.23`)
- Upgraded dependencies across `adk_dart`, `packages/adk`, `packages/adk_mcp`, `packages/adk_litertlm`, and `packages/flutter_adk` to latest stable releases (`archive: ^4.5.2`, `crypto: ^3.0.7`, `googleapis_auth: ^2.3.5`, `http: ^1.6.0`, `postgres: ^3.5.20`, `sqlite3: ^3.7.1`, `unorm_dart: ^0.3.3`, `yaml: ^3.1.4`, `meta: ^1.19.0`, `litertlm: >=0.0.14 <0.1.0`, `web: ^1.1.2`, `analyzer: ^14.6.0`, `lints: ^6.1.0`, `test: ^1.33.0`).

---

## Verification
- `dart analyze --fatal-infos` (`adk_dart`, `packages/adk`, `packages/adk_mcp`, `packages/adk_litertlm`, `packages/flutter_adk`): **0 issues**
- `dart test` (`adk_dart`): **1,682 passed, 0 failed**
- `dart test` (`packages/adk`): **396 passed, 0 failed**
- `flutter test` (`packages/flutter_adk`): **190 passed, 0 failed**
