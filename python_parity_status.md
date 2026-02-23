# ADK Dart Python Parity Status

Last updated: 2026-02-23
Reference: `ref/adk-python/src/google/adk`

## Core Runtime

- [x] agents
- [x] events
- [x] sessions (in-memory + local persistence facades)
- [x] runner (in-memory)
- [x] base tools / function tools
- [x] base plugins
- [x] artifacts (in-memory)
- [x] dev CLI (`create`, `run`, `web`, `api_server` alias)

## Newly Added Foundation (this iteration)

- [x] memory base + in-memory service
- [x] auth credential models
- [x] credential service base + in-memory + session-state
- [x] telemetry base + in-memory trace service
- [x] evaluation base + local evaluator skeleton
- [x] code executors base + unsafe local executor
- [x] dependencies container skeleton
- [x] platform runtime environment skeleton
- [x] feature flags skeleton
- [x] planner skeleton (rule-based)
- [x] optimization skeleton
- [x] skills registry skeleton
- [x] A2A in-memory router skeleton

## Newly Added Agent Config Parity (this iteration)

- [x] agent config contracts (`ArgumentConfig`, `CodeConfig`, `AgentRefConfig`, `BaseAgentConfig`)
- [x] specialized config models (`LlmAgentConfig`, `LoopAgentConfig`, `ParallelAgentConfig`, `SequentialAgentConfig`)
- [x] config union/discriminator parity (`AgentConfig`, `agentConfigDiscriminator`)
- [x] context cache/transcription contracts (`ContextCacheConfig`, `TranscriptionEntry`)
- [x] config runtime loader parity (`fromConfig`, `resolveAgentReference`, `resolveCodeReference`, callback resolution)
- [x] dependency-free YAML decoding path for ADK-style config files
- [x] streaming helper parity (`ActiveStreamingTool`)
- [x] MCP instruction provider parity (`McpInstructionProvider`) with prompt-resource interpolation
- [x] parity regression tests for config normalization/validation/loading/custom-factory hooks

## Newly Added Utility Parity (this iteration)

- [x] environment flag helper parity (`utils/env_utils.isEnvEnabled`)
- [x] model-name utility parity (`extractModelName`, `isGeminiModel`, `isGemini1Model`, `isGemini2OrAbove`)
- [x] Gemini model-id check flag parity (`isGeminiModelIdCheckDisabled`)
- [x] context management utility parity (`Aclosing`, `withAclosing`)
- [x] feature-gate utility parity (`workingInProgress`, `experimental`)
- [x] YAML utility parity (`loadYamlFile`, `dumpPydanticToYaml`)
- [x] version constant parity (`adkVersion`)
- [x] content audio filtering parity (`isAudioPart`, `filterAudioParts`)
- [x] Google LLM variant parity (`GoogleLLMVariant`, `getGoogleLlmVariant`)
- [x] output-schema compatibility parity (`canUseOutputSchemaWithTools`)
- [x] utility regression tests for env/model helpers

## Newly Added Skills Parity (this iteration)

- [x] skill frontmatter/resource models (`Frontmatter`, `Resources`, `Script`, `Skill`)
- [x] skill directory loading (`loadSkillFromDir`) from `SKILL.md` + resources
- [x] skill directory validation (`validateSkillDir`)
- [x] frontmatter-only property read (`readSkillProperties`)
- [x] skill prompt XML formatter (`formatSkillsAsXml`)
- [x] Python-parity tests for skills models/utils/prompt

## Newly Added Auth Flow Parity (this iteration)

- [x] credential exchanger interfaces + registry
- [x] credential refresher interfaces + registry
- [x] oauth2 exchanger/refresher hooks (pluggable handlers)
- [x] service-account exchanger hook + registry wiring
- [x] credential manager workflow (`requestCredential`, load/exchange/refresh/save)
- [x] stable auth credential key generation + auth response state key helper
- [x] auth request preprocessor (parse auth response + resume tool call)
- [x] auth handler (`generateAuthRequest` + auth response persistence)
- [x] auth tool arguments model (`AuthToolArguments`)
- [x] credential manager tests (load/exchange/refresh/request)

## Newly Added LLM Flow Parity (this iteration)

