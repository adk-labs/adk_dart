# 2026-11-20 Upstream Parity Sync (`2026.11.20+1`)

## Upstream Range
- `adk-python`: `fb08c784242c9afc3d8645508d8c5c08c9836eb9..c81876a49911745248f2b774c02770ed211ff460`
- `adk-web`: `4b7d11542b2a5540213d0578d733fae86505c024` (`v1.0.8`, no new commits; `main-PJ4DBNMP.js` already synced)

## Task-Unit Commits
1. `ecd8cbc5` — `fix(telemetry,models,a2a): set gen_ai.response.model, report malformed Apigee tool calls, and revert RemoteA2aAgent last_chunk persistence`
   - `ecc6b6e01`: Set `gen_ai.response.model` on LLM / generate-content / inference telemetry spans (`lib/src/telemetry/tracing.dart`).
   - `7b07e7df7`: Added `reportMalformedFunctionCalls` (`lib/src/models/malformed_function_calls.dart`) and malformed tool-call argument reporting for non-streaming & streaming SSE in `ApigeeLlm` (`lib/src/models/apigee_llm.dart`).
   - `5523aa733`: Reverted streamed artifact `lastChunk` buffering in `RemoteA2aAgent` (`lib/src/agents/remote_a2a_agent.dart`).
   - Tests: `test/upstream_nov20_telemetry_apigee_a2a_parity_test.dart`, updated `test/remote_a2a_agent_parity_test.dart` & `test/upstream_nov19_core_sessions_workflow_parity_test.dart` (`202/202` passed).
2. `c55b730c` — `fix(workflow): retry a failed workflow child in place`
   - `f04b5fe42`, `c81876a49`: Implemented in-place child retry on `Workflow` (`retryConfig` propagation, `WorkflowContext.attemptCount`, keeping `NodeStatus.running` during retries, non-multiplying nested workflow failures, detached dynamic child handling, flushing checkpoints & completed outputs before rethrowing) in `lib/src/workflow/`.
   - Tests: `test/upstream_nov20_workflow_in_place_retry_parity_test.dart` (`164/164` workflow tests passed).

## Release
- Version: `2026.11.20+1` (same-day follow-up to `2026.11.20`)
- Packages: `adk_mcp`, `adk_dart`, `adk_litertlm`, `flutter_adk`, `adk`
