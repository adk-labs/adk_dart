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
        if (slowRequestId != null && params['requestId'] == slowRequestId) {
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
        respond(
          id,
          result: <String, Object?>{
            'resources': <Map<String, Object?>>[
              <String, Object?>{'uri': 'file:///r1', 'name': 'r1'},
            ],
          },
        );
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
      expect(resources.single['uri'], 'file:///r1');
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

    await Future<void>.delayed(const Duration(milliseconds: 450));
    final Map<String, Object?> debug =
        (await client.call(
              connectionParams: params,
              method: 'debug/cancelledSeen',
              params: const <String, Object?>{},
            ))
            as Map<String, Object?>;
    expect(debug['seen'], isTrue);
  });
}