- [x] single flow request processor chain bootstrap
- [x] `basic` request processor (model/config/output schema baseline)
- [x] `instructions` request processor (global/static/dynamic instruction append)
- [x] `identity` request processor (agent identity injection)
- [x] `contents` request processor (event filtering + branch isolation + compaction-aware context build)
- [x] `compaction` request processor (token-threshold pre-compaction hook)
- [x] `context_cache_processor` (cache config/metadata and previous token count wiring)
- [x] `interactions_processor` (previous interaction id extraction)
- [x] `_code_execution` request processor baseline (code-execution result -> text context conversion)
- [x] `_code_execution` response processor baseline (fenced code execution loop + result event emission)
- [x] `_output_schema_processor` request behavior (`set_model_response` tool injection)
- [x] structured output finalization (`set_model_response` function-response -> final model text event)
- [x] `request_confirmation` request processor (resume confirmed tool calls)
- [x] toolset pre-flight auth resolution (`BaseToolset.getAuthConfig` + auth interrupt event)
- [x] include-contents mode handling in preprocess (`default`/`current_turn`/`none`)
- [x] parity tests for flow/auth handler/toolset-auth behaviors

## Newly Added Runner Parity (this iteration)

- [x] post-invocation sliding-window compaction hook in runner
- [x] token-threshold compaction utility + summary event appending
- [x] live-mode transcription buffering for tool call/response ordering
- [x] live run defaults: response modality fallback + transcription config placeholders
- [x] live flow baseline implementation (queue-driven content/blob/activity handling)
- [x] runner/compaction parity tests

## Newly Added Tools Parity (this iteration)

- [x] `load_memory` tool (`LoadMemoryTool`) + memory query instruction wiring
- [x] `preload_memory` tool (`PreloadMemoryTool`) for implicit memory injection
- [x] `load_artifacts` tool (`LoadArtifactsTool`) with request-time artifact attachment
- [x] `agent_tool` baseline (`AgentTool`) for wrapped child-agent invocation
- [x] `api_registry` baseline (`ApiRegistry`) + MCP server registration lookup
- [x] MCP tooling baseline (`McpToolset`, `McpSessionManager`, `StreamableHTTPConnectionParams`)
- [x] tool parity tests for memory/artifacts/agent/MCP flows

## Newly Added Agent/Memory Parity (this iteration)

- [x] default live fallback in `BaseAgent.runLiveImpl` (no `UnimplementedError`)
- [x] live fallback for `LoopAgent` and `ParallelAgent`
- [x] memory APIs on invocation/tool context (`searchMemory`, `addEventsToMemory`, `addMemory`)
- [x] base memory incremental/default write paths (no `UnimplementedError`)

## Newly Added Evaluation/Sessions Parity (this iteration)

- [x] `CodeConfig` parity surface (`agents/common_configs.dart`)
- [x] `NotFoundError` parity surface
- [x] evaluation config parity baseline (`EvalConfig`, `CustomMetricConfig`, default criteria loader)
- [x] evaluation metric schema baseline (`BaseCriterion`, `EvalMetricSpec`, metric info provider types)
- [x] eval set model/manager stack (`EvalSet`, `EvalSetsManager`, in-memory/local implementations)
- [x] eval set result manager stack (`EvalSetResult`, `EvalSetResultsManager`, local persistence)
- [x] eval manager utility parity (`eval_sets_manager_utils`, `eval_set_results_manager_utils`)
- [x] legacy evalset JSON conversion support in local manager
- [x] session persistence service parity baseline (`DatabaseSessionService`, `SqliteSessionService`, `VertexAiSessionService`)
- [x] parity tests for eval manager/config/result/session persistence flows

## Newly Added Tools/MCP Parity (this iteration)

- [x] tool schema/util parity surfaces (`_automatic_function_calling_util`, `_function_parameter_parse_util`, `_function_tool_declarations`, `_gemini_schema_util`)
- [x] memory/artifact utility parity (`_memory_entry_utils`, `_forwarding_artifact_service`)
- [x] authenticated tool parity surfaces (`BaseAuthenticatedTool`, `AuthenticatedFunctionTool`)
- [x] user-interaction/web utility tools (`get_user_choice_tool`, `load_web_page`)
- [x] MCP resource loading tool (`LoadMcpResourceTool`) with request-time resource injection
- [x] MCP conversion/session/tool parity surfaces (`conversion_utils`, `SessionContext`, `McpTool`)
- [x] MCP session manager resource/executor capabilities and extended tests

