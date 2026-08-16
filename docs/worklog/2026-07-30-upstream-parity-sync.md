# 2026-07-30 Upstream Parity Sync Worklog

## Overview
Porting resiliency plugins, function schema optimizations, MCP protocol upgrades, and web tooling from upstream ADK.

## Changes Implemented

### 1. Reflect and Retry Model Error Recovery Plugin
- **Files Modified**: `lib/src/plugins/reflect_retry_model_plugin.dart`, `lib/adk_dart.dart`
- **Details**:
  - Implemented `ReflectAndRetryModelPlugin` for framework-level LLM error recovery.
  - Intercepts model generation errors and triggers self-healing reflection tool calls (`adkHandleModelError`) with customizable retry budgets.

### 2. FunctionTool Schema Declaration Caching
- **Files Modified**: `lib/src/tools/function_tool.dart`
- **Details**:
  - Added `_cachedDeclaration` to `FunctionTool` to eliminate redundant parameter schema rebuilds across conversational turns.

### 3. MCP Protocol Version 2026-07-28 & Elicitation Support
- **Files Modified**: `packages/adk_mcp/lib/src/mcp_protocol.dart`, `packages/adk_mcp/lib/src/mcp_session_manager.dart`, `lib/src/tools/mcp_tool/mcp_toolset.dart`
- **Details**:
  - Updated MCP specification to `2026-07-28`.
  - Added `elicitationCallback` support (`elicitation/create` and `notifications/elicitation/complete`) for client-side user prompt and OAuth challenge handling.
  - Implemented `AdkAgentMcpServer` (`lib/src/tools/mcp_tool/agent_to_mcp.dart`) to expose any ADK agent as an MCP server.

### 4. Web Scraping & Enterprise Search Tools
- **Files Modified**: `lib/src/tools/load_web_page.dart`, `lib/src/tools/enterprise_web_search_tool.dart`
- **Details**:
  - Implemented `LoadWebPageTool` with SSRF protection, private IP blocking, and content sanitization.
  - Implemented `EnterpriseWebSearchTool` powered by Vertex AI search grounding.

## Verification
- Validated with MCP tooling test suites and web server integration tests.
