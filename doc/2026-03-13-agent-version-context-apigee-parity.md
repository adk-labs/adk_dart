# 2026-03-13 Agent Version / Context / Apigee Parity

## Scope

- Reference: `ref/adk-python`
- Reviewed range: `9d155177..31b005c3`
- Goal: close remaining runtime gaps after the March 10-13 parity batches

## Work Unit 1: Agent version parity

- Added `version` to `BaseAgent`.
- Added `version` to `BaseAgentConfig`.
- Propagated `version` through:
  - runtime agent constructors
  - clone paths
  - config decoding / encoding
  - config-to-agent builders

Files:

- `lib/src/agents/base_agent.dart`
- `lib/src/agents/base_agent_config.dart`
- `lib/src/agents/llm_agent.dart`
- `lib/src/agents/loop_agent.dart`
- `lib/src/agents/parallel_agent.dart`
- `lib/src/agents/sequential_agent.dart`
- `lib/src/agents/langgraph_agent.dart`
- `lib/src/agents/remote_a2a_agent.dart`
- `lib/src/agents/llm_agent_config.dart`
- `lib/src/agents/loop_agent_config.dart`
- `lib/src/agents/parallel_agent_config.dart`
- `lib/src/agents/sequential_agent_config.dart`
- `lib/src/agents/config_agent_utils.dart`

## Work Unit 2: Telemetry agent version parity

- Changed `gen_ai.agent.version` from package version to `agent.version`.
- Applied the change to:
  - `traceAgentInvocation(...)`
  - common inference span attributes

File:

- `lib/src/telemetry/tracing.dart`

## Work Unit 3: Context UI widget parity

- Removed the tool-only restriction from `Context.renderUiWidget(...)`.
- Added duplicate widget id rejection within the same event action batch.

File:

- `lib/src/agents/context.dart`

## Work Unit 4: Apigee usage metadata parity

- Added `completion_tokens_details.reasoning_tokens` mapping to
  `thoughts_token_count` in parsed usage metadata.

File:

- `lib/src/models/apigee_llm.dart`

## Tests

- Updated / added coverage for:
  - config version round-trip
  - config-to-agent version propagation
  - clone version preservation / override
  - telemetry agent version attributes
  - context UI widget duplicate handling
  - Apigee reasoning token parsing

Files:

- `test/agent_config_parity_test.dart`
- `test/agent_clone_parity_test.dart`
- `test/context_tool_flow_test.dart`
- `test/features_telemetry_parity_test.dart`
- `test/models_parity_batch2_test.dart`

## Verification

```bash
dart analyze lib/src/agents/base_agent.dart \
  lib/src/agents/base_agent_config.dart \
  lib/src/agents/llm_agent.dart \
  lib/src/agents/loop_agent.dart \
  lib/src/agents/parallel_agent.dart \
  lib/src/agents/sequential_agent.dart \
  lib/src/agents/langgraph_agent.dart \
  lib/src/agents/remote_a2a_agent.dart \
  lib/src/agents/llm_agent_config.dart \
  lib/src/agents/loop_agent_config.dart \
  lib/src/agents/parallel_agent_config.dart \
  lib/src/agents/sequential_agent_config.dart \
  lib/src/agents/config_agent_utils.dart \
  lib/src/telemetry/tracing.dart \
  lib/src/agents/context.dart \
  lib/src/models/apigee_llm.dart \
  test/context_tool_flow_test.dart \
  test/features_telemetry_parity_test.dart \
  test/models_parity_batch2_test.dart \
  test/agent_config_parity_test.dart \
  test/agent_clone_parity_test.dart

dart test test/context_tool_flow_test.dart \
  test/features_telemetry_parity_test.dart \
  test/models_parity_batch2_test.dart \
  test/agent_config_parity_test.dart \
  test/agent_clone_parity_test.dart
```
