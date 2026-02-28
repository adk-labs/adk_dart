import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'package:adk_dart/src/agents/context.dart';
import 'package:adk_dart/src/agents/invocation_context.dart';
import 'package:adk_dart/src/agents/llm_agent.dart';
import 'package:adk_dart/src/agents/mcp_instruction_provider.dart';
import 'package:adk_dart/src/agents/readonly_context.dart';
import 'package:adk_dart/src/models/base_llm.dart';
import 'package:adk_dart/src/models/llm_request.dart';
import 'package:adk_dart/src/models/llm_response.dart';
import 'package:adk_dart/src/sessions/in_memory_session_service.dart';
import 'package:adk_dart/src/sessions/session.dart';
import 'package:adk_dart/src/tools/api_registry.dart';
import 'package:adk_dart/src/tools/base_tool.dart';
import 'package:adk_dart/src/tools/mcp_tool/mcp_session_manager.dart';
import 'package:adk_dart/src/tools/mcp_tool/mcp_toolset.dart';

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
    sessionId: 's_mcp_http',
  );
  return Context(
    InvocationContext(
      invocationId: 'inv_mcp_http',
      agent: Agent(name: 'root', model: _NoopModel()),
      session: session,
      sessionService: sessionService,
    ),
  );
}

InvocationContext _newInvocationContext({Map<String, Object?>? state}) {
  return InvocationContext(
    sessionService: InMemorySessionService(),
    invocationId: 'inv_mcp_instruction_http',
    agent: LlmAgent(name: 'root', instruction: 'hi'),
    session: Session(
      id: 's_mcp_instruction_http',
      appName: 'app',
      userId: 'u1',
      state: state ?? <String, Object?>{},
    ),
  );
}

Future<void> _respondJsonRpc(
  HttpRequest request, {
  required Object? id,
  Object? result,
  Map<String, Object?>? error,
  Map<String, String>? headers,
}) async {
  request.response.statusCode = HttpStatus.ok;
  request.response.headers.contentType = ContentType.json;
  if (headers != null) {
    headers.forEach(request.response.headers.set);
  }
  request.response.write(
    jsonEncode(<String, Object?>{
      'jsonrpc': '2.0',
      if (id case final Object responseId) 'id': responseId,
      if (error != null) 'error': error else 'result': result,
    }),
  );
  await request.response.close();
}

