# Latest Four-Day Review Follow-up

## Scope

- Re-reviewed `reports/adk-python/2026-03-14.md` through `2026-03-17.md`
- Compared `ref/adk-python` latest runtime/library deltas against the Dart port
- Closed remaining concrete gaps before updating changelog

## Closed Gaps

### 1. MCP sampling callback parity

- Added ADK-facing `samplingCallback` and `samplingCapabilities` support to `McpToolset`
- Stored per-connection sampling configuration in `McpSessionManager`
- Routed `sampling/createMessage` server requests to the configured callback
- Added per-connection MCP client capability overrides during initialize
- Added regression coverage that verifies:
  - sampling callback invocation
  - sampling capability advertisement in `initialize`
  - server-side receipt of the callback result

### 2. Multi-turn evaluation metric parity

- Added metric names for:
  - `multi_turn_task_success_v1`
  - `multi_turn_trajectory_quality_v1`
  - `multi_turn_tool_use_quality_v1`
- Added metric info providers and default registry wiring
- Added evaluator implementations backed by a multi-turn Vertex AI eval facade
- Added regression coverage that verifies:
  - registry exposure for all three metrics
  - evaluator resolution
  - last-turn-only scoring semantics for multi-turn evaluation

## Validation

- `dart analyze` on all changed source/test files: passed
- `dart test` passed for:
  - `test/mcp_tooling_test.dart`
  - `test/evaluation_parity_batch3_test.dart`
  - `test/evaluation_cloud_parity_test.dart`
  - `packages/adk_mcp/test/mcp_remote_client_test.dart`
  - `packages/adk_mcp/test/mcp_stdio_client_test.dart`

## Notes

- Temporary root `pubspec_overrides.yaml` was used only to point `adk_mcp` to the local package for validation.
- The temporary override was removed after tests completed and was not kept in the worktree.
