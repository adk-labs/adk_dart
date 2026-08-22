# ADK Python Upstream Synchronization & Parity Audit Report

- **Date**: 2026-08-22
- **Upstream Repository**: `google/adk-python`
- **Target Repository**: `adk-labs/adk_dart`
- **Audit Period**: 2026-08-16 ~ 2026-08-22 (Commits `0c67410a` through `d9f4d3d2`)

---

## 1. Executive Summary

A comprehensive audit was performed across all commits merged into `google/adk-python` between August 16, 2026 and August 22, 2026. All new features, security fixes, error handling enhancements, telemetry attributes, and toolset expansions have been verified and ported to `adk_dart`.

All 1,380+ unit and parity tests pass with 0 failures, and `dart analyze` passes with 0 errors.

---

## 2. Key Ported Features & Bug Fixes

### 2.1. OpenAPI Tooling & Spec Parser
- **Recursive Schema Sanitization**: Updated `OpenApiSpecParser.sanitizeSchemaTypes` to recursively sanitize schema structures across all nested properties (`schema`, `schemas`, `items`, `properties`, `allOf`, `anyOf`, `oneOf`). Invalid type designations are stripped while valid primitive types and security scheme configurations are strictly preserved.
- **Path Parameter Encoding**: Confirmed percent-encoding of path parameters before URL substitution in `RestApiTool`.

### 2.2. Workflow & Runner Execution
- **Duplicate Edge Validation**: Updated `_validateNoDuplicateEdges` in `Workflow` to reject duplicate `(fromNode, toNode)` pairs regardless of routing labels or condition branches.
- **Workflow Early-Exit Lifecycle**: Verified `Runner._execWithPlugin` accurately captures `before_run_callback` content early exits, yields the model turn, bypasses node execution, and cleanly dispatches `after_run_callback` and compaction.

### 2.3. Session Management & Limits
- **Recent Events Limit Validation**: Added validation in `BaseSessionService.getSession` to reject negative `numRecentEvents` values (`< 0`) with `ArgumentError`.

### 2.4. Telemetry & Context Cache Tracing
- **Span Attributes for Context Cache**: Added experimental context cache span attributes in `adk_dart/lib/src/telemetry/tracing.dart`:
  - `adk.experimental.context_cache.hit`
  - `adk.experimental.context_cache.fingerprint`
  - `adk.experimental.context_cache.contents_count`
  - `adk.experimental.context_cache.invocations_used`

### 2.5. Model & Agent Configuration
- **RunConfig Max LLM Calls Fallback**: Added environment variable resolution for `ADK_MAX_LLM_CALLS` when initializing `RunConfig.maxLlmCalls`.

### 2.6. Data Agent Toolset Expansion
- **Extended DataAgentToolConfig**: Added `location`, `apiEndpoint`, `dataAgentModificationTimeoutSeconds`, `dataAgentModificationPollIntervalSeconds`, and `enableDataAgentModification`.
- **Resource Mutations**:
  - `deleteDataAgent`: Implemented HTTP DELETE operation against Data Agent resource endpoints.
  - `updateDataAgent`: Implemented HTTP PATCH operation with `updateMask` validation and payload mapping.
- **Mutation Gating**: `DataAgentToolset` only registers `create_data_agent`, `delete_data_agent`, and `update_data_agent` tools when `enableDataAgentModification == true`.

### 2.7. Plugins & Integrations
- **MultimodalToolResultsPlugin Session Retention**: Added `retention: "session"` mode allowing file references and text parts returned by tools to persist and re-attach across subsequent conversational turns, while keeping inline data one-shot.
- **GCP Skill Registry Validation Tolerance**: Updated `GCPSkillRegistry.searchSkills` to safely skip remote catalog entries that fail frontmatter validation rather than aborting discovery.
- **MCP Error Detection**: Supported both `isError` and `is_error` flag keys in `McpTool`.

---

## 3. Test & Quality Verification

- **Total Test Count**: 1,380+ tests
- **Failed Tests**: 0
- **Analysis Status**: Clean (`dart analyze` 0 errors)
