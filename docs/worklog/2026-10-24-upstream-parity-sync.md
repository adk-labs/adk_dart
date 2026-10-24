# 2026-10-24 Upstream ADK Parity Sync (`adk-python` `v2.13.0`)

## Overview
Synchronized `adk_dart` and its subpackages (`adk`, `adk_mcp`, `adk_litertlm`, `flutter_adk`) with the latest upstream commits pulled from `adk-python` (`7f3517e43..12c7bed76`, including release `v2.13.0`) and `adk-web` (`dfac466d9`).

---

## Key Features & Parity Updates

### 1. Upstream Version Alignment (`ceb0627f1`)
- Updated `adkVersion` to `'2.13.0'` and `adkPackageVersion` to `'2026.10.24'` in `lib/src/version.dart`.

### 2. MongoDB-Backed Memory Service (`cbca417c4`)
- Registered `FeatureName.mongodbMemoryService` (`MONGODB_MEMORY_SERVICE`, `FeatureStage.experimental`, `defaultOn: true`) in `lib/src/features/_feature_registry.dart`.
- Created `lib/src/memory/mongodb_memory_service.dart` (`MongoDbMemoryService`, `MongoMemoryStore`, `InMemoryMongoMemoryStore`, `MongoDbOperationFailure`, `extractKeywords`) supporting Latin and CJK bigram keyword indexing, idempotent `(app_name, user_id, session_id, event_id)` upserts, keyword-overlap ranking, and response deduplication.
- Updated `MongoDbSessionService._ensureInitialized` in `lib/src/sessions/mongodb_session_service.dart` to tolerate `MongoDbOperationFailure` on `createIndexes` while rethrowing unexpected errors.

### 3. BigQuery Agent Analytics Workflow Node Observations (`c31856d17`)
- Updated `BigQueryAgentAnalyticsPlugin` (`lib/src/plugins/bigquery_agent_analytics_plugin.dart`) to record `WORKFLOW_NODE_FIRST_OBSERVED` and `WORKFLOW_NODE_OBSERVATION_SUMMARY` events during workflow runs, capped at `_maxTrackedWorkflowNodesPerInvocation = 1000` with `untracked_node_count` and `untracked_observation_count` overflow tracking.
- Reserved `_reservedTerminalQueueSlots = 16` queue slots for terminal invocation events (`INVOCATION_COMPLETED`, `INVOCATION_ERROR`, `WORKFLOW_NODE_OBSERVATION_SUMMARY`) and added `v_workflow_node_first_observed` and `v_workflow_node_observation_summary` analytics view definitions.

### 4. `AgentTool` Caller `temp:` State Propagation & Isolation (`12c7bed76`)
- Updated `AgentTool.run` (`lib/src/tools/agent_tool.dart`) to pass caller `temp:` state keys via `runner.runAsync(..., stateDelta: tempState)` with shallow copies of mutable containers (`Map`, `List`, `Set`), while filtering out `_adk` / `temp:_adk` internal keys and excluding child `temp:` writes when forwarding `stateDelta` back to the parent `toolContext.state`.

### 5. Connector Tool Name Disambiguation & `McpTool` OAuth2 Guard (`f08f9d677`, `83acbc50f`)
- Added `OpenAPIToolset.getToolsWithPrefix`, `IntegrationConnectorTool.entity` / `operation`, and `disambiguateToolNames` in `ApplicationIntegrationToolset` (`lib/src/tools/application_integration_tool/application_integration_toolset.dart`).
- Updated `McpTool` (`_headersFromCredential` in `lib/src/tools/mcp_tool/mcp_tool.dart`) so an `oauth2` credential with an empty `accessToken` returns empty headers instead of falling back to `credential.http`.

### 6. Failed A2A Task Error Events, `LiteLlm` Quoted Tool Calls & Firestore Empty `userId` Guard (`25d191710`, `6b00a3890`, `b98125006`)
- Added `extractErrorCode` and `extractErrorMessage` (`lib/src/a2a/converters/utils.dart`) and populated `errorCode` and `errorMessage` on `Event` when converting failed A2A `Task` or `TaskStatusUpdateEvent` payloads.
- Updated `LiteLlm` inline tool-call parser (`lib/src/models/lite_llm.dart`) to mask fenced code blocks, inline code spans, and closed `<think>...</think>` blocks so tool call examples quoted in answer text are not executed.
- Guarded `FirestoreSessionService.listSessions` (`lib/src/integrations/firestore/firestore.dart`) to return an empty session list immediately when `userId == ''`.

---

## Verification
- `dart analyze --fatal-infos` (`adk_dart`, `packages/adk`, `packages/adk_mcp`, `packages/adk_litertlm`): **0 issues**
- `dart test` (`adk_dart`): **1,660 passed, 0 failed**
- `dart test` (`packages/adk`): **396 passed, 0 failed**