void main() {
  group('MCP HTTP integration', () {
    late HttpServer server;
    late StreamableHTTPConnectionParams connectionParams;
    late List<String> seenMethods;
    late Map<String, List<Map<String, String>>> seenHeadersByMethod;
    late bool resourcesReadSentLegacyNameParam;
    late Map<String, Object?> lastPromptGetArguments;

    setUp(() async {
      seenMethods = <String>[];
      seenHeadersByMethod = <String, List<Map<String, String>>>{};
      resourcesReadSentLegacyNameParam = false;
      lastPromptGetArguments = <String, Object?>{};
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      connectionParams = StreamableHTTPConnectionParams(
        url: 'http://${server.address.address}:${server.port}/mcp',
      );

      server.listen((HttpRequest request) async {
        final Map<String, String> requestHeaders = <String, String>{};
        request.headers.forEach((String name, List<String> values) {
          requestHeaders[name.toLowerCase()] = values.join(', ');
        });
        final String body = await utf8.decoder.bind(request).join();
        final Map<String, Object?> rpc = (jsonDecode(body) as Map).map(
          (Object? key, Object? value) => MapEntry('$key', value),
        );
        final Object? id = rpc['id'];
        final String method = '${rpc['method'] ?? ''}';
        seenMethods.add(method);
        seenHeadersByMethod
            .putIfAbsent(method, () => <Map<String, String>>[])
            .add(requestHeaders);

        switch (method) {
          case 'initialize':
            if (request.headers.value('x-init-mode') == 'unsupported') {
              await _respondJsonRpc(
                request,
                id: id,
                error: <String, Object?>{
                  'code': -32601,
                  'message': 'Method not found: initialize',
                },
              );
              return;
            }
            await _respondJsonRpc(
              request,
              id: id,
              result: <String, Object?>{
                'protocolVersion': '2025-11-25',
                'capabilities': <String, Object?>{
                  'tools': <String, Object?>{},
                  'resources': <String, Object?>{},
                  'prompts': <String, Object?>{},
                },
              },
              headers: <String, String>{'MCP-Session-Id': 'session-main'},
            );
            return;
          case 'notifications/initialized':
            request.response.statusCode = HttpStatus.accepted;
            await request.response.close();
            return;
          case 'tools/list':
            if (request.headers.value('x-sse-mode') ==
                'notify-before-response') {
              request.response.statusCode = HttpStatus.ok;
              request.response.headers.set(
                HttpHeaders.contentTypeHeader,
                'text/event-stream',
              );
              request.response.write(
                'data: ${jsonEncode(<String, Object?>{'jsonrpc': '2.0', 'method': 'notifications/tools/list_changed', 'params': <String, Object?>{}})}\n\n',
              );
              request.response.write(
                'data: ${jsonEncode(<String, Object?>{
                  'jsonrpc': '2.0',
                  'id': id,
                  'result': <String, Object?>{
                    'tools': <Map<String, Object?>>[
                      <String, Object?>{'name': 'remote_echo', 'description': 'Remote echo tool'},
                    ],
                  },
                })}\n\n',
              );
              await request.response.close();
              return;
            }
            await _respondJsonRpc(
              request,
              id: id,
              result: <String, Object?>{
                'tools': <Map<String, Object?>>[
                  <String, Object?>{
                    'name': 'remote_echo',
                    'description': 'Remote echo tool',
                    'inputSchema': <String, Object?>{
                      'type': 'object',
                      'properties': <String, Object?>{
                        'q': <String, Object?>{'type': 'string'},
                      },
                      'required': <String>['q'],
                    },
                  },
                ],
              },
            );
            return;
          case 'tools/call':
            final Map<String, Object?> params = (rpc['params'] as Map).map(
              (Object? key, Object? value) => MapEntry('$key', value),
            );
            final Map<String, Object?> args = (params['arguments'] as Map).map(
              (Object? key, Object? value) => MapEntry('$key', value),
            );
            final String query = '${args['q'] ?? ''}';
            if (query == 'boom') {
              await _respondJsonRpc(
                request,
                id: id,
                error: <String, Object?>{
                  'code': -32042,
                  'message': 'tool exploded',
                },
              );
              return;
            }
            await _respondJsonRpc(
              request,
              id: id,
              result: <String, Object?>{
                'structuredContent': <String, Object?>{'echo': query},
                'content': <Map<String, Object?>>[
                  <String, Object?>{'type': 'text', 'text': 'echo:$query'},
                ],
              },
            );
            return;
          case 'resources/list':
            await _respondJsonRpc(
              request,
              id: id,
              result: <String, Object?>{
                'resources': <Map<String, Object?>>[
                  <String, Object?>{'uri': 'docs://guide'},
                ],
              },
            );
            return;
          case 'resources/read':
            final Map<String, Object?> params = (rpc['params'] as Map).map(
              (Object? key, Object? value) => MapEntry('$key', value),
            );
            resourcesReadSentLegacyNameParam = params.containsKey('name');
            final String uri = '${params['uri'] ?? ''}';
            if (uri == 'docs://guide') {
              await _respondJsonRpc(
                request,
                id: id,
                result: <String, Object?>{
                  'contents': <Map<String, Object?>>[
                    <String, Object?>{
                      'uri': 'docs://guide',
                      'mimeType': 'text/plain',
                      'text': 'Remote MCP guide',
                    },
                  ],
                },
              );
              return;
            }
            await _respondJsonRpc(
              request,
              id: id,
              result: <String, Object?>{'contents': <Object>[]},
            );
            return;
          case 'prompts/list':
            await _respondJsonRpc(
              request,
              id: id,
              result: <String, Object?>{
                'prompts': <Map<String, Object?>>[
                  <String, Object?>{
                    'name': 'agent_prompt',
                    'arguments': <Map<String, Object?>>[
                      <String, Object?>{'name': 'city'},
                    ],
                  },
                  <String, Object?>{'name': 'error_prompt'},
                ],
              },
            );
            return;
          case 'resources/templates/list':
            await _respondJsonRpc(
              request,
              id: id,
              result: <String, Object?>{'resourceTemplates': <Object?>[]},
            );
            return;
          case 'prompts/get':
            final Map<String, Object?> params = (rpc['params'] as Map).map(
              (Object? key, Object? value) => MapEntry('$key', value),
            );
            lastPromptGetArguments = (params['arguments'] as Map? ?? const {})
                .map((Object? key, Object? value) => MapEntry('$key', value));
            final String name = '${params['name'] ?? ''}';
            if (name == 'agent_prompt') {
              await _respondJsonRpc(
                request,
                id: id,
                result: <String, Object?>{
                  'messages': <Map<String, Object?>>[
                    <String, Object?>{
                      'role': 'system',
                      'content': <String, Object?>{
                        'type': 'text',
                        'text': 'Hello {city}!',
                      },
                    },
                  ],
                },
              );
              return;
            }
            if (name == 'error_prompt') {
              await _respondJsonRpc(
                request,
                id: id,
                error: <String, Object?>{
                  'code': -32050,
                  'message': 'prompt read denied',
                },
              );
              return;
            }
            await _respondJsonRpc(
              request,
              id: id,
              result: <String, Object?>{'messages': <Object>[]},
            );
            return;
          default:
            await _respondJsonRpc(
              request,
              id: id,
              error: <String, Object?>{
                'code': -32601,
                'message': 'Method not found: $method',
              },
            );
            return;
        }
      });
    });

    tearDown(() async {
      McpSessionManager.instance.clear();
      await server.close(force: true);
    });

    test('discovers remote MCP tools and executes remote tool calls', () async {
      final ApiRegistry registry = ApiRegistry(apiRegistryProjectId: 'p1');
      registry.registerMcpServer(
        name: 'remote',
        connectionParams: connectionParams,
      );

      final McpToolset toolset = registry.getToolset('remote');
      final List<BaseTool> tools = await toolset.getTools();
      expect(tools, hasLength(1));
      expect(tools.first.name, 'remote_echo');

      final Object? result = await tools.first.run(
        args: <String, dynamic>{'q': 'hello'},
        toolContext: await _newToolContext(),
      );

      expect(result, isA<Map<String, Object?>>());
      final Map<String, Object?> payload = result! as Map<String, Object?>;
      expect(
        (payload['structuredContent'] as Map<String, Object?>)['echo'],
        'hello',
      );
      expect(seenMethods, contains('initialize'));
      expect(seenMethods, contains('notifications/initialized'));
      expect(seenMethods, contains('tools/list'));
      expect(seenMethods, contains('tools/call'));

      final Map<String, String> toolsListHeaders =
          seenHeadersByMethod['tools/list']!.single;
      final Map<String, String> initializeHeaders =
          seenHeadersByMethod['initialize']!.single;
      expect(initializeHeaders.containsKey('mcp-protocol-version'), isFalse);
      expect(toolsListHeaders['mcp-protocol-version'], '2025-11-25');
      expect(toolsListHeaders['mcp-session-id'], 'session-main');
      expect(toolsListHeaders['accept'], contains('text/event-stream'));
    });

    test('loads remote MCP resources through toolset', () async {
      final McpToolset toolset = McpToolset(connectionParams: connectionParams);

      final List<String> resourceNames = await toolset.listResources();
      expect(resourceNames, contains('docs://guide'));

      final List<McpResourceContent> resources = await toolset.readResource(
        'docs://guide',
      );
      expect(resources, hasLength(1));
      expect(resources.single.text, 'Remote MCP guide');
      expect(resourcesReadSentLegacyNameParam, isFalse);
      expect(seenMethods, contains('resources/list'));
      expect(seenMethods, contains('resources/read'));
    });

    test(
      'parses SSE responses when server sends notifications before result',
      () async {
        final StreamableHTTPConnectionParams sseParams =
            StreamableHTTPConnectionParams(
              url: connectionParams.url,
              headers: <String, String>{'x-sse-mode': 'notify-before-response'},
            );
        final McpToolset toolset = McpToolset(connectionParams: sseParams);

        final List<BaseTool> tools = await toolset.getTools();
        expect(tools, hasLength(1));
        expect(tools.single.name, 'remote_echo');
      },
    );

    test('instruction provider reads prompt via remote prompts/get', () async {
      final McpInstructionProvider provider = McpInstructionProvider(
        connectionParams: connectionParams,
        promptName: 'agent_prompt',
      );

      final InvocationContext invocationContext = _newInvocationContext(
        state: <String, Object?>{'city': 'Seoul', 'unused': 'ignored'},
      );
      final String instruction = await provider(
        ReadonlyContext(invocationContext),
      );

      expect(instruction, 'Hello Seoul!');
      expect(lastPromptGetArguments['city'], 'Seoul');
      expect(lastPromptGetArguments.containsKey('unused'), isFalse);
      expect(seenMethods, contains('prompts/list'));
      expect(seenMethods, contains('prompts/get'));
    });

    test('fails when initialize is unsupported by the server', () async {
      final StreamableHTTPConnectionParams unsupportedInitParams =
          StreamableHTTPConnectionParams(
            url: connectionParams.url,
            headers: <String, String>{'x-init-mode': 'unsupported'},
          );
      final McpToolset toolset = McpToolset(
        connectionParams: unsupportedInitParams,
      );

      await expectLater(
        toolset.getTools(),
        throwsA(
          predicate(
            (Object error) =>
                error is StateError &&
                '$error'.contains('(-32601)') &&
                '$error'.contains('Method not found: initialize'),
          ),
        ),
      );
      expect(seenMethods, isNot(contains('tools/list')));
    });

    test('propagates JSON-RPC tool call errors', () async {
      final McpToolset toolset = McpToolset(connectionParams: connectionParams);
      final List<BaseTool> tools = await toolset.getTools();

      expect(
        () async => tools.first.run(
          args: <String, dynamic>{'q': 'boom'},
          toolContext: await _newToolContext(),
        ),
        throwsA(
          predicate(
            (Object error) =>
                error is StateError &&
                '$error'.contains('(-32042)') &&
                '$error'.contains('tool exploded'),
          ),
        ),
      );
    });

    test('propagates JSON-RPC prompt errors to instruction provider', () async {
      final McpInstructionProvider provider = McpInstructionProvider(
        connectionParams: connectionParams,
        promptName: 'error_prompt',
      );

      expect(
        () async => provider(ReadonlyContext(_newInvocationContext())),
        throwsA(
          predicate(
            (Object error) =>
                error is StateError &&
                '$error'.contains('(-32050)') &&
                '$error'.contains('prompt read denied'),
          ),
        ),
      );
    });
  });

  group('MCP HTTP failure handling', () {
    tearDown(() {
      McpSessionManager.instance.clear();
    });

    test('retries initialize after transient initialization error', () async {
      final HttpServer flakyInitServer = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(() async {
        await flakyInitServer.close(force: true);
      });

      int initializeAttempts = 0;
      bool initialized = false;

      flakyInitServer.listen((HttpRequest request) async {
        final String body = await utf8.decoder.bind(request).join();
        final Map<String, Object?> rpc = (jsonDecode(body) as Map).map(
          (Object? key, Object? value) => MapEntry('$key', value),
        );
        final Object? id = rpc['id'];
        final String method = '${rpc['method'] ?? ''}';

        switch (method) {
          case 'initialize':
            initializeAttempts += 1;
            if (initializeAttempts == 1) {
              await _respondJsonRpc(
                request,
                id: id,
                error: <String, Object?>{
                  'code': -32001,
                  'message': 'temporary init failure',
                },
              );
              return;
            }
            initialized = true;
            await _respondJsonRpc(
              request,
              id: id,
              result: <String, Object?>{
                'protocolVersion': '2025-11-25',
                'capabilities': <String, Object?>{'tools': <String, Object?>{}},
              },
              headers: <String, String>{'MCP-Session-Id': 'session-flaky'},
            );
            return;
          case 'notifications/initialized':
            initialized = true;
            request.response.statusCode = HttpStatus.accepted;
            await request.response.close();
            return;
          case 'tools/list':
            if (!initialized) {
              await _respondJsonRpc(
                request,
                id: id,
                error: <String, Object?>{
                  'code': -32011,
                  'message': 'not initialized',
                },
              );
              return;
            }
            await _respondJsonRpc(
              request,
              id: id,
              result: <String, Object?>{
                'tools': <Map<String, Object?>>[
                  <String, Object?>{
                    'name': 'remote_echo',
                    'description': 'Remote echo tool',
                  },
                ],
              },
            );
            return;
          default:
            await _respondJsonRpc(
              request,
              id: id,
              error: <String, Object?>{
                'code': -32601,
                'message': 'Method not found: $method',
              },
            );
            return;
        }
      });

      final StreamableHTTPConnectionParams
      params = StreamableHTTPConnectionParams(
        url:
            'http://${flakyInitServer.address.address}:${flakyInitServer.port}/mcp',
      );
      final McpToolset toolset = McpToolset(connectionParams: params);

      await expectLater(
        toolset.getTools(),
        throwsA(
          predicate(
            (Object error) =>
                error is StateError &&
                '$error'.contains('(-32001)') &&
                '$error'.contains('temporary init failure'),
          ),
        ),
      );

      final List<BaseTool> tools = await toolset.getTools();
      expect(tools, hasLength(1));
      expect(initializeAttempts, 2);
    });

    test('does not attempt remote JSON-RPC for non-http MCP URLs', () async {
      final StreamableHTTPConnectionParams params =
          StreamableHTTPConnectionParams(url: 'mock://local');
      final McpToolset toolset = McpToolset(connectionParams: params);

      expect(await toolset.getTools(), isEmpty);
      expect(await toolset.listResources(), isEmpty);
      expect(await toolset.readResource('anything'), isEmpty);

      final McpInstructionProvider provider = McpInstructionProvider(
        connectionParams: params,
        promptName: 'missing_prompt',
      );
      await expectLater(
        provider(ReadonlyContext(_newInvocationContext())),
        throwsA(isA<StateError>()),
      );

      await expectLater(
        McpSessionManager.instance.callTool(
          connectionParams: params,
          toolName: 'missing_tool',
          args: <String, dynamic>{},
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('propagates transport errors for remote tool discovery', () async {
      final HttpServer unavailableServer = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final int closedPort = unavailableServer.port;
      await unavailableServer.close(force: true);

      final StreamableHTTPConnectionParams params =
          StreamableHTTPConnectionParams(
            url: 'http://127.0.0.1:$closedPort/mcp',
          );
      final McpToolset toolset = McpToolset(connectionParams: params);

      await expectLater(
        toolset.getTools(),
        throwsA(
          predicate(
            (Object error) =>
                error is SocketException ||
                error is HttpException ||
                '$error'.toLowerCase().contains('connection'),
          ),
        ),
      );
    });
  });
}
