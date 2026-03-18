/// Toolset that materializes tools from MCP server connections.
library;

import '../../agents/readonly_context.dart';
import '../base_tool.dart';
import '../base_toolset.dart';
import 'mcp_session_manager.dart';
import 'mcp_tool.dart';

/// Header-builder callback applied to MCP tool calls in this toolset.
typedef McpHeaderProvider =
    Map<String, String> Function(ReadonlyContext readonlyContext);

/// Toolset that exposes tools and resources from one MCP connection.
class McpToolset extends BaseToolset {
  /// Creates an MCP toolset bound to [connectionParams].
  McpToolset({
    required this.connectionParams,
    super.toolFilter,
    super.toolNamePrefix,
    this.headerProvider,
    this.samplingCallback,
    Map<String, Object?>? samplingCapabilities,
  }) : samplingCapabilities = samplingCapabilities ?? <String, Object?>{} {
    McpSessionManager.instance.configureConnection(
      connectionParams: connectionParams,
      samplingCallback: samplingCallback,
      samplingCapabilities: this.samplingCapabilities,
    );
  }

  /// MCP transport parameters for this toolset.
  final McpConnectionParams connectionParams;

  /// Optional callback for injecting request headers dynamically.
  final McpHeaderProvider? headerProvider;

  /// Optional callback used to answer MCP `sampling/createMessage` requests.
  final McpSamplingCallback? samplingCallback;

  /// Optional MCP client capabilities advertised for sampling support.
  final Map<String, Object?> samplingCapabilities;

  @override
  /// Returns filtered MCP tools discovered from cache or remote server.
  Future<List<BaseTool>> getTools({ReadonlyContext? readonlyContext}) async {
    final McpSessionManager manager = McpSessionManager.instance;

    List<BaseTool> tools = manager.getTools(connectionParams);
    if (tools.isEmpty) {
      final List<Map<String, Object?>> descriptors = await manager
          .listRemoteToolDescriptors(
            connectionParams: connectionParams,
            forceRefresh: true,
          );

      tools = descriptors
          .map((Map<String, Object?> descriptor) {
            final String name = _readString(descriptor['name']);
            if (name.isEmpty) {
              return null;
            }
            final String description = _readString(descriptor['description']);
            return McpTool(
              mcpTool: McpBaseTool(
                name: name,
                description: description,
                inputSchema: _readSchema(descriptor, const <String>[
                  'inputSchema',
                  'input_schema',
                  'parameters',
                ]),
                outputSchema: _readSchema(descriptor, const <String>[
                  'outputSchema',
                  'output_schema',
                ]),
                meta: _readObjectMap(descriptor['meta']),
              ),
              connectionParams: connectionParams,
              sessionManager: manager,
              headerProvider: headerProvider,
            );
          })
          .whereType<BaseTool>()
          .toList(growable: false);
    }

    if (tools.isEmpty) {
      return const <BaseTool>[];
    }

    return tools
        .where((BaseTool tool) => isToolSelected(tool, readonlyContext))
        .toList(growable: false);
  }

  /// Lists available MCP resource names.
  Future<List<String>> listResources() async {
    return McpSessionManager.instance.listResourcesAsync(connectionParams);
  }

  /// Reads one named MCP resource into content parts.
  Future<List<McpResourceContent>> readResource(String resourceName) async {
    return McpSessionManager.instance.readResourceAsync(
      connectionParams: connectionParams,
      resourceName: resourceName,
    );
  }
}

Map<String, dynamic> _readSchema(
  Map<String, Object?> descriptor,
  List<String> keys,
) {
  for (final String key in keys) {
    final Object? value = descriptor[key];
    if (value is Map<String, dynamic>) {
      return Map<String, dynamic>.from(value);
    }
    if (value is Map) {
      return value.map(
        (Object? mapKey, Object? mapValue) => MapEntry('$mapKey', mapValue),
      );
    }
  }
  return <String, dynamic>{};
}

Map<String, Object?> _readObjectMap(Object? value) {
  if (value is Map<String, Object?>) {
    return Map<String, Object?>.from(value);
  }
  if (value is Map) {
    return value.map(
      (Object? mapKey, Object? mapValue) => MapEntry('$mapKey', mapValue),
    );
  }
  return <String, Object?>{};
}

String _readString(Object? value) {
  if (value is String) {
    return value;
  }
  if (value == null) {
    return '';
  }
  return '$value';
}
