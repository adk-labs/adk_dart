import '../agents/readonly_context.dart';
import 'base_toolset.dart';
import 'mcp_tool/mcp_session_manager.dart';
import 'mcp_tool/mcp_toolset.dart';

class RegisteredMcpServer {
  RegisteredMcpServer({required this.name, required this.connectionParams});

  final String name;
  final StreamableHTTPConnectionParams connectionParams;
}

class ApiRegistry {
  ApiRegistry({
    required this.apiRegistryProjectId,
    this.location = 'global',
    this.headerProvider,
    Iterable<RegisteredMcpServer>? mcpServers,
  }) {
    if (mcpServers != null) {
      for (final RegisteredMcpServer server in mcpServers) {
        _mcpServers[server.name] = server;
      }
    }
  }

  final String apiRegistryProjectId;
  final String location;
  final Map<String, String> Function(ReadonlyContext)? headerProvider;
  final Map<String, RegisteredMcpServer> _mcpServers =
      <String, RegisteredMcpServer>{};

  void registerMcpServer({
    required String name,
    required StreamableHTTPConnectionParams connectionParams,
  }) {
    _mcpServers[name] = RegisteredMcpServer(
      name: name,
      connectionParams: connectionParams,
    );
  }

  List<String> listMcpServers() {
    return _mcpServers.keys.toList(growable: false);
  }

  McpToolset getToolset(
    String mcpServerName, {
    Object? toolFilter,
    String? toolNamePrefix,
  }) {
    final RegisteredMcpServer? server = _mcpServers[mcpServerName];
    if (server == null) {
      throw ArgumentError('MCP server `$mcpServerName` not found.');
    }

    return McpToolset(
      connectionParams: server.connectionParams,
      toolFilter: toolFilter is ToolPredicate || toolFilter is List<String>
          ? toolFilter
          : null,
      toolNamePrefix: toolNamePrefix,
      headerProvider: headerProvider,
    );
  }
}