## Newly Added Google Tooling Parity (this iteration)

- [x] Google credential config/manager parity (`_google_credentials`) including external token lookup and OAuth request bridge
- [x] Google API tool wrapper parity (`GoogleTool`) with credential/settings-aware invocation
- [x] Google search built-in tool parity (`GoogleSearchTool`) with Gemini model guard behavior
- [x] Google search sub-agent helper parity (`createGoogleSearchAgent`, `GoogleSearchAgentTool`)
- [x] regression tests for Google tools and credential flow integration

## Newly Added Search/Grounding Tool Parity (this iteration)

- [x] enterprise web search built-in tool parity (`EnterpriseWebSearchTool`)
- [x] Google Maps grounding built-in tool parity (`GoogleMapsGroundingTool`)
- [x] Vertex AI Search built-in tool parity (`VertexAiSearchTool`) with overridable config builder
- [x] Discovery Engine Search callable tool parity baseline (`DiscoveryEngineSearchTool`) with request/result contracts
- [x] parity tests for Gemini model guards, multi-tool constraints, config serialization, and discovery handler integration

## Newly Added Google Credential Package Parity (this iteration)

- [x] BigQuery credential config parity (`BigQueryCredentialsConfig`)
- [x] Bigtable credential config parity (`BigtableCredentialsConfig`)
- [x] Pub/Sub credential config parity (`PubSubCredentialsConfig`)
- [x] Spanner credential config parity (`SpannerCredentialsConfig`)
- [x] Data Agent credential config parity (`DataAgentCredentialsConfig`)
- [x] parity tests for default scope/token-cache-key assignment and explicit scope override behavior

## Newly Added Skill Toolset Parity (this iteration)

- [x] skill toolset parity (`SkillToolset`) with duplicate-name guard and tool filtering integration
- [x] `list_skills` parity (available-skill XML formatting)
- [x] `load_skill` parity (instruction/frontmatter load + error-code responses)
- [x] `load_skill_resource` parity (references/assets/scripts path handling + error-code responses)
- [x] request-time default skill instruction + available-skills XML injection parity
- [x] dedicated parity tests for all skill toolset behaviors

## Newly Added Toolbox Toolset Parity (this iteration)

- [x] `ToolboxToolset` parity baseline with constructor contract fields (`server_url`, `toolset_name`, `tool_names`, auth/bound params)
- [x] delegate-backed tool loading and close lifecycle forwarding parity
- [x] explicit missing-toolbox integration error path
- [x] dedicated parity tests for delegate forwarding and missing-delegate failures

## Newly Added External Tool Adapter Parity (this iteration)

- [x] `LangchainTool` parity baseline with run-manager filtering, schema-aware declaration override, and config-driven runner resolution
- [x] `CrewaiTool` parity baseline with mandatory-argument validation, schema-aware declaration override, and config-driven runner resolution
- [x] adapter config model parity (`LangchainToolConfig`, `CrewaiToolConfig`)
- [x] dedicated parity tests for adapter execution paths and config loader hooks

## Newly Added Planner/Plugin/Skills Utility Parity (this iteration)

- [x] planner parity validation completed (`BasePlanner`, `BuiltInPlanner`, `PlanReActPlanner`) with dedicated planner parity tests
- [x] plugin manager callback execution parity (`early-exit`, callback error wrapping, close aggregation) + targeted tests
- [x] `ContextFilterPlugin` parity (invocation-window truncation with orphaned function-call/response protection)
- [x] `MultimodalToolResultsPlugin` parity (tool-returned `Part` stash + request-time re-attachment)
- [x] `ReflectAndRetryToolPlugin` parity (scoped retries, reset on success, exceed guidance behavior)
- [x] `GlobalInstructionPlugin` parity (global instruction prepend via string/provider)
- [x] `LoggingPlugin` parity baseline callback surface
- [x] memory timestamp utility parity (`memory/_utils.format_timestamp`)
- [x] skills module file-structure parity (`skills/models.py`, `skills/_utils.py`, `skills/prompt.py` mapped to Dart module files)

## Newly Added Optimization/Artifact Plugin Parity (this iteration)

