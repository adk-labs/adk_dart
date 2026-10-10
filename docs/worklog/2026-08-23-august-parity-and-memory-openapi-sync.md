# 2026-08-23 August Upstream Parity, Memory Unicode Search & OpenAPI Hardening Worklog

## Overview
This worklog records the upstream `adk-python` parity batches executed across `2026-08-22` and `2026-08-23` (`b0fb482..74e5ce0`), covering core session/workflow validation, context cache telemetry, plugin session retention, DataAgent/MCP/OpenAPI tooling, evaluation rubrics, Unicode memory matching, and single-turn workflow resumption.

---

## 1. Core Session, Workflow & RunConfig Parity (`b0fb482`, `74e5ce0`)
- **Session Limit Validation**: Ported strict `numRecentEvents` / session history limit validation and environment variable fallbacks in `RunConfig`.
- **Workflow Edge Checks & Resumption**:
  - Added graph edge validation and cycle/boundary checks in `Workflow`.
  - Fixed single-turn agent resumption in `Workflow` (`74e5ce0`) to prevent duplicate synthetic user events when resuming an interrupted single-turn node.

## 2. Telemetry & Context Cache Metrics (`7cc1487`)
- Recorded context cache hit/utilization span attributes (`gen_ai.usage.cache_read_input_tokens`, cache metadata) in `Tracing` and updated `BaseLlmFlow` span instrumentation.

## 3. Plugins & Skill Search Robustness (`aed5a9a`)
- **`MultimodalToolResultsPlugin`**: Added session-level retention support for multimodal tool responses across turns.
- **`SkillToolset`**: Hardened skill query matching and resource lookup against malformed paths.

## 4. DataAgent, MCP & OpenAPI Tooling (`8ea92c0`, `5de5f68`)
- **`DataAgentTool`**: Expanded mutation operations and parameter validation for Data Agent toolsets.
- **`McpTool`**: Added dual error key (`isError` / `is_error`) detection on MCP tool call responses.
- **`RestApiTool` (`5de5f68`)**: Added RFC 3986 percent-encoding (`Uri.encodeComponent`) for OpenAPI path parameter values and operation name sanitization.

## 5. Evaluation Rubrics & Simulators (`4dde5f3`)
- Updated `RubricBasedFinalResponseQualityV1`, `RubricBasedToolUseQualityV1`, and user simulator prompts/scoring to match upstream `adk-python` evaluation specifications.

## 6. Unicode-Aware `InMemoryMemoryService` (`e6163b8`)
- Enhanced `InMemoryMemoryService.searchMemory` with Unicode property regex matching (`unicode: true`) and CJK/non-Latin substring matching so Korean, Japanese, Chinese, and accented Latin queries match memory entries accurately.

---

## Verification
- Verified via `test/memory_parity_test.dart`, `test/openapi_tool_test.dart`, `test/workflow_runtime_parity_test.dart`, and `test/evaluation_parity_test.dart`.
- Static analysis (`dart analyze`): 0 issues.
