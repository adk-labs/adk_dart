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

  test('ApiRegistry.create loads remote MCP servers with pagination', () async {
    final StreamableHTTPConnectionParams connectionParams =
        StreamableHTTPConnectionParams(url: 'https://mcp.remote');
    McpSessionManager.instance.registerTools(
      connectionParams: connectionParams,
      tools: <BaseTool>[
        FunctionTool(func: () => 'ok', name: 'tool_one', description: 'first'),
      ],
    );

    final List<Uri> requestedUris = <Uri>[];
    final List<Map<String, String>> requestedHeaders = <Map<String, String>>[];
    final ApiRegistry registry = await ApiRegistry.create(
      apiRegistryProjectId: 'p1',
      httpGetProvider: (Uri uri, {required Map<String, String> headers}) async {
        requestedUris.add(uri);
        requestedHeaders.add(Map<String, String>.from(headers));
        final String? pageToken = uri.queryParameters['pageToken'];
        if (pageToken == null) {
          return ApiRegistryHttpResponse(
            statusCode: 200,
            body: <String, Object?>{
              'mcpServers': <Map<String, Object?>>[
                <String, Object?>{
                  'name': 'serverA',
                  'urls': <String>['mcp.remote'],
                },
              ],
              'nextPageToken': 'page-2',
            },
          );
        }
        return ApiRegistryHttpResponse(
          statusCode: 200,
          body: <String, Object?>{
            'mcpServers': <Map<String, Object?>>[
              <String, Object?>{
                'name': 'serverB',
                'urls': <String>['https://mcp.other'],
              },
            ],
          },
        );
      },
      authHeadersProvider: () async {
        return <String, String>{'Authorization': 'Bearer token'};
      },
    );

    expect(registry.listMcpServers(), <String>['serverA', 'serverB']);
    expect(requestedUris, hasLength(2));
    expect(
      requestedUris.first.toString(),
      contains('/v1beta/projects/p1/locations/global/mcpServers'),
    );
    expect(requestedUris.last.queryParameters['pageToken'], 'page-2');
    expect(
      requestedHeaders.first,
      containsPair('Authorization', 'Bearer token'),
    );

    final McpToolset toolset = registry.getToolset('serverA');
    final List<BaseTool> tools = await toolset.getTools();
    expect(tools.map((BaseTool tool) => tool.name), <String>['tool_one']);
  });
}
