# 2026-11-08 Upstream Parity Sync & Release (`2026.11.8`)

## Summary
Synced `adk_dart`, `packages/adk`, and `packages/flutter_adk` against upstream `adk-python` `v2.14.0` (`3640e7d0c74bb2d377a58271ac6290d2e51ee60d..dd7161f7a3875625677b3abbf322c461001c60ba`) and `adk-web` (`dfac466dd9cd6a0a916327411dc117df0ff8c721..07a07025aa84654db88ab0728d6b267bd5742c5c`), modularized large subsystems into focused `part` files with 9 domain-scoped entrypoint barrels, upgraded dependencies to the latest `pub.dev` releases, and released `2026.11.8`.

## Key Changes
1. **Core, Agents, Workflows & Events (`adk-python` `v2.14.0`)**:
   - Added `Event.acceptConvenienceKwargs` (`author`, `text`, `thought`, `functionCall`, `functionResponse`, `customMetadata`), `LlmAgent.rejectMisplacedGenerateContentKwargs` guard (`generationConfig` / `safetySettings` / `thinkingConfig` -> `generateContentConfig`), `AuthHandler.getAuthResponseAsync` async token/state cleanup, and `FileArtifactService` exact line-ending preservation (`5bf4b5d12`, `e69e7db20`, `dd7161f7a`, `7c2b93909`).
   - Added `ReplayManager` `waitForOutput` resume guard (`_resuming` check), `Workflow` subagent recursion cycle guard, and A2A `buildA2aServerUrl` / `extractA2aTasksPath` reverse-proxy path routing (`ec3de1446`, `6ef1682d6`, `56202b36e`).
2. **Models, Plugins, Integrations & Telemetry**:
   - Added `LlmRequest.toGenerateContentBody()` (`lib/src/models/generate_content_body.dart`) for official Gemini wire-format serialization (`0622d48ca`).
   - Added `LiteLlm` system/developer prompt collapse on legacy models, `Gemini` non-empty `Part` validation, `VertexAiSessionService` empty content part pruning, `ReflectAndRetryToolPlugin` retry warning state persistence, `AgentSimulatorPlugin` multi-turn session injection, and `SqliteMemoryService` CJK bigram tokenization (`75fc85319`).
3. **Tools, MCP, Evaluation & CLI/Web (`packages/adk`)**:
   - Added `BaseTool.displayTitle` (`adk:tool_display_names` metadata), `FunctionTool` enum confirmation wire values, automatic MCP session recreation on server termination, and `OpenApiSpecParser` recursive multi-document `$ref` resolution (`b7bf023db`, `8136ca543`, `2a0866cf7`).
   - Added `pass@k` (`>= 1` pass) and `pass^k` (all `k` pass) multi-run evaluation criteria in `lib/src/evaluation/multi_run_eval.dart` (`b8a42797c`).
   - Achieved 1:1 `adk-python` CLI module parity (`adk generate_agent_card`, `adk optimize`, `adk eval_set`, HTTP 500 unconfigured eval manager guard, UTF-8 `data:` URL decoding in Web UI) (`e3e72dd24`, `07a07025a`).
4. **Flutter UI Kit (`packages/flutter_adk`)**:
   - Added 10 specialized tool, usage, compaction, and evaluation widgets (`AdkUsageMonitorCard`, `AdkContextWindowMeter`, `AdkSkillToolCard`, `AdkFileEditCard`, `AdkShellCommandCard`, `AdkWebPageCard`, `AdkComputerActionCard`, `AdkCompactionSummaryCard`, `AdkReflectRetryBanner`, `AdkMultiRunEvalCard`) and `AdkCardStyle` theme customization.
   - Added `AdkTokenUsage.cacheCreationTokens`, `AdkToolCallInfo.displayTitle`, `AdkChatMessage.toolDisplayTitle`, `pass@k` / `pass^k` & `[INFO]` badges on `AdkMultiRunEvalCard`, `AdkFormatters.decodeDataUrlTextUtf8`, `AdkFormatters.encodeArtifactFilename`, `AdkEventStreamUtils.extractVisibleText`, `AdkEventStreamUtils.isAbortedEvent`, and `AdkEventStreamUtils.detectSystemInstructionChangesByAgent`.
5. **Architecture Modularization & Dependency Upgrades**:
   - Added 9 selective domain entrypoints (`package:adk_dart/{agents,workflow,evaluation,tools,models,sessions,integrations,a2a,telemetry}.dart`) and modularized `workflow.dart`, `bigquery_agent_analytics_plugin.dart`, `lite_llm.dart`, `cli.dart`, and `web_server.dart` using `part` / `part of`.
   - Upgraded `crypto` (`^3.0.8`), `googleapis_auth` (`^2.3.7`), `postgres` (`^3.6.0`), `sqlite3` (`^3.9.0`), `archive` (`^4.6.0`), `analyzer` (`^14.7.0`), `cupertino_icons` (`^2.0.0`), and `lints` (`^6.1.0`).
