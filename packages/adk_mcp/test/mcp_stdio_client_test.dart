import 'dart:async';
import 'dart:io';

import 'package:adk_mcp/adk_mcp.dart';
import 'package:test/test.dart';

Future<StdioConnectionParams> _createStdioServerParams() async {
  final Directory tempDir = await Directory.systemTemp.createTemp(
    'adk_mcp_stdio_server_',
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
    connectionId: 'stdio-test-server',
  );
}

const String _serverScript = r'''
import 'dart:async';
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

void request(Object id, String method, Map<String, Object?> params) {
  stdout.writeln(
    jsonEncode(<String, Object?>{
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      'params': params,
    }),
  );
}

Future<void> main() async {
  final Stream<String> lines = stdin
      .transform(utf8.decoder)
      .transform(const LineSplitter());

  Object? pendingToolsListId;
  bool waitingPingResponse = false;
  bool waitingRootsResponse = false;
  bool waitingSamplingResponse = false;
  bool waitingElicitationResponse = false;
  bool samplingAck = false;
  bool elicitationAck = false;
  bool cancelledSeen = false;
  Object? slowRequestId;

  stderr.writeln('server starting');

  await for (final String line in lines) {
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

    if (method.isEmpty && rpc.containsKey('result')) {
      if (waitingPingResponse && '$id' == 'srv-ping-1') {
        waitingPingResponse = false;
        final Object? responseId = pendingToolsListId;
        pendingToolsListId = null;
        if (responseId != null) {
          respond(
            responseId,
            result: <String, Object?>{
              'tools': <Map<String, Object?>>[
                <String, Object?>{'name': 'remote_echo'},
              ],
            },
          );
        }
        continue;
      }
      if (waitingRootsResponse && '$id' == 'srv-roots-1') {
        waitingRootsResponse = false;
        final Map<String, Object?> resultMap = rpc['result'] is Map
            ? (rpc['result'] as Map).map(
                (Object? key, Object? value) =>
                    MapEntry<String, Object?>('$key', value),
              )
            : <String, Object?>{};
        final bool rootAck = (resultMap['roots'] is List) &&
            (resultMap['roots'] as List).isNotEmpty;
        final Object? responseId = pendingToolsListId;
        pendingToolsListId = null;
        if (responseId != null) {
          respond(
            responseId,
            result: <String, Object?>{
              'tools': <Map<String, Object?>>[
                <String, Object?>{'name': 'remote_echo'},
              ],
              'rootAck': rootAck,
            },
          );
        }
        continue;
      }
      if (waitingSamplingResponse && '$id' == 'srv-sampling-1') {
        waitingSamplingResponse = false;
        final Map<String, Object?> resultMap = rpc['result'] is Map
            ? (rpc['result'] as Map).map(
                (Object? key, Object? value) =>
                    MapEntry<String, Object?>('$key', value),
              )
            : <String, Object?>{};
        samplingAck = resultMap['model'] == 'test-model';
        final Object? responseId = pendingToolsListId;
        pendingToolsListId = null;
        if (responseId != null) {
          respond(
            responseId,
            result: <String, Object?>{
              'tools': <Map<String, Object?>>[
                <String, Object?>{'name': 'remote_echo'},
              ],
              'samplingAck': samplingAck,
            },
          );
        }
        continue;
      }
      if (waitingElicitationResponse && '$id' == 'srv-elicit-1') {
        waitingElicitationResponse = false;
        final Map<String, Object?> resultMap = rpc['result'] is Map
            ? (rpc['result'] as Map).map(
                (Object? key, Object? value) =>
                    MapEntry<String, Object?>('$key', value),
              )
            : <String, Object?>{};
        elicitationAck = resultMap['action'] == 'accept';
        final Object? responseId = pendingToolsListId;
        pendingToolsListId = null;
        if (responseId != null) {
          respond(
            responseId,
            result: <String, Object?>{
              'tools': <Map<String, Object?>>[
                <String, Object?>{'name': 'remote_echo'},
              ],
              'elicitationAck': elicitationAck,
            },
          );
        }
        continue;
      }
    }

    switch (method) {
      case 'initialize':
        respond(
          id,
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
        );
        continue;
      case 'notifications/initialized':
      case 'notifications/progress':
      case 'notifications/roots/list_changed':
      case 'notifications/tasks/status':
        continue;
      case 'notifications/cancelled':
        final Map<String, Object?> params = rpc['params'] is Map
            ? (rpc['params'] as Map).map(
                (Object? key, Object? value) =>
                    MapEntry<String, Object?>('$key', value),
              )
            : <String, Object?>{};
        if (params['requestId'] != null) {
          cancelledSeen = true;
        }
        continue;
      case 'ping':
        respond(id, result: <String, Object?>{});
        continue;
      case 'completion/complete':
        respond(
          id,
          result: <String, Object?>{
            'completion': <String, Object?>{
              'values': <String>['one', 'two'],
              'total': 2,
              'hasMore': false,
            },
          },
        );
        continue;
      case 'logging/setLevel':
        respond(id, result: <String, Object?>{});
        continue;
      case 'resources/list':
        final Map<String, Object?> params = rpc['params'] is Map
            ? (rpc['params'] as Map).map(
                (Object? key, Object? value) =>
                    MapEntry<String, Object?>('$key', value),
              )
            : <String, Object?>{};
        if (params['cursor'] == 'p2') {
          respond(
            id,
            result: <String, Object?>{
              'resources': <Map<String, Object?>>[
                <String, Object?>{'uri': 'file:///r2', 'name': 'r2'},
              ],
            },
          );
        } else {
          respond(
            id,
            result: <String, Object?>{
              'resources': <Map<String, Object?>>[
                <String, Object?>{'uri': 'file:///r1', 'name': 'r1'},
              ],
              'nextCursor': 'p2',
            },
          );
        }
        continue;
      case 'resources/templates/list':
        respond(
          id,
          result: <String, Object?>{
            'resourceTemplates': <Map<String, Object?>>[
              <String, Object?>{'uriTemplate': 'file:///tmpl/{name}'},
            ],
          },
        );
        continue;
      case 'resources/read':
        respond(
          id,
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
        continue;
      case 'resources/subscribe':
      case 'resources/unsubscribe':
        respond(id, result: <String, Object?>{});
        continue;
      case 'prompts/list':
        respond(
          id,
          result: <String, Object?>{
            'prompts': <Map<String, Object?>>[
              <String, Object?>{'name': 'prompt.one'},
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
                'role': 'user',
                'content': <String, Object?>{'type': 'text', 'text': 'hello'},
              },
            ],
          },
        );
        continue;
      case 'tools/list':
        final Map<String, Object?> params = rpc['params'] is Map
            ? (rpc['params'] as Map).map(
                (Object? key, Object? value) =>
                    MapEntry<String, Object?>('$key', value),
              )
            : <String, Object?>{};
        pendingToolsListId = id;
        if (params['requestRoots'] == true) {
          waitingRootsResponse = true;
          request('srv-roots-1', 'roots/list', <String, Object?>{});
        } else if (params['requestSampling'] == true) {
          waitingSamplingResponse = true;
          request('srv-sampling-1', 'sampling/createMessage', <String, Object?>{
            'messages': <Map<String, Object?>>[
              <String, Object?>{
                'role': 'user',
                'content': <String, Object?>{'type': 'text', 'text': 'hello'},
              },
            ],
          });
        } else if (params['requestElicitation'] == true) {
          waitingElicitationResponse = true;
          request('srv-elicit-1', 'elicitation/create', <String, Object?>{
            'mode': 'form',
            'message': 'Need email',
            'requestedSchema': <String, Object?>{
              'type': 'object',
              'properties': <String, Object?>{
                'email': <String, Object?>{'type': 'string', 'format': 'email'},
              },
              'required': <String>['email'],
            },
          });
        } else {
          waitingPingResponse = true;
          request('srv-ping-1', 'ping', <String, Object?>{});
        }
        continue;
      case 'tools/call':
        respond(
          id,
          result: <String, Object?>{
            'content': <Map<String, Object?>>[
              <String, Object?>{'type': 'text', 'text': 'done'},
            ],
            'isError': false,
          },
        );
        continue;
      case 'tasks/list':
        final Map<String, Object?> params = rpc['params'] is Map
            ? (rpc['params'] as Map).map(
                (Object? key, Object? value) =>
                    MapEntry<String, Object?>('$key', value),
              )
            : <String, Object?>{};
        if (params['cursor'] == 'tp2') {
          respond(
            id,
            result: <String, Object?>{
              'tasks': <Map<String, Object?>>[
                <String, Object?>{
                  'taskId': 'task-2',
                  'status': 'completed',
                },
              ],
            },
          );
        } else if (params['paginate'] == true) {
          respond(
            id,
            result: <String, Object?>{
              'tasks': <Map<String, Object?>>[
                <String, Object?>{
                  'taskId': 'task-1',
                  'status': 'running',
                },
              ],
              'nextCursor': 'tp2',
            },
          );
        } else {
          respond(
            id,
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
        }
        continue;
      case 'tasks/get':
        respond(
          id,
          result: <String, Object?>{
            'taskId': 'task-1',
            'status': 'completed',
            'createdAt': '2026-02-28T00:00:00Z',
            'updatedAt': '2026-02-28T00:00:01Z',
          },
        );
        continue;
      case 'tasks/result':
        respond(
          id,
          result: <String, Object?>{
            'content': <Map<String, Object?>>[
              <String, Object?>{'type': 'text', 'text': 'task-result'},
            ],
          },
        );
        continue;
      case 'tasks/cancel':
        respond(
          id,
          result: <String, Object?>{
            'taskId': 'task-1',
            'status': 'cancelled',
            'createdAt': '2026-02-28T00:00:00Z',
            'updatedAt': '2026-02-28T00:00:02Z',
          },
        );
        continue;
      case 'slow/list':
        slowRequestId = id;
        await Future<void>.delayed(const Duration(milliseconds: 250));
        respond(
          id,
          result: <String, Object?>{
            'items': <String>['slow'],
          },
        );
        continue;
      case 'debug/cancelledSeen':
        respond(
          id,
          result: <String, Object?>{
            'seen': cancelledSeen,
          },
        );
        continue;
      case 'debug/samplingAck':
        respond(
          id,
          result: <String, Object?>{
            'seen': samplingAck,
          },
        );
        continue;
      case 'debug/elicitationAck':
        respond(
          id,
          result: <String, Object?>{
            'seen': elicitationAck,
          },
        );
        continue;
      case 'test/error_code':
        respond(id, error: <String, Object?>{'code': -32001, 'message': 'Custom Error'});
        continue;
      case 'test/missing_result_and_error':
        stdout.writeln(jsonEncode(<String, Object?>{'jsonrpc': '2.0', 'id': id, 'error': null}));
        continue;
      case 'test/trigger_server_requests':
        request(101, 'test/unsupported', <String, Object?>{});
        request(102, 'test/throw_custom', <String, Object?>{});
        request(103, 'test/throw_generic', <String, Object?>{});
        stdout.writeln(jsonEncode(<String, Object?>{
          'jsonrpc': '2.0',
          'method': 'notifications/server_event',
          'params': <String, Object?>{'info': 'active'},
        }));
        respond(id, result: <String, Object?>{'dispatched': true});
        continue;
      case 'test/error_empty_message':
        respond(id, error: <String, Object?>{'code': -32002, 'message': ''});
        continue;
      case 'test/num_id':
        respond((id as num).toDouble(), result: <dynamic, dynamic>{'num_id': true, 'items': <dynamic>[1, 2]});
        continue;
      case 'test/str_id':
        respond('$id', result: <dynamic, dynamic>{'str_id': true});
        continue;
      case 'test/num_code_error':
        respond(id, error: <String, Object?>{'code': 123.0, 'message': 'num code'});
        continue;
      case 'test/str_code_error':
        respond(id, error: <String, Object?>{'code': '456', 'message': 'str code'});
        continue;
      default:
        respond(
          id,
          error: <String, Object?>{
            'code': -32601,
            'message': 'Method not found: $method',
          },
        );
    }
  }
}
''';

