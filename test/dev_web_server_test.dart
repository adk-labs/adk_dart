import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:adk_dart/src/dev/project.dart';
import 'package:adk_dart/src/dev/runtime.dart';
import 'package:adk_dart/src/dev/web_server.dart';
import 'package:adk_dart/src/plugins/base_plugin.dart';
import 'package:adk_dart/src/cli/service_registry.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:test/test.dart';

void main() {
  group('startAdkDevWebServer', () {
    late HttpServer server;
    late HttpClient client;
    late DevAgentRuntime runtime;
    late DevProjectConfig config;

    setUp(() async {
      config = const DevProjectConfig(
        appName: 'test_app',
        agentName: 'root_agent',
        description: 'test',
      );
      runtime = DevAgentRuntime(config: config);
      server = await startAdkDevWebServer(
        runtime: runtime,
        project: config,
        port: 0,
      );
      client = HttpClient();
    });

    tearDown(() async {
      client.close(force: true);
      await server.close(force: true);
      await runtime.runner.close();
    });

    test('serves health endpoint', () async {
      final HttpClientRequest request = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/health'),
      );
      final HttpClientResponse response = await request.close();
      final String body = await utf8.decoder.bind(response).join();

      expect(response.statusCode, HttpStatus.ok);
      expect(jsonDecode(body), <String, Object>{
        'status': 'ok',
        'service': 'adk_dart_web',
        'appName': 'test_app',
      });
    });

    test('reports a2a/trace/otel/extra plugin options in api info', () async {
      final DevAgentRuntime infoRuntime = DevAgentRuntime(config: config);
      final HttpServer infoServer = await startAdkDevWebServer(
        runtime: infoRuntime,
        project: config,
        port: 0,
        traceToCloud: true,
        otelToCloud: true,
        a2a: true,
        extraPlugins: const <String>[
          'logging_plugin',
          'unknown.package.CustomPlugin',
        ],
      );
      addTearDown(() async {
        await infoServer.close(force: true);
        await infoRuntime.runner.close();
      });

      final HttpClient infoClient = HttpClient();
      addTearDown(() => infoClient.close(force: true));

      final HttpClientRequest request = await infoClient.getUrl(
        Uri.parse('http://127.0.0.1:${infoServer.port}/api/info'),
      );
      final HttpClientResponse response = await request.close();
      final String body = await utf8.decoder.bind(response).join();
      final Map<String, dynamic> payload =
          jsonDecode(body) as Map<String, dynamic>;

      expect(response.statusCode, HttpStatus.ok);
      expect(payload['a2a'], isTrue);
      expect(payload['trace_to_cloud'], isTrue);
      expect(payload['otel_to_cloud'], isTrue);
      expect(payload['extra_plugins'], <String>[
        'logging_plugin',
        'unknown.package.CustomPlugin',
      ]);
    });

    test('loads extra plugin via registered class factory fallback', () async {
      _FactoryLoadedPlugin.instances = 0;
      registerServiceClassFactory('test.plugins.FactoryPlugin', (
        String _, {
        Map<String, Object?>? kwargs,
      }) {
        return _FactoryLoadedPlugin(
          name: 'factory_plugin_${_FactoryLoadedPlugin.instances}',
        );
      });
      addTearDown(resetServiceRegistryForTest);

      final DevAgentRuntime pluginRuntime = DevAgentRuntime(config: config);
      final HttpServer pluginServer = await startAdkDevWebServer(
        runtime: pluginRuntime,
        project: config,
        port: 0,
        autoCreateSession: true,
        extraPlugins: const <String>['test.plugins.FactoryPlugin'],
      );
      addTearDown(() async {
        await pluginServer.close(force: true);
        await pluginRuntime.runner.close();
      });

      final HttpClient pluginClient = HttpClient();
      addTearDown(() => pluginClient.close(force: true));

      final HttpClientRequest runRequest = await pluginClient.postUrl(
        Uri.parse('http://127.0.0.1:${pluginServer.port}/run'),
      );
      runRequest.headers.contentType = ContentType.json;
      runRequest.write(
        jsonEncode(<String, Object>{
          'app_name': 'test_app',
          'user_id': 'u1',
          'session_id': 's_plugin',
          'new_message': <String, Object>{
            'role': 'user',
            'parts': <Object>[
              <String, Object>{'text': 'hello'},
            ],
          },
        }),
      );
      final HttpClientResponse runResponse = await runRequest.close();
      await utf8.decoder.bind(runResponse).join();

      expect(runResponse.statusCode, HttpStatus.ok);
      expect(_FactoryLoadedPlugin.instances, greaterThan(0));
    });

    test('loads extra plugin via dynamic file-path class spec', () async {
      final Directory sandbox = await Directory.systemTemp.createTemp(
        'adk_dynamic_plugin_',
      );
      addTearDown(() async {
        if (await sandbox.exists()) {
          await sandbox.delete(recursive: true);
        }
      });

      final String fixturePath =
          '${Directory.current.path}${Platform.pathSeparator}test${Platform.pathSeparator}fixtures${Platform.pathSeparator}dynamic_extra_plugin.dart';
      final String markerPath =
          '${sandbox.path}${Platform.pathSeparator}.dynamic_extra_plugin_marker';
      final File marker = File(markerPath);

      final DevAgentRuntime pluginRuntime = DevAgentRuntime(config: config);
      final HttpServer pluginServer = await startAdkDevWebServer(
        runtime: pluginRuntime,
        project: config,
        agentsDir: sandbox.path,
        port: 0,
        autoCreateSession: true,
        extraPlugins: <String>['$fixturePath:DynamicExtraPlugin'],
      );
      addTearDown(() async {
        await pluginServer.close(force: true);
        await pluginRuntime.runner.close();
      });

      final HttpClient pluginClient = HttpClient();
      addTearDown(() => pluginClient.close(force: true));

      final HttpClientRequest runRequest = await pluginClient.postUrl(
        Uri.parse('http://127.0.0.1:${pluginServer.port}/run'),
      );
      runRequest.headers.contentType = ContentType.json;
      runRequest.write(
        jsonEncode(<String, Object>{
          'app_name': 'test_app',
          'user_id': 'u1',
          'session_id': 's_dynamic_file',
          'new_message': <String, Object>{
            'role': 'user',
            'parts': <Object>[
              <String, Object>{'text': 'hello'},
            ],
          },
        }),
      );
      final HttpClientResponse runResponse = await runRequest.close();
      await utf8.decoder.bind(runResponse).join();

      expect(runResponse.statusCode, HttpStatus.ok);
      expect(await marker.exists(), isTrue);
      final String markerText = await marker.readAsString();
      expect(markerText, contains('DynamicExtraPlugin'));
    });

    test('loads extra plugin via dotted package class path', () async {
      final String debugPath =
          '${Directory.current.path}${Platform.pathSeparator}adk_debug.yaml';
      final File debugFile = File(debugPath);
      if (await debugFile.exists()) {
        await debugFile.delete();
      }
      addTearDown(() async {
        if (await debugFile.exists()) {
          await debugFile.delete();
        }
      });

      final DevAgentRuntime pluginRuntime = DevAgentRuntime(config: config);
      final HttpServer pluginServer = await startAdkDevWebServer(
        runtime: pluginRuntime,
        project: config,
        port: 0,
        autoCreateSession: true,
        extraPlugins: const <String>[
          'adk_dart.src.plugins.debug_logging_plugin.DebugLoggingPlugin',
        ],
      );
      addTearDown(() async {
        await pluginServer.close(force: true);
        await pluginRuntime.runner.close();
      });

      final HttpClient pluginClient = HttpClient();
      addTearDown(() => pluginClient.close(force: true));

      final HttpClientRequest runRequest = await pluginClient.postUrl(
        Uri.parse('http://127.0.0.1:${pluginServer.port}/run'),
      );
      runRequest.headers.contentType = ContentType.json;
      runRequest.write(
        jsonEncode(<String, Object>{
          'app_name': 'test_app',
          'user_id': 'u1',
          'session_id': 's_dynamic_dotted',
          'new_message': <String, Object>{
            'role': 'user',
            'parts': <Object>[
              <String, Object>{'text': 'hello'},
            ],
          },
        }),
      );
      final HttpClientResponse runResponse = await runRequest.close();
      await utf8.decoder.bind(runResponse).join();

      expect(runResponse.statusCode, HttpStatus.ok);
      expect(await debugFile.exists(), isTrue);
      final String debugText = await debugFile.readAsString();
      expect(debugText, contains('invocation_id'));
    });

    test('returns not found for a2a agent card when a2a is disabled', () async {
      final HttpClientRequest request = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/.well-known/agent.json'),
      );
      final HttpClientResponse response = await request.close();
      await utf8.decoder.bind(response).join();
      expect(response.statusCode, HttpStatus.notFound);
    });

    test('serves a2a agent cards when a2a is enabled', () async {
      final DevAgentRuntime a2aRuntime = DevAgentRuntime(config: config);
      final HttpServer a2aServer = await startAdkDevWebServer(
        runtime: a2aRuntime,
        project: config,
        port: 0,
        a2a: true,
      );
      addTearDown(() async {
        await a2aServer.close(force: true);
        await a2aRuntime.runner.close();
      });

      final HttpClient a2aClient = HttpClient();
      addTearDown(() => a2aClient.close(force: true));

      final HttpClientRequest rootRequest = await a2aClient.getUrl(
        Uri.parse('http://127.0.0.1:${a2aServer.port}/.well-known/agent.json'),
      );
      final HttpClientResponse rootResponse = await rootRequest.close();
      final Map<String, dynamic> rootPayload =
          jsonDecode(await utf8.decoder.bind(rootResponse).join())
              as Map<String, dynamic>;

      final HttpClientRequest scopedRequest = await a2aClient.getUrl(
        Uri.parse(
          'http://127.0.0.1:${a2aServer.port}/a2a/test_app/.well-known/agent.json',
        ),
      );
      final HttpClientResponse scopedResponse = await scopedRequest.close();
      final Map<String, dynamic> scopedPayload =
          jsonDecode(await utf8.decoder.bind(scopedResponse).join())
              as Map<String, dynamic>;

      expect(rootResponse.statusCode, HttpStatus.ok);
      expect(scopedResponse.statusCode, HttpStatus.ok);
      expect(rootPayload['name'], 'root_agent');
      expect(rootPayload['url'], contains('/a2a/test_app'));
      expect(scopedPayload['name'], 'root_agent');
      expect(scopedPayload['url'], contains('/a2a/test_app'));
    });

    test(
      'returns not found for a2a rpc endpoint when a2a is disabled',
      () async {
        final HttpClientRequest request = await client.postUrl(
          Uri.parse('http://127.0.0.1:${server.port}/a2a/test_app'),
        );
        request.headers.contentType = ContentType.json;
        request.write(
          jsonEncode(<String, Object?>{
            'jsonrpc': '2.0',
            'id': 'rpc-disabled',
            'method': 'message/send',
            'params': <String, Object?>{},
          }),
        );
        final HttpClientResponse response = await request.close();
        await utf8.decoder.bind(response).join();
        expect(response.statusCode, HttpStatus.notFound);
      },
    );

    test('handles a2a message send and task get rpc routes', () async {
      final DevAgentRuntime a2aRuntime = DevAgentRuntime(config: config);
      final HttpServer a2aServer = await startAdkDevWebServer(
        runtime: a2aRuntime,
        project: config,
        port: 0,
        a2a: true,
      );
      addTearDown(() async {
        await a2aServer.close(force: true);
        await a2aRuntime.runner.close();
      });

      final HttpClient a2aClient = HttpClient();
      addTearDown(() => a2aClient.close(force: true));

      final HttpClientRequest sendRequest = await a2aClient.postUrl(
        Uri.parse(
          'http://127.0.0.1:${a2aServer.port}/a2a/test_app/v1/message:send',
        ),
      );
      sendRequest.headers.contentType = ContentType.json;
      sendRequest.write(
        jsonEncode(<String, Object?>{
          'jsonrpc': '2.0',
          'id': 'rpc-send-1',
          'params': <String, Object?>{
            'message': <String, Object?>{
              'kind': 'message',
              'messageId': 'msg-send-1',
              'role': 'user',
              'parts': <Object>[
                <String, Object?>{
                  'kind': 'text',
                  'text': 'What time in Seoul?',
                },
              ],
            },
          },
        }),
      );
      final HttpClientResponse sendResponse = await sendRequest.close();
      final Map<String, dynamic> sendPayload =
          jsonDecode(await utf8.decoder.bind(sendResponse).join())
              as Map<String, dynamic>;
      final Map<String, dynamic> result =
          sendPayload['result'] as Map<String, dynamic>;
      final String taskId = '${result['taskId'] ?? result['task_id'] ?? ''}';

      expect(sendResponse.statusCode, HttpStatus.ok);
      expect(sendPayload['jsonrpc'], '2.0');
      expect(taskId, isNotEmpty);
      expect(result['kind'], 'message');
      expect(result['contextId'] ?? result['context_id'], isNotEmpty);

      final HttpClientRequest getRequest = await a2aClient.postUrl(
        Uri.parse(
          'http://127.0.0.1:${a2aServer.port}/a2a/test_app/v1/tasks:get',
        ),
      );
      getRequest.headers.contentType = ContentType.json;
      getRequest.write(
        jsonEncode(<String, Object?>{
          'jsonrpc': '2.0',
          'id': 'rpc-get-1',
          'params': <String, Object?>{'taskId': taskId},
        }),
      );
      final HttpClientResponse getResponse = await getRequest.close();
      final Map<String, dynamic> getPayload =
          jsonDecode(await utf8.decoder.bind(getResponse).join())
              as Map<String, dynamic>;
      final Map<String, dynamic> task =
          getPayload['result'] as Map<String, dynamic>;

      expect(getResponse.statusCode, HttpStatus.ok);
      expect(task['kind'], 'task');
      expect(task['id'] ?? task['taskId'] ?? task['task_id'], taskId);
      expect(task['status'], isA<Map>());
    });

    test('supports a2a streaming, push config, and resubscribe routes', () async {
      final DevAgentRuntime a2aRuntime = DevAgentRuntime(config: config);
      final HttpServer a2aServer = await startAdkDevWebServer(
        runtime: a2aRuntime,
        project: config,
        port: 0,
        a2a: true,
      );
      addTearDown(() async {
        await a2aServer.close(force: true);
        await a2aRuntime.runner.close();
      });

      final HttpClient a2aClient = HttpClient();
      addTearDown(() => a2aClient.close(force: true));

      final HttpClientRequest streamRequest = await a2aClient.postUrl(
        Uri.parse('http://127.0.0.1:${a2aServer.port}/a2a/test_app'),
      );
      streamRequest.headers.contentType = ContentType.json;
      streamRequest.write(
        jsonEncode(<String, Object?>{
          'jsonrpc': '2.0',
          'id': 'rpc-stream-1',
          'method': 'message/stream',
          'params': <String, Object?>{
            'message': <String, Object?>{
              'kind': 'message',
              'messageId': 'msg-stream-1',
              'role': 'user',
              'parts': <Object>[
                <String, Object?>{
                  'kind': 'text',
                  'text': 'Give me a short answer.',
                },
              ],
            },
          },
        }),
      );
      final HttpClientResponse streamResponse = await streamRequest.close();
      final String streamBody = await utf8.decoder.bind(streamResponse).join();
      final List<Map<String, dynamic>> streamEvents = _decodeSseJsonEvents(
        streamBody,
      );

      expect(streamResponse.statusCode, HttpStatus.ok);
      expect(
        streamResponse.headers.contentType?.mimeType,
        ContentType('text', 'event-stream').mimeType,
      );
      expect(streamEvents, isNotEmpty);
      expect(streamEvents.first['jsonrpc'], '2.0');

      final Map<String, dynamic> streamedTask =
          streamEvents.first['result'] as Map<String, dynamic>;
      final String taskId =
          '${streamedTask['id'] ?? streamedTask['taskId'] ?? streamedTask['task_id']}';
      expect(taskId, isNotEmpty);
      expect(streamedTask['kind'], 'task');

      final HttpClientRequest setPushRequest = await a2aClient.postUrl(
        Uri.parse(
          'http://127.0.0.1:${a2aServer.port}/a2a/test_app/v1/tasks:pushNotificationConfig:set',
        ),
      );
      setPushRequest.headers.contentType = ContentType.json;
      setPushRequest.write(
        jsonEncode(<String, Object?>{
          'jsonrpc': '2.0',
          'id': 'rpc-push-set-1',
          'params': <String, Object?>{
            'taskId': taskId,
            'pushNotificationConfig': <String, Object?>{
              'url': 'https://example.invalid/hook',
              'authentication': <String, Object?>{
                'scheme': 'bearer',
                'token': 'secret',
              },
            },
          },
        }),
      );
      final HttpClientResponse setPushResponse = await setPushRequest.close();
      final Map<String, dynamic> setPushPayload =
          jsonDecode(await utf8.decoder.bind(setPushResponse).join())
              as Map<String, dynamic>;
      final Map<String, dynamic> setPushResult =
          setPushPayload['result'] as Map<String, dynamic>;

      expect(setPushResponse.statusCode, HttpStatus.ok);
      expect(
        (setPushResult['pushNotificationConfig']
            as Map<String, dynamic>)['url'],
        'https://example.invalid/hook',
      );

      final HttpClientRequest getPushRequest = await a2aClient.postUrl(
        Uri.parse(
          'http://127.0.0.1:${a2aServer.port}/a2a/test_app/v1/tasks:pushNotificationConfig:get',
        ),
      );
      getPushRequest.headers.contentType = ContentType.json;
      getPushRequest.write(
        jsonEncode(<String, Object?>{
          'jsonrpc': '2.0',
          'id': 'rpc-push-get-1',
          'params': <String, Object?>{'taskId': taskId},
        }),
      );
      final HttpClientResponse getPushResponse = await getPushRequest.close();
      final Map<String, dynamic> getPushPayload =
          jsonDecode(await utf8.decoder.bind(getPushResponse).join())
              as Map<String, dynamic>;
      final Map<String, dynamic> getPushResult =
          getPushPayload['result'] as Map<String, dynamic>;

      expect(getPushResponse.statusCode, HttpStatus.ok);
      expect(
        (getPushResult['pushNotificationConfig']
            as Map<String, dynamic>)['url'],
        'https://example.invalid/hook',
      );

      final HttpClientRequest resubscribeRequest = await a2aClient.postUrl(
        Uri.parse('http://127.0.0.1:${a2aServer.port}/a2a/test_app'),
      );
      resubscribeRequest.headers.contentType = ContentType.json;
      resubscribeRequest.write(
        jsonEncode(<String, Object?>{
          'jsonrpc': '2.0',
          'id': 'rpc-resub-1',
          'method': 'tasks/resubscribe',
          'params': <String, Object?>{'taskId': taskId},
        }),
      );
      final HttpClientResponse resubscribeResponse = await resubscribeRequest
          .close();
      final String resubscribeBody = await utf8.decoder
          .bind(resubscribeResponse)
          .join();
      final List<Map<String, dynamic>> resubscribeEvents = _decodeSseJsonEvents(
        resubscribeBody,
      );

      expect(resubscribeResponse.statusCode, HttpStatus.ok);
      expect(
        resubscribeResponse.headers.contentType?.mimeType,
        ContentType('text', 'event-stream').mimeType,
      );
      expect(resubscribeEvents, isNotEmpty);
      expect(
        resubscribeEvents.any((Map<String, dynamic> event) {
          final Object? result = event['result'];
          if (result is! Map) {
            return false;
          }
          final Map<String, dynamic> resultMap = result.cast<String, dynamic>();
          return '${resultMap['kind'] ?? ''}' == 'task_status_update';
        }),
        isTrue,
      );

      final HttpClientRequest pathGetRequest = await a2aClient.getUrl(
        Uri.parse(
          'http://127.0.0.1:${a2aServer.port}/a2a/test_app/v1/tasks/$taskId',
        ),
      );
      final HttpClientResponse pathGetResponse = await pathGetRequest.close();
      final Map<String, dynamic> pathGetPayload =
          jsonDecode(await utf8.decoder.bind(pathGetResponse).join())
              as Map<String, dynamic>;

      expect(pathGetResponse.statusCode, HttpStatus.ok);
      expect(pathGetPayload['kind'], 'task');
    });

    test('dispatches a2a push notifications to callback endpoint', () async {
      final Completer<Map<String, dynamic>> pushRequestCompleter =
          Completer<Map<String, dynamic>>();
      final HttpServer callbackServer = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      callbackServer.listen((HttpRequest request) async {
        final String body = await utf8.decoder.bind(request).join();
        if (!pushRequestCompleter.isCompleted) {
          pushRequestCompleter.complete(
            jsonDecode(body) as Map<String, dynamic>,
          );
        }
        request.response.statusCode = HttpStatus.ok;
        await request.response.close();
      });
      addTearDown(() async {
        await callbackServer.close(force: true);
      });

      final DevAgentRuntime a2aRuntime = DevAgentRuntime(config: config);
      final HttpServer a2aServer = await startAdkDevWebServer(
        runtime: a2aRuntime,
        project: config,
        port: 0,
        a2a: true,
      );
      addTearDown(() async {
        await a2aServer.close(force: true);
        await a2aRuntime.runner.close();
      });

      final HttpClient a2aClient = HttpClient();
      addTearDown(() => a2aClient.close(force: true));

      const String taskId = 'task_push_dispatch_1';

      final HttpClientRequest firstSendRequest = await a2aClient.postUrl(
        Uri.parse('http://127.0.0.1:${a2aServer.port}/a2a/test_app'),
      );
      firstSendRequest.headers.contentType = ContentType.json;
      firstSendRequest.write(
        jsonEncode(<String, Object?>{
          'jsonrpc': '2.0',
          'id': 'rpc-send-push-1',
          'method': 'message/send',
          'params': <String, Object?>{
            'message': <String, Object?>{
              'messageId': 'msg-push-1',
              'role': 'user',
              'taskId': taskId,
              'parts': <Object>[
                <String, Object?>{'kind': 'text', 'text': 'hello'},
              ],
            },
          },
        }),
      );
      final HttpClientResponse firstSendResponse = await firstSendRequest
          .close();
      await utf8.decoder.bind(firstSendResponse).join();
      expect(firstSendResponse.statusCode, HttpStatus.ok);

      final HttpClientRequest setPushRequest = await a2aClient.postUrl(
        Uri.parse('http://127.0.0.1:${a2aServer.port}/a2a/test_app'),
      );
      setPushRequest.headers.contentType = ContentType.json;
      setPushRequest.write(
        jsonEncode(<String, Object?>{
          'jsonrpc': '2.0',
          'id': 'rpc-push-set-dispatch',
          'method': 'tasks/pushNotificationConfig/set',
          'params': <String, Object?>{
            'taskId': taskId,
            'pushNotificationConfig': <String, Object?>{
              'url':
                  'http://127.0.0.1:${callbackServer.port}/push/task-updates',
              'authentication': <String, Object?>{
                'scheme': 'Bearer',
                'token': 'token-123',
              },
            },
          },
        }),
      );
      final HttpClientResponse setPushResponse = await setPushRequest.close();
      await utf8.decoder.bind(setPushResponse).join();
      expect(setPushResponse.statusCode, HttpStatus.ok);

      final HttpClientRequest secondSendRequest = await a2aClient.postUrl(
        Uri.parse('http://127.0.0.1:${a2aServer.port}/a2a/test_app'),
      );
      secondSendRequest.headers.contentType = ContentType.json;
      secondSendRequest.write(
        jsonEncode(<String, Object?>{
          'jsonrpc': '2.0',
          'id': 'rpc-send-push-2',
          'method': 'message/send',
          'params': <String, Object?>{
            'message': <String, Object?>{
              'messageId': 'msg-push-2',
              'role': 'user',
              'taskId': taskId,
              'parts': <Object>[
                <String, Object?>{'kind': 'text', 'text': 'second'},
              ],
            },
          },
        }),
      );
      final HttpClientResponse secondSendResponse = await secondSendRequest
          .close();
      await utf8.decoder.bind(secondSendResponse).join();
      expect(secondSendResponse.statusCode, HttpStatus.ok);

      final Map<String, dynamic> callbackPayload = await pushRequestCompleter
          .future
          .timeout(const Duration(seconds: 5));

      expect(callbackPayload['jsonrpc'], '2.0');
      expect(callbackPayload['method'], 'tasks/pushNotification');
      final Map<String, dynamic> callbackParams =
          callbackPayload['params'] as Map<String, dynamic>;
      expect(callbackParams['taskId'], taskId);
      expect(callbackParams['task'], isA<Map<String, dynamic>>());
      expect(callbackParams['update'], isA<Map<String, dynamic>>());
    });

    test(
      'retries and drains persisted a2a push deliveries after server restart',
      () async {
        final Completer<Map<String, dynamic>> deliveredPayload =
            Completer<Map<String, dynamic>>();
        int callbackAttempts = 0;
        bool failResponses = true;
        final HttpServer callbackServer = await HttpServer.bind(
          InternetAddress.loopbackIPv4,
          0,
        );
        callbackServer.listen((HttpRequest request) async {
          callbackAttempts += 1;
          final String body = await utf8.decoder.bind(request).join();
          if (!failResponses && !deliveredPayload.isCompleted) {
            deliveredPayload.complete(jsonDecode(body) as Map<String, dynamic>);
            request.response.statusCode = HttpStatus.ok;
          } else {
            request.response.statusCode = HttpStatus.serviceUnavailable;
          }
          await request.response.close();
        });
        addTearDown(() async {
          await callbackServer.close(force: true);
        });

        final Directory sandbox = await Directory.systemTemp.createTemp(
          'adk_a2a_push_restart_',
        );
        addTearDown(() async {
          if (await sandbox.exists()) {
            await sandbox.delete(recursive: true);
          }
        });

        Future<void> sendA2aMessage({
          required HttpClient httpClient,
          required int port,
          required String rpcId,
          required String taskId,
          required String text,
        }) async {
          final HttpClientRequest sendRequest = await httpClient.postUrl(
            Uri.parse('http://127.0.0.1:$port/a2a/test_app'),
          );
          sendRequest.headers.contentType = ContentType.json;
          sendRequest.write(
            jsonEncode(<String, Object?>{
              'jsonrpc': '2.0',
              'id': rpcId,
              'method': 'message/send',
              'params': <String, Object?>{
                'message': <String, Object?>{
                  'messageId': 'msg-$rpcId',
                  'role': 'user',
                  'taskId': taskId,
                  'parts': <Object>[
                    <String, Object?>{'kind': 'text', 'text': text},
                  ],
                },
              },
            }),
          );
          final HttpClientResponse response = await sendRequest.close();
          await utf8.decoder.bind(response).join();
          expect(response.statusCode, HttpStatus.ok);
        }

        Future<void> setPushConfig({
          required HttpClient httpClient,
          required int port,
          required String taskId,
        }) async {
          final HttpClientRequest setPushRequest = await httpClient.postUrl(
            Uri.parse('http://127.0.0.1:$port/a2a/test_app'),
          );
          setPushRequest.headers.contentType = ContentType.json;
          setPushRequest.write(
            jsonEncode(<String, Object?>{
              'jsonrpc': '2.0',
              'id': 'rpc-push-set-restart',
              'method': 'tasks/pushNotificationConfig/set',
              'params': <String, Object?>{
                'taskId': taskId,
                'pushNotificationConfig': <String, Object?>{
                  'url':
                      'http://127.0.0.1:${callbackServer.port}/push/task-updates',
                  'retry': <String, Object?>{
                    'maxAttempts': 20,
                    'initialDelayMs': 60000,
                    'maxDelayMs': 60000,
                    'requestTimeoutMs': 2000,
                  },
                },
              },
            }),
          );
          final HttpClientResponse setPushResponse = await setPushRequest
              .close();
          await utf8.decoder.bind(setPushResponse).join();
          expect(setPushResponse.statusCode, HttpStatus.ok);
        }

        const String taskId = 'task_push_restart_1';

        final DevAgentRuntime runtime1 = DevAgentRuntime(config: config);
        final HttpServer server1 = await startAdkDevWebServer(
          runtime: runtime1,
          project: config,
          agentsDir: sandbox.path,
          port: 0,
          a2a: true,
        );
        final HttpClient client1 = HttpClient();

        await sendA2aMessage(
          httpClient: client1,
          port: server1.port,
          rpcId: 'rpc-send-restart-1',
          taskId: taskId,
          text: 'first',
        );
        await setPushConfig(
          httpClient: client1,
          port: server1.port,
          taskId: taskId,
        );
        await sendA2aMessage(
          httpClient: client1,
          port: server1.port,
          rpcId: 'rpc-send-restart-2',
          taskId: taskId,
          text: 'second',
        );

        await Future<void>.delayed(const Duration(milliseconds: 200));
        expect(callbackAttempts, greaterThan(0));

        client1.close(force: true);
        await server1.close(force: true);
        await runtime1.runner.close();

        final String queueDbPath =
            '${sandbox.path}${Platform.pathSeparator}.adk${Platform.pathSeparator}a2a_push_delivery.db';
        final sqlite.Database queueDb = sqlite.sqlite3.open(queueDbPath);
        try {
          queueDb.execute(
            'UPDATE a2a_push_delivery_queue SET next_attempt_at_ms = ?',
            <Object?>[DateTime.now().millisecondsSinceEpoch],
          );
        } finally {
          queueDb.close();
        }

        failResponses = false;

        final DevAgentRuntime runtime2 = DevAgentRuntime(config: config);
        final HttpServer server2 = await startAdkDevWebServer(
          runtime: runtime2,
          project: config,
          agentsDir: sandbox.path,
          port: 0,
          a2a: true,
        );
        addTearDown(() async {
          await server2.close(force: true);
          await runtime2.runner.close();
        });

        final Map<String, dynamic> payload = await deliveredPayload.future
            .timeout(const Duration(seconds: 10));
        expect(payload['jsonrpc'], '2.0');
        expect(payload['method'], 'tasks/pushNotification');
        final Map<String, dynamic> params =
            payload['params'] as Map<String, dynamic>;
        expect(params['taskId'], taskId);
      },
    );

    test('creates a session and sends a message', () async {
      final HttpClientRequest createSessionRequest = await client.postUrl(
        Uri.parse('http://127.0.0.1:${server.port}/api/sessions'),
      );
      createSessionRequest.headers.contentType = ContentType.json;
      createSessionRequest.write(jsonEncode(<String, Object>{'userId': 'u1'}));

      final HttpClientResponse createSessionResponse =
          await createSessionRequest.close();
      final String createBody = await utf8.decoder
          .bind(createSessionResponse)
          .join();
      final Map<String, dynamic> createPayload =
          jsonDecode(createBody) as Map<String, dynamic>;
      final String sessionId =
          (createPayload['session'] as Map<String, dynamic>)['id'] as String;

      final HttpClientRequest messageRequest = await client.postUrl(
        Uri.parse(
          'http://127.0.0.1:${server.port}/api/sessions/$sessionId/messages',
        ),
      );
      messageRequest.headers.contentType = ContentType.json;
      messageRequest.write(
        jsonEncode(<String, Object>{
          'userId': 'u1',
          'text': 'What time in Seoul?',
        }),
      );
      final HttpClientResponse messageResponse = await messageRequest.close();
      final String messageBody = await utf8.decoder
          .bind(messageResponse)
          .join();
      final Map<String, dynamic> payload =
          jsonDecode(messageBody) as Map<String, dynamic>;

      expect(messageResponse.statusCode, HttpStatus.ok);
      expect(payload['reply'], contains('The current time in'));
    });

    test('serves list-apps endpoint', () async {
      final HttpClientRequest request = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/list-apps?detailed=true'),
      );
      final HttpClientResponse response = await request.close();
      final String body = await utf8.decoder.bind(response).join();
      final Map<String, dynamic> payload =
          jsonDecode(body) as Map<String, dynamic>;
      final List<dynamic> apps = payload['apps'] as List<dynamic>;

      expect(response.statusCode, HttpStatus.ok);
      expect(
        apps.any(
          (dynamic app) => (app as Map<String, dynamic>)['name'] == 'test_app',
        ),
        isTrue,
      );
    });

    test('serves metrics info endpoint', () async {
      final HttpClientRequest request = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/apps/test_app/metrics-info'),
      );
      final HttpClientResponse response = await request.close();
      final Map<String, dynamic> payload =
          jsonDecode(await utf8.decoder.bind(response).join())
              as Map<String, dynamic>;

      expect(response.statusCode, HttpStatus.ok);
      expect(payload['metrics_info'], isA<List<dynamic>>());
      expect((payload['metrics_info'] as List<dynamic>).isNotEmpty, isTrue);
    });

    test('creates and lists eval sets via web routes', () async {
      final String evalSetId =
          'smoke_eval_${DateTime.now().microsecondsSinceEpoch}';
      final HttpClientRequest createRequest = await client.postUrl(
        Uri.parse('http://127.0.0.1:${server.port}/apps/test_app/eval-sets'),
      );
      createRequest.headers.contentType = ContentType.json;
      createRequest.write(
        jsonEncode(<String, Object?>{
          'eval_set': <String, Object?>{'eval_set_id': evalSetId},
        }),
      );
      final HttpClientResponse createResponse = await createRequest.close();
      final String createBody = await utf8.decoder.bind(createResponse).join();
      final Map<String, dynamic> created =
          jsonDecode(createBody) as Map<String, dynamic>;

      final HttpClientRequest listRequest = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/apps/test_app/eval-sets'),
      );
      final HttpClientResponse listResponse = await listRequest.close();
      final String listBody = await utf8.decoder.bind(listResponse).join();
      final Map<String, dynamic> listed =
          jsonDecode(listBody) as Map<String, dynamic>;

      expect(createResponse.statusCode, HttpStatus.ok);
      expect(created['eval_set_id'], evalSetId);
      expect(listResponse.statusCode, HttpStatus.ok);
      expect((listed['eval_set_ids'] as List<dynamic>), contains(evalSetId));
    });

    test('runs agent via /run endpoint', () async {
      final String sessionId = 's_run_${DateTime.now().microsecondsSinceEpoch}';
      final HttpClientRequest createRequest = await client.postUrl(
        Uri.parse(
          'http://127.0.0.1:${server.port}/apps/test_app/users/u1/sessions',
        ),
      );
      createRequest.headers.contentType = ContentType.json;
      createRequest.write(
        jsonEncode(<String, Object>{'session_id': sessionId}),
      );
      final HttpClientResponse createResponse = await createRequest.close();
      await utf8.decoder.bind(createResponse).join();
      expect(createResponse.statusCode, HttpStatus.ok);

      final HttpClientRequest runRequest = await client.postUrl(
        Uri.parse('http://127.0.0.1:${server.port}/run'),
      );
      runRequest.headers.contentType = ContentType.json;
      runRequest.write(
        jsonEncode(<String, Object>{
          'app_name': 'test_app',
          'user_id': 'u1',
          'session_id': sessionId,
          'new_message': <String, Object>{
            'role': 'user',
            'parts': <Object>[
              <String, Object>{'text': 'What time in Seoul?'},
            ],
          },
        }),
      );

      final HttpClientResponse runResponse = await runRequest.close();
      final String runBody = await utf8.decoder.bind(runResponse).join();
      final List<dynamic> events = jsonDecode(runBody) as List<dynamic>;

      expect(runResponse.statusCode, HttpStatus.ok);
      expect(events, isNotEmpty);
    });

    test('serves debug trace and event graph after run', () async {
      final String sessionId =
          's_trace_${DateTime.now().microsecondsSinceEpoch}';
      final HttpClientRequest createRequest = await client.postUrl(
        Uri.parse(
          'http://127.0.0.1:${server.port}/apps/test_app/users/u1/sessions',
        ),
      );
      createRequest.headers.contentType = ContentType.json;
      createRequest.write(
        jsonEncode(<String, Object>{'session_id': sessionId}),
      );
      final HttpClientResponse createResponse = await createRequest.close();
      await utf8.decoder.bind(createResponse).join();
      expect(createResponse.statusCode, HttpStatus.ok);

      final HttpClientRequest runRequest = await client.postUrl(
        Uri.parse('http://127.0.0.1:${server.port}/run'),
      );
      runRequest.headers.contentType = ContentType.json;
      runRequest.write(
        jsonEncode(<String, Object>{
          'app_name': 'test_app',
          'user_id': 'u1',
          'session_id': sessionId,
          'new_message': <String, Object>{
            'role': 'user',
            'parts': <Object>[
              <String, Object>{'text': 'What time in Seoul?'},
            ],
          },
        }),
      );
      final HttpClientResponse runResponse = await runRequest.close();
      final List<dynamic> events =
          jsonDecode(await utf8.decoder.bind(runResponse).join())
              as List<dynamic>;
      expect(runResponse.statusCode, HttpStatus.ok);
      expect(events, isNotEmpty);

      final String eventId = '${(events.first as Map<String, dynamic>)['id']}';
      final HttpClientRequest traceRequest = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/debug/trace/$eventId'),
      );
      final HttpClientResponse traceResponse = await traceRequest.close();
      final Map<String, dynamic> tracePayload =
          jsonDecode(await utf8.decoder.bind(traceResponse).join())
              as Map<String, dynamic>;

      final HttpClientRequest sessionTraceRequest = await client.getUrl(
        Uri.parse(
          'http://127.0.0.1:${server.port}/debug/trace/session/$sessionId',
        ),
      );
      final HttpClientResponse sessionTraceResponse = await sessionTraceRequest
          .close();
      final List<dynamic> sessionTracePayload =
          jsonDecode(await utf8.decoder.bind(sessionTraceResponse).join())
              as List<dynamic>;

      final HttpClientRequest graphRequest = await client.getUrl(
        Uri.parse(
          'http://127.0.0.1:${server.port}/apps/test_app/users/u1/sessions/$sessionId/events/$eventId/graph',
        ),
      );
      final HttpClientResponse graphResponse = await graphRequest.close();
      final Map<String, dynamic> graphPayload =
          jsonDecode(await utf8.decoder.bind(graphResponse).join())
              as Map<String, dynamic>;

      expect(traceResponse.statusCode, HttpStatus.ok);
      expect(tracePayload['event_id'], eventId);
      expect(sessionTraceResponse.statusCode, HttpStatus.ok);
      expect(sessionTracePayload, isNotEmpty);
      expect(graphResponse.statusCode, HttpStatus.ok);
      expect('${graphPayload['dot_src']}', contains('digraph'));
    });

    test('streams events via /run_sse endpoint', () async {
      final String sessionId = 's_sse_${DateTime.now().microsecondsSinceEpoch}';
      final HttpClientRequest createRequest = await client.postUrl(
        Uri.parse(
          'http://127.0.0.1:${server.port}/apps/test_app/users/u1/sessions',
        ),
      );
      createRequest.headers.contentType = ContentType.json;
      createRequest.write(
        jsonEncode(<String, Object>{'session_id': sessionId}),
      );
      final HttpClientResponse createResponse = await createRequest.close();
      await utf8.decoder.bind(createResponse).join();
      expect(createResponse.statusCode, HttpStatus.ok);

      final HttpClientRequest sseRequest = await client.postUrl(
        Uri.parse('http://127.0.0.1:${server.port}/run_sse'),
      );
      sseRequest.headers.contentType = ContentType.json;
      sseRequest.write(
        jsonEncode(<String, Object>{
          'app_name': 'test_app',
          'user_id': 'u1',
          'session_id': sessionId,
          'streaming': true,
          'new_message': <String, Object>{
            'role': 'user',
            'parts': <Object>[
              <String, Object>{'text': 'What time in Tokyo?'},
            ],
          },
        }),
      );

      final HttpClientResponse sseResponse = await sseRequest.close();
      final String sseBody = await utf8.decoder.bind(sseResponse).join();

      expect(sseResponse.statusCode, HttpStatus.ok);
      expect(
        sseResponse.headers.contentType?.mimeType,
        ContentType('text', 'event-stream').mimeType,
      );
      expect(sseBody, contains('data: '));
    });

    test('lists empty artifact names', () async {
      final String sessionId = 's_art_${DateTime.now().microsecondsSinceEpoch}';
      final HttpClientRequest createRequest = await client.postUrl(
        Uri.parse(
          'http://127.0.0.1:${server.port}/apps/test_app/users/u1/sessions',
        ),
      );
      createRequest.headers.contentType = ContentType.json;
      createRequest.write(
        jsonEncode(<String, Object>{'session_id': sessionId}),
      );
      final HttpClientResponse createResponse = await createRequest.close();
      await utf8.decoder.bind(createResponse).join();
      expect(createResponse.statusCode, HttpStatus.ok);

      final HttpClientRequest listRequest = await client.getUrl(
        Uri.parse(
          'http://127.0.0.1:${server.port}/apps/test_app/users/u1/sessions/$sessionId/artifacts',
        ),
      );
      final HttpClientResponse listResponse = await listRequest.close();
      final String listBody = await utf8.decoder.bind(listResponse).join();
      final List<dynamic> artifacts = jsonDecode(listBody) as List<dynamic>;

      expect(listResponse.statusCode, HttpStatus.ok);
      expect(artifacts, isEmpty);
    });

    test('serves index page', () async {
      final HttpClientRequest request = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/'),
      );
      final HttpClientResponse response = await request.close();
      final String body = await utf8.decoder.bind(response).join();

      expect(response.statusCode, HttpStatus.ok);
      expect(body, contains('Agent Development Kit Dev UI'));
    });

    test('supports url_prefix routing', () async {
      final DevAgentRuntime prefixedRuntime = DevAgentRuntime(config: config);
      final HttpServer prefixedServer = await startAdkDevWebServer(
        runtime: prefixedRuntime,
        project: config,
        port: 0,
        urlPrefix: '/adk',
      );
      addTearDown(() async {
        await prefixedServer.close(force: true);
        await prefixedRuntime.runner.close();
      });

      final HttpClient prefixedClient = HttpClient();
      addTearDown(() => prefixedClient.close(force: true));

      final HttpClientRequest prefixedRequest = await prefixedClient.getUrl(
        Uri.parse('http://127.0.0.1:${prefixedServer.port}/adk/health'),
      );
      final HttpClientResponse prefixedResponse = await prefixedRequest.close();
      final String prefixedBody = await utf8.decoder
          .bind(prefixedResponse)
          .join();

      final HttpClientRequest bareRequest = await prefixedClient.getUrl(
        Uri.parse('http://127.0.0.1:${prefixedServer.port}/health'),
      );
      final HttpClientResponse bareResponse = await bareRequest.close();
      await utf8.decoder.bind(bareResponse).join();

      expect(prefixedResponse.statusCode, HttpStatus.ok);
      expect(prefixedBody, contains('"status":"ok"'));
      expect(bareResponse.statusCode, HttpStatus.notFound);
    });

    test('applies CORS allow list', () async {
      final DevAgentRuntime corsRuntime = DevAgentRuntime(config: config);
      final HttpServer corsServer = await startAdkDevWebServer(
        runtime: corsRuntime,
        project: config,
        port: 0,
        allowOrigins: const <String>['https://example.com'],
      );
      addTearDown(() async {
        await corsServer.close(force: true);
        await corsRuntime.runner.close();
      });

      final HttpClient corsClient = HttpClient();
      addTearDown(() => corsClient.close(force: true));

      final HttpClientRequest allowedRequest = await corsClient.getUrl(
        Uri.parse('http://127.0.0.1:${corsServer.port}/health'),
      );
      allowedRequest.headers.set('origin', 'https://example.com');
      final HttpClientResponse allowedResponse = await allowedRequest.close();
      await utf8.decoder.bind(allowedResponse).join();

      final HttpClientRequest deniedRequest = await corsClient.getUrl(
        Uri.parse('http://127.0.0.1:${corsServer.port}/health'),
      );
      deniedRequest.headers.set('origin', 'https://denied.example.com');
      final HttpClientResponse deniedResponse = await deniedRequest.close();
      await utf8.decoder.bind(deniedResponse).join();

      expect(
        allowedResponse.headers.value('access-control-allow-origin'),
        'https://example.com',
      );
      expect(
        deniedResponse.headers.value('access-control-allow-origin'),
        isNull,
      );
    });

    test('supports run_live websocket stream', () async {
      final String sessionId =
          's_live_${DateTime.now().microsecondsSinceEpoch}';
      final HttpClientRequest createRequest = await client.postUrl(
        Uri.parse(
          'http://127.0.0.1:${server.port}/apps/test_app/users/u1/sessions',
        ),
      );
      createRequest.headers.contentType = ContentType.json;
      createRequest.write(
        jsonEncode(<String, Object>{'session_id': sessionId}),
      );
      final HttpClientResponse createResponse = await createRequest.close();
      await utf8.decoder.bind(createResponse).join();
      expect(createResponse.statusCode, HttpStatus.ok);

      final WebSocket socket = await WebSocket.connect(
        'ws://127.0.0.1:${server.port}/run_live?app_name=test_app&user_id=u1&session_id=$sessionId',
      );
      addTearDown(() async {
        await socket.close();
      });

      socket.add(
        jsonEncode(<String, Object>{
          'content': <String, Object>{
            'role': 'user',
            'parts': <Object>[
              <String, Object>{'text': 'What time in Seoul?'},
            ],
          },
        }),
      );

      final dynamic firstMessage = await socket.first.timeout(
        const Duration(seconds: 5),
      );
      expect(firstMessage, isA<String>());
      final Map<String, dynamic> payload =
          jsonDecode(firstMessage as String) as Map<String, dynamic>;
      expect(payload['author'], isNotNull);
    });
  });
}

List<Map<String, dynamic>> _decodeSseJsonEvents(String body) {
  final List<Map<String, dynamic>> events = <Map<String, dynamic>>[];
  for (final String line in const LineSplitter().convert(body)) {
    final String trimmed = line.trim();
    if (!trimmed.startsWith('data:')) {
      continue;
    }
    final String payload = trimmed.substring('data:'.length).trim();
    if (payload.isEmpty) {
      continue;
    }
    final Object? decoded = jsonDecode(payload);
    if (decoded is Map<String, dynamic>) {
      events.add(decoded);
      continue;
    }
    if (decoded is Map) {
      events.add(
        decoded.map(
          (Object? key, Object? value) =>
              MapEntry<String, dynamic>('$key', value),
        ),
      );
    }
  }
  return events;
}

class _FactoryLoadedPlugin extends BasePlugin {
  _FactoryLoadedPlugin({required super.name}) {
    instances += 1;
  }

  static int instances = 0;
}
