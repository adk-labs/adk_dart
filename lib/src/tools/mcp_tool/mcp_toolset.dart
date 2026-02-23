import '../../agents/readonly_context.dart';
import '../base_tool.dart';
import '../base_toolset.dart';
import 'mcp_session_manager.dart';

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
    final List<BaseTool> tools = McpSessionManager.instance.getTools(
      connectionParams,
    );
    if (tools.isEmpty) {
      return const <BaseTool>[];
    }
    return tools
        .where((BaseTool tool) => isToolSelected(tool, readonlyContext))
        .toList(growable: false);
  }

  Future<List<String>> listResources() async {
    return McpSessionManager.instance.listResources(connectionParams);
  }

  Future<List<McpResourceContent>> readResource(String resourceName) async {
    return McpSessionManager.instance.readResource(
      connectionParams: connectionParams,
      resourceName: resourceName,
    );
  }
}
