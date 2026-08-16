## Unreleased (Upcoming 2026.8.17)

- Synced latest core features & bug fixes from `adk-python` v2.7.0, `adk-js` v1.6.0, `adk-go` v2.2.0, and `adk-kotlin` v0.7.0:
  - Added `LlmCapabilities` (`lib/src/models/capabilities.dart`) model feature capability reporting system and updated `BaseLlm.capabilities` & `Gemini.capabilities`.
  - Added `GetUserChoiceTool` (`lib/src/tools/get_user_choice_tool.dart`) with `getUserChoice` callable helper for user choice prompts.
  - Enhanced `FunctionTool` with self-correction feedback returned to the model when mandatory `required` parameters are missing.
  - Added 20MB file size guard (`maxArtifactSizeBytes = 20 * 1024 * 1024`) to `SaveFilesAsArtifactsPlugin` to protect against oversized artifact payloads.
  - Supported multimodal media extraction (`FunctionResponse.parts`) from tool execution results in `functions.dart`.
  - Added automatic orphaned `function_response` pruning (`_dropOrphanedFunctionResponses`) in `ContentsLlmRequestProcessor` (`contents.dart`).
  - Improved `InMemoryMemoryService` with tuple record keys (`(appName, userId)`) to prevent delimiter collisions when identifiers contain slashes.
  - Enhanced `StreamingResponseAggregator` to preserve `thoughtSignature` across streamed text chunk runs without premature buffer flushing.
  - Aligned Gemini EAP model detection regex in `model_name_utils.dart` (`r'^gemini-(?:[a-z0-9_]+(?:-[a-z0-9_]+)*-)?early-exp\d*$'`).
  - Added `StaleSessionError` (`lib/src/errors/stale_session_error.dart`) for optimistic concurrency write conflicts in database and SQLite session services.
  - Synced latest compiled `adk-web` UI assets (`lib/src/cli/browser/`) supporting telemetry consent modal, GA4 analytics instrumentation, live audio eval UI, and 3-legged AuthManager OAuth flow.
  - Implemented `/config/telemetry` (GET and POST) endpoint in `startAdkDevWebServer` with CSRF header check (`x-adk-telemetry-request: true`) and local config persistence (`lib/src/utils/telemetry_config.dart`).
  - Added unit test coverage in `test/upstream_v2_7_parity_test.dart`, `test/telemetry_config_test.dart`, `test/get_user_choice_tool_test.dart`, `test/capabilities_test.dart`, and `test/function_tool_mandatory_args_test.dart` (1,506 total tests passing).

## 2026.7.30

- Bumped package release versions to `2026.7.30` for `adk_dart`, `adk`, `adk_mcp`, `flutter_adk`, and `adk_litertlm`.
- Added `ReflectAndRetryModelPlugin` (`lib/src/plugins/reflect_retry_model_plugin.dart`) for framework-level LLM error recovery, self-healing reflection tool calls (`adkHandleModelError`), and retry tracking.
- Added `FunctionTool` declaration caching (`_cachedDeclaration`) to eliminate redundant parameter schema rebuilds during agent turns.
- Standardized `SessionNotFoundError` handling across session services, agent runners, and dev web server.
- Updated MCP protocol support to official specification version `2026-07-28` (`mcpLatestProtocolVersion = '2026-07-28'`).
- Added `elicitationCallback` support (`elicitation/create` and `notifications/elicitation/complete`) to `McpToolset` and `McpSessionManager` for client-side user input & OAuth challenge handling.
- Added `AdkAgentMcpServer` (`lib/src/tools/mcp_tool/agent_to_mcp.dart`) to expose any ADK `BaseAgent` as a compliant MCP server over tool interfaces.
- Implemented `LoadWebPageTool` and `EnterpriseWebSearchTool` (ported from `adk-js`) for web scraping with SSRF prevention and Vertex AI search grounding.

## 2026.7.24

