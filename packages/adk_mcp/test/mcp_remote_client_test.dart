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

  test('McpResourceContent and McpServerMessage properties', () {
    final res = McpResourceContent(text: 'txt', blob: 'aW1n', mimeType: 'text/plain');
    expect(res.text, 'txt');
    expect(res.blob, 'aW1n');
    expect(res.mimeType, 'text/plain');

    final msgNotif = McpServerMessage(
      url: 'http://test',
      method: mcpMethodResourcesListChangedNotification,
      params: const <String, Object?>{},
    );
    expect(msgNotif.isNotification, isTrue);
    expect(msgNotif.isResourceListChangedNotification, isTrue);
    expect(msgNotif.isResourceUpdatedNotification, isFalse);

    final msgUpd = McpServerMessage(url: 'http://test', method: mcpMethodResourcesUpdatedNotification, params: const {});
    expect(msgUpd.isResourceUpdatedNotification, isTrue);

    final msgPrompt = McpServerMessage(url: 'http://test', method: mcpMethodPromptsListChangedNotification, params: const {});
    expect(msgPrompt.isPromptListChangedNotification, isTrue);

    final msgTool = McpServerMessage(url: 'http://test', method: mcpMethodToolsListChangedNotification, params: const {});
    expect(msgTool.isToolListChangedNotification, isTrue);

    final msgTask = McpServerMessage(url: 'http://test', method: mcpMethodTasksStatusNotification, params: const {});
    expect(msgTask.isTaskStatusNotification, isTrue);

    final msgLog = McpServerMessage(url: 'http://test', method: mcpMethodLoggingMessageNotification, params: const {});
    expect(msgLog.isLoggingMessageNotification, isTrue);

    final msgElicit = McpServerMessage(url: 'http://test', method: mcpMethodElicitationCompleteNotification, params: const {});
    expect(msgElicit.isElicitationCompleteNotification, isTrue);
  });

  test('McpRemoteClient negotiated capabilities and session queries', () async {
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
      if (method == 'initialize') {
        await _respondJsonRpc(
          request,
          id: rpc['id'],
          result: <String, Object?>{
            'protocolVersion': '2025-11-25',
            'capabilities': <String, Object?>{
              'tools': <String, Object?>{},
              'experimental': true,
            },
          },
          headers: <String, String>{'MCP-Session-Id': 'session-cap-test'},
        );
        return;
      }
      if (method == 'notifications/initialized') {
        request.response.statusCode = HttpStatus.accepted;
        await request.response.close();
        return;
      }
      if (method == 'resources/list') {
        await _respondJsonRpc(
          request,
          id: rpc['id'],
          result: <String, Object?>{
            'resources': [
              {'uri': 'test://r1'},
            ],
          },
        );
        return;
      }
      if (method == 'resources/templates/list') {
        await _respondJsonRpc(
          request,
          id: rpc['id'],
          result: <String, Object?>{
            'resourceTemplates': [
              {'uriTemplate': 'test://{id}'},
            ],
          },
        );
        return;
      }
      if (method == 'prompts/list') {
        await _respondJsonRpc(
          request,
          id: rpc['id'],
          result: <String, Object?>{
            'prompts': [
              {'name': 'p1'},
            ],
          },
        );
        return;
      }
      if (method == 'tools/list') {
        await _respondJsonRpc(
          request,
          id: rpc['id'],
          result: <String, Object?>{
            'tools': [
              {'name': 't1'},
            ],
          },
        );
        return;
      }
      await _respondJsonRpc(request, id: rpc['id'], result: <String, Object?>{});
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

    expect(client.negotiatedProtocolVersion(connectionParams), '2025-11-25');
    expect(client.sessionId(connectionParams), 'session-cap-test');
    expect(client.negotiatedCapabilities(connectionParams)['tools'], isA<Map>());
    expect(client.hasNegotiatedCapability(connectionParams, 'tools'), isTrue);
    expect(client.hasNegotiatedCapability(connectionParams, 'experimental'), isTrue);
    expect(client.hasNegotiatedCapability(connectionParams, 'nonexistent'), isFalse);

    // Single-page list calls
    final resPage = await client.listResourcesPage(connectionParams: connectionParams);
    expect((resPage['resources'] as List).isNotEmpty, isTrue);

    final tplPage = await client.listResourceTemplatesPage(connectionParams: connectionParams);
    expect((tplPage['resourceTemplates'] as List).isNotEmpty, isTrue);

    final promptPage = await client.listPromptsPage(connectionParams: connectionParams);
    expect((promptPage['prompts'] as List).isNotEmpty, isTrue);

    final toolsPage = await client.listToolsPage(connectionParams: connectionParams);
    expect((toolsPage['tools'] as List).isNotEmpty, isTrue);
  });

  test('McpRemoteClient initialize error and deleteSession error handling', () async {
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    addTearDown(() async => server.close(force: true));

    var initializeMissingProtocol = false;
    var initializeUnsupportedProtocol = false;
    var return405OnDelete = false;
    var return500OnDelete = false;

    server.listen((HttpRequest request) async {
      if (request.method == 'DELETE') {
        if (return405OnDelete) {
          request.response.statusCode = HttpStatus.methodNotAllowed;
          await request.response.close();
          return;
        }
        if (return500OnDelete) {
          request.response.statusCode = HttpStatus.internalServerError;
          request.response.write('Server Error');
          await request.response.close();
          return;
        }
        request.response.statusCode = HttpStatus.noContent;
        await request.response.close();
        return;
      }

      final String body = await utf8.decoder.bind(request).join();
      final Map<String, Object?> rpc = (jsonDecode(body) as Map).map(
        (Object? key, Object? value) => MapEntry('$key', value),
      );
      if (initializeMissingProtocol) {
        await _respondJsonRpc(
          request,
          id: rpc['id'],
          result: <String, Object?>{'capabilities': {}},
        );
        return;
      }
      if (initializeUnsupportedProtocol) {
        await _respondJsonRpc(
          request,
          id: rpc['id'],
          result: <String, Object?>{'protocolVersion': '1999-01-01', 'capabilities': {}},
        );
        return;
      }
      await _respondJsonRpc(
        request,
        id: rpc['id'],
        result: <String, Object?>{
          'protocolVersion': '2025-11-25',
          'capabilities': {},
        },
        headers: {'MCP-Session-Id': 'del-test'},
      );
    });

    final params = StreamableHTTPConnectionParams(
      url: 'http://${server.address.address}:${server.port}/mcp',
    );

    // Missing protocol version
    initializeMissingProtocol = true;
    final client1 = McpRemoteClient(clientInfoName: 'test', clientInfoVersion: '1');
    await expectLater(client1.ensureInitialized(params), throwsStateError);

    // Unsupported protocol version
    initializeMissingProtocol = false;
    initializeUnsupportedProtocol = true;
    final client2 = McpRemoteClient(clientInfoName: 'test', clientInfoVersion: '1');
    await expectLater(client2.ensureInitialized(params), throwsStateError);

    // Delete session with 405 allowed
    initializeUnsupportedProtocol = false;
    final client3 = McpRemoteClient(clientInfoName: 'test', clientInfoVersion: '1');
    await client3.ensureInitialized(params);
    return405OnDelete = true;
    await client3.terminateSession(connectionParams: params, allowMethodNotAllowed: true);

    // Delete session with 500 error
    await client3.ensureInitialized(params);
    return405OnDelete = false;
    return500OnDelete = true;
    await expectLater(
      client3.terminateSession(connectionParams: params, allowMethodNotAllowed: false),
      throwsA(isA<McpHttpStatusException>()),
    );
  });

  test('McpRemoteClient session recovery on 404 for call and notify', () async {
    final HttpServer server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async => server.close(force: true));

    int initializeCalls = 0;
    int pingCalls = 0;
    bool return404OnPing = true;
    bool return404OnNotify = true;

    server.listen((HttpRequest request) async {
      final String body = await utf8.decoder.bind(request).join();
      final Map<String, Object?> rpc = (jsonDecode(body) as Map).map(
        (Object? k, Object? v) => MapEntry('$k', v),
      );
      final String method = '${rpc['method'] ?? ''}';

      if (method == 'initialize') {
        initializeCalls++;
        await _respondJsonRpc(
          request,
          id: rpc['id'],
          result: <String, Object?>{
            'protocolVersion': '2025-11-25',
            'capabilities': <String, Object?>{},
          },
          headers: <String, String>{'MCP-Session-Id': 'recovered-session-$initializeCalls'},
        );
        return;
      }
      if (method == 'notifications/initialized') {
        request.response.statusCode = HttpStatus.accepted;
        await request.response.close();
        return;
      }
      if (method == 'ping') {
        pingCalls++;
        if (return404OnPing) {
          return404OnPing = false;
          request.response.statusCode = HttpStatus.notFound;
          request.response.write('Session not found');
          await request.response.close();
          return;
        }
        await _respondJsonRpc(request, id: rpc['id'], result: <String, Object?>{});
        return;
      }
      if (method == 'notifications/custom') {
        if (return404OnNotify) {
          return404OnNotify = false;
          request.response.statusCode = HttpStatus.notFound;
          request.response.write('Session not found');
          await request.response.close();
          return;
        }
        request.response.statusCode = HttpStatus.accepted;
        await request.response.close();
        return;
      }
      await _respondJsonRpc(request, id: rpc['id'], result: <String, Object?>{});
    });

    final McpRemoteClient client = McpRemoteClient(
      clientInfoName: 'recovery_test',
      clientInfoVersion: '1.0.0',
    );
    final StreamableHTTPConnectionParams params = StreamableHTTPConnectionParams(
      url: 'http://${server.address.address}:${server.port}/mcp',
    );

    // Ensure initial handshake
    await client.ensureInitialized(params);
    expect(initializeCalls, equals(1));

    // Call triggers 404, recovers and re-initializes
    final pingResult = await client.ping(connectionParams: params);
    expect(pingResult, isNotNull);
    expect(initializeCalls, equals(2));
    expect(pingCalls, equals(2));

    // Notification triggers 404, recovers and re-initializes
    await client.notify(
      connectionParams: params,
      method: 'notifications/custom',
      params: <String, Object?>{'test': true},
    );
    expect(initializeCalls, equals(3));
  });

  test('McpRemoteClient error formatting and response decoding edge cases', () async {
    final HttpServer server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async => server.close(force: true));

    String responseMode = 'empty';

    server.listen((HttpRequest request) async {
      final String body = await utf8.decoder.bind(request).join();
      final Map<String, Object?> rpc = (jsonDecode(body) as Map).map(
        (Object? k, Object? v) => MapEntry('$k', v),
      );
      final String method = '${rpc['method'] ?? ''}';

      if (method == 'initialize') {
        await _respondJsonRpc(
          request,
          id: rpc['id'],
          result: <String, Object?>{'protocolVersion': '2025-11-25', 'capabilities': <String, Object?>{}},
          headers: <String, String>{'MCP-Session-Id': 'err-session'},
        );
        return;
      }
      if (method == 'notifications/initialized') {
        request.response.statusCode = HttpStatus.accepted;
        await request.response.close();
        return;
      }

      switch (responseMode) {
        case 'empty':
          request.response.statusCode = HttpStatus.ok;
          await request.response.close();
          break;
        case 'empty_sse':
          request.response.statusCode = HttpStatus.ok;
          request.response.headers.set(HttpHeaders.contentTypeHeader, 'text/event-stream');
          request.response.write(': comment only\n\n');
          await request.response.close();
          break;
        case 'sse_id_mismatch':
          request.response.statusCode = HttpStatus.ok;
          request.response.headers.set(HttpHeaders.contentTypeHeader, 'text/event-stream');
          request.response.write('data: ${jsonEncode(<String, Object?>{'jsonrpc': '2.0', 'id': 99999, 'result': {}})}\n\n');
          await request.response.close();
          break;
        case 'non_json':
          request.response.statusCode = HttpStatus.ok;
          request.response.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
          request.response.write('not-json-at-all');
          await request.response.close();
          break;
        case 'request_instead_of_response':
          request.response.statusCode = HttpStatus.ok;
          request.response.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
          request.response.write(jsonEncode(<String, Object?>{
            'jsonrpc': '2.0',
            'id': 123,
            'method': 'server/query',
          }));
          await request.response.close();
          break;
        case 'neither_request_nor_response':
          request.response.statusCode = HttpStatus.ok;
          request.response.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
          request.response.write(jsonEncode(<String, Object?>{'random_key': 'random_value'}));
          await request.response.close();
          break;
        case 'id_mismatch':
          await _respondJsonRpc(request, id: 88888, result: <String, Object?>{});
          break;
        case 'rpc_error':
          await _respondJsonRpc(
            request,
            id: rpc['id'],
            error: <String, Object?>{'code': -32600, 'message': 'Invalid Request'},
          );
          break;
        case 'missing_result_and_error':
          request.response.statusCode = HttpStatus.ok;
          request.response.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
          request.response.write(jsonEncode(<String, Object?>{'jsonrpc': '2.0', 'id': rpc['id']}));
          await request.response.close();
          break;
      }
    });

    final McpRemoteClient client = McpRemoteClient(
      clientInfoName: 'test_err',
      clientInfoVersion: '1.0.0',
    );
    final StreamableHTTPConnectionParams params = StreamableHTTPConnectionParams(
      url: 'http://${server.address.address}:${server.port}/mcp',
    );
    await client.ensureInitialized(params);

    responseMode = 'empty';
    await expectLater(client.ping(connectionParams: params), throwsFormatException);

    responseMode = 'empty_sse';
    await expectLater(client.ping(connectionParams: params), throwsFormatException);

    responseMode = 'sse_id_mismatch';
    await expectLater(client.ping(connectionParams: params), throwsFormatException);

    responseMode = 'non_json';
    await expectLater(client.ping(connectionParams: params), throwsFormatException);

    responseMode = 'request_instead_of_response';
    await expectLater(client.ping(connectionParams: params), throwsFormatException);

    responseMode = 'neither_request_nor_response';
    await expectLater(client.ping(connectionParams: params), throwsFormatException);

    responseMode = 'id_mismatch';
    await expectLater(client.ping(connectionParams: params), throwsFormatException);

    responseMode = 'missing_result_and_error';
    await expectLater(client.ping(connectionParams: params), throwsFormatException);

    responseMode = 'rpc_error';
    await expectLater(client.ping(connectionParams: params), throwsA(isA<McpJsonRpcException>()));

    // Test tryCall error suppression
    final suppressed = await client.tryCall(
      connectionParams: params,
      method: 'ping',
      params: const <String, Object?>{},
      suppressJsonRpcErrorCodes: const <int>{-32600},
    );
    expect(suppressed, isNull);

    final suppressedAll = await client.tryCall(
      connectionParams: params,
      method: 'ping',
      params: const <String, Object?>{},
      suppressErrors: true,
    );
    expect(suppressedAll, isNull);
  });

  test('McpRemoteClient pagination, operations, and notification helpers', () async {
    final HttpServer server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async => server.close(force: true));

    final List<Map<String, Object?>> receivedNotifications = <Map<String, Object?>>[];

    server.listen((HttpRequest request) async {
      final String body = await utf8.decoder.bind(request).join();
      final Map<String, Object?> rpc = (jsonDecode(body) as Map).map(
        (Object? k, Object? v) => MapEntry('$k', v),
      );
      final String method = '${rpc['method'] ?? ''}';

      if (method.startsWith('notifications/')) {
        receivedNotifications.add(rpc);
        request.response.statusCode = HttpStatus.accepted;
        await request.response.close();
        return;
      }

      if (method == 'initialize') {
        await _respondJsonRpc(
          request,
          id: rpc['id'],
          result: <String, Object?>{
            'protocolVersion': '2025-11-25',
            'capabilities': <String, Object?>{},
            'sessionId': 'session-from-result',
          },
        );
        return;
      }

      final Map<String, Object?> params = (rpc['params'] as Map?)?.cast<String, Object?>() ?? <String, Object?>{};

      if (method == 'resources/list') {
        final cursor = params['cursor'] as String?;
        if (cursor == null) {
          await _respondJsonRpc(request, id: rpc['id'], result: <String, Object?>{
            'resources': [<String, Object?>{'uri': 'res://1'}],
            'nextCursor': 'page2',
          });
        } else {
          await _respondJsonRpc(request, id: rpc['id'], result: <String, Object?>{
            'resources': [<String, Object?>{'uri': 'res://2'}],
          });
        }
        return;
      }

      if (method == 'resources/templates/list') {
        await _respondJsonRpc(request, id: rpc['id'], result: <String, Object?>{
          'resourceTemplates': [<String, Object?>{'uriTemplate': 'tmpl://{id}'}],
        });
        return;
      }

      if (method == 'prompts/list') {
        await _respondJsonRpc(request, id: rpc['id'], result: <String, Object?>{
          'prompts': [<String, Object?>{'name': 'test_prompt'}],
        });
        return;
      }

      if (method == 'prompts/get') {
        await _respondJsonRpc(request, id: rpc['id'], result: <String, Object?>{
          'name': params['name'],
          'arguments': params['arguments'],
        });
        return;
      }

      if (method == 'tools/list') {
        await _respondJsonRpc(request, id: rpc['id'], result: <String, Object?>{
          'tools': [<String, Object?>{'name': 'test_tool'}],
        });
        return;
      }

      if (method == 'tools/call') {
        await _respondJsonRpc(request, id: rpc['id'], result: <String, Object?>{
          'content': [<String, Object?>{'type': 'text', 'text': 'ok'}],
          'task': params['task'],
          'meta': params['_meta'],
        });
        return;
      }

      if (method == 'tasks/list') {
        await _respondJsonRpc(request, id: rpc['id'], result: <String, Object?>{
          'tasks': [<String, Object?>{'taskId': 'task_1'}],
        });
        return;
      }

      if (method == 'completion/complete') {
        await _respondJsonRpc(request, id: rpc['id'], result: <String, Object?>{
          'completion': {'values': ['completed']},
        });
        return;
      }

      if (method == 'logging/setLevel') {
        await _respondJsonRpc(request, id: rpc['id'], result: <String, Object?>{});
        return;
      }

      await _respondJsonRpc(request, id: rpc['id'], result: <String, Object?>{});
    });

    final McpRemoteClient client = McpRemoteClient(
      clientInfoName: 'pagination_test',
      clientInfoVersion: '1.0.0',
    );
    final StreamableHTTPConnectionParams params = StreamableHTTPConnectionParams(
      url: 'http://${server.address.address}:${server.port}/mcp',
      headers: <String, String>{'X-Custom': 'param-header'},
    );

    await client.ensureInitialized(params);

    // Test multi-page resources collection
    final resources = await client.listResources(connectionParams: params);
    expect(resources.length, equals(2));

    // Test single-page with cursor
    final resPage = await client.listResourcesPage(connectionParams: params, cursor: 'page2');
    expect(resPage['resources'], isNotEmpty);

    final templates = await client.listResourceTemplates(connectionParams: params);
    expect(templates, isNotEmpty);
    final tmplPage = await client.listResourceTemplatesPage(connectionParams: params, cursor: 'c');
    expect(tmplPage, isNotEmpty);

    final prompts = await client.listPrompts(connectionParams: params);
    expect(prompts, isNotEmpty);
    final promptPage = await client.listPromptsPage(connectionParams: params, cursor: 'c');
    expect(promptPage, isNotEmpty);

    final promptDetail = await client.getPrompt(
      connectionParams: params,
      name: 'test_prompt',
      arguments: <String, String>{'arg1': 'val1'},
    );
    expect(promptDetail['name'], equals('test_prompt'));

    final tools = await client.listTools(connectionParams: params);
    expect(tools, isNotEmpty);
    final toolPage = await client.listToolsPage(connectionParams: params, cursor: 'c');
    expect(toolPage, isNotEmpty);

    final toolCall = await client.callTool(
      connectionParams: params,
      name: 'test_tool',
      arguments: <String, Object?>{'q': 'test'},
      task: <String, Object?>{'taskId': 't1'},
      meta: <String, Object?>{'source': 'unit_test'},
    );
    expect(toolCall['content'], isNotNull);

    final tasks = await client.listTasks(connectionParams: params);
    expect(tasks, isNotEmpty);
    final taskPage = await client.listTasksPage(connectionParams: params, cursor: 'c');
    expect(taskPage, isNotEmpty);

    final completion = await client.complete(
      connectionParams: params,
      ref: <String, Object?>{'type': 'prompt', 'name': 'test'},
      argument: 'input',
      context: <String, Object?>{'active': true},
    );
    expect(completion['completion'], isNotNull);

    // Logging level validation
    expect(
      () => client.setLoggingLevel(connectionParams: params, level: 'invalid_level'),
      throwsArgumentError,
    );
    await client.setLoggingLevel(connectionParams: params, level: 'debug');

    // Notifications
    await client.notifyCancelledRequest(
      connectionParams: params,
      requestId: 42,
      reason: 'user_cancelled',
      meta: <String, Object?>{'note': 'test'},
    );
    await client.notifyProgress(
      connectionParams: params,
      progressToken: 'tok1',
      progress: 50,
      total: 100,
      message: 'halfway',
      meta: <String, Object?>{'info': 'prog'},
    );
    await client.notifyRootsListChanged(
      connectionParams: params,
      meta: <String, Object?>{'updated': true},
    );
    await client.notifyTaskStatus(
      connectionParams: params,
      status: <String, Object?>{'taskId': 't1', 'status': 'completed'},
    );
    await client.sendInitializedNotification(
      connectionParams: params,
      meta: <String, Object?>{'init': true},
    );
    expect(receivedNotifications.length, greaterThanOrEqualTo(5));

    // Clear connection & clear all
    client.clearConnection(params);
    client.clear();
  });

  test('McpRemoteClient server requests and SSE message handling', () async {
    final HttpServer server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async => server.close(force: true));

    bool return400OnSse = false;
    bool returnJsonOnSse = false;

    server.listen((HttpRequest request) async {
      if (request.method == 'GET') {
        if (return400OnSse) {
          request.response.statusCode = HttpStatus.badRequest;
          request.response.write('Bad Request for SSE');
          await request.response.close();
          return;
        }
        if (returnJsonOnSse) {
          request.response.statusCode = HttpStatus.ok;
          request.response.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
          request.response.write('{}');
          await request.response.close();
          return;
        }

        request.response.statusCode = HttpStatus.ok;
        request.response.headers.set(HttpHeaders.contentTypeHeader, 'text/event-stream');
        // Send a ping request from server
        request.response.write(
          'data: ${jsonEncode(<String, Object?>{'jsonrpc': '2.0', 'id': 500, 'method': 'ping', 'params': {}})}\n\n',
        );
        // Send a server notification
        request.response.write(
          'data: ${jsonEncode(<String, Object?>{'jsonrpc': '2.0', 'method': 'notifications/roots/list_changed', 'params': {}})}\n\n',
        );
        await request.response.close();
        return;
      }

      final String body = await utf8.decoder.bind(request).join();
      final Map<String, Object?> rpc = (jsonDecode(body) as Map).map(
        (Object? k, Object? v) => MapEntry('$k', v),
      );
      final String method = '${rpc['method'] ?? ''}';

      if (method == 'initialize') {
        await _respondJsonRpc(
          request,
          id: rpc['id'],
          result: <String, Object?>{'protocolVersion': '2025-11-25', 'capabilities': <String, Object?>{}},
        );
        return;
      }
      if (method == 'notifications/initialized') {
        request.response.statusCode = HttpStatus.accepted;
        await request.response.close();
        return;
      }

      await _respondJsonRpc(request, id: rpc['id'], result: <String, Object?>{});
    });

    final McpRemoteClient client = McpRemoteClient(
      clientInfoName: 'sse_test',
      clientInfoVersion: '1.0.0',
    );
    final StreamableHTTPConnectionParams params = StreamableHTTPConnectionParams(
      url: 'http://${server.address.address}:${server.port}/mcp',
    );
    await client.ensureInitialized(params);

    // Test SSE status >= 400
    return400OnSse = true;
    await expectLater(
      client.readServerMessagesOnce(connectionParams: params).toList(),
      throwsA(isA<McpHttpStatusException>()),
    );

    // Test SSE content-type not text/event-stream
    return400OnSse = false;
    returnJsonOnSse = true;
    await expectLater(
      client.readServerMessagesOnce(connectionParams: params).toList(),
      throwsFormatException,
    );

    // Test successful SSE with server message and ping handled
    returnJsonOnSse = false;
    final messages = await client.readServerMessagesOnce(
      connectionParams: params,
      headers: <String, String>{'X-Test': 'sse'},
      lastEventId: 'evt_123',
    ).toList();
    expect(messages, isNotEmpty);

    // Exception toString tests
    final rpcEx = McpJsonRpcException(method: 'foo', code: -32000, message: 'fail');
    expect(rpcEx.toString(), contains('foo'));
    final httpEx = McpHttpStatusException(uri: Uri.parse('http://example.com'), statusCode: 404, body: 'not found');
    expect(httpEx.toString(), contains('404'));
    final srvEx = McpServerRequestException(code: -32601, message: 'not found', method: 'testMethod', data: {'d': 1});
    expect(srvEx.toString(), contains('testMethod'));
  });

  test('McpRemoteClient final coverage edge cases', () async {
    final HttpServer server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async => server.close(force: true));

    String currentMode = 'init';

    server.listen((HttpRequest request) async {
      if (request.method == 'DELETE') {
        request.response.statusCode = HttpStatus.noContent;
        await request.response.close();
        return;
      }

      final String body = await utf8.decoder.bind(request).join();
      final Map<String, Object?> rpc = (jsonDecode(body) as Map).map(
        (Object? k, Object? v) => MapEntry('$k', v),
      );
      final String method = '${rpc['method'] ?? ''}';

      if (method == 'initialize') {
        await _respondJsonRpc(
          request,
          id: rpc['id'],
          result: <String, Object?>{'protocolVersion': '2025-11-25', 'capabilities': <String, Object?>{}},
          headers: <String, String>{'MCP-Session-Id': 'edge-session'},
        );
        return;
      }
      if (method == 'notifications/initialized') {
        request.response.statusCode = HttpStatus.accepted;
        await request.response.close();
        return;
      }

      switch (currentMode) {
        case 'json_primitive':
          request.response.statusCode = HttpStatus.ok;
          request.response.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
          request.response.write('12345');
          await request.response.close();
          break;
        case 'null_error_no_result':
          request.response.statusCode = HttpStatus.ok;
          request.response.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
          request.response.write(jsonEncode(<String, Object?>{
            'jsonrpc': '2.0',
            'id': rpc['id'],
            'error': null,
          }));
          await request.response.close();
          break;
        case 'num_id':
          request.response.statusCode = HttpStatus.ok;
          request.response.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
          request.response.write(jsonEncode(<String, Object?>{
            'jsonrpc': '2.0',
            'id': (rpc['id'] as num).toDouble(),
            'result': <dynamic, dynamic>{'num_id': true, 'items': <dynamic>[1, 2]},
          }));
          await request.response.close();
          break;
        case 'string_id':
          request.response.statusCode = HttpStatus.ok;
          request.response.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
          request.response.write(jsonEncode(<String, Object?>{
            'jsonrpc': '2.0',
            'id': '${rpc['id']}',
            'result': <dynamic, dynamic>{'str_id': true},
          }));
          await request.response.close();
          break;
        case 'string_code_error':
          request.response.statusCode = HttpStatus.ok;
          request.response.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
          request.response.write(jsonEncode(<String, Object?>{
            'jsonrpc': '2.0',
            'id': rpc['id'],
            'error': <String, Object?>{'code': '123', 'message': 'string error code'},
          }));
          await request.response.close();
          break;
        case 'num_code_error':
          request.response.statusCode = HttpStatus.ok;
          request.response.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
          request.response.write(jsonEncode(<String, Object?>{
            'jsonrpc': '2.0',
            'id': rpc['id'],
            'error': <String, Object?>{'code': 456.0, 'message': 'num error code'},
          }));
          await request.response.close();
          break;
        case 'server_req_crash':
          request.response.statusCode = HttpStatus.ok;
          request.response.headers.set(HttpHeaders.contentTypeHeader, 'text/event-stream');
          // send notification to trigger onServerMessage
          request.response.write('data: ${jsonEncode(<String, Object?>{'jsonrpc': '2.0', 'method': 'notifications/msg', 'params': {}})}\n\n');
          // send server request that causes onServerRequest to throw Exception
          request.response.write('data: ${jsonEncode(<String, Object?>{'jsonrpc': '2.0', 'id': 99, 'method': 'server/crash', 'params': {}})}\n\n');
          // send actual response
          request.response.write('data: ${jsonEncode(<String, Object?>{'jsonrpc': '2.0', 'id': rpc['id'], 'result': {}})}\n\n');
          await request.response.close();
          break;
      }
    });

    final List<McpServerMessage> serverMessages = [];
    final McpRemoteClient client = McpRemoteClient(
      clientInfoName: 'edge_test',
      clientInfoVersion: '1.0.0',
      onServerMessage: (m) => serverMessages.add(m),
      onServerRequest: (m) {
        if (m.method == 'server/crash') {
          throw Exception('onServerRequest crash');
        }
        return null;
      },
    );
    final StreamableHTTPConnectionParams params = StreamableHTTPConnectionParams(
      url: 'http://${server.address.address}:${server.port}/mcp',
    );
    await client.ensureInitialized(params);

    // terminateSession with custom headers (line 459)
    await client.terminateSession(
      connectionParams: params,
      headers: <String, String>{'X-Terminate': 'true'},
    );
    await client.ensureInitialized(params);

    // Call with headers (lines 1213, 1220)
    currentMode = 'num_id';
    final numResult = await client.ping(
      connectionParams: params,
      headers: <String, String>{'X-Call': 'yes'},
    );
    expect(numResult, isNotNull);

    // string_id (line 1445-1446)
    currentMode = 'string_id';
    final strResult = await client.ping(connectionParams: params);
    expect(strResult, isNotNull);

    // json_primitive (line 1344)
    currentMode = 'json_primitive';
    await expectLater(client.ping(connectionParams: params), throwsFormatException);

    // null_error_no_result (line 1188-1189)
    currentMode = 'null_error_no_result';
    await expectLater(client.ping(connectionParams: params), throwsFormatException);

    // string_code_error (line 1597-1598)
    currentMode = 'string_code_error';
    await expectLater(client.ping(connectionParams: params), throwsA(isA<McpJsonRpcException>()));

    // num_code_error (line 1594-1595)
    currentMode = 'num_code_error';
    await expectLater(client.ping(connectionParams: params), throwsA(isA<McpJsonRpcException>()));

    // server_req_crash (line 1457, 1460, 1461, 1507, 1509, 1510)
    currentMode = 'server_req_crash';
    await client.ping(connectionParams: params);
    expect(serverMessages, isNotEmpty);
  });
}


