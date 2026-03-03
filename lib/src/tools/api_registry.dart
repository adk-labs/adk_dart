import '../agents/readonly_context.dart';
import 'base_toolset.dart';
import 'mcp_tool/mcp_session_manager.dart';
import 'mcp_tool/mcp_toolset.dart';

/// Registered MCP server connection details.
class RegisteredMcpServer {
  /// Creates a registered MCP server entry.
  RegisteredMcpServer({required this.name, required this.connectionParams});

  /// Logical server name used for lookups.
  final String name;

  /// Connection parameters for this MCP server.
  final McpConnectionParams connectionParams;
}

/// Registry that resolves MCP-backed toolsets for ADK tools.
class ApiRegistry {
  /// Creates an API registry scoped to one API Registry project.
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

  /// API Registry project identifier.
  final String apiRegistryProjectId;

  /// API Registry location.
  final String location;

  /// Optional header provider used when connecting to MCP servers.
  final Map<String, String> Function(ReadonlyContext)? headerProvider;
  final Map<String, RegisteredMcpServer> _mcpServers =
      <String, RegisteredMcpServer>{};

  /// Registers or replaces an MCP server entry.
  void registerMcpServer({
    required String name,
    required McpConnectionParams connectionParams,
  }) {
    _mcpServers[name] = RegisteredMcpServer(
      name: name,
      connectionParams: connectionParams,
    );
  }

  /// Lists registered MCP server names.
  List<String> listMcpServers() {
    return _mcpServers.keys.toList(growable: false);
  }

  /// Returns an [McpToolset] bound to [mcpServerName].
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