- Bumped package release versions to `2026.7.24` for `adk_dart`, `adk`, `adk_mcp`, `flutter_adk`, and `adk_litertlm`.
- Synced latest core features & bug fixes from `adk-python` (`be5828f3..07455ee6`):
  - Added user labels (`labels`) support in `RunConfig` and automatic merging in `BasicLlmRequestProcessor` to propagate Vertex AI billing/attribution labels.
  - Guarded resumable invocation replay in `BaseLlmFlow` against partial streaming function-call SSE events to prevent replay loops.
  - Expanded `AnthropicLlm` `finishReason` mapping to support `pause_turn` (`STOP`) and `refusal` (`SAFETY`).
  - Fixed `VertexAiSessionService.getSession` to apply `afterTimestamp` server-side filtering alongside `numRecentEvents`.
  - Added opt-in `finalResponseToolNames` to `BigQueryAgentAnalyticsPlugin` to log final answer tool call payloads as `AGENT_RESPONSE` events.
- Added comprehensive unit test suite in `test/python_upstream_updates_test.dart` (1,105 total unit tests passing).
- Fixed nested workflow resume by yielding resolved outputs of resumed request-input nodes on resume instead of skipping them.
- Fixed `AgentNode.run` event loop to not misclassify `endOfAgent` and `agentState` checkpoint events as `finalEvent`.
- Enhanced `LoadArtifactsTool` with Gemini unsupported inline MIME type blocklist (SVG/XML image variants) to deliver them as text.
- Rebuilt and updated the bundled Web UI assets (`adk-web`) to the latest version to support nested navigation breadcrumbs, bidi streaming restarts, and usage token counts.
- Renamed the `example` folder to `examples` and reorganized all code examples into self-contained, user-friendly Dart project templates with individual `README.md` and dependency setup files in 4 languages (KO, EN, JA, ZH).
- Implemented a default HTTP completions invoker inside `LiteLlm` supporting streaming (SSE) and non-streaming requests to connect out-of-the-box with Ollama and LiteLLM servers.
- Added new local model examples: `08_local_llm_ollama_litellm` (Ollama/LiteLLM integration via `LiteLlm` client) and `09_local_llm_litert` (on-device Gemma inference via `adk_litertlm` sub-package).

## 2026.7.11

- Bumped package release versions to `2026.7.11` for `adk_dart`, `adk`, `adk_mcp`, `flutter_adk`, and `adk_litertlm`.
- Added ADK 2.0 Managed Agent support: `ManagedAgent` and `RemoteMcpServer` for server-side tool execution via the GCP Interactions API.
- Added `environmentId` propagation across `LlmResponse`, `Event`, session persistence, and telemetry tracing.
- Added `isManagedAgent` toggle to `LlmRequest` for grounding tool check bypass in managed workflows.
- Updated `InteractionsProcessor.findPreviousInteractionState` to return both `previousInteractionId` and `environmentId` for turn-to-turn chaining.
- Added `isEnterpriseModeEnabled` helper in `env_utils.dart`.
- Added ADK 2.0 Workflow & Managed Agent documentation to README (EN/KO).
- All 1,365 tests passing.

## 2026.6.6

- Bumped package release versions to `2026.6.6` for `adk_dart`, `adk`, `adk_mcp`, and `flutter_adk`.
- Updated the exported ADK runtime baseline version to `2.2.0` to match the current local `adk-python` reference baseline.
- Added broad workflow parity coverage, including workflow nodes, routed edges, dynamic run IDs, request-input helpers, retry/cancellation/concurrency handling, terminal-output ownership, replay/resume/rehydration, nested workflow events, graph serialization, and status-aware graph DOT output.
- Expanded runtime event and conversion parity with structured events, node path building, A2A part metadata preservation, Event convenience routing, and output-key callback visibility coverage.
- Added and exposed newer integration/tool surfaces, including GCP Skill Registry, BigQuery integration exports, environment tools, public skill tools, URL/load-web-page handling, Vertex RAG retrieval updates, and OpenAI labs adapter support.
- Hardened model, streaming, and tool-call behavior across Gemini schemas, Anthropic/LiteLLM/Apigee paths, REST streaming function continuations, streaming tool-call preservation, and cooperative abort handling.
- Added telemetry/plugin parity updates, including metrics instrumentation, auto tracing plugin support, BigQuery analytics hardening, and save-files-as-artifacts behavior updates.
- Refreshed `flutter_adk` example and documentation surface and consolidated repository documentation under `docs/knowledge` and `docs/worklog`.

## 2026.4.17

