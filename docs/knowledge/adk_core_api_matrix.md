# adk_core API Matrix (v3 — 2026-10-10)

Date: 2026-10-10
Related plans & worklogs:
- `docs/worklog/2026-02-28_21-44-13_adk_core_split_plan.md`
- `docs/worklog/2026-03-01_16-59-24_flutter_adk_all_platform_plan.md`
- `docs/worklog/2026-08-17-full-parity-suite-and-flutter-adk-completion.md`
- `docs/worklog/2026-10-10-cascade-live-elevenlabs-and-upstream-parity.md`

## Scope
- Entrypoint: `lib/adk_core.dart`
- Goal: Flutter/Web/WASM-safe import path (`dart:io` and `dart:ffi` free) that compiles cleanly on Web (`dart2js` / `dart2wasm`) and powers `package:flutter_adk`.

## Included Surface (`lib/adk_core.dart`)

### 1. Agents, Workflows & App Runtime Primitives
- `src/agents/abort_signal.dart` (`AbortSignal`)
- `src/agents/agent_state.dart`
- `src/agents/base_agent.dart`
- `src/agents/callback_context.dart`
- `src/agents/context.dart`
- `src/agents/invocation_context.dart`
- `src/agents/live_request_queue.dart`
- `src/agents/llm_agent.dart` (`LlmAgent`, `Agent`)
- `src/agents/loop_agent.dart` (`LoopAgent`)
- `src/agents/parallel_agent.dart` (`ParallelAgent`)
- `src/agents/readonly_context.dart`
- `src/agents/run_config.dart` (`RunConfig`, `StreamingMode`)
- `src/agents/sequential_agent.dart` (`SequentialAgent`)
- `src/apps/app.dart` (`App`, `ResumabilityConfig`)
- `src/apps/compaction.dart` (`EventsCompactionConfig`)
- `src/runners/runner.dart` (`Runner`, `InMemoryRunner`)
- `src/workflow/workflow.dart` (`Workflow`, `Node`, `BaseNode`, `NodeConfig`, `RetryConfig`, `Edge`, `JoinNode`)

### 2. Multi-LLM & Cascaded Live Audio Models
- `src/models/base_llm.dart` (`BaseLlm`)
- `src/models/base_llm_connection.dart` (`BaseLlmConnection`)
- `src/models/capabilities.dart` (`LlmCapabilities`)
- `src/models/google_llm.dart` (`Gemini`)
- `src/models/anthropic_llm.dart` (`AnthropicLlm`)
- `src/models/lite_llm.dart` (`LiteLlm` — OpenAI, Ollama, LM Studio, DeepSeek, Groq)
- `src/models/gemma_llm.dart` (`Gemma`, `GemmaLlm`)
- `src/models/fallback_model.dart` (`FallbackModel`)
- `src/models/registry.dart` (`LLMRegistry`)
- `src/models/llm_request.dart` & `src/models/llm_response.dart`
- `src/live/live.dart` (`CascadeLive`, `CascadeLiveConnection`, `IngressEvent`, `EgressEvent`, `LiveIngress`, `LiveEgress`, `CancelSignal`)
- `src/integrations/eleven_labs/eleven_labs.dart` (`ElevenLabsSTT`, `ElevenLabsTTS`, `ElevenLabsSpeechClient`)

### 3. Data Model, Events, Sessions, Memory & Auth
- `src/events/event.dart`, `src/events/event_actions.dart`, `src/events/abort_events.dart`, `src/events/internal_metadata.dart`, `src/events/structured_events.dart`
- `src/types/content.dart` (`Content`, `Part`, `FunctionCall`, `FunctionResponse`, `InlineData`, `FileData`)
- `src/sessions/base_session_service.dart`, `src/sessions/in_memory_session_service.dart`, `src/sessions/session.dart`, `src/sessions/state.dart`
- `src/memory/base_memory_service.dart`, `src/memory/in_memory_memory_service.dart`, `src/memory/memory_entry.dart`
- `src/auth/auth_credential.dart`, `src/auth/auth_handler.dart`, `src/auth/auth_schemes.dart`, `src/auth/auth_tool.dart`, `src/auth/secret.dart` (`Secret`, `ExperimentalAuthApi`, `SecretAccess`)

### 4. Plugins, Tools, Artifacts, Features & Telemetry Base
- `src/plugins/base_plugin.dart`, `src/plugins/plugin_manager.dart`, `src/plugins/reflect_retry_model_plugin.dart`, `src/plugins/reflect_retry_tool_plugin.dart`
- `src/tools/base_tool.dart` (`BaseTool`, `ToolBehavior`), `src/tools/base_toolset.dart`, `src/tools/function_tool.dart` (`FunctionTool`), `src/tools/agent_tool.dart` (`AgentTool`), `src/tools/google_search_tool.dart`, `src/tools/get_user_choice_tool.dart`, `src/tools/tool_context.dart`
- `src/artifacts/base_artifact_service.dart`, `src/artifacts/in_memory_artifact_service.dart`
- `src/features/_feature_registry.dart` (`FeatureName`, `FeatureStage`, `isFeatureEnabled`, `overrideFeatureEnabled`)
- `src/telemetry/base_telemetry_service.dart`, `src/telemetry/in_memory_telemetry_service.dart`

### 5. Common Errors
- `src/errors/already_exists_error.dart`
- `src/errors/input_validation_error.dart`
- `src/errors/invocation_not_found_error.dart`
- `src/errors/not_found_error.dart`
- `src/errors/session_not_found_error.dart`
- `src/errors/stale_session_error.dart`
- `src/errors/tool_execution_error.dart`

## Excluded from `adk_core.dart` (VM-only APIs)
- CLI & Dev Web Server stack (`packages/adk`)
- FFI-backed SQLite session & span exporters (`src/sessions/sqlite_session_service.dart`, `src/telemetry/sqlite_span_exporter.dart`)
- Local process & filesystem code executors (`UnsafeLocalCodeExecutor`, `BashTool`)
