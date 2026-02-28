import 'dart:io';

import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

class _NoopModel extends BaseLlm {
  _NoopModel() : super(model: 'noop');

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {}
}

Future<Context> _newToolContext() async {
  final InMemorySessionService sessionService = InMemorySessionService();
  final Session session = await sessionService.createSession(
    appName: 'app',
    userId: 'user',
    sessionId: 's_mcp_stdio',
  );
  return Context(
    InvocationContext(
      invocationId: 'inv_mcp_stdio',
      agent: Agent(name: 'root', model: _NoopModel()),
      session: session,
      sessionService: sessionService,
    ),
  );
}

Future<StdioConnectionParams> _createStdioServerParams() async {
  final Directory tempDir = await Directory.systemTemp.createTemp(
    'adk_stdio_integration_',
  );
  addTearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  final File script = File('${tempDir.path}/server.dart');
  await script.writeAsString(_serverScript);

  return StdioConnectionParams(
    command: Platform.resolvedExecutable,
    arguments: <String>[script.path],
    connectionId: 'adk-stdio-integration',
  );
}

const String _serverScript = r'''
import 'dart:convert';
import 'dart:io';

void respond(Object? id, {Object? result, Map<String, Object?>? error}) {
  stdout.writeln(
    jsonEncode(<String, Object?>{
      'jsonrpc': '2.0',
      if (id != null) 'id': id,
      if (error != null) 'error': error else 'result': result,
    }),
  );
}

Future<void> main() async {
  await for (final String line in stdin
      .transform(utf8.decoder)
      .transform(const LineSplitter())) {
    if (line.trim().isEmpty) {
      continue;
    }

    final Object? decoded = jsonDecode(line);
    if (decoded is! Map) {
      continue;
    }

    final Map<String, Object?> rpc = decoded.map(
      (Object? key, Object? value) => MapEntry<String, Object?>('$key', value),
    );
    final String method = '${rpc['method'] ?? ''}';
    final Object? id = rpc['id'];

    switch (method) {
      case 'initialize':
        respond(
          id,
          result: <String, Object?>{
            'protocolVersion': '2025-11-25',
            'capabilities': <String, Object?>{
              'tools': <String, Object?>{},
              'resources': <String, Object?>{},
              'prompts': <String, Object?>{},
            },
          },
        );
        continue;
      case 'notifications/initialized':
        continue;
      case 'tools/list':
        respond(
          id,
          result: <String, Object?>{
            'tools': <Map<String, Object?>>[
              <String, Object?>{
                'name': 'stdio_echo',
                'description': 'Echoes query',
                'inputSchema': <String, Object?>{
                  'type': 'object',
                  'properties': <String, Object?>{
                    'q': <String, Object?>{'type': 'string'},
                  },
                },
              },
            ],
          },
        );
        continue;
      case 'tools/call':
        final Map<String, Object?> params = (rpc['params'] as Map).map(
          (Object? key, Object? value) => MapEntry<String, Object?>('$key', value),
        );
        final Map<String, Object?> args = (params['arguments'] as Map).map(
          (Object? key, Object? value) => MapEntry<String, Object?>('$key', value),
        );
        final String q = '${args['q'] ?? ''}';
        respond(
          id,
          result: <String, Object?>{
            'structuredContent': <String, Object?>{'echo': q},
          },
        );
        continue;
      case 'resources/list':
        respond(
          id,
          result: <String, Object?>{
            'resources': <Map<String, Object?>>[
              <String, Object?>{'uri': 'docs://guide'},
            ],
          },
        );
        continue;
      case 'resources/templates/list':
        respond(
          id,
          error: <String, Object?>{
            'code': -32601,
            'message': 'Method not found: resources/templates/list',
          },
        );
        continue;
      case 'resources/read':
        respond(
          id,
          result: <String, Object?>{
            'contents': <Map<String, Object?>>[
              <String, Object?>{'text': 'Stdio MCP resource body'},
            ],
          },
        );
        continue;
      case 'prompts/list':
        respond(
          id,
          result: <String, Object?>{
            'prompts': <Map<String, Object?>>[
              <String, Object?>{'name': 'assistant_prompt'},
            ],
          },
        );
        continue;
      case 'prompts/get':
        respond(
          id,
          result: <String, Object?>{
            'messages': <Map<String, Object?>>[
              <String, Object?>{
                'role': 'system',
                'content': <String, Object?>{
                  'type': 'text',
                  'text': 'Prompt from stdio server',
                },
              },
            ],
          },
        );
        continue;
      default:
        respond(
          id,
          error: <String, Object?>{
            'code': -32601,
            'message': 'Method not found: $method',
          },
        );
        continue;
    }
  }
}
''';

void main() {
  tearDown(() {
    McpSessionManager.instance.clear();
  });

  test('McpToolset supports stdio MCP servers end-to-end', () async {
    final StdioConnectionParams params = await _createStdioServerParams();

    final ApiRegistry registry = ApiRegistry(apiRegistryProjectId: 'p1');
    registry.registerMcpServer(name: 'stdio', connectionParams: params);

    final McpToolset toolset = registry.getToolset('stdio');
    final List<BaseTool> tools = await toolset.getTools();
    expect(tools, hasLength(1));
    expect(tools.first.name, 'stdio_echo');

    final Object? result = await tools.first.run(
      args: <String, dynamic>{'q': 'hello-stdio'},
      toolContext: await _newToolContext(),
    );

    expect(result, isA<Map<String, Object?>>());
    final Map<String, Object?> map = result! as Map<String, Object?>;
    expect(
      (map['structuredContent'] as Map<String, Object?>)['echo'],
      'hello-stdio',
    );

    final List<String> resources = await toolset.listResources();
    expect(resources, contains('docs://guide'));

    final List<McpResourceContent> content = await toolset.readResource(
      'docs://guide',
    );
    expect(content.single.text, 'Stdio MCP resource body');
  });
}
