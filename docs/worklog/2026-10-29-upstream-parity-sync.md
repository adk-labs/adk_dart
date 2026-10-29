# 2026-10-29 Upstream Parity Sync & Release (`2026.10.29`)

## Summary
Synced `adk_dart` and `packages/adk` against upstream `adk-python` (`12c7bed7661ccf942f0f6d3b62bed22a23ea0a85..3640e7d0c74bb2d377a58271ac6290d2e51ee60d`, 66 `src/` commits) and `adk-web`, verified Effective Dart documentation guidelines across all public symbols, and released `2026.10.29`.

## Key Changes
1. **Core, Context, Plugins & Compaction**:
   - Added `CallbackType`, `CallbackInfo`, `Context.callbackInfo`, and `runWithCallbackScope` (`c19e10c05`).
   - Added `ReflectAndRetryModelPlugin` and updated `ReflectAndRetryToolPlugin` to reset consecutive failure counters on paused/resumable turns (`c9c0e6c78`, `f1d8c7b7d`).
   - Added `applyRewinds` and `getActiveEvents` (`lib/src/events/rewind_events.dart`) and paired `FunctionCall` / `FunctionResponse` events across compaction boundaries (`158b1f4c2`, `c5096ca52`).
   - Elided quote and system-instruction boundary markers across non-text relayed `Part` payloads (`3640e7d0c`).
   - Encoded `/` and `%` in `InMemoryArtifactService` scope segments (`27cdf7fb5`).
2. **Workflows, Memory & Live Audio**:
   - Added `NodePathBuilder`, `requireConfirmation` on `FunctionNode`, `maxParallelWorkers` on `ParallelWorker`, `validateNodeData` on `AgentNode`, task-mode agent serialization while waiting, sibling batch completion on failure, and loop re-iteration invalidation on workflow resume (`4e1df8bb7`, `df29b50b5`, `d509de7f2`, `519468942`, `d17cb3e24`, `98945ef1c`, `7a2835b7c`, `61d997367`).
   - Filtered rewound events and stripped `thought` parts in `InMemoryMemoryService` and `SqliteMemoryService` (`a859a32f9`).
   - Split `AudioCacheManager` flush into separate user and model events when trailing model audio lacks a transcription flush (`cf89d3e8f`).
3. **Models, Telemetry, Skills & Sandboxes**:
   - Normalized upper-case schema `type` values in `AnthropicLlm`, preserved non-UTF-8 function argument strings in `LiteLlm`, stripped trailing `/v1` in `GemmaLlm` vertex endpoints, and rejected empty `CustomMetadata` keys in `Gemini` (`c1b9769d3`, `a7c454a02`, `fb9b88dc0`, `a325c6c07`).
   - Recorded OpenTelemetry LLM operation duration, token usage, and time-to-first-chunk histograms, and hardened `SqliteSpanExporter` against corrupt JSON rows (`4c22083a2`, `54dc88bd0`).
   - Promoted all 16 toolset and integration features to `FeatureStage.stable` (`799fc9459`).
   - Added `FeatureName.snakeCaseSkillName`, bundled `loadBigQuerySkill` (`bigquery-ai-ml`), added `AgentRegistry` GCP IAM connector auth binding helpers, and isolated `DaytonaEnvironment` / `OpenSandboxEnvironment` working directories (`ce9a45bd7`, `a8d1a1f71`, `bc2984e6d`, `6c8f392a2`).
4. **Tools, OpenAPI, Evaluation & CLI/Web**:
   - Returned structured validation error dictionaries on `AgentTool` `inputSchema` failures, forwarded caller token-threshold compaction into nested `AgentTool` sessions, added `processArtifactNames` hook to `LoadArtifactsTool`, rejected backslashes in URL authority in `loadWebPage` and `RestApiTool`, marked `BaseRetrievalTool` `query` as required, and supported OpenAPI query parameter `style` / `explode` serialization (`95dd267c2`, `ae8323b6d`, `0c053dd5a`, `4d0cd985f`, `5cc364b75`, `1d81896aa`).
   - Added `Enum` tool argument conversion in `FunctionTool` and aliased field normalization in `SetModelResponseTool` (`82fe029b8`, `3700f0d1b`).
   - Updated `parseCritique`, `RougeEvaluator`, `ResponseEvaluator`, `AgentEvaluator.evaluateEvalSet`, and `RubricBasedMultiTurnTrajectoryEvaluator` (`4c66a0091`, `571670d9f`, `ce92e9247`, `047815043`).
   - Hardened `adk web` / `adk api_server` (`--avatar_config`, `file://` eval storage URIs, foreign origin protection for special agents and `/dev/*`, and `/run_live` WebSocket `1007`/`1011` close handling) (`27dda3e11`, `ff66b1f17`, `b7ac5ef75`, `3b227d6ec`).
