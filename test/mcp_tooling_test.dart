import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

void main() {
  tearDown(() {
    McpSessionManager.instance.clear();
  });

  test('ApiRegistry returns McpToolset with filtered/prefixed tools', () async {
    final StreamableHTTPConnectionParams connectionParams =
        StreamableHTTPConnectionParams(url: 'https://mcp.example');
    final FunctionTool t1 = FunctionTool(
      func: () => 'ok',
      name: 'tool_one',
      description: 'first',
    );
    final FunctionTool t2 = FunctionTool(
      func: () => 'ok',
      name: 'tool_two',
      description: 'second',
    );
    McpSessionManager.instance.registerTools(
      connectionParams: connectionParams,
      tools: <BaseTool>[t1, t2],
    );

    final ApiRegistry registry = ApiRegistry(apiRegistryProjectId: 'p1');
    registry.registerMcpServer(
      name: 'serverA',
      connectionParams: connectionParams,
    );

    final McpToolset toolset = registry.getToolset(
      'serverA',
      toolFilter: <String>['tool_one'],
      toolNamePrefix: 'mcp',
    );
    final List<BaseTool> tools = await toolset.getToolsWithPrefix();

    expect(tools, hasLength(1));
    expect(tools.first.name, 'mcp_tool_one');
  });
}
