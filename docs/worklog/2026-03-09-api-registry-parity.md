# 2026-03-09 API Registry Parity

## Scope
- Close the runtime gap between Dart and the latest `adk-python` API Registry integration.
- Keep the existing manual registration path intact while adding a live Google Cloud API Registry discovery path.

## Work Units

### 1. Live API Registry discovery
- Added `ApiRegistry.create(...)` async factory for loading MCP servers from Google Cloud API Registry.
- Added paginated MCP server discovery against `cloudapiregistry.googleapis.com`.
- Added injectable HTTP and auth providers so the live path is testable without network access.

### 2. Auth and MCP handoff
- Added default auth header resolution using the existing Google access-token helper.
- Propagated auth headers into the resulting `StreamableHTTPConnectionParams` so fetched MCP servers can be used immediately by `McpToolset`.
- Preserved the existing manual `registerMcpServer()` path for local and test use.

### 3. Verification
- `dart analyze lib/src/tools/api_registry.dart test/mcp_tooling_test.dart`
- `dart test test/mcp_tooling_test.dart`
