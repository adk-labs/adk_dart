/// Remote MCP Server configuration.
library;

import 'dart:async';
import '../agents/readonly_context.dart';

/// Callback signature for dynamic MCP headers.
typedef RemoteMcpHeaderProvider = FutureOr<Map<String, String>?> Function(ReadonlyContext context);

/// A remote MCP server executed server-side by the Managed Agents API.
class RemoteMcpServer {
  /// Creates a remote MCP server configuration.
  RemoteMcpServer({
    required this.url,
    this.name,
    this.headers,
    this.allowedTools,
    this.headerProvider,
  });

  /// Full URL of the remote MCP server endpoint.
  final String url;

  /// Optional server label.
  final String? name;

  /// Static headers sent on every turn.
  final Map<String, String>? headers;

  /// Restrict which of the server's tools are exposed.
  final List<String>? allowedTools;

  /// Runtime callback that mints headers at request time.
  final RemoteMcpHeaderProvider? headerProvider;
}