- [x] optimization contracts (`AgentOptimizer`, `Sampler`, `ExampleSet`)
- [x] optimization data types (`BaseSamplingResult`, `UnstructuredSamplingResult`, `BaseAgentWithScores`, `OptimizerResult`)
- [x] iterative optimizer baseline (`SimplePromptOptimizer`) with candidate prompt generation + train-batch scoring + final validation
- [x] `DebugLoggingPlugin` file-output lifecycle capture parity
- [x] `SaveFilesAsArtifactsPlugin` inline upload persistence and model-accessible URI reference behavior
- [x] content part extensions for file payloads (`InlineData`, `FileData`) and session/artifact serialization support

## Newly Added A2A/Code Execution Parity (this iteration)

- [x] A2A protocol surface (`A2aMessage`, `A2aPart`, task/events/request context, in-memory event queue, agent card/provider/skill models)
- [x] A2A converter parity (`event_converter`, `part_converter`, `request_converter`, `converters/utils`)
- [x] A2A executor parity baseline (`A2aAgentExecutor`, `TaskResultAggregator`) with runner integration + final artifact/status flow
- [x] A2A logging/util parity (`logs/log_utils`, `utils/agent_card_builder`, `utils/agent_to_a2a`, `experimental`)
- [x] code execution utility parity (`code_execution_utils`) for executable/result part conversion and code extraction/truncation
- [x] code executor persistent context parity (`code_executor_context`) for execution-id/input files/error counters/result history
- [x] executor surface expansion (`ContainerCodeExecutor`, `GkeCodeExecutor`, `VertexAiCodeExecutor`, `AgentEngineSandboxCodeExecutor`) with functional local fallback baselines
- [x] parity tests for A2A converters/executor and code execution utils/context/executor behaviors

## Newly Added Evaluation Pipeline Parity (this iteration)

- [x] eval shared contracts/constants (`common`, `constants`, `evaluation_constants`)
- [x] eval rubric/app/scenario models (`eval_rubrics`, `app_details`, `conversation_scenarios`)
- [x] retry option parity utility + plugin (`_retry_options_utils`)
- [x] evaluator core contracts (`evaluator`, `trajectory_evaluator`, `response_evaluator`, `safety_evaluator`)
- [x] final response evaluators (`final_response_match_v1`, `final_response_match_v2` heuristic path)
- [x] rubric-based evaluator stack (`rubric_based_evaluator`, final/tool-use v1 specializations)
- [x] metric metadata/registry stack (`metric_info_providers`, `metric_evaluator_registry`)
- [x] custom metric execution surface (`custom_metric_evaluator` function registry)
- [x] model request interception plugin parity (`request_intercepter_plugin`)
- [x] response generation pipeline baseline (`evaluation_generator`) with runner event→invocation conversion
- [x] eval-set orchestrator baseline (`agent_evaluator`) with metric aggregation over repeated runs
- [x] judge evaluator base contract (`llm_as_judge`) with pluggable auto-rater invoker + sample aggregation
- [x] simulation persona baseline (`user_simulator_personas`, `pre_built_personas`, `per_turn_user_simulator_quality_v1`)
- [x] parity regression tests for evaluation constants/models/tool-extraction/trajectory/registry/retry paths
- [x] parity tests for evaluation generator / agent evaluator / llm-as-judge baselines

## Remaining for Full Python Parity

- [ ] full auth flow parity (protocol edge-cases + richer oauth/openid handlers)
- [ ] full contents parity (async function-response history merging, richer live artifact transcription handling)
- [ ] full code-execution processor parity (data-file optimization, artifact outputs, retry counters, built-in executor compatibility)
- [ ] runner live buffering parity for inline audio/file artifact edge cases
- [ ] full live flow parity (`BaseLlmFlow.runLive`, audio cache manager, transcription manager, artifact-backed media routing)
- [ ] code executors parity
- [ ] optimization/features parity
- [ ] telemetry parity with OTEL semconv mapping
- [ ] full evaluation suite parity (model-registry-backed judge calls, full hallucination pipeline, full prebuilt persona catalog, simulator prompt modules)
- [ ] A2A protocol parity
- [ ] full skills framework parity (integration with toolset/runtime wiring)
- [ ] platform/dependencies/utils parity modules
- [ ] full tool ecosystem parity (OpenAPI, MCP advanced, integrations, retrieval, etc.)
- [ ] production-grade web/dev server parity with Python CLI behavior

## Notes

- This file tracks implementation progress in `adk_dart`.
- “Full parity” requires multiple iterations; each completed slice must include tests.
