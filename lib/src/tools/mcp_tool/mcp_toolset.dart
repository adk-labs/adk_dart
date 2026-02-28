import '../../agents/readonly_context.dart';
import '../base_tool.dart';
import '../base_toolset.dart';
import 'mcp_session_manager.dart';
import 'mcp_tool.dart';

typedef McpHeaderProvider =
    Map<String, String> Function(ReadonlyContext readonlyContext);

class McpToolset extends BaseToolset {
  McpToolset({
    required this.connectionParams,
    super.toolFilter,
    super.toolNamePrefix,
    this.headerProvider,
  });

  final StreamableHTTPConnectionParams connectionParams;
  final McpHeaderProvider? headerProvider;

  @override
  Future<List<BaseTool>> getTools({ReadonlyContext? readonlyContext}) async {
    final McpSessionManager manager = McpSessionManager.instance;

    List<BaseTool> tools = manager.getTools(connectionParams);
    if (tools.isEmpty) {
      final List<Map<String, Object?>> descriptors = await manager
          .listRemoteToolDescriptors(connectionParams: connectionParams);

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

  Future<List<String>> listResources() async {
    return McpSessionManager.instance.listResourcesAsync(connectionParams);
  }

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

String _readString(Object? value) {
  if (value is String) {
    return value;
  }
  if (value == null) {
    return '';
  }
  return '$value';
}
