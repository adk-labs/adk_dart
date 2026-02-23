import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

Future<Context> _newContext({
  String? functionCallId,
  ToolConfirmation? toolConfirmation,
}) async {
  final InMemorySessionService sessionService = InMemorySessionService();
  final Session session = await sessionService.createSession(
    appName: 'app',
    userId: 'user',
    sessionId: 's_mcp',
  );
  return Context(
    InvocationContext(
      invocationId: 'inv_mcp',
      agent: Agent(name: 'root', model: _NoopModel()),
      session: session,
      sessionService: sessionService,
    ),
    functionCallId: functionCallId,
    toolConfirmation: toolConfirmation,
  );
}

class _NoopModel extends BaseLlm {
  _NoopModel() : super(model: 'noop');

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {}
}

void main() {
  tearDown(() {
    McpSessionManager.instance.clear();
  });

  test(
    'LoadMcpResourceTool appends instructions and requested resources',
    () async {
      final StreamableHTTPConnectionParams params =
          StreamableHTTPConnectionParams(url: 'https://mcp.local');
      McpSessionManager.instance.registerResources(
        connectionParams: params,
        resources: <String, List<McpResourceContent>>{
          'docs://guide': <McpResourceContent>[
            McpResourceContent(text: 'Guide content for MCP usage'),
          ],
        },
      );

      final McpToolset toolset = McpToolset(connectionParams: params);
      final LoadMcpResourceTool tool = LoadMcpResourceTool(toolset);
      final Context context = await _newContext();

      final LlmRequest request = LlmRequest(
        contents: <Content>[
          Content(
            role: 'model',
            parts: <Part>[
              Part.fromFunctionResponse(
                name: 'load_mcp_resource',
                response: <String, dynamic>{
                  'resource_names': <String>['docs://guide'],
                },
              ),
            ],
          ),
        ],
      );

      await tool.processLlmRequest(toolContext: context, llmRequest: request);
      expect(
        request.config.systemInstruction,
        contains('You have a list of MCP resources'),
      );
      expect(
        request.contents.any((Content c) {
          return c.parts.any(
            (Part p) =>
                p.text != null &&
                p.text!.contains('Guide content for MCP usage'),
          );
        }),
        isTrue,
      );
    },
  );

  test('McpTool calls registered executor with auth headers', () async {
    final StreamableHTTPConnectionParams params =
        StreamableHTTPConnectionParams(url: 'https://mcp.exec');
    McpSessionManager.instance.registerToolExecutor(
      connectionParams: params,
      toolName: 'echo',
      executor: (Map<String, dynamic> args, {Map<String, String>? headers}) {
        return <String, Object?>{
          'args': args,
          'x_api_key': headers?['x-api-key'],
        };
      },
    );

    final McpTool tool = McpTool(
      mcpTool: McpBaseTool(
        name: 'echo',
        description: 'echo',
        inputSchema: <String, dynamic>{
          'type': 'object',
          'properties': <String, dynamic>{
            'q': <String, dynamic>{'type': 'string'},
          },
        },
      ),
      connectionParams: params,
      sessionManager: McpSessionManager.instance,
      authConfig: AuthConfig(
        authScheme: 'api_key',
        rawAuthCredential: AuthCredential(
          authType: AuthCredentialType.apiKey,
          apiKey: 'k1',
        ),
      ),
    );

    final Object? result = await tool.run(
      args: <String, dynamic>{'q': 'hello'},
      toolContext: await _newContext(),
    );
    expect(result, isA<Map<String, Object?>>());
    final Map<String, Object?> map = result! as Map<String, Object?>;
    expect((map['args'] as Map<String, dynamic>)['q'], 'hello');
    expect(map['x_api_key'], 'k1');
  });

  test('McpTool requests confirmation when required', () async {
    final StreamableHTTPConnectionParams params =
        StreamableHTTPConnectionParams(url: 'https://mcp.confirm');
    McpSessionManager.instance.registerToolExecutor(
      connectionParams: params,
      toolName: 'confirm_tool',
      executor: (Map<String, dynamic> args, {Map<String, String>? headers}) {
        return <String, Object?>{'ok': true};
      },
    );

    final McpTool tool = McpTool(
      mcpTool: McpBaseTool(name: 'confirm_tool', description: 'confirm'),
      connectionParams: params,
      sessionManager: McpSessionManager.instance,
      requireConfirmation: true,
    );

    final Context context = await _newContext(functionCallId: 'call_confirm');
    final Object? blocked = await tool.run(
      args: <String, dynamic>{'x': 1},
      toolContext: context,
    );
    expect((blocked as Map<String, Object>)['error'], isNotNull);
    expect(
      context.actions.requestedToolConfirmations.containsKey('call_confirm'),
      isTrue,
    );

    final Context approved = await _newContext(
      functionCallId: 'call_confirm',
      toolConfirmation: ToolConfirmation(confirmed: true),
    );
    final Object? result = await tool.run(
      args: <String, dynamic>{'x': 1},
      toolContext: approved,
    );
    expect((result as Map<String, Object?>)['ok'], isTrue);
  });
}
