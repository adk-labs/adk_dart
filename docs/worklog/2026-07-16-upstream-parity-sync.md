# 2026-07-16 Upstream Parity Sync Worklog

## Overview
Syncing recent upstream commits from `adk-python` to `adk-dart` to ensure functional parity and fix edge cases.

## Changes Implemented

### 1. Upgrade Gemini Data Analytics (GDA) API to v1
- **Upstream Commit**: `f6387c46` (Upgrade Gemini Data Analytics API version to v1)
- **Files Modified**: `lib/src/tools/data_agent/data_agent_tool.dart`
- **Details**: Updated `dataAgentBaseUrl` endpoint from `https://geminidataanalytics.googleapis.com/v1beta` to `https://geminidataanalytics.googleapis.com/v1` to follow the updated GDA API contract.

### 2. Fix Sub-Branch Event Routing for Nested Workflows/Agents/Tools
- **Upstream Commit**: `3cdc1022` (Fix sub-branch event routing for nested sub-agents and tools in InvocationContext)
- **Files Modified**: `lib/src/agents/invocation_context.dart`
- **Details**: 
  - Updated `getEvents(currentBranch: true)` to match not only the current branch but also descendant branches (e.g. `branch.startswith(current_branch + ".")`).
  - Added user-authored event validation: verified function responses targeting a call that originated inside this branch or its descendants, preventing cross-branch/parallel event leakage.

### 3. Reuse Resolved Canonical Tools and Avoid Tool Leakage
- **Upstream Commit**: `3164504f` (Reuse current-step tool resolution / canonical tools caching)
- **Files Modified**: `lib/src/flows/llm_flows/base_llm_flow.dart`
- **Details**:
  - Populated `context.canonicalToolsCache` with the full list of resolved canonical tools during request preprocessing in `_processAgentTools`.
  - Cleared/initialized the cache to an empty list when `agent.tools` is empty to prevent tools from leaking across steps.
  - Reused the cache in response preprocessing instead of re-resolving tools.

## Verification
- Ran targeted test suites: `test/replay_manager_test.dart`, `test/tools_memory_artifacts_test.dart`, `test/utils_missing_parity_test.dart`, `test/flow_processors_parity_test.dart`, `test/node_tool_test.dart`.
- All tests passed successfully with 0 regressions.
