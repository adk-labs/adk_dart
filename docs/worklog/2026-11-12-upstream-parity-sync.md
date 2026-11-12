# 2026-11-12 Upstream Parity Sync & Release (`2026.11.12`)

## Summary

Synced `adk_dart`, `packages/adk`, `packages/adk_mcp`, `packages/adk_litertlm`, and `packages/flutter_adk` against upstream `adk-python` (`67b217d00668400383a5dc8ef1b241c8fb114b31..df9f9d0452c02e2d461899f34acfb756e9612746`, 47 commits across 67 `src/` files) and `adk-web` (`07a07025a71c86f2c66da39cbef1f441bcdb28d6..969cee92b7e249f4b66c3de1f2d354ab012fc0ce`, 2 commits), rebuilt the bundled `adk-web` static UI assets, updated `flutter_adk` widgets and helpers, and released `2026.11.12`.

## Upstream Reference Heads

- `adk-python`: `df9f9d0452c02e2d461899f34acfb756e9612746`
- `adk-web`: `969cee92b7e249f4b66c3de1f2d354ab012fc0ce`

## Key Changes Ported

1. **Core, Agents, Workflows, Events, Auth, Plugins & Sessions (`c2f9b41c`)**:
   - `LangGraphAgent` structured content-block reply extraction (`079586136`).
   - `FinishTaskTool` `skipSummarization` and `afterAgentCallback` execution for delegated task agents and `Workflow` task nodes (`fa647fcc1`).
   - `single_turn` transfer target reply forwarding in `Workflow` (`b4126cddb`).
   - `LlmAgent.clone` mode-tool reconstruction for cloned sub-agents (`61a4dc642`).
   - Off-turn async service-account & OpenAPI credential exchange (`9651df04d`).
   - Open long-running call preservation (`guardedCallIds`) on external cancellation, raw string preservation for `RequestInput` string schemas, and error `FunctionResponse` interrupt clearing (`e1e231cb3`, `b989d6849`, `efc7717bf`).
   - Artifact-free code execution when no files are written, `DebugLoggingPlugin.onRunErrorCallback`, `InMemorySessionService.deleteSession` map pruning, `Workflow` multi-route deduplication, and `rerunOnResume: false` node error naming (`9687bae1c`, `9e549adf7`, `c0bcdaa48`, `dc7d7431a`, `ba43b4f0a`).
2. **Environments & Integrations (`babbb857`)**:
   - `{Context? ctx}` and lazy tool-call initialization (`ensureInitialized`, `closeIfInitialized`) across `BaseEnvironment`, `LocalEnvironment`, `DaytonaEnvironment`, `E2bEnvironment`, `OpenSandboxEnvironment`, `AgentEngineEnvironment`, and `EnvironmentToolset` (`1bd22e34d`, `61efa3003`).
   - Full `FsspecArtifactService` write, delete, version metadata, Rapid GCS streaming, `artifact://` reference resolution, and rewind tombstone support (`df9f9d045`).
3. **Models, Memory, Live, Antigravity & Optimization (`fd75efe6`)**:
   - Streamed parallel tool call separation & ordering in `OciGenAiLlm`, empty non-`STOP` Claude error reporting in `AnthropicLlm`, `cached_content_token_count` on `AntigravityAgent`, `cascadeLiveClientLabel` telemetry in `CascadeLiveConnection`, mixed-script query splitting in `InMemoryMemoryService`, per-`Zone` `VertexAiRagClient` reuse, and clean optimization JSON schemas (`353a771d7`, `583900785`, `cd8debd2e`, `9620b4296`, `e9f9790f9`, `112491db8`, `3bb410c90`).
4. **Tools & Evaluation (`110521f2`)**:
   - Configurable `ToolParameterMatchEvaluator` (`tool_parameter_match`, `ToolParameterMatchCriterion`) with `exact`, `inOrder`, and Kuhn-Munkres `anyOrder` matching (`04ba41209`).
   - `hallucinations_v1` unlabelled-sentence handling, framework client function-call filtering, `null` vs `{}` tool arg equivalence in `TrajectoryEvaluator`, and `EvalCaseResult.sessionDetails` retention (`59b0dd63c`, `825a3747e`, `6e448cf59`, `f1b1f9d96`).
   - `LoadSkillTool` bundled `resources` listing, `BaseToolset.disableInvocationCache`, `McpToolset.useMcpResources`, `ApiParameter.required` serialization, `removeAnyOf` first non-null union selection, and bounded `ConnectionsClient` polling (`c41bc42fb`, `b979abe57`, `b79c529b5`, `e5ffe9c9d`, `ca42dcd18`, `ab6384438`).
5. **CLI, Dev Web Server, `adk-web` & `flutter_adk` (`b667da04`)**:
   - `POST /agent-identity/finalize` v1 client (`AuthProviderCredentialsServiceClient`), Agent Engine server trace-continuation disablement (`GOOGLE_CLOUD_AGENT_ENGINE_ID`), `.agent_engine_config.json` `display_name` precedence, standalone `BaseNode` / `Workflow` loader support, rebuilt `adk-web` bundle (`6528d2f`, `969cee9`), and `AdkSkillToolCard` / `AdkFormatters.centeredPopupFeatures` in `flutter_adk` (`f0eb6139c`, `88b3afe70`, `319b5a70e`, `f0086e3f4`).