- Bumped package release versions to `2026.4.17` for `adk_dart`, `adk`, `adk_mcp`, and `flutter_adk`.
- Updated the exported ADK runtime baseline version to `1.31.0` to match the current `adk-python` main baseline.
- Rolled the release forward with the latest live runtime parity fixes, including reconnect control-flow hardening, `goAway` surfacing, and remaining session/runtime parity closures.

## 2026.3.21

- Bumped package release versions to `2026.3.21` for `adk_dart`, `adk`, `adk_mcp`, and `flutter_adk`.
- Added latest parity coverage for session persistence and storage safety, including stricter stale-session detection, Vertex AI session metadata round-tripping, LiteLLM Anthropic thinking-block support, and Spanner `database_role` propagation.
- Added March 18-19 parity coverage for the experimental `SpannerAdminToolset`, including admin client/runtime factories, bootstrap wiring, and regression tests.
- Added `environment_simulation` rename-compatible exports and factory aliases on top of the existing agent simulator runtime.
- Hardened Anthropic tool-result serialization so arbitrary map/list payloads are emitted as JSON instead of lossy stringified Dart map text.
- Closed the latest four-day parity tail by adding MCP sampling callback/capability wiring across `adk_mcp`, `McpSessionManager`, and `McpToolset`, with HTTP integration coverage.
- Added multi-turn evaluation metric support for task success, trajectory quality, and tool-use quality, including registry/metric-info wiring and regression tests.
- Added Slack runner, Agent Registry integration, and GCP IAM connector compatibility surfaces to close remaining 3/19 runtime gaps.
- Added latest ref parity updates for A2A action-metadata round-tripping, `toA2a(..., lifespan: ...)`, compaction safety around pending function calls, structured Discovery Engine datastore fallback, and feature-gated `snake_case` skill names.
- Added import-path compatibility exports for CrewAI and LangChain integrations under `src/integrations/...`.

## 2026.3.13

- Bumped package release versions to `2026.3.13` for `adk_dart`, `adk`, `adk_mcp`, and `flutter_adk`.
- Expanded the post-`2026.3.6` Python parity rollout across skills runtime/GCS loading, API Registry discovery, A2A resume and long-running execution, Anthropic runtime transport/streaming, GEPA root-agent optimization, and BigQuery analytics view automation.
- Added March 10-12 parity updates covering auth provider registry resolution, MCP UI widget actions, optimize CLI/local eval sampling, OpenAPI/artifact ordering fixes, Gemini live grounding metadata, LiteLLM thought signatures, and conformance SSE record/test flows.
- Aligned tail parity for agent version propagation and telemetry, context UI widget handling, Apigee reasoning token usage parsing, LiteLLM output schema with tools, positional `adk conformance record <path> [none|sse]` parsing, and MCP schema-aware function declarations.

## 2026.3.6

- Bumped package release versions to `2026.3.6` for `adk_dart`, `adk`, `adk_mcp`, and `flutter_adk`.
- Fixed nested `.adk/session.db` path creation when app directory mappings resolve to absolute agent paths.
- Applied the March Python parity batch covering temp-scoped session state visibility, `listAgents()` agent filtering, `gen_ai.agent.version` telemetry, LiteLLM `reasoning` parsing, and Bigtable cluster metadata tools.

## 2026.3.2+4

- Added Python-style positional deploy target support: `adk deploy cloud_run|agent_engine|gke` in addition to `--target`.
- Added deploy CLI regression coverage for positional target parsing and execution.

## 2026.3.2+3

- Implemented `adk conformance test --mode live` execution path so discovered conformance specs are run against the target ADK server instead of returning a placeholder failure.
- Added live-mode CLI regression coverage with an in-process ADK web server and a real `spec.yaml` case.

## 2026.3.2+2

- Fixed `adk web`/`adk api_server` project loading to use the same agent-root resolution path as `adk run`, preventing unintended fallback to demo-time responses.
- Added `/run` request support for per-request `auto_create_session`/`autoCreateSession` overrides and automatic missing-session creation when enabled.
- Added regression coverage for `/run` auto-session creation and verified search-grounding tool wrapping parity (`VertexAiSearchTool` -> `DiscoveryEngineSearchTool`) in multi-tool bypass mode.
- Completed Effective Dart API doc-comment coverage for public declarations across `adk_dart`, `adk`, `adk_mcp`, and `flutter_adk` (`lib` surfaces).

