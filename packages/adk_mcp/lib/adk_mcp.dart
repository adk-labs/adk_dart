/// APIs for connecting to and interacting with Model Context Protocol servers.
///
/// ```dart
/// import 'package:adk_mcp/adk_mcp.dart';
///
/// Future<void> main() async {
///   final client = McpRemoteClient(
///     clientInfoName: 'example-client',
///     clientInfoVersion: '1.0.0',
///   );
///   final params = StreamableHTTPConnectionParams(
///     url: 'https://example.com/mcp',
///   );
///   final tools = await client.listTools(connectionParams: params);
/// }
/// ```
library;

export 'src/mcp_remote_client.dart';
export 'src/mcp_stdio_client_stub.dart'
    if (dart.library.io) 'src/mcp_stdio_client.dart';
