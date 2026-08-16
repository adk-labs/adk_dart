# 2026-08-17 Upstream v2.7.0 Parity & Live API Enhancements Worklog

## Overview
Comprehensive synchronization with `adk-python` v2.7.0 and implementation of all remaining upstream features across Live API, Workflow-as-Tool, Cloud Integrations, Simulation, and Model Compatibility.

## Changes Implemented

### 1. Live API Multimodal Streaming & Voice Activity Detection (VAD)
- **Files Modified**:
  - `lib/src/types/content.dart`: Added `VoiceActivity`, `VoiceActivityType`, and `FunctionResponseScheduling` (`whenIdle`, `silent`, `interrupt`).
  - `lib/src/models/llm_response.dart`: Added `voiceActivity` field and `copyWith` propagation.
  - `lib/src/events/event.dart`: Added `voiceActivity` to `Event` constructor and payload.
  - `lib/src/agents/run_config.dart` & `lib/src/models/llm_request.dart`: Added `explicitVadSignal` flag.
  - `lib/src/flows/llm_flows/base_llm_flow.dart`: Forwarded `voiceActivity` during Live stream post-processing.
  - `lib/src/models/gemini_llm_connection.dart`: Handled `voiceActivity` in `GeminiLiveSessionMessage` and emitted responses.
  - `lib/src/agents/invocation_context.dart`: Added `activeNonBlockingToolTasks` container.
  - `lib/src/flows/llm_flows/functions.dart`: Implemented non-blocking tool execution pipeline in Live mode; background tasks dispatch results asynchronously to `liveRequestQueue`.

### 2. Workflow as Tool
- **Files Modified/Created**:
  - `lib/src/workflow/workflow_tool.dart`: Implemented `WorkflowTool` wrapper executing full workflow graphs via function calling.
  - `lib/src/workflow/workflow.dart`: Added `Workflow.asTool()` method.
  - `lib/adk_dart.dart`: Exported `WorkflowTool`.

### 3. Google Cloud Eventarc Advanced Integration
- **Files Created**:
  - `lib/src/tools/eventarc/config.dart`: `EventarcToolConfig` and `EventarcCredentialsConfig` (extending `BaseGoogleCredentialsConfig`).
  - `lib/src/tools/eventarc/message_tool.dart`: Implemented `publishEventarcMessage` publishing structured CloudEvents 1.0 JSON payloads.
  - `lib/src/tools/eventarc/eventarc_toolset.dart`: Implemented `EventarcToolset`.
  - `lib/adk_dart.dart`: Exported Eventarc configuration and toolset classes.

### 4. Daytona Isolated Cloud Sandbox Environment
- **Files Created**:
  - `lib/src/tools/environment/daytona_environment.dart`: Implemented `DaytonaEnvironment` with remote shell command execution and file CRUD operations.
  - `lib/adk_dart.dart`: Exported `DaytonaEnvironment`.

### 5. Multimodal Audio Simulation Evaluation
- **Files Created**:
  - `lib/src/evaluation/simulation/llm_audio_user_simulator.dart`: Implemented `LlmAudioUserSimulator` and `LlmAudioUserSimulatorConfig` combining text turn generation with TTS audio synthesis.
  - `lib/adk_dart.dart`: Exported `LlmAudioUserSimulator`.

### 6. Storage, Data Agent & Model Parity
- **Files Modified**:
  - `lib/src/sessions/base_session_service.dart` & `lib/src/sessions/database_session_service.dart`: Added `prepareTables()` for proactive table creation and schema migration.
  - `lib/src/tools/data_agent/data_agent_tool.dart` & `lib/src/tools/data_agent/data_agent_toolset.dart`: Added `create_data_agent` tool and `DataAgentHttpPost`.
  - `lib/src/memory/vertex_ai_memory_bank_service.dart`: Added `memory_id` and `allowed_topics` support in memory generation/creation configs.
  - `lib/src/models/gemma_llm.dart`: Updated `GemmaLlm.supportedModels()` to match Gemma 4 models (`gemma-(3|4).*`).

### 7. Feature Registry & Batch Parity Versions
- **Files Modified**:
  - `lib/src/features/_feature_registry.dart`: Added `eventarcToolset` and `daytonaEnvironment` feature flags.
  - `test/utils_batch_parity_test.dart`: Updated expected version assertions to `2.7.0`.

## Verification & Test Results
- Created dedicated test suite: `test/recent_upstream_parity_features_test.dart` (8 feature groups).
- Full test suite run: **1,517 total tests passed (100% Pass, 0 Failures)**.