## 2026.3.2+1

- Bumped package release versions using build metadata (`2026.3.2+1`) for `adk_dart`, `adk`, `adk_mcp`, and `flutter_adk`.
- Improved `adk` CLI parity for `run`/`web`/`conformance` flows to better match `adk-python` behavior.
- Fixed `adk run .` project path resolution when running from the agent directory.
- Updated conformance client/server wiring (`/apps/.../sessions`, `/run_sse`) and replay validation/report handling, including non-zero exit on test failures.
- Hardened local `.adk` path handling and project directory validation, with expanded CLI/web regression tests.

## 2026.3.2

- Bumped package release versions to `2026.3.2`.
- Updated cross-package dependency alignment (`adk_dart` / `adk` / `adk_mcp` / `flutter_adk`) for the new release.

## 2026.3.1

- Hardened A2A push callback delivery with a persistent SQLite queue, retry/backoff policy handling, startup/background drain, and dead-letter capture.
- Added A2A delivery reliability coverage in `test/dev_web_server_test.dart`, including persisted queue replay after restart.
- Added live network backend integration tests for PostgreSQL/MySQL session services (env-gated via `ADK_TEST_POSTGRES_URL` / `ADK_TEST_MYSQL_URL`).
- Added unified runtime adapter bootstrap APIs: `configureToolRuntimeBootstrap(...)` and `resetToolRuntimeBootstrap(...)`.
- Added global default audio recognizer registration support via `AudioTranscriber.registerDefaultRecognizer(...)`.
- Added bundled default runtime clients for BigQuery, Bigtable (admin/data), and Spanner (REST-based), removing mandatory client-factory injection for core paths.
- Added token resolution fallbacks for default cloud clients (explicit oauth token, environment variables, gcloud ADC, metadata server).
- Added built-in default Spanner embedder runtime via Vertex AI predict API (with env/full-model resource fallback handling and explicit fallback guidance).
- Added built-in default Toolbox HTTP delegate (`/api/toolset/*`, `/api/tool/*/invoke`) so `ToolboxToolset` can run without pre-registered delegate wiring.
- Added built-in live HTTP/auth providers in `GcsArtifactService`, removing mandatory provider injection for direct service usage.
- Ported telemetry parity for inference span/experimental semconv paths and added regression coverage.
- Added telemetry parity worklog and aligned package release versions to `2026.3.1`.
- Updated parity tests to validate concrete default Bigtable/Spanner client availability.
- Refreshed runtime checklist and README feature matrix to reflect current implemented behavior.

## 2026.2.28

- Switched package versioning scheme to date-based `YYYY.M.D`.
- Expanded `adk web` / `adk api_server` parity surface with bundled `/dev-ui` serving and broader API route compatibility.
- Hardened MCP transport/session behavior through `adk_mcp` integration updates and related tests.
- Replaced deprecated `mysql1` runtime dependency with `mysql_client_plus` in network session backend wiring.
- Added MySQL secure-fallback connect behavior for auth plugins that require TLS (for example `caching_sha2_password`).
- Added MySQL TLS hardening options (`ssl_ca_file`, `ssl_cert_file`/`ssl_key_file`, `ssl_verify`) with fail-fast validation for invalid TLS file configuration.
- Added runtime gap audit document for remaining non-functional/default-unwired features.

## 0.1.2

- Added package topics metadata on pub.dev to improve discoverability.

## 0.1.1

- Expanded Python parity coverage across evaluator workflows and remote code executor paths.
- Added parity ports for model contracts and toolset stacks, including Google API, Pub/Sub, and OpenAPI integrations.
- Added Spanner, Bigtable, and BigQuery client/toolset parity layers with vector store and metadata/query support.
- Added session schema/migration utilities and missing shared utility modules.

## 0.1.0

- Bootstrap `adk_dart` package as an ADK core runtime port (based on `ref/adk-python`).
- Added core agent/session/event/tool/model abstractions and execution flow.
- Added `Runner` / `InMemoryRunner` with async invocation path.
- Added function-call orchestration in LLM flow.
- Added baseline tests for event behavior, session service, and runner flow.
