import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:adk_mcp/adk_mcp.dart';
import 'package:test/test.dart';

Future<void> _respondJsonRpc(
  HttpRequest request, {
  required Object? id,
  Object? result,
  Map<String, Object?>? error,
  Map<String, String>? headers,
  String contentType = 'application/json',
}) async {
  request.response.statusCode = HttpStatus.ok;
  request.response.headers.set(HttpHeaders.contentTypeHeader, contentType);
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

Future<Map<String, Object?>> _readRpc(HttpRequest request) async {
  final String body = await utf8.decoder.bind(request).join();
  final Object? decoded = jsonDecode(body);
  if (decoded is! Map) {
    return <String, Object?>{};
  }
  return decoded.map(
    (Object? key, Object? value) => MapEntry<String, Object?>('$key', value),
  );
}

void main() {
  test('does not send protocol header on initialize', () async {
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    addTearDown(() async => server.close(force: true));

    final Map<String, String> seenHeaders = <String, String>{};
    server.listen((HttpRequest request) async {
      final String body = await utf8.decoder.bind(request).join();
      final Map<String, Object?> rpc = (jsonDecode(body) as Map).map(
        (Object? key, Object? value) => MapEntry('$key', value),
      );
      final String method = '${rpc['method'] ?? ''}';
      if (method == 'initialize') {
        request.headers.forEach((String name, List<String> values) {
          seenHeaders[name.toLowerCase()] = values.join(', ');
        });
        await _respondJsonRpc(
          request,
          id: rpc['id'],
          result: <String, Object?>{
            'protocolVersion': '2025-11-25',
            'capabilities': <String, Object?>{'tools': <String, Object?>{}},
          },
          headers: <String, String>{'MCP-Session-Id': 'session-main'},
        );
        return;
      }
      if (method == 'notifications/initialized') {
        request.response.statusCode = HttpStatus.accepted;
        await request.response.close();
        return;
      }
      await _respondJsonRpc(
        request,
        id: rpc['id'],
        result: <String, Object?>{'tools': <Object?>[]},
      );
    });

    final McpRemoteClient client = McpRemoteClient(
      clientInfoName: 'test_client',
      clientInfoVersion: '0.0.0',
    );
    final StreamableHTTPConnectionParams connectionParams =
        StreamableHTTPConnectionParams(
          url: 'http://${server.address.address}:${server.port}/mcp',
        );

    await client.ensureInitialized(connectionParams);

    expect(seenHeaders.containsKey('mcp-protocol-version'), isFalse);
  });

  test(
    'matches SSE responses by id and ignores prior server notifications',
    () async {
      final HttpServer server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(() async => server.close(force: true));

      server.listen((HttpRequest request) async {
        final String body = await utf8.decoder.bind(request).join();
        final Map<String, Object?> rpc = (jsonDecode(body) as Map).map(
          (Object? key, Object? value) => MapEntry('$key', value),
        );
        final String method = '${rpc['method'] ?? ''}';
        final Object? id = rpc['id'];

        switch (method) {
          case 'initialize':
            await _respondJsonRpc(
              request,
              id: id,
              result: <String, Object?>{
                'protocolVersion': '2025-11-25',
                'capabilities': <String, Object?>{'tools': <String, Object?>{}},
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
              'data: ${jsonEncode(<String, Object?>{'jsonrpc': '2.0', 'method': 'notifications/tools/list_changed', 'params': <String, Object?>{}})}\n\n',
            );
            request.response.write(
              'data: ${jsonEncode(<String, Object?>{
                'jsonrpc': '2.0',
                'id': 9999,
                'result': <String, Object?>{'tools': <Object?>[]},
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

      final StreamableHTTPConnectionParams connectionParams =
          StreamableHTTPConnectionParams(
            url: 'http://${server.address.address}:${server.port}/mcp',
          );
      final McpRemoteClient client = McpRemoteClient(
        clientInfoName: 'test_client',
        clientInfoVersion: '0.0.0',
      );

      final List<Map<String, Object?>> tools = await client
          .collectPaginatedMaps(
            connectionParams: connectionParams,
            method: 'tools/list',
            resultArrayField: 'tools',
          );

      expect(tools, hasLength(1));
      expect(tools.single['name'], 'remote_echo');
    },
  );

  test('sends notifications/cancelled when request times out', () async {
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    addTearDown(() async => server.close(force: true));

    final List<String> seenMethods = <String>[];
    server.listen((HttpRequest request) async {
      final String body = await utf8.decoder.bind(request).join();
      final Map<String, Object?> rpc = (jsonDecode(body) as Map).map(
        (Object? key, Object? value) => MapEntry('$key', value),
      );
      final String method = '${rpc['method'] ?? ''}';
      seenMethods.add(method);
      final Object? id = rpc['id'];

      switch (method) {
        case 'initialize':
          await _respondJsonRpc(
            request,
            id: id,
            result: <String, Object?>{
              'protocolVersion': '2025-11-25',
              'capabilities': <String, Object?>{'tools': <String, Object?>{}},
            },
            headers: <String, String>{'MCP-Session-Id': 'session-main'},
          );
          return;
        case 'notifications/initialized':
          request.response.statusCode = HttpStatus.accepted;
          await request.response.close();
          return;
        case 'tools/list':
          await Future<void>.delayed(const Duration(milliseconds: 300));
          await _respondJsonRpc(
            request,
            id: id,
            result: <String, Object?>{'tools': <Object?>[]},
          );
          return;
        case 'notifications/cancelled':
          request.response.statusCode = HttpStatus.accepted;
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

    final McpRemoteClient client = McpRemoteClient(
      clientInfoName: 'test_client',
      clientInfoVersion: '0.0.0',
      requestTimeout: const Duration(milliseconds: 80),
    );
    final StreamableHTTPConnectionParams connectionParams =
        StreamableHTTPConnectionParams(
          url: 'http://${server.address.address}:${server.port}/mcp',
        );

    await expectLater(
      client.collectPaginatedMaps(
        connectionParams: connectionParams,
        method: 'tools/list',
        resultArrayField: 'tools',
      ),
      throwsA(isA<TimeoutException>()),
    );

    await Future<void>.delayed(const Duration(milliseconds: 250));
    expect(seenMethods, contains('notifications/cancelled'));
  });

  test('covers 2025-11-25 client request/notification wrappers', () async {
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    addTearDown(() async => server.close(force: true));

    final List<String> seenMethods = <String>[];
    server.listen((HttpRequest request) async {
      final Map<String, Object?> rpc = await _readRpc(request);
      final String method = '${rpc['method'] ?? ''}';
      if (method.isNotEmpty) {
        seenMethods.add(method);
      }
      final Object? id = rpc['id'];

      switch (method) {
        case 'initialize':
          await _respondJsonRpc(
            request,
            id: id,
            result: <String, Object?>{
              'protocolVersion': '2025-11-25',
              'capabilities': <String, Object?>{
                'tools': <String, Object?>{'listChanged': true},
                'resources': <String, Object?>{
                  'subscribe': true,
                  'listChanged': true,
                },
                'prompts': <String, Object?>{'listChanged': true},
                'tasks': <String, Object?>{
                  'list': <String, Object?>{},
                  'cancel': <String, Object?>{},
                },
                'logging': <String, Object?>{},
                'completions': <String, Object?>{},
              },
            },
            headers: <String, String>{'MCP-Session-Id': 'session-main'},
          );
          return;
        case 'notifications/initialized':
        case 'notifications/progress':
        case 'notifications/roots/list_changed':
        case 'notifications/tasks/status':
        case 'notifications/cancelled':
          request.response.statusCode = HttpStatus.accepted;
          await request.response.close();
          return;
        case 'ping':
        case 'logging/setLevel':
        case 'resources/subscribe':
        case 'resources/unsubscribe':
          await _respondJsonRpc(request, id: id, result: <String, Object?>{});
          return;
        case 'completion/complete':
          await _respondJsonRpc(
            request,
            id: id,
            result: <String, Object?>{
              'completion': <String, Object?>{
                'values': <String>['one', 'two'],
                'total': 2,
                'hasMore': false,
              },
            },
          );
          return;
        case 'resources/list':
          await _respondJsonRpc(
            request,
            id: id,
            result: <String, Object?>{
              'resources': <Map<String, Object?>>[
                <String, Object?>{'uri': 'file:///r1', 'name': 'r1'},
              ],
            },
          );
          return;
        case 'resources/templates/list':
          await _respondJsonRpc(
            request,
            id: id,
            result: <String, Object?>{
              'resourceTemplates': <Map<String, Object?>>[
                <String, Object?>{'uriTemplate': 'file:///tmpl/{name}'},
              ],
            },
          );
          return;
        case 'resources/read':
          await _respondJsonRpc(
            request,
            id: id,
            result: <String, Object?>{
              'contents': <Map<String, Object?>>[
                <String, Object?>{
                  'uri': 'file:///r1',
                  'mimeType': 'text/plain',
                  'text': 'resource-body',
                },
              ],
            },
          );
          return;
        case 'prompts/list':
          await _respondJsonRpc(
            request,
            id: id,
            result: <String, Object?>{
              'prompts': <Map<String, Object?>>[
                <String, Object?>{'name': 'prompt.one'},
              ],
            },
          );
          return;
        case 'prompts/get':
          await _respondJsonRpc(
            request,
            id: id,
            result: <String, Object?>{
              'messages': <Map<String, Object?>>[
                <String, Object?>{
                  'role': 'user',
                  'content': <String, Object?>{'type': 'text', 'text': 'hello'},
                },
              ],
            },
          );
          return;
        case 'tools/list':
          await _respondJsonRpc(
            request,
            id: id,
            result: <String, Object?>{
              'tools': <Map<String, Object?>>[
                <String, Object?>{
                  'name': 'echo',
                  'description': 'echo tool',
                  'inputSchema': <String, Object?>{
                    'type': 'object',
                    'properties': <String, Object?>{
                      'text': <String, Object?>{'type': 'string'},
                    },
                  },
                },
              ],
            },
          );
          return;
        case 'tools/call':
          await _respondJsonRpc(
            request,
            id: id,
            result: <String, Object?>{
              'content': <Map<String, Object?>>[
                <String, Object?>{'type': 'text', 'text': 'done'},
              ],
              'isError': false,
            },
          );
          return;
        case 'tasks/list':
          await _respondJsonRpc(
            request,
            id: id,
            result: <String, Object?>{
              'tasks': <Map<String, Object?>>[
                <String, Object?>{
                  'taskId': 'task-1',
                  'status': 'completed',
                  'createdAt': '2026-02-28T00:00:00Z',
                  'updatedAt': '2026-02-28T00:00:01Z',
                },
              ],
            },
          );
          return;
        case 'tasks/get':
          await _respondJsonRpc(
            request,
            id: id,
            result: <String, Object?>{
              'taskId': 'task-1',
              'status': 'completed',
              'createdAt': '2026-02-28T00:00:00Z',
              'updatedAt': '2026-02-28T00:00:01Z',
            },
          );
          return;
        case 'tasks/result':
          await _respondJsonRpc(
            request,
            id: id,
            result: <String, Object?>{
              'content': <Map<String, Object?>>[
                <String, Object?>{'type': 'text', 'text': 'task-result'},
              ],
            },
          );
          return;
        case 'tasks/cancel':
          await _respondJsonRpc(
            request,
            id: id,
            result: <String, Object?>{
              'taskId': 'task-1',
              'status': 'cancelled',
              'createdAt': '2026-02-28T00:00:00Z',
              'updatedAt': '2026-02-28T00:00:02Z',
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
      }
    });

    final StreamableHTTPConnectionParams connectionParams =
        StreamableHTTPConnectionParams(
          url: 'http://${server.address.address}:${server.port}/mcp',
        );
    final McpRemoteClient client = McpRemoteClient(
      clientInfoName: 'test_client',
      clientInfoVersion: '0.0.0',
    );

    final Map<String, Object?> ping = await client.ping(
      connectionParams: connectionParams,
    );
    final Map<String, Object?> completion = await client.complete(
      connectionParams: connectionParams,
      ref: <String, Object?>{'type': 'ref/prompt', 'name': 'prompt.one'},
      argument: 'pr',
    );
    final Map<String, Object?> logResult = await client.setLoggingLevel(
      connectionParams: connectionParams,
      level: 'info',
    );
    final List<Map<String, Object?>> resources = await client.listResources(
      connectionParams: connectionParams,
    );
    final List<Map<String, Object?>> templates = await client
        .listResourceTemplates(connectionParams: connectionParams);
    final Map<String, Object?> readResource = await client.readResource(
      connectionParams: connectionParams,
      uri: 'file:///r1',
    );
    await client.subscribeResource(
      connectionParams: connectionParams,
      uri: 'file:///r1',
    );
    await client.unsubscribeResource(
      connectionParams: connectionParams,
      uri: 'file:///r1',
    );
    final List<Map<String, Object?>> prompts = await client.listPrompts(
      connectionParams: connectionParams,
    );
    final Map<String, Object?> prompt = await client.getPrompt(
      connectionParams: connectionParams,
      name: 'prompt.one',
    );
    final List<Map<String, Object?>> tools = await client.listTools(
      connectionParams: connectionParams,
    );
    final Map<String, Object?> toolCall = await client.callTool(
      connectionParams: connectionParams,
      name: 'echo',
      arguments: <String, Object?>{'text': 'hello'},
      task: <String, Object?>{'ttlMs': 1000},
    );
    final List<Map<String, Object?>> tasks = await client.listTasks(
      connectionParams: connectionParams,
    );
    final Map<String, Object?> task = await client.getTask(
      connectionParams: connectionParams,
      taskId: 'task-1',
    );
    final Map<String, Object?> taskResult = await client.getTaskResult(
      connectionParams: connectionParams,
      taskId: 'task-1',
    );
    final Map<String, Object?> cancelled = await client.cancelTask(
      connectionParams: connectionParams,
      taskId: 'task-1',
    );
    await client.notifyProgress(
      connectionParams: connectionParams,
      progressToken: 'tok-1',
      progress: 30,
      total: 100,
      message: 'in progress',
    );
    await client.notifyRootsListChanged(connectionParams: connectionParams);
    await client.notifyTaskStatus(
      connectionParams: connectionParams,
      status: <String, Object?>{
        'taskId': 'task-1',
        'status': 'running',
        'createdAt': '2026-02-28T00:00:00Z',
        'updatedAt': '2026-02-28T00:00:01Z',
      },
    );
    await client.notifyCancelledRequest(
      connectionParams: connectionParams,
      requestId: 999,
      reason: 'test_cancel',
    );

    expect(ping, isEmpty);
    expect(logResult, isEmpty);
    expect((completion['completion'] as Map)['values'], isNotEmpty);
    expect(resources.single['uri'], 'file:///r1');
    expect(templates.single['uriTemplate'], 'file:///tmpl/{name}');
    expect(readResource['contents'], isNotEmpty);
    expect(prompts.single['name'], 'prompt.one');
    expect(prompt['messages'], isNotEmpty);
    expect(tools.single['name'], 'echo');
    expect((toolCall['content'] as List).isNotEmpty, isTrue);
    expect(tasks.single['taskId'], 'task-1');
    expect(task['status'], 'completed');
    expect((taskResult['content'] as List).isNotEmpty, isTrue);
    expect(cancelled['status'], 'cancelled');

    expect(seenMethods, contains('ping'));
    expect(seenMethods, contains('completion/complete'));
    expect(seenMethods, contains('logging/setLevel'));
    expect(seenMethods, contains('resources/list'));
    expect(seenMethods, contains('resources/templates/list'));
    expect(seenMethods, contains('resources/read'));
    expect(seenMethods, contains('resources/subscribe'));
    expect(seenMethods, contains('resources/unsubscribe'));
    expect(seenMethods, contains('prompts/list'));
    expect(seenMethods, contains('prompts/get'));
    expect(seenMethods, contains('tools/list'));
    expect(seenMethods, contains('tools/call'));
    expect(seenMethods, contains('tasks/list'));
    expect(seenMethods, contains('tasks/get'));
    expect(seenMethods, contains('tasks/result'));
    expect(seenMethods, contains('tasks/cancel'));
    expect(seenMethods, contains('notifications/progress'));
    expect(seenMethods, contains('notifications/roots/list_changed'));
    expect(seenMethods, contains('notifications/tasks/status'));
    expect(seenMethods, contains('notifications/cancelled'));
  });

  test('automatically responds to server ping request over SSE', () async {
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    addTearDown(() async => server.close(force: true));

    final Completer<Map<String, Object?>> pingResponseCompleter =
        Completer<Map<String, Object?>>();
    server.listen((HttpRequest request) async {
      final Map<String, Object?> rpc = await _readRpc(request);
      final String method = '${rpc['method'] ?? ''}';
      final Object? id = rpc['id'];

      if (method.isEmpty && rpc.containsKey('result')) {
        if (!pingResponseCompleter.isCompleted) {
          pingResponseCompleter.complete(rpc);
        }
        request.response.statusCode = HttpStatus.accepted;
        await request.response.close();
        return;
      }

      switch (method) {
        case 'initialize':
          await _respondJsonRpc(
            request,
            id: id,
            result: <String, Object?>{
              'protocolVersion': '2025-11-25',
              'capabilities': <String, Object?>{'tools': <String, Object?>{}},
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
            'data: ${jsonEncode(<String, Object?>{'jsonrpc': '2.0', 'id': 'srv-ping-1', 'method': 'ping', 'params': <String, Object?>{}})}\n\n',
          );
          request.response.write(
            'data: ${jsonEncode(<String, Object?>{
              'jsonrpc': '2.0',
              'id': id,
              'result': <String, Object?>{
                'tools': <Map<String, Object?>>[
                  <String, Object?>{'name': 'echo'},
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

    final McpRemoteClient client = McpRemoteClient(
      clientInfoName: 'test_client',
      clientInfoVersion: '0.0.0',
    );
    final StreamableHTTPConnectionParams connectionParams =
        StreamableHTTPConnectionParams(
          url: 'http://${server.address.address}:${server.port}/mcp',
        );

    final List<Map<String, Object?>> tools = await client.listTools(
      connectionParams: connectionParams,
    );
    expect(tools.single['name'], 'echo');

    final Map<String, Object?> pingResponse = await pingResponseCompleter.future
        .timeout(const Duration(seconds: 1));
    expect(pingResponse['id'], 'srv-ping-1');
    expect(pingResponse['result'], <String, Object?>{});
  });

  test('uses onServerRequest callback for server-initiated requests', () async {
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    addTearDown(() async => server.close(force: true));

    final Completer<Map<String, Object?>> rootsResponseCompleter =
        Completer<Map<String, Object?>>();
    server.listen((HttpRequest request) async {
      final Map<String, Object?> rpc = await _readRpc(request);
      final String method = '${rpc['method'] ?? ''}';
      final Object? id = rpc['id'];

      if (method.isEmpty && rpc.containsKey('result')) {
        if (!rootsResponseCompleter.isCompleted) {
          rootsResponseCompleter.complete(rpc);
        }
        request.response.statusCode = HttpStatus.accepted;
        await request.response.close();
        return;
      }

      switch (method) {
        case 'initialize':
          await _respondJsonRpc(
            request,
            id: id,
            result: <String, Object?>{
              'protocolVersion': '2025-11-25',
              'capabilities': <String, Object?>{'tools': <String, Object?>{}},
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
            'data: ${jsonEncode(<String, Object?>{'jsonrpc': '2.0', 'id': 77, 'method': 'roots/list', 'params': <String, Object?>{}})}\n\n',
          );
          request.response.write(
            'data: ${jsonEncode(<String, Object?>{
              'jsonrpc': '2.0',
              'id': id,
              'result': <String, Object?>{'tools': <Object?>[]},
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

    final McpRemoteClient client = McpRemoteClient(
      clientInfoName: 'test_client',
      clientInfoVersion: '0.0.0',
      onServerRequest: (McpServerMessage request) {
        if (request.method == 'roots/list') {
          return <String, Object?>{
            'roots': <Map<String, Object?>>[
              <String, Object?>{
                'uri': 'file:///workspace',
                'name': 'workspace',
              },
            ],
          };
        }
        return const <String, Object?>{};
      },
    );
    final StreamableHTTPConnectionParams connectionParams =
        StreamableHTTPConnectionParams(
          url: 'http://${server.address.address}:${server.port}/mcp',
        );

    await client.listTools(connectionParams: connectionParams);

    final Map<String, Object?> rootsResponse = await rootsResponseCompleter
        .future
        .timeout(const Duration(seconds: 1));
    expect(rootsResponse['id'], 77);
    expect(
      (rootsResponse['result'] as Map<String, Object?>)['roots'],
      isNotEmpty,
    );
  });

  test('rejects invalid logging level', () async {
    final McpRemoteClient client = McpRemoteClient(
      clientInfoName: 'test_client',
      clientInfoVersion: '0.0.0',
    );

    await expectLater(
      () async => client.setLoggingLevel(
        connectionParams: StreamableHTTPConnectionParams(
          url: 'https://example.com/mcp',
        ),
        level: 'verbose',
      ),
      throwsArgumentError,
    );
  });

  test('terminates session with DELETE and session headers', () async {
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    addTearDown(() async => server.close(force: true));

    final Map<String, String> deleteHeaders = <String, String>{};
    server.listen((HttpRequest request) async {
      if (request.method == 'DELETE') {
        request.headers.forEach((String name, List<String> values) {
          deleteHeaders[name.toLowerCase()] = values.join(', ');
        });
        request.response.statusCode = HttpStatus.ok;
        await request.response.close();
        return;
      }

      final Map<String, Object?> rpc = await _readRpc(request);
      final String method = '${rpc['method'] ?? ''}';
      final Object? id = rpc['id'];
      if (method == 'initialize') {
        await _respondJsonRpc(
          request,
          id: id,
          result: <String, Object?>{
            'protocolVersion': '2025-11-25',
            'capabilities': <String, Object?>{},
          },
          headers: <String, String>{'MCP-Session-Id': 'delete-session-id'},
        );
        return;
      }
      if (method == 'notifications/initialized') {
        request.response.statusCode = HttpStatus.accepted;
        await request.response.close();
        return;
      }
      await _respondJsonRpc(
        request,
        id: id,
        error: <String, Object?>{
          'code': -32601,
          'message': 'Method not found: $method',
        },
      );
    });

    final McpRemoteClient client = McpRemoteClient(
      clientInfoName: 'test_client',
      clientInfoVersion: '0.0.0',
    );
    final StreamableHTTPConnectionParams connectionParams =
        StreamableHTTPConnectionParams(
          url: 'http://${server.address.address}:${server.port}/mcp',
        );

    await client.ensureInitialized(connectionParams);
    expect(client.sessionId(connectionParams), 'delete-session-id');

    await client.terminateSession(connectionParams: connectionParams);
    expect(deleteHeaders['mcp-session-id'], 'delete-session-id');
    expect(deleteHeaders['mcp-protocol-version'], '2025-11-25');
    expect(client.sessionId(connectionParams), isNull);
  });

  test('reads server notifications from GET SSE stream', () async {
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    addTearDown(() async => server.close(force: true));

    server.listen((HttpRequest request) async {
      if (request.method == 'GET') {
        request.response.statusCode = HttpStatus.ok;
        request.response.headers.set(
          HttpHeaders.contentTypeHeader,
          'text/event-stream',
        );
        request.response.write(
          'data: ${jsonEncode(<String, Object?>{
            'jsonrpc': '2.0',
            'method': 'notifications/message',
            'params': <String, Object?>{'level': 'info', 'data': 'hello'},
          })}\n\n',
        );
        await request.response.close();
        return;
      }

      final Map<String, Object?> rpc = await _readRpc(request);
      final String method = '${rpc['method'] ?? ''}';
      final Object? id = rpc['id'];
      if (method == 'initialize') {
        await _respondJsonRpc(
          request,
          id: id,
          result: <String, Object?>{
            'protocolVersion': '2025-11-25',
            'capabilities': <String, Object?>{},
          },
          headers: <String, String>{'MCP-Session-Id': 'stream-session-id'},
        );
        return;
      }
      if (method == 'notifications/initialized') {
        request.response.statusCode = HttpStatus.accepted;
        await request.response.close();
        return;
      }
      await _respondJsonRpc(
        request,
        id: id,
        error: <String, Object?>{
          'code': -32601,
          'message': 'Method not found: $method',
        },
      );
    });

    final List<McpServerMessage> notifications = <McpServerMessage>[];
    final McpRemoteClient client = McpRemoteClient(
      clientInfoName: 'test_client',
      clientInfoVersion: '0.0.0',
      onServerMessage: notifications.add,
    );
    final StreamableHTTPConnectionParams connectionParams =
        StreamableHTTPConnectionParams(
          url: 'http://${server.address.address}:${server.port}/mcp',
        );

    final List<McpServerMessage> streamed = await client
        .readServerMessagesOnce(connectionParams: connectionParams)
        .toList();

    expect(streamed, hasLength(1));
    expect(streamed.single.method, 'notifications/message');
    expect(streamed.single.params['level'], 'info');
    expect(streamed.single.params['data'], 'hello');
    expect(notifications, hasLength(1));
  });

  test('handles sampling and elicitation server requests via callback', () async {
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    addTearDown(() async => server.close(force: true));

    final Completer<Map<String, Object?>> samplingResponseCompleter =
        Completer<Map<String, Object?>>();
    final Completer<Map<String, Object?>> elicitationResponseCompleter =
        Completer<Map<String, Object?>>();

    server.listen((HttpRequest request) async {
      final Map<String, Object?> rpc = await _readRpc(request);
      final String method = '${rpc['method'] ?? ''}';
      final Object? id = rpc['id'];

      if (method.isEmpty && id != null) {
        if ('$id' == 'srv-sampling-1' &&
            !samplingResponseCompleter.isCompleted) {
          samplingResponseCompleter.complete(rpc);
        }
        if ('$id' == 'srv-elicit-1' &&
            !elicitationResponseCompleter.isCompleted) {
          elicitationResponseCompleter.complete(rpc);
        }
        request.response.statusCode = HttpStatus.accepted;
        await request.response.close();
        return;
      }

      switch (method) {
        case 'initialize':
          await _respondJsonRpc(
            request,
            id: id,
            result: <String, Object?>{
              'protocolVersion': '2025-11-25',
              'capabilities': <String, Object?>{'tools': <String, Object?>{}},
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
              'id': 'srv-elicit-1',
              'method': 'elicitation/create',
              'params': <String, Object?>{
                'mode': 'form',
                'message': 'Need email',
                'requestedSchema': <String, Object?>{
                  'type': 'object',
                  'properties': <String, Object?>{
                    'email': <String, Object?>{'type': 'string', 'format': 'email'},
                  },
                  'required': <String>['email'],
                },
              },
            })}\n\n',
          );
          request.response.write(
            'data: ${jsonEncode(<String, Object?>{
              'jsonrpc': '2.0',
              'id': id,
              'result': <String, Object?>{
                'tools': <Map<String, Object?>>[
                  <String, Object?>{'name': 'echo'},
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

    final McpRemoteClient client = McpRemoteClient(
      clientInfoName: 'test_client',
      clientInfoVersion: '0.0.0',
      onServerRequest: (McpServerMessage request) {
        if (request.method == 'sampling/createMessage') {
          return <String, Object?>{
            'model': 'test-model',
            'role': 'assistant',
            'content': <String, Object?>{'type': 'text', 'text': 'sampled'},
            'stopReason': 'endTurn',
          };
        }
        if (request.method == 'elicitation/create') {
          return <String, Object?>{
            'action': 'accept',
            'content': <String, Object?>{'email': 'user@example.com'},
          };
        }
        return const <String, Object?>{};
      },
    );
    final StreamableHTTPConnectionParams connectionParams =
        StreamableHTTPConnectionParams(
          url: 'http://${server.address.address}:${server.port}/mcp',
        );

    final List<Map<String, Object?>> tools = await client.listTools(
      connectionParams: connectionParams,
    );
    expect(tools.single['name'], 'echo');

    final Map<String, Object?> samplingResponse =
        await samplingResponseCompleter.future.timeout(
          const Duration(seconds: 1),
        );
    expect(samplingResponse['id'], 'srv-sampling-1');
    expect(
      (samplingResponse['result'] as Map<String, Object?>)['model'],
      'test-model',
    );

    final Map<String, Object?> elicitationResponse =
        await elicitationResponseCompleter.future.timeout(
          const Duration(seconds: 1),
        );
    expect(elicitationResponse['id'], 'srv-elicit-1');
    expect(
      (elicitationResponse['result'] as Map<String, Object?>)['action'],
      'accept',
    );
  });
}
