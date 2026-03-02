# adk_mcp

English | [한국어](README.ko.md) | [日本語](README.ja.md) | [中文](README.zh.md)

`adk_mcp` provides MCP (Model Context Protocol) client primitives for Dart.

It includes:

- Streamable HTTP MCP client (`McpRemoteClient`)
- stdio MCP client (`McpStdioClient`)
- MCP constants, method names, protocol version handling, and JSON-RPC helpers

## Platform Support Matrix (Current)

Status legend:

- `✅` Supported
- `⚠️` Partially supported / environment dependent
- `❌` Not supported

| Feature / Surface | Dart VM / CLI | Flutter (Android/iOS/Linux/macOS/Windows) | Flutter Web | Notes |
| --- | --- | --- | --- | --- |
| `McpRemoteClient` (Streamable HTTP transport) | ✅ | ✅ | ✅ | HTTP/HTTPS only (`StreamableHTTPConnectionParams`). |
| Protocol negotiation + JSON-RPC helper methods | ✅ | ✅ | ✅ | Same protocol behavior across transports/platforms. |
| Server message/read loop (`readServerMessagesOnce`) | ✅ | ✅ | ✅ | Web requires CORS-compatible MCP endpoint for browser access. |
| `McpStdioClient` transport | ✅ | ⚠️ | ❌ | Web uses a stub that throws `UnsupportedError`; non-web requires local process support. |
| `StdioConnectionParams` process spawn (`Process.start`) | ✅ | ⚠️ | ❌ | Environment-dependent on Flutter runtime/sandbox policies. |
| HTTP session termination (`terminateSession`) | ✅ | ✅ | ✅ | Uses MCP Streamable HTTP DELETE termination flow. |
| Built-in credential/token lifecycle manager | ❌ | ❌ | ❌ | Headers/tokens are caller-managed. |

## Feature Support Matrix (Current)

Status legend:

- `✅` Supported
- `⚠️` Partial / integration required
- `❌` Not supported yet

### Supported / Working

| Area | Feature | Status | Notes |
| --- | --- | --- | --- |
| Transport | Streamable HTTP MCP client | ✅ | JSON-RPC call/notify with initialize handshake support. |
| Transport | stdio MCP client | ✅ | Child-process based JSON-RPC transport. |
| Protocol | MCP protocol version negotiation | ✅ | Supports `2025-03-26`, `2025-06-18`, `2025-11-25`. |
| RPC helpers | Tools/resources/prompts/tasks/logging/sampling/roots/elicitation method helpers | ✅ | High-level helper methods are provided for client calls. |
| Paging | Cursor-based pagination helper (`collectPaginatedMaps`) | ✅ | Works for both HTTP and stdio clients. |
| Server events | Server notification/request callback hooks | ✅ | `onServerMessage` / `onServerRequest` are supported. |
| Session | HTTP session termination helper | ✅ | `terminateSession()` sends MCP DELETE termination request. |

### Partial / Not Yet Supported

| Area | Feature | Status | Notes |
| --- | --- | --- | --- |
| Package scope | MCP server implementation | ❌ | `adk_mcp` is client-only. |
| Transport | WebSocket/other non-HTTP non-stdio transports | ❌ | Only streamable HTTP and stdio are implemented. |
| Server request handling | Built-in business handlers for server-initiated requests | ⚠️ | Without `onServerRequest`, only `ping` is implicitly accepted. |
| Streaming lifecycle | Long-lived managed background subscription API | ⚠️ | `readServerMessagesOnce()` provides one SSE read pass; lifecycle orchestration is app-managed. |
| Auth | Built-in OAuth/token lifecycle manager | ❌ | Caller supplies headers/tokens; credential lifecycle is out of scope. |
| ADK integration | Runner/tool wiring for ADK agents | ❌ | Integration lives in `adk_dart`, not in `adk_mcp`. |

## Install

```bash
dart pub add adk_mcp
```

## Usage

```dart
import 'package:adk_mcp/adk_mcp.dart';

final McpRemoteClient client = McpRemoteClient(
  clientInfoName: 'example_client',
  clientInfoVersion: '1.0.0',
);

final connection = StreamableHTTPConnectionParams(
  url: 'http://localhost:8000/mcp',
);

final Object? result = await client.call(
  connectionParams: connection,
  method: 'tools/list',
  params: const <String, Object?>{},
);
```

## Repository

- https://github.com/adk-labs/adk_dart

## License

Apache-2.0
