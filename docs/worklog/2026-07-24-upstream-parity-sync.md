# 2026-07-24 Upstream Parity Sync Worklog

## Overview
Syncing core features, performance improvements, and bug fixes from `adk-python` (`be5828f3..07455ee6`) into `adk-dart`.

## Changes Implemented

### 1. User Attribution & Billing Labels
- **Files Modified**: `lib/src/agents/run_config.dart`, `lib/src/flows/llm_flows/basic.dart`
- **Details**:
  - Added user labels (`labels`) map to `RunConfig`.
  - Automatically propagated and merged labels in `BasicLlmRequestProcessor` to pass Vertex AI billing and telemetry metadata.

### 2. Guard Replay Against Partial Streaming Function Calls
- **Files Modified**: `lib/src/flows/llm_flows/base_llm_flow.dart`
- **Details**:
  - Guarded resumable invocation replay against partial streaming function-call SSE events to prevent replay loops and duplicate invocations.

### 3. Anthropic Model Finish Reason Mapping
- **Files Modified**: `lib/src/models/anthropic_llm.dart`
- **Details**:
  - Expanded `AnthropicLlm` `finishReason` mapping to properly handle `pause_turn` (mapped to `FinishReason.stop`) and `refusal` (mapped to `FinishReason.safety`).

### 4. Vertex AI Session Service Filtering
- **Files Modified**: `lib/src/sessions/vertex_ai_session_service.dart`
- **Details**:
  - Fixed `VertexAiSessionService.getSession` to apply `afterTimestamp` server-side filtering alongside `numRecentEvents`.

### 5. BigQuery Final Response Tool Names
- **Files Modified**: `lib/src/plugins/bigquery_agent_analytics_plugin.dart`
- **Details**:
  - Added opt-in `finalResponseToolNames` to `BigQueryAgentAnalyticsPlugin` to log final answer tool call payloads as `AGENT_RESPONSE` events.

### 6. Nested Workflow Resume Output Delivery
- **Files Modified**: `lib/src/workflow/workflow.dart`
- **Details**:
  - Fixed nested workflow resume by yielding resolved outputs of resumed request-input nodes on resume instead of skipping them.

### 7. Examples Reorganization & Local LLM Integration
- **Files Modified**: `examples/`
- **Details**:
  - Reorganized all code examples into self-contained Dart project templates with individual `README.md` and multi-language documentation (KO, EN, JA, ZH).
  - Added `08_local_llm_ollama_litellm` (Ollama/LiteLLM integration via `LiteLlm` client) and `09_local_llm_litert` (on-device Gemma inference via `adk_litertlm`).

## Verification
- Added test coverage in `test/python_upstream_updates_test.dart`.
- All 1,105 unit tests passed.
