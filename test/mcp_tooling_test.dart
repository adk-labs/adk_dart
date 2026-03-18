import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

Future<void> _respondJsonRpc(
  HttpRequest request, {
  required Object? id,
  Object? result,
  Map<String, Object?>? error,
  Map<String, String>? headers,
}) async {
  request.response.statusCode = HttpStatus.ok;
  request.response.headers.contentType = ContentType.json;
  headers?.forEach(request.response.headers.set);
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

  test(
    'McpToolset forwards sampling callback and sampling capabilities to MCP sessions',
    () async {
      final HttpServer server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(() async => server.close(force: true));

      Map<String, Object?> initializeCapabilities = <String, Object?>{};
      final Completer<Map<String, Object?>> samplingResponseCompleter =
          Completer<Map<String, Object?>>();

      server.listen((HttpRequest request) async {
        final String body = await utf8.decoder.bind(request).join();
        final Map<String, Object?> rpc = (jsonDecode(body) as Map).map(
          (Object? key, Object? value) => MapEntry('$key', value),
        );
        final Object? id = rpc['id'];
        final String method = '${rpc['method'] ?? ''}';

        if (method.isEmpty && id != null) {
          if ('$id' == 'srv-sampling-1' &&
              !samplingResponseCompleter.isCompleted) {
            samplingResponseCompleter.complete(rpc);
          }
          request.response.statusCode = HttpStatus.accepted;
          await request.response.close();
          return;
        }

        switch (method) {
          case 'initialize':
            final Map<String, Object?> params = (rpc['params'] as Map).map(
              (Object? key, Object? value) => MapEntry('$key', value),
            );
            initializeCapabilities =
                (params['capabilities'] as Map?)?.map(
                  (Object? key, Object? value) => MapEntry('$key', value),
                ) ??
                <String, Object?>{};
            await _respondJsonRpc(
              request,
              id: id,
              result: <String, Object?>{
                'protocolVersion': '2025-11-25',
                'capabilities': <String, Object?>{
                  'tools': <String, Object?>{},
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
            request.response.statusCode = HttpStatus.ok;
            request.response.headers.set(
              HttpHeaders.contentTypeHeader,
              'text/event-stream',
            );
            request.response.write(
              'data: ${jsonEncode(<String, Object?>{
                'jsonrpc': '2.0',
                'id': 'srv-sampling-1',
                'method': 'sampling/createMessage',
                'params': <String, Object?>{
                  'messages': <Map<String, Object?>>[
                    <String, Object?>{
                      'role': 'user',
                      'content': <String, Object?>{'type': 'text', 'text': 'hello'},
                    },
                  ],
                },
              })}\n\n',
            );
            request.response.write(
              'data: ${jsonEncode(<String, Object?>{
                'jsonrpc': '2.0',
                'id': id,
                'result': <String, Object?>{
                  'tools': <Map<String, Object?>>[
                    <String, Object?>{'name': 'remote_echo'},
                  ],
                },
              })}\n\n',
            );
            await request.response.close();
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
        }
      });

      bool called = false;
      final McpToolset toolset = McpToolset(
        connectionParams: StreamableHTTPConnectionParams(
          url: 'http://${server.address.address}:${server.port}/mcp',
        ),
        samplingCallback: (
          List<Map<String, Object?>> messages, {
          Map<String, Object?>? params,
        }) {
          called = true;
          expect(messages.single['role'], 'user');
          expect((params?['messages'] as List).single, isA<Map>());
          return <String, Object?>{
            'model': 'test-model',
            'role': 'assistant',
            'content': <String, Object?>{'type': 'text', 'text': 'sampled'},
            'stopReason': 'endTurn',
          };
        },
        samplingCapabilities: <String, Object?>{
          'supportedModels': <String>['test-model'],
        },
      );

      final List<BaseTool> tools = await toolset.getTools();

      expect(called, isTrue);
      expect(tools.map((BaseTool tool) => tool.name), <String>['remote_echo']);
      expect(
        initializeCapabilities['sampling'],
        <String, Object?>{'supportedModels': <String>['test-model']},
      );
      final Map<String, Object?> samplingResponse =
          await samplingResponseCompleter.future.timeout(
            const Duration(seconds: 1),
          );
      expect(samplingResponse['id'], 'srv-sampling-1');
      expect(
        (samplingResponse['result'] as Map<String, Object?>)['model'],
        'test-model',
      );
    },
  );
}
