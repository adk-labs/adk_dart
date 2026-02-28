# adk_mcp

`adk_mcp` provides MCP (Model Context Protocol) client primitives for Dart.

It includes:

- Streamable HTTP MCP client (`McpRemoteClient`)
- stdio MCP client (`McpStdioClient`)
- MCP constants, method names, protocol version handling, and JSON-RPC helpers

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
