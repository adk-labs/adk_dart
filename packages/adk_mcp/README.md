# adk_mcp

English | [한국어](README.ko.md) | [日本語](README.ja.md) | [中文](README.zh.md)

`adk_mcp` provides MCP (Model Context Protocol) client primitives for Dart.

It includes:

- Streamable HTTP MCP client (`McpRemoteClient`)
- stdio MCP client (`McpStdioClient`)
- MCP constants, method names, protocol version handling, and JSON-RPC helpers

## Platform Support Matrix (Current)

Status legend:

- `Y` Supported
- `Partial` Partially supported / environment dependent
- `N` Not supported

| Feature / Surface | Dart VM / CLI | Flutter (Android/iOS/Linux/macOS/Windows) | Flutter Web | Notes |
| --- | --- | --- | --- | --- |
| `McpRemoteClient` (Streamable HTTP transport) | Y | Y | Y | HTTP/HTTPS only (`StreamableHTTPConnectionParams`). |
| Protocol negotiation + JSON-RPC helper methods | Y | Y | Y | Same protocol behavior across transports/platforms. |
| Server message/read loop (`readServerMessagesOnce`) | Y | Y | Y | Web requires CORS-compatible MCP endpoint for browser access. |
| `McpStdioClient` transport | Y | Partial | N | Web uses a stub that throws `UnsupportedError`; non-web requires local process support. |
| `StdioConnectionParams` process spawn (`Process.start`) | Y | Partial | N | Environment-dependent on Flutter runtime/sandbox policies. |
| HTTP session termination (`terminateSession`) | Y | Y | Y | Uses MCP Streamable HTTP DELETE termination flow. |
| Built-in credential/token lifecycle manager | N | N | N | Headers/tokens are caller-managed. |

## Feature Support Matrix (Current)

Status legend:

- `Y` Supported
- `Partial` Partial / integration required
- `N` Not supported yet

### Supported / Working

| Area | Feature | Status | Notes |
| --- | --- | --- | --- |
| Transport | Streamable HTTP MCP client | Y | JSON-RPC call/notify with initialize handshake support. |
| Transport | stdio MCP client | Y | Child-process based JSON-RPC transport. |
| Protocol | MCP protocol version negotiation | Y | Supports `2025-03-26`, `2025-06-18`, `2025-11-25`. |
| RPC helpers | Tools/resources/prompts/tasks/logging/sampling/roots/elicitation method helpers | Y | High-level helper methods are provided for client calls. |
| Paging | Cursor-based pagination helper (`collectPaginatedMaps`) | Y | Works for both HTTP and stdio clients. |
| Server events | Server notification/request callback hooks | Y | `onServerMessage` / `onServerRequest` are supported. |
| Session | HTTP session termination helper | Y | `terminateSession()` sends MCP DELETE termination request. |

### Partial / Not Yet Supported

| Area | Feature | Status | Notes |
| --- | --- | --- | --- |
| Package scope | MCP server implementation | N | `adk_mcp` is client-only. |
| Transport | WebSocket/other non-HTTP non-stdio transports | N | Only streamable HTTP and stdio are implemented. |
| Server request handling | Built-in business handlers for server-initiated requests | Partial | Without `onServerRequest`, only `ping` is implicitly accepted. |
| Streaming lifecycle | Long-lived managed background subscription API | Partial | `readServerMessagesOnce()` provides one SSE read pass; lifecycle orchestration is app-managed. |
| Auth | Built-in OAuth/token lifecycle manager | N | Caller supplies headers/tokens; credential lifecycle is out of scope. |
| ADK integration | Runner/tool wiring for ADK agents | N | Integration lives in `adk_dart`, not in `adk_mcp`. |

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
