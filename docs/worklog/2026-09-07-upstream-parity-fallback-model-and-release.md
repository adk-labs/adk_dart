# 2026-09-07 Upstream Parity, `FallbackModel`, and Release `2026.9.7` Worklog

## Overview
This worklog documents the `2026-09-07` upstream parity commits (`96b4a60..faed4bb`) and the `2026.9.7` ecosystem release across `adk_dart`, `packages/adk`, `packages/flutter_adk`, `packages/adk_mcp`, and `packages/adk_litertlm`.

---

## 1. Models & Interactions API Parity (`cb1b3cd`, `672c113`, `cacae68`, `59e464b`, `7be904e`)
- **`FallbackModel` (`cb1b3cd`)**: Implemented `FallbackModel` (`lib/src/models/fallback_model.dart`) for automatic sequential failover across primary and backup `BaseLlm` models when transient errors, rate limits, or quota exhaustion occur.
- **Multi-Candidate & Non-Zero Stream Index Filtering (`672c113`)**: Logged warnings when multiple candidates are returned and filtered out non-zero candidate indices during streaming.
- **Interactions Generation Config Filtering (`cacae68`, `59e464b`)**:
  - Dropped unsupported sampling parameters from Interactions API generation configs with a one-time warning.
  - Routed interleaved function-call deltas by step index in `InteractionsLlmRequestProcessor`.
- **`AnthropicLlm` Model Version (`7be904e`)**: Populated `modelVersion` on `LlmResponse` from Anthropic message payloads.

## 2. Agents, Flows & Workflow Execution (`96b4a60`, `02b8147`, `409aa4c`, `2a4ece7`, `ba82959`, `c81ff3a`, `4afe9cd`)
- **Unknown Tool Reporting (`96b4a60`)**: Reported unknown tool names back to the model as structured tool error responses instead of throwing an unhandled exception.
- **Error Events as Final Response (`02b8147`)**: Treated error events without function calls as terminal final responses.
- **Agent Transfer Reason & Target Validation (`409aa4c`, `2a4ece7`)**:
  - Added optional `transfer_reason` parameter to `transfer_to_agent` to supply handoff context to the target agent.
  - Refused transfers to forbidden parent or peer agents when disallowed by `disallowTransferToParent` / `disallowTransferToPeers`.
- **Workflow `START` Predecessor & Partial Calls (`ba82959`)**: Honored `START` as an already-satisfied predecessor for join nodes and ignored partial streaming function calls during workflow routing.
- **`ParallelAgent` Direct Escalation (`c81ff3a`)**: Ended `ParallelAgent` early only when a direct sub-agent escalates.
- **`RunConfig.maxLlmCalls` Bound (`4afe9cd`)**: Rejected `maxLlmCalls` values greater than or equal to `sys.maxsize`.

## 3. Auth, Sessions, Live, MCP, A2A & Skills (`486373a`, `08301c9`, `7f55e3d`, `e8d1b82`, `c980b02`, `00827b6`, `0245270`)
- **`VertexAiSessionService` 429 Retry (`486373a`)**: Added single-retry backoff on HTTP 429 rate-limit responses in `appendEvent`.
- **Auth-Gated Tool Author Check (`08301c9`)**: Validated function call `author` before resuming auth-gated tool invocations.
- **Live Queue Close Handling (`7f55e3d`)**: Suppressed live stream auto-reconnect when the client explicitly closes `LiveRequestQueue`.
- **`McpTool` & A2A Summarization (`e8d1b82`, `c980b02`, `00827b6`)**:
  - Skipped LLM summarization when an MCP tool call pauses for user confirmation or when an A2A task reaches a terminal state.
  - Defaulted `AgentCardBuilder` capabilities to `streaming = true`.
- **`SkillToolset` Tool Filter (`0245270`)**: Made `SkillToolset` system instruction generation respect `toolFilter`.

## 4. Evaluation Enhancements (`e623cf5`, `effb00d`)
- **`ignoreArgs` in Trajectory Evaluation (`e623cf5`)**: Added `ignoreArgs` option to `TrajectoryEvaluator` to evaluate tool call sequences by tool name only when arguments are dynamic.
- **`not_evaluated` Metric Status (`effb00d`)**: Reported metrics that never executed as `EvalStatus.notEvaluated` instead of `failed`.

## 5. Release `2026.9.7` (`faed4bb`)
- Bumped all workspace packages (`adk_dart`, `packages/adk`, `packages/flutter_adk`, `packages/adk_mcp`, `packages/adk_litertlm`) to `2026.9.7` and synced changelogs.