void main() {
  test(
    'supports stdio MCP requests, notifications, and server callbacks',
    () async {
      final StdioConnectionParams params = await _createStdioServerParams();
      final McpStdioClient client = McpStdioClient(
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
      addTearDown(() async => client.close());

      final Map<String, Object?> ping = await client.ping(
        connectionParams: params,
      );
      final List<Map<String, Object?>> tools = await client.listTools(
        connectionParams: params,
      );
      final Map<String, Object?> toolsWithRoots =
          (await client.call(
                connectionParams: params,
                method: 'tools/list',
                params: const <String, Object?>{'requestRoots': true},
              ))
              as Map<String, Object?>;
      final Map<String, Object?> toolsWithSampling =
          (await client.call(
                connectionParams: params,
                method: 'tools/list',
                params: const <String, Object?>{'requestSampling': true},
              ))
              as Map<String, Object?>;
      final Map<String, Object?> toolsWithElicitation =
          (await client.call(
                connectionParams: params,
                method: 'tools/list',
                params: const <String, Object?>{'requestElicitation': true},
              ))
              as Map<String, Object?>;
      final Map<String, Object?> completion = await client.complete(
        connectionParams: params,
        ref: const <String, Object?>{
          'type': 'ref/prompt',
          'name': 'prompt.one',
        },
        argument: 'pr',
      );
      final Map<String, Object?> logging = await client.setLoggingLevel(
        connectionParams: params,
        level: 'info',
      );
      final List<Map<String, Object?>> resources = await client.listResources(
        connectionParams: params,
      );
      final List<Map<String, Object?>> templates = await client
          .listResourceTemplates(connectionParams: params);
      final Map<String, Object?> readResource = await client.readResource(
        connectionParams: params,
        uri: 'file:///r1',
      );
      await client.subscribeResource(
        connectionParams: params,
        uri: 'file:///r1',
      );
      await client.unsubscribeResource(
        connectionParams: params,
        uri: 'file:///r1',
      );
      final List<Map<String, Object?>> prompts = await client.listPrompts(
        connectionParams: params,
      );
      final Map<String, Object?> prompt = await client.getPrompt(
        connectionParams: params,
        name: 'prompt.one',
      );
      final Map<String, Object?> toolCall = await client.callTool(
        connectionParams: params,
        name: 'remote_echo',
        arguments: const <String, Object?>{'text': 'hello'},
      );
      final List<Map<String, Object?>> tasks = await client.listTasks(
        connectionParams: params,
      );
      final Map<String, Object?> task = await client.getTask(
        connectionParams: params,
        taskId: 'task-1',
      );
      final Map<String, Object?> taskResult = await client.getTaskResult(
        connectionParams: params,
        taskId: 'task-1',
      );
      final Map<String, Object?> cancelledTask = await client.cancelTask(
        connectionParams: params,
        taskId: 'task-1',
      );
      await client.notifyProgress(
        connectionParams: params,
        progressToken: 'p1',
        progress: 50,
      );
      await client.notifyRootsListChanged(connectionParams: params);
      await client.notifyTaskStatus(
        connectionParams: params,
        status: const <String, Object?>{
          'taskId': 'task-1',
          'status': 'running',
        },
      );

      expect(ping, <String, Object?>{});
      expect(tools.single['name'], 'remote_echo');
      expect(toolsWithRoots['rootAck'], isTrue);
      expect(toolsWithSampling['samplingAck'], isTrue);
      expect(toolsWithElicitation['elicitationAck'], isTrue);
      expect(completion['completion'], isNotEmpty);
      expect(logging, <String, Object?>{});
      expect(resources.first['uri'], 'file:///r1');
      expect(templates.single['uriTemplate'], 'file:///tmpl/{name}');
      expect(readResource['contents'], isNotEmpty);
      expect(prompts.single['name'], 'prompt.one');
      expect(prompt['messages'], isNotEmpty);
      expect((toolCall['content'] as List).isNotEmpty, isTrue);
      expect(tasks.single['taskId'], 'task-1');
      expect(task['status'], 'completed');
      expect((taskResult['content'] as List).isNotEmpty, isTrue);
      expect(cancelledTask['status'], 'cancelled');
      expect(client.negotiatedProtocolVersion, '2025-11-25');
      expect(client.negotiatedCapabilities['tools'], isA<Map>());
    },
  );

  test('sends notifications/cancelled on stdio timeout', () async {
    final StdioConnectionParams params = await _createStdioServerParams();
    final McpStdioClient client = McpStdioClient(
      clientInfoName: 'test_client',
      clientInfoVersion: '0.0.0',
      requestTimeout: const Duration(milliseconds: 150),
    );
    addTearDown(() async => client.close());

    await expectLater(
      client.call(
        connectionParams: params,
        method: 'slow/list',
        params: const <String, Object?>{},
      ),
      throwsA(isA<TimeoutException>()),
    );

    bool seen = false;
    for (int attempt = 0; attempt < 10 && !seen; attempt += 1) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final Map<String, Object?> debug =
          (await client.call(
                connectionParams: params,
                method: 'debug/cancelledSeen',
                params: const <String, Object?>{},
              ))
              as Map<String, Object?>;
      seen = debug['seen'] == true;
    }
    expect(seen, isTrue);
  });

  test('StdioConnectionParams resolvedConnectionId logic', () {
    final p1 = StdioConnectionParams(command: 'echo', connectionId: 'my-id');
    expect(p1.resolvedConnectionId, 'my-id');

    final p2 = StdioConnectionParams(command: 'echo', arguments: []);
    expect(p2.resolvedConnectionId, 'stdio:echo');

    final p3 = StdioConnectionParams(command: 'echo', arguments: ['hello', 'world']);
    expect(p3.resolvedConnectionId, 'stdio:echo hello world');
  });

  test('McpStdioClient connection state, single-page queries and stderr logging', () async {
    final List<String> stderrLines = [];
    final StdioConnectionParams params = await _createStdioServerParams();
    final McpStdioClient client = McpStdioClient(
      clientInfoName: 'test_client',
      clientInfoVersion: '0.0.0',
      onStderrLine: (connId, line) => stderrLines.add(line),
    );
    addTearDown(() async => client.close());

    expect(client.isConnected, isFalse);
    expect(client.isInitialized, isFalse);

    await client.ensureInitialized(params);

    expect(client.isConnected, isTrue);
    expect(client.isInitialized, isTrue);
    expect(client.negotiatedProtocolVersion, '2025-11-25');
    expect(client.negotiatedCapabilities, isNotEmpty);

    // Single-page list methods
    final resPage = await client.listResourcesPage(connectionParams: params);
    expect((resPage['resources'] as List).isNotEmpty, isTrue);

    final tplPage = await client.listResourceTemplatesPage(connectionParams: params);
    expect((tplPage['resourceTemplates'] as List).isNotEmpty, isTrue);

    final promptPage = await client.listPromptsPage(connectionParams: params);
    expect((promptPage['prompts'] as List).isNotEmpty, isTrue);

    final toolsPage = await client.listToolsPage(connectionParams: params);
    expect((toolsPage['tools'] as List).isNotEmpty, isTrue);

    await client.close();
    expect(client.isConnected, isFalse);
    expect(client.isInitialized, isFalse);
  });

  test('McpStdioClient pagination, operations, and notification helpers', () async {
    final StdioConnectionParams params = await _createStdioServerParams();
    final McpStdioClient client = McpStdioClient(
      clientInfoName: 'test_client',
      clientInfoVersion: '0.0.0',
    );
    addTearDown(() async => client.close());

    await client.ensureInitialized(params);

    // Pagination for resources
    final resList = await client.collectPaginatedMaps(
      connectionParams: params,
      method: 'resources/list',
      resultArrayField: 'resources',
    );
    expect(resList, isNotEmpty);

    final resPage = await client.listResourcesPage(connectionParams: params, cursor: 'p2');
    expect(resPage['resources'], isNotEmpty);

    final tplPage = await client.listResourceTemplatesPage(connectionParams: params, cursor: 'c');
    expect(tplPage['resourceTemplates'], isNotEmpty);

    final promptPage = await client.listPromptsPage(connectionParams: params, cursor: 'c');
    expect(promptPage['prompts'], isNotEmpty);

    final promptDetail = await client.getPrompt(
      connectionParams: params,
      name: 'prompt.one',
      arguments: <String, String>{'a': '1'},
    );
    expect(promptDetail['messages'], isNotEmpty);

    final toolsPage = await client.listToolsPage(connectionParams: params, cursor: 'c');
    expect(toolsPage['tools'], isNotEmpty);

    final toolCall = await client.callTool(
      connectionParams: params,
      name: 'remote_echo',
      arguments: <String, Object?>{'x': 'y'},
      task: <String, Object?>{'taskId': 't1'},
      meta: <String, Object?>{'m': '1'},
    );
    expect(toolCall['content'], isNotEmpty);

    // Tasks list and pagination
    final tasksList = await client.listTasks(connectionParams: params);
    expect(tasksList, isNotEmpty);
    final tasksPage = await client.listTasksPage(connectionParams: params, cursor: 'tp2');
    expect(tasksPage['tasks'], isNotEmpty);

    // Complete with context
    final comp = await client.complete(
      connectionParams: params,
      ref: <String, Object?>{'type': 'prompt'},
      argument: 'arg',
      context: <String, Object?>{'ctx': true},
    );
    expect(comp['completion'], isNotNull);

    // Logging level
    expect(
      () => client.setLoggingLevel(connectionParams: params, level: 'bad_level'),
      throwsArgumentError,
    );
    await client.setLoggingLevel(connectionParams: params, level: 'info');

    // Notifications
    await client.notifyCancelledRequest(
      connectionParams: params,
      requestId: 10,
      reason: 'timeout',
      meta: <String, Object?>{'note': 'cancelled'},
    );
    await client.notifyProgress(
      connectionParams: params,
      progressToken: 'ptok',
      progress: 25,
      total: 100,
      message: 'working',
      meta: <String, Object?>{'detail': 'step'},
    );
    await client.notifyRootsListChanged(
      connectionParams: params,
      meta: <String, Object?>{'changed': true},
    );
    await client.notifyTaskStatus(
      connectionParams: params,
      status: <String, Object?>{'taskId': 't1', 'status': 'in_progress'},
    );
    await client.sendInitializedNotification(
      connectionParams: params,
      meta: <String, Object?>{'init': true},
    );

    // Test call with method == 'initialize'
    final initCall = await client.call(
      connectionParams: params,
      method: 'initialize',
      params: <String, Object?>{
        'protocolVersion': '2025-11-25',
        'capabilities': <String, Object?>{},
        'clientInfo': <String, Object?>{'name': 'c', 'version': '1'},
      },
    );
    expect(initCall, isNotNull);
  });

  test('McpStdioClient error cases, server requests, and process exit', () async {
    final List<McpServerMessage> receivedMessages = <McpServerMessage>[];
    final StdioConnectionParams params = await _createStdioServerParams();
    final McpStdioClient client = McpStdioClient(
      clientInfoName: 'test_client',
      clientInfoVersion: '0.0.0',
      onServerMessage: (msg) => receivedMessages.add(msg),
      onServerRequest: (msg) async {
        if (msg.method == 'test/throw_custom') {
          throw McpServerRequestException(
            code: -32099,
            message: 'Custom Server Request Failure',
            data: <String, Object?>{'reason': 'test'},
          );
        }
        if (msg.method == 'test/throw_generic') {
          throw Exception('Generic Server Request Error');
        }
        return <String, Object?>{'handled': true};
      },
    );
    addTearDown(() async => client.close());

    await client.ensureInitialized(params);

    // RPC Error response
    await expectLater(
      client.call(
        connectionParams: params,
        method: 'test/error_code',
        params: const <String, Object?>{},
      ),
      throwsA(isA<McpJsonRpcException>()),
    );

    // tryCall error suppression
    final suppressedRpc = await client.tryCall(
      connectionParams: params,
      method: 'test/error_code',
      params: const <String, Object?>{},
      suppressJsonRpcErrorCodes: const <int>{-32001},
    );
    expect(suppressedRpc, isNull);

    final suppressedAll = await client.tryCall(
      connectionParams: params,
      method: 'test/error_code',
      params: const <String, Object?>{},
      suppressErrors: true,
    );
    expect(suppressedAll, isNull);

    // Missing result and error
    await expectLater(
      client.call(
        connectionParams: params,
        method: 'test/missing_result_and_error',
        params: const <String, Object?>{},
      ),
      throwsFormatException,
    );

    // Trigger server requests and notification
    final triggerResult = await client.call(
      connectionParams: params,
      method: 'test/trigger_server_requests',
      params: const <String, Object?>{},
    );
    expect(triggerResult, isNotNull);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(receivedMessages, isNotEmpty);
  });

  test('McpStdioClient handles premature process exit and bad initialize handshake', () async {
    // 1. Script that exits unexpectedly with code 42
    final Directory dir1 = await Directory.systemTemp.createTemp('mcp_exit_');
    addTearDown(() => dir1.delete(recursive: true));
    final File script1 = File('${dir1.path}/exit_server.dart');
    await script1.writeAsString('''
import 'dart:io';
void main() {
  exit(42);
}
''');
    final p1 = StdioConnectionParams(
      command: Platform.resolvedExecutable,
      arguments: [script1.path],
    );
    final c1 = McpStdioClient(clientInfoName: 'c1', clientInfoVersion: '1');
    addTearDown(() => c1.close());
    await expectLater(c1.ensureInitialized(p1), throwsStateError);

    // 2. Script that returns missing protocolVersion
    final Directory dir2 = await Directory.systemTemp.createTemp('mcp_missing_proto_');
    addTearDown(() => dir2.delete(recursive: true));
    final File script2 = File('${dir2.path}/missing_proto_server.dart');
    await script2.writeAsString('''
import 'dart:convert';
import 'dart:io';
void main() {
  stdin.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
    final rpc = jsonDecode(line) as Map;
    if (rpc['method'] == 'initialize') {
      stdout.writeln(jsonEncode({
        'jsonrpc': '2.0',
        'id': rpc['id'],
        'result': {'capabilities': {}},
      }));
    }
  });
}
''');
    final p2 = StdioConnectionParams(
      command: Platform.resolvedExecutable,
      arguments: [script2.path],
    );
    final c2 = McpStdioClient(clientInfoName: 'c2', clientInfoVersion: '1');
    addTearDown(() => c2.close());
    await expectLater(c2.ensureInitialized(p2), throwsStateError);

    // 3. Script that returns unsupported protocolVersion
    final Directory dir3 = await Directory.systemTemp.createTemp('mcp_bad_proto_');
    addTearDown(() => dir3.delete(recursive: true));
    final File script3 = File('${dir3.path}/bad_proto_server.dart');
    await script3.writeAsString('''
import 'dart:convert';
import 'dart:io';
void main() {
  stdin.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
    final rpc = jsonDecode(line) as Map;
    if (rpc['method'] == 'initialize') {
      stdout.writeln(jsonEncode({
        'jsonrpc': '2.0',
        'id': rpc['id'],
        'result': {'protocolVersion': '1999-01-01', 'capabilities': {}},
      }));
    }
  });
}
''');
    final p3 = StdioConnectionParams(
      command: Platform.resolvedExecutable,
      arguments: [script3.path],
    );
    final c3 = McpStdioClient(clientInfoName: 'c3', clientInfoVersion: '1');
    addTearDown(() => c3.close());
    await expectLater(c3.ensureInitialized(p3), throwsStateError);
  });

  test('McpStdioClient final edge cases coverage', () async {
    final StdioConnectionParams params = await _createStdioServerParams();
    // 1. Client with onServerRequest: null to trigger unsupported server request
    final McpStdioClient client = McpStdioClient(
      clientInfoName: 'stdio_edge',
      clientInfoVersion: '1.0.0',
    );
    addTearDown(() async => client.close(killProcess: true));

    await client.ensureInitialized(params);

    // Collect paginated maps across pages
    final pages = await client.collectPaginatedMaps(
      connectionParams: params,
      method: 'resources/list',
      resultArrayField: 'resources',
    );
    expect(pages.length, equals(2));

    // test/num_id
    final numRes = await client.call(
      connectionParams: params,
      method: 'test/num_id',
      params: const <String, Object?>{},
    );
    expect(numRes, isNotNull);

    // test/str_id
    final strRes = await client.call(
      connectionParams: params,
      method: 'test/str_id',
      params: const <String, Object?>{},
    );
    expect(strRes, isNotNull);

    // test/error_empty_message
    await expectLater(
      client.call(
        connectionParams: params,
        method: 'test/error_empty_message',
        params: const <String, Object?>{},
      ),
      throwsA(isA<McpJsonRpcException>()),
    );

    // test/num_code_error
    await expectLater(
      client.call(
        connectionParams: params,
        method: 'test/num_code_error',
        params: const <String, Object?>{},
      ),
      throwsA(isA<McpJsonRpcException>()),
    );

    // test/str_code_error
    await expectLater(
      client.call(
        connectionParams: params,
        method: 'test/str_code_error',
        params: const <String, Object?>{},
      ),
      throwsA(isA<McpJsonRpcException>()),
    );

    // Server request when onServerRequest is null
    await client.call(
      connectionParams: params,
      method: 'test/trigger_server_requests',
      params: const <String, Object?>{},
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));

    // Close with killProcess: true
    await client.close(killProcess: true);
  });
}


