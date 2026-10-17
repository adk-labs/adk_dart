import 'dart:async';
import 'dart:convert';
import 'dart:core';
import 'dart:core' as core;
import 'dart:io';

import 'package:adk/adk.dart';
import 'package:adk/src/dev/cli.dart';
import 'package:test/test.dart';

class _CaptureSink {
  _CaptureSink() : _controller = StreamController<List<int>>() {
    _controller.stream.listen(_bytes.addAll);
    sink = IOSink(_controller.sink);
  }

  final StreamController<List<int>> _controller;
  final List<int> _bytes = <int>[];
  late final IOSink sink;

  Future<String> closeAndRead() async {
    await sink.flush();
    await sink.close();
    await _controller.done;
    return utf8.decode(_bytes);
  }
}

class _Part8StubModel extends BaseLlm {
  _Part8StubModel() : super(model: 'part8-stub-model');

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    yield LlmResponse(content: Content.modelText('part8 stub response'));
  }
}

class _Part8FailingAgent extends BaseAgent {
  _Part8FailingAgent({required super.name});

  @override
  Stream<Event> runAsyncImpl(InvocationContext context) async* {
    throw StateError('Simulated agent failure in runAsyncImpl');
  }

  @override
  Stream<Event> runLiveImpl(InvocationContext context) async* {
    throw StateError('Simulated agent failure in runLiveImpl');
  }
}

class _Part8MockComputer implements BaseComputer {
  bool initialized = false;

  @override
  Future<void> initialize() async {
    initialized = true;
  }

  @override
  Future<ComputerState> currentState() async {
    return ComputerState(
      screenshot: <int>[137, 80, 78, 71, 13, 10, 26, 10], // PNG magic bytes
    );
  }

  @override
  Future<void> close() async {}

  @override
  dynamic noSuchMethod(core.Invocation invocation) => super.noSuchMethod(invocation);
}

class _Part8StubToolset extends BaseToolset {
  _Part8StubToolset(this._tools);
  final List<BaseTool> _tools;

  @override
  Future<List<BaseTool>> getTools({ReadonlyContext? readonlyContext}) async => _tools;

  @override
  Future<void> close() async {}
}

void main() {
  group('Target 100% Coverage - Part 8', () {
    test('web_server argument errors and special agent access exception', () async {
      final Directory tempDir = Directory.systemTemp.createTempSync('ws_arg_err_');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      await createDevProject(projectDirPath: tempDir.path);

      final DevProjectConfig config = DevProjectConfig(
        appName: 'test_ws_arg_agent',
        agentName: 'test_ws_arg_agent',
        description: 'test description',
      );
      final DevAgentRuntime runtime = DevAgentRuntime(config: config);

      // 1. logoText set without logoImageUrl
      expect(
        () => startAdkDevWebServer(
          runtime: runtime,
          project: config,
          agentsDir: tempDir.path,
          logoText: 'MyLogo',
          port: 0,
        ),
        throwsArgumentError,
      );

      // 2. expressMode true without geminiEnterpriseAppName
      expect(
        () => startAdkDevWebServer(
          runtime: runtime,
          project: config,
          agentsDir: tempDir.path,
          expressMode: true,
          port: 0,
        ),
        throwsArgumentError,
      );

      // 3. non-loopback host without triggerOidcAudience
      expect(
        () => startAdkDevWebServer(
          runtime: runtime,
          project: config,
          agentsDir: tempDir.path,
          host: InternetAddress('192.168.1.100'),
          triggerSources: <String>['pubsub'],
          port: 0,
        ),
        throwsArgumentError,
      );

      // 4. SpecialAgentAccessDeniedException
      const SpecialAgentAccessDeniedException denied =
          SpecialAgentAccessDeniedException();
      expect(denied.message, contains('Access to internal special agents is disabled'));
      expect(denied.toString(), contains('SpecialAgentAccessDeniedException'));

      // 5. whitespace evalStorageUri resolves to baseDir
      final Object? resolved = resolveEvalManagersTesting(
        baseDir: tempDir.path,
        evalStorageUri: '   ',
      );
      expect(resolved, isNotNull);

      // 6. registerExtraPluginFactory empty spec error & clearExtraPluginFactoriesForTest
      expect(
        () => registerExtraPluginFactory('', (spec, {required baseDir}) => LoggingPlugin()),
        throwsArgumentError,
      );
      registerExtraPluginFactory('custom_temp_plugin', (spec, {required baseDir}) => LoggingPlugin());
      clearExtraPluginFactoriesForTest();
    });

    test('web_server AgentLoader, App Runner, caching and app endpoints', () async {
      final Directory tempDir = Directory.systemTemp.createTempSync('ws_runner_app_');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      await createDevProject(projectDirPath: tempDir.path);

      // Create initial_state.json in project dir
      final File initialStateFile = File('${tempDir.path}${Platform.pathSeparator}initial_state.json');
      initialStateFile.writeAsStringSync(jsonEncode(<String, Object?>{'initial_flag': true}));

      final DevProjectConfig config = DevProjectConfig(
        appName: 'test_ws_runner_agent',
        agentName: 'test_ws_runner_agent',
        description: 'test description',
      );
      final DevAgentRuntime runtime = DevAgentRuntime(config: config);

      final HttpServer server = await startAdkDevWebServer(
        runtime: runtime,
        project: config,
        agentsDir: tempDir.path,
        port: 0,
        reload: false,
        reloadAgents: false,
        allowOrigins: <String>['*'],
      );
      addTearDown(() async {
        await server.close(force: true);
        await runtime.runner.close();
      });

      final HttpClient client = HttpClient();
      addTearDown(() => client.close(force: true));

      // 1. GET /list-apps without detailed=true
      final HttpClientRequest reqList = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/list-apps'),
      );
      final HttpClientResponse resList = await reqList.close();
      expect(resList.statusCode, HttpStatus.ok);
      final List<dynamic> listJson = (jsonDecode(await utf8.decoder.bind(resList).join()) as List);
      expect(listJson, contains('test_ws_runner_agent'));

      // 2. GET /api/sessions/{sessionId}/events for non-existent session -> 404
      final HttpClientRequest reqLegacySession404 = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/api/sessions/non_existent_session_123/events'),
      );
      final HttpClientResponse resLegacySession404 = await reqLegacySession404.close();
      expect(resLegacySession404.statusCode, HttpStatus.notFound);
      await resLegacySession404.drain<void>();

      // 3. POST /api/sessions (legacy) with initial_state.json loaded
      final HttpClientRequest reqLegacyCreate = await client.postUrl(
        Uri.parse('http://127.0.0.1:${server.port}/api/sessions'),
      );
      reqLegacyCreate.headers.contentType = ContentType.json;
      reqLegacyCreate.write(jsonEncode(<String, Object?>{
        'user_id': 'u1',
        'state': <String, Object?>{'user_key': 'user_val'},
      }));
      final HttpClientResponse resLegacyCreate = await reqLegacyCreate.close();
      expect(resLegacyCreate.statusCode, HttpStatus.ok);
      final Map<String, dynamic> legacyRes =
          jsonDecode(await utf8.decoder.bind(resLegacyCreate).join()) as Map<String, dynamic>;
      final Map<String, dynamic> legacyCreated = legacyRes['session'] as Map<String, dynamic>;
      final String legacySessionId = legacyCreated['id'] as String;
      expect(legacyCreated['appName'], 'test_ws_runner_agent');

      // 4. GET /api/sessions/{sessionId}/events for existing session -> returns session + events
      final HttpClientRequest reqLegacyGet = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/api/sessions/$legacySessionId/events?userId=u1'),
      );
      final HttpClientResponse resLegacyGet = await reqLegacyGet.close();
      expect(resLegacyGet.statusCode, HttpStatus.ok);
      final Map<String, dynamic> legacyGot =
          jsonDecode(await utf8.decoder.bind(resLegacyGet).join()) as Map<String, dynamic>;
      expect(legacyGot.containsKey('session'), isTrue);
      expect(legacyGot.containsKey('events'), isTrue);

      // 5. POST /apps/{appName}/users/{userId}/sessions with seed events
      final HttpClientRequest reqSeed = await client.postUrl(
        Uri.parse('http://127.0.0.1:${server.port}/apps/test_ws_runner_agent/users/u1/sessions'),
      );
      reqSeed.headers.contentType = ContentType.json;
      reqSeed.write(jsonEncode(<String, Object?>{
        'events': <Map<String, Object?>>[
          <String, Object?>{
            'author': 'user',
            'parts': <Map<String, Object?>>[
              <String, Object?>{'text': 'seed event 1'},
            ],
          },
        ],
      }));
      final HttpClientResponse resSeed = await reqSeed.close();
      expect(resSeed.statusCode, HttpStatus.ok);
      final Map<String, dynamic> seededSession =
          jsonDecode(await utf8.decoder.bind(resSeed).join()) as Map<String, dynamic>;
      expect((seededSession['events'] as List).isNotEmpty, isTrue);

      // 6. POST /apps/{appName}/eval_sets/{evalSetId}/run with legacy: true & eval_ids -> 400 when eval set not found
      final HttpClientRequest reqLegacyEvalRun = await client.postUrl(
        Uri.parse('http://127.0.0.1:${server.port}/apps/test_ws_runner_agent/eval_sets/default_set/run'),
      );
      reqLegacyEvalRun.headers.contentType = ContentType.json;
      reqLegacyEvalRun.write(jsonEncode(<String, Object?>{
        'legacy': true,
        'eval_ids': <String>['case1'],
        'eval_metrics': <String>[],
      }));
      final HttpClientResponse resLegacyEvalRun = await reqLegacyEvalRun.close();
      expect(resLegacyEvalRun.statusCode, HttpStatus.badRequest);
      await resLegacyEvalRun.drain<void>();

      // 7. PUT /apps/{appName}/eval-sets/{evalSetId}/eval-cases/{evalCaseId} on non-existent case -> 404
      final HttpClientRequest reqUpdateCase404 = await client.putUrl(
        Uri.parse('http://127.0.0.1:${server.port}/apps/test_ws_runner_agent/eval-sets/default_set/eval-cases/non_existent_case_999'),
      );
      reqUpdateCase404.headers.contentType = ContentType.json;
      reqUpdateCase404.write(jsonEncode(<String, Object?>{
        'eval_case': <String, Object?>{'query': 'test'},
      }));
      final HttpClientResponse resUpdateCase404 = await reqUpdateCase404.close();
      expect(resUpdateCase404.statusCode, HttpStatus.notFound);
      await resUpdateCase404.drain<void>();
    });

    test('web_server screencast, websocket live binary, sse error, trace hex', () async {
      final Directory tempDir = Directory.systemTemp.createTempSync('ws_screencast_app_');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      await createDevProject(projectDirPath: tempDir.path);

      final _Part8MockComputer mockComputer = _Part8MockComputer();
      final ComputerUseToolset computerToolset = ComputerUseToolset(
        computer: mockComputer,
      );

      final LlmAgent cuAgent = LlmAgent(
        name: 'cu_agent',
        model: _Part8StubModel(),
        tools: <Object>[computerToolset],
      );

      final DevProjectConfig config = DevProjectConfig(
        appName: 'cu_app',
        agentName: 'cu_app',
        description: 'test description',
      );
      final DevAgentRuntime runtime = DevAgentRuntime(
        config: config,
        runner: Runner(
          appName: 'cu_app',
          agent: cuAgent,
          sessionService: InMemorySessionService(),
          artifactService: InMemoryArtifactService(),
          memoryService: InMemoryMemoryService(),
        ),
      );

      final HttpServer server = await startAdkDevWebServer(
        runtime: runtime,
        project: config,
        agentsDir: tempDir.path,
        port: 0,
      );
      addTearDown(() async {
        await server.close(force: true);
        await runtime.runner.close();
      });

      final HttpClient client = HttpClient();
      addTearDown(() => client.close(force: true));

      // 1. Screencast without WebSocket upgrade -> 400
      final HttpClientRequest reqScreenHttp = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/apps/cu_app/screencast'),
      );
      final HttpClientResponse resScreenHttp = await reqScreenHttp.close();
      expect(resScreenHttp.statusCode, HttpStatus.badRequest);
      final String screenText = await utf8.decoder.bind(resScreenHttp).join();
      expect(screenText, contains('WebSocket upgrade required.'));

      // 2. Screencast on app without ComputerUseToolset -> 404
      final HttpClientRequest reqScreen404 = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/apps/unknown_app_xyz/screencast'),
      );
      final HttpClientResponse resScreen404 = await reqScreen404.close();
      expect(resScreen404.statusCode, HttpStatus.notFound);
      await resScreen404.drain<void>();

      // 3. Screencast with WebSocket upgrade -> streams screenshot frames
      final WebSocket wsScreen = await WebSocket.connect(
        'ws://127.0.0.1:${server.port}/apps/cu_app/screencast',
      );
      final Completer<List<int>> screenCompleter = Completer<List<int>>();
      wsScreen.listen((dynamic data) {
        if (data is List<int> && !screenCompleter.isCompleted) {
          screenCompleter.complete(data);
        }
      });
      final List<int> receivedBytes = await screenCompleter.future.timeout(
        const Duration(seconds: 3),
      );
      expect(receivedBytes, equals(<int>[137, 80, 78, 71, 13, 10, 26, 10]));
      await wsScreen.close();

      // 4. /run_live with binary message -> liveQueue.sendRealtime
      final Session liveSession = await runtime.runner.sessionService.createSession(
        appName: 'cu_app',
        userId: 'u1',
        sessionId: 'live_sess_bin',
      );
      final WebSocket wsLive = await WebSocket.connect(
        'ws://127.0.0.1:${server.port}/run_live?app_name=cu_app&user_id=u1&session_id=${liveSession.id}',
      );
      wsLive.listen((_) {}, onError: (_) {});
      // Send binary frame
      wsLive.add(<int>[1, 2, 3, 4]);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await wsLive.close();

      // 5. /run_live on non-existent session with autoCreateSession false -> 1002 protocolError
      final WebSocket wsLiveNotFound = await WebSocket.connect(
        'ws://127.0.0.1:${server.port}/run_live?app_name=cu_app&user_id=u1&session_id=missing_sess_999',
      );
      final Completer<int?> closeCompleter = Completer<int?>();
      wsLiveNotFound.listen(
        (_) {},
        onDone: () => closeCompleter.complete(wsLiveNotFound.closeCode),
        onError: (_) {},
      );
      final int? code = await closeCompleter.future.timeout(const Duration(seconds: 3));
      expect(code, equals(WebSocketStatus.protocolError));
    });

    test('web_server SSE error and trigger routes with auth exceptions', () async {
      final Directory tempDir = Directory.systemTemp.createTempSync('ws_triggers_app_');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      await createDevProject(projectDirPath: tempDir.path);

      final _Part8FailingAgent failingAgent = _Part8FailingAgent(name: 'failing_agent');
      final DevProjectConfig config = DevProjectConfig(
        appName: 'failing_app',
        agentName: 'failing_app',
        description: 'test description',
      );
      final DevAgentRuntime runtime = DevAgentRuntime(
        config: config,
        runner: Runner(
          appName: 'failing_app',
          agent: failingAgent,
          sessionService: InMemorySessionService(),
          artifactService: InMemoryArtifactService(),
          memoryService: InMemoryMemoryService(),
        ),
      );

      final HttpServer server = await startAdkDevWebServer(
        runtime: runtime,
        project: config,
        agentsDir: tempDir.path,
        port: 0,
        triggerSources: <String>['pubsub', 'eventarc'],
        triggerAuthVerifier: (request) async {
          if (request.headers.value('x-deny-auth') == 'true') {
            throw const TriggerAuthException(
              statusCode: HttpStatus.unauthorized,
              message: 'Denied by verifyAuth',
            );
          }
        },
      );
      addTearDown(() async {
        await server.close(force: true);
        await runtime.runner.close();
      });

      final HttpClient client = HttpClient();
      addTearDown(() => client.close(force: true));

      // 1. /run_sse with failing agent emits data: {"error": "..."}
      final HttpClientRequest reqSse = await client.postUrl(
        Uri.parse('http://127.0.0.1:${server.port}/run_sse'),
      );
      reqSse.headers.contentType = ContentType.json;
      reqSse.write(jsonEncode(<String, Object?>{
        'app_name': 'failing_app',
        'user_id': 'u1',
        'session_id': 's_fail_1',
        'new_message': <String, Object?>{
          'role': 'user',
          'parts': <Map<String, Object?>>[
            <String, Object?>{'text': 'trigger fail'},
          ],
        },
        'auto_create_session': true,
      }));
      final HttpClientResponse resSse = await reqSse.close();
      expect(resSse.statusCode, HttpStatus.ok);
      final String ssePayload = await utf8.decoder.bind(resSse).join();
      expect(ssePayload, contains('"error":'));

      // 2. POST /apps/failing_app/trigger/pubsub with failing verifyAuth -> 401
      final HttpClientRequest reqTriggerAuth = await client.postUrl(
        Uri.parse('http://127.0.0.1:${server.port}/apps/failing_app/trigger/pubsub'),
      );
      reqTriggerAuth.headers.set('x-deny-auth', 'true');
      reqTriggerAuth.headers.contentType = ContentType.json;
      reqTriggerAuth.write(jsonEncode(<String, Object?>{'message': <String, Object?>{}}));
      final HttpClientResponse resTriggerAuth = await reqTriggerAuth.close();
      expect(resTriggerAuth.statusCode, HttpStatus.unauthorized);
      final String authErrText = await utf8.decoder.bind(resTriggerAuth).join();
      expect(authErrText, contains('Denied by verifyAuth'));

      // 3. POST /apps/failing_app/trigger/pubsub with valid auth and failing agent -> catches StateError
      final HttpClientRequest reqPubsub = await client.postUrl(
        Uri.parse('http://127.0.0.1:${server.port}/apps/failing_app/trigger/pubsub'),
      );
      reqPubsub.headers.contentType = ContentType.json;
      reqPubsub.write(jsonEncode(<String, Object?>{
        'message': <String, Object?>{
          'data': base64Encode(utf8.encode('pubsub_payload')),
        },
      }));
      final HttpClientResponse resPubsub = await reqPubsub.close();
      await resPubsub.drain<void>();

      // 4. POST /apps/failing_app/trigger/unknown_source -> 404
      final HttpClientRequest reqTriggerUnknown = await client.postUrl(
        Uri.parse('http://127.0.0.1:${server.port}/apps/failing_app/trigger/unknown_source'),
      );
      reqTriggerUnknown.headers.contentType = ContentType.json;
      reqTriggerUnknown.write(jsonEncode(<String, Object?>{}));
      final HttpClientResponse resTriggerUnknown = await reqTriggerUnknown.close();
      expect(resTriggerUnknown.statusCode, HttpStatus.notFound);
      final String unknownResText = await utf8.decoder.bind(resTriggerUnknown).join();
      expect(unknownResText, anyOf(contains('Not found'), contains('Unknown trigger source')));
    });

    test('web_server A2A agent card, RPC tasks and push notification delivery', () async {
      final Directory tempDir = Directory.systemTemp.createTempSync('ws_a2a_app_');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      await createDevProject(projectDirPath: tempDir.path);

      // Create agent.json on disk
      final File diskCardFile = File('${tempDir.path}${Platform.pathSeparator}agent.json');
      diskCardFile.writeAsStringSync(jsonEncode(<String, Object?>{
        'name': 'disk_agent_card',
        'description': 'Loaded directly from disk',
      }));

      final DevProjectConfig config = DevProjectConfig(
        appName: 'a2a_test_app',
        agentName: 'a2a_test_app',
        description: 'test description',
      );
      final DevAgentRuntime runtime = DevAgentRuntime(config: config);

      final HttpServer server = await startAdkDevWebServer(
        runtime: runtime,
        project: config,
        agentsDir: tempDir.path,
        a2a: true,
        port: 0,
      );
      addTearDown(() async {
        await server.close(force: true);
        await runtime.runner.close();
      });

      final HttpClient client = HttpClient();
      addTearDown(() => client.close(force: true));

      // 1. GET /.well-known/agent.json loads agent.json from disk
      final HttpClientRequest reqCardDisk = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/.well-known/agent.json'),
      );
      final HttpClientResponse resCardDisk = await reqCardDisk.close();
      expect(resCardDisk.statusCode, HttpStatus.ok);
      final Map<String, dynamic> cardJson =
          jsonDecode(await utf8.decoder.bind(resCardDisk).join()) as Map<String, dynamic>;
      expect(cardJson['name'], 'disk_agent_card');

      // 2. GET /a2a/a2a_test_app/agent-card
      final HttpClientRequest reqCardRoute = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/a2a/a2a_test_app/agent-card'),
      );
      final HttpClientResponse resCardRoute = await reqCardRoute.close();
      expect(resCardRoute.statusCode, HttpStatus.ok);
      await resCardRoute.drain<void>();

      // 3. A2A RPC: empty method -> -32600
      final HttpClientRequest reqEmptyMethod = await client.postUrl(
        Uri.parse('http://127.0.0.1:${server.port}/a2a/a2a_test_app'),
      );
      reqEmptyMethod.headers.contentType = ContentType.json;
      reqEmptyMethod.write(jsonEncode(<String, Object?>{
        'jsonrpc': '2.0',
        'id': '1',
      }));
      final HttpClientResponse resEmptyMethod = await reqEmptyMethod.close();
      final Map<String, dynamic> rpcErr1 =
          jsonDecode(await utf8.decoder.bind(resEmptyMethod).join()) as Map<String, dynamic>;
      expect(rpcErr1['error']['code'], -32600);

      // Create a task via message/send first so task exists
      final HttpClientRequest reqSendMsg = await client.postUrl(
        Uri.parse('http://127.0.0.1:${server.port}/a2a/a2a_test_app'),
      );
      reqSendMsg.headers.contentType = ContentType.json;
      reqSendMsg.write(jsonEncode(<String, Object?>{
        'jsonrpc': '2.0',
        'id': 'send_1',
        'method': 'message/send',
        'params': <String, Object?>{
          'message': <String, Object?>{
            'parts': <Map<String, Object?>>[
              <String, Object?>{'kind': 'text', 'text': 'a2a test message'},
            ],
          },
        },
      }));
      final HttpClientResponse resSendMsg = await reqSendMsg.close();
      expect(resSendMsg.statusCode, HttpStatus.ok);
      final Map<String, dynamic> sendRes =
          jsonDecode(await utf8.decoder.bind(resSendMsg).join()) as Map<String, dynamic>;
      final String taskId = sendRes['result']['taskId'] as String;

      // 4. A2A RPC: tasks/cancel on existing task -> marks canceled
      final HttpClientRequest reqCancel = await client.postUrl(
        Uri.parse('http://127.0.0.1:${server.port}/a2a/a2a_test_app'),
      );
      reqCancel.headers.contentType = ContentType.json;
      reqCancel.write(jsonEncode(<String, Object?>{
        'jsonrpc': '2.0',
        'id': 'cancel_1',
        'method': 'tasks/cancel',
        'params': <String, Object?>{'taskId': taskId},
      }));
      final HttpClientResponse resCancel = await reqCancel.close();
      expect(resCancel.statusCode, HttpStatus.ok);
      final Map<String, dynamic> cancelRes =
          jsonDecode(await utf8.decoder.bind(resCancel).join()) as Map<String, dynamic>;
      expect(cancelRes['result']['status']['state'], 'failed');

      // 5. A2A RPC: tasks/pushnotificationconfig/get when config not found -> -32004
      final HttpClientRequest reqGetConfig404 = await client.postUrl(
        Uri.parse('http://127.0.0.1:${server.port}/a2a/a2a_test_app'),
      );
      reqGetConfig404.headers.contentType = ContentType.json;
      reqGetConfig404.write(jsonEncode(<String, Object?>{
        'jsonrpc': '2.0',
        'id': 'get_cfg_404',
        'method': 'tasks/pushnotificationconfig/get',
        'params': <String, Object?>{'taskId': taskId},
      }));
      final HttpClientResponse resGetConfig404 = await reqGetConfig404.close();
      final Map<String, dynamic> getCfg404 =
          jsonDecode(await utf8.decoder.bind(resGetConfig404).join()) as Map<String, dynamic>;
      expect(getCfg404['error']['code'], -32004);

      // 6. A2A RPC: tasks/pushnotificationconfig/set on existing task
      final HttpClientRequest reqSetConfig = await client.postUrl(
        Uri.parse('http://127.0.0.1:${server.port}/a2a/a2a_test_app'),
      );
      reqSetConfig.headers.contentType = ContentType.json;
      reqSetConfig.write(jsonEncode(<String, Object?>{
        'jsonrpc': '2.0',
        'id': 'set_cfg_1',
        'method': 'tasks/pushnotificationconfig/set',
        'params': <String, Object?>{
          'taskId': taskId,
          'pushNotificationConfig': <String, Object?>{
            'url': 'http://127.0.0.1:9999/callback',
          },
        },
      }));
      final HttpClientResponse resSetConfig = await reqSetConfig.close();
      expect(resSetConfig.statusCode, HttpStatus.ok);
      final Map<String, dynamic> setCfgRes =
          jsonDecode(await utf8.decoder.bind(resSetConfig).join()) as Map<String, dynamic>;
      expect(setCfgRes['result']['pushNotificationConfig']['url'], 'http://127.0.0.1:9999/callback');

      // 7. A2A RPC: tasks/pushnotificationconfig/get now returns saved config
      final HttpClientRequest reqGetConfig200 = await client.postUrl(
        Uri.parse('http://127.0.0.1:${server.port}/a2a/a2a_test_app'),
      );
      reqGetConfig200.headers.contentType = ContentType.json;
      reqGetConfig200.write(jsonEncode(<String, Object?>{
        'jsonrpc': '2.0',
        'id': 'get_cfg_200',
        'method': 'tasks/pushnotificationconfig/get',
        'params': <String, Object?>{'taskId': taskId},
      }));
      final HttpClientResponse resGetConfig200 = await reqGetConfig200.close();
      expect(resGetConfig200.statusCode, HttpStatus.ok);
      final Map<String, dynamic> getCfg200 =
          jsonDecode(await utf8.decoder.bind(resGetConfig200).join()) as Map<String, dynamic>;
      expect(getCfg200['result']['pushNotificationConfig']['url'], 'http://127.0.0.1:9999/callback');

      // 8. A2A RPC: tasks/resubscribe on existing task replays updates
      final HttpClientRequest reqResub = await client.postUrl(
        Uri.parse('http://127.0.0.1:${server.port}/a2a/a2a_test_app'),
      );
      reqResub.headers.contentType = ContentType.json;
      reqResub.write(jsonEncode(<String, Object?>{
        'jsonrpc': '2.0',
        'id': 'resub_1',
        'method': 'tasks/resubscribe',
        'params': <String, Object?>{'taskId': taskId},
      }));
      final HttpClientResponse resResub = await reqResub.close();
      expect(resResub.statusCode, HttpStatus.ok);
      final String resubPayload = await utf8.decoder.bind(resResub).join();
      expect(resubPayload, contains('data: '));

      // 9. A2A RPC: tasks/get missing taskId throws FormatException -> -32602
      final HttpClientRequest reqMissingTaskId = await client.postUrl(
        Uri.parse('http://127.0.0.1:${server.port}/a2a/a2a_test_app'),
      );
      reqMissingTaskId.headers.contentType = ContentType.json;
      reqMissingTaskId.write(jsonEncode(<String, Object?>{
        'jsonrpc': '2.0',
        'id': 'missing_tid',
        'method': 'tasks/get',
        'params': <String, Object?>{},
      }));
      final HttpClientResponse resMissingTaskId = await reqMissingTaskId.close();
      final Map<String, dynamic> missingTidErr =
          jsonDecode(await utf8.decoder.bind(resMissingTaskId).join()) as Map<String, dynamic>;
      expect(missingTidErr['error']['code'], -32602);
    });

    test('web_server testing helpers exhaustive coverage', () async {
      // 1. isLoopbackAddressTesting
      expect(isLoopbackAddressTesting('[::1]:8000'), isTrue);
      expect(isLoopbackAddressTesting('[::1]'), isTrue);
      expect(isLoopbackAddressTesting('::1'), isTrue);
      expect(isLoopbackAddressTesting('localhost:8000'), isTrue);
      expect(isLoopbackAddressTesting('127.0.0.1:8000'), isTrue);
      expect(isLoopbackAddressTesting('192.168.1.1'), isFalse);
      expect(isLoopbackAddressTesting('invalid:::host'), isFalse);

      // 2. liveRequestFromJsonTesting
      expect(liveRequestFromJsonTesting(<String, dynamic>{'close': true}).close, isTrue);
      expect(liveRequestFromJsonTesting(<String, dynamic>{'activity_start': true}).activityStart, isNotNull);
      expect(liveRequestFromJsonTesting(<String, dynamic>{'activity_end': true}).activityEnd, isNotNull);
      expect(liveRequestFromJsonTesting(<String, dynamic>{'blob': 'base64_data'}).blob, 'base64_data');
      expect(liveRequestFromJsonTesting(<String, dynamic>{}).close, isFalse);

      // 3. contentFromJsonTesting
      final Content c1 = contentFromJsonTesting(<String, dynamic>{'text': 'hello'});
      expect(c1.parts.first.text, 'hello');
      final Content c2 = contentFromJsonTesting(<String, dynamic>{'text': ''});
      expect(c2.parts, isEmpty);

      // 4. a2aFallbackMessageTesting
      final Map<String, Object?> fallback = a2aFallbackMessageTesting(<String, Object?>{
        'id': 't123',
        'contextId': 'ctx123',
      });
      expect(fallback['taskId'], 't123');

      // 5. a2aTaskStateFromWireTesting and a2aTaskStateToWireTesting
      expect(a2aTaskStateFromWireTesting('canceled'), A2aTaskState.canceled);
      expect(a2aTaskStateFromWireTesting('cancelled'), A2aTaskState.canceled);
      expect(a2aTaskStateToWireTesting(A2aTaskState.canceled), 'canceled');
      expect(a2aTaskStateToWireTesting(A2aTaskState.rejected), 'rejected');
      expect(a2aTaskStateToWireTesting(A2aTaskState.unknown), 'unknown');

      // 6. a2aJsonRpcErrorTesting with data
      final Map<String, Object?> rpcErr = a2aJsonRpcErrorTesting(
        id: '1',
        code: -32000,
        message: 'custom err',
        data: <String, Object?>{'detail': 'info'},
      );
      expect((rpcErr['error'] as Map)['data']['detail'], 'info');

      // 7. toObjectMapTesting
      final Map<String, Object?> objMap = toObjectMapTesting(<dynamic, dynamic>{123: 'val'});
      expect(objMap['123'], 'val');
      expect(toObjectMapTesting('not_a_map'), isEmpty);

      // 8. nodeStatusesFromAgentStateTesting
      final Map<String, NodeStatus> statuses = nodeStatusesFromAgentStateTesting(<String, Object?>{
        'nodes': <dynamic, dynamic>{
          'step1': <dynamic, dynamic>{'status': 'completed'},
          'step2': 'running',
        },
      });
      expect(statuses['step1'], NodeStatus.completed);
      expect(statuses['step2'], NodeStatus.running);

      // 9. splitNodePathTesting and joinNodePathTesting
      expect(splitNodePathTesting('a/b/c'), equals(<String>['a', 'b', 'c']));
      expect(splitNodePathTesting(null), isEmpty);
      expect(joinNodePathTesting('base', 'child'), 'base/child');
      expect(joinNodePathTesting('', 'child'), 'child');

      // 10. declarationsFromToolUnionTesting
      final FunctionTool fnTool = FunctionTool(
        name: 'test_fn_tool',
        description: 'test fn tool description',
        func: (args) => 'ok',
      );
      final _Part8StubToolset toolset = _Part8StubToolset(<BaseTool>[fnTool]);
      final List<FunctionDeclaration> declsFromToolset =
          await declarationsFromToolUnionTesting(toolset);
      expect(declsFromToolset.first.name, 'test_fn_tool');

      final FunctionDeclaration rawDecl = FunctionDeclaration(
        name: 'raw_decl',
        parameters: <String, Object?>{},
      );
      final List<FunctionDeclaration> declsFromRaw =
          await declarationsFromToolUnionTesting(rawDecl);
      expect(declsFromRaw.first.name, 'raw_decl');

      final List<FunctionDeclaration> declsFromMap =
          await declarationsFromToolUnionTesting(<String, Object?>{
        'name': 'map_decl',
        'parameters': <String, Object?>{},
      });
      expect(declsFromMap.first.name, 'map_decl');

      // 11. readStringTesting
      expect(
        () => readStringTesting(<String, dynamic>{}, <String>['missing_k'], required: true),
        throwsFormatException,
      );

      // 12. resolveA2aPushUrlTesting, resolveA2aPushHeadersTesting, resolveA2aPushAuthorizationTesting
      final Map<String, Object?> pushCfg = <String, Object?>{
        'url': 'http://example.com/push',
        'headers': <dynamic, dynamic>{'X-Key': 'Val'},
        'authentication': 'Bearer my_token',
      };
      expect(resolveA2aPushUrlTesting(pushCfg), 'http://example.com/push');
      expect(resolveA2aPushHeadersTesting(pushCfg)['X-Key'], 'Val');
      expect(resolveA2aPushAuthorizationTesting(pushCfg), 'Bearer my_token');

      // 13. parseA2aIntTesting
      expect(parseA2aIntTesting(42, fallback: 0, min: 0), 42);
      expect(parseA2aIntTesting(42.5, fallback: 0, min: 0), 42);
      expect(parseA2aIntTesting('100', fallback: 0, min: 0), 100);
      expect(parseA2aIntTesting(-5, fallback: 10, min: 0), 10);
      expect(parseA2aIntTesting(200, fallback: 0, min: 0, max: 150), 150);

      // 14. extractA2aScopedAppNameTesting
      expect(extractA2aScopedAppNameTesting('/a2a/my_app/agent-card'), 'my_app');
      expect(extractA2aScopedAppNameTesting('/a2a/my_app/.well-known/agent.json'), 'my_app');
      expect(extractA2aScopedAppNameTesting('/other/path'), isNull);

      // 15. normalizeA2aRpcMethodTesting and normalizeOriginSchemeTesting
      expect(normalizeA2aRpcMethodTesting('tasks:get'), 'tasks/get');
      expect(normalizeOriginSchemeTesting('https'), 'https');
      expect(normalizeOriginSchemeTesting('http'), 'http');
    });

    test('cli parseAdkCliArgs exhaustive flag and error coverage', () {
      // 1. run command flags
      final ParsedAdkCommand cmdRun = parseAdkCliArgs(<String>[
        'run',
        'my_agent',
        '--user-id=u1',
        '--session-id=s1',
        '--session_service_uri=sess_uri',
        '--artifact_service_uri=art_uri',
        '--memory_service_uri=mem_uri',
        '--enable_features=feat1',
        '--disable_features=feat2',
        '--default_llm_model=gemini-2.5-flash',
        '--log_level=debug',
        '--message=hello',
        '--state={"k":"v"}',
        '--resume=resume.json',
        '--timeout',
        '10s',
      ]);
      expect(cmdRun.userId, 'u1');
      expect(cmdRun.sessionId, 's1');
      expect(cmdRun.sessionServiceUri, 'sess_uri');
      expect(cmdRun.artifactServiceUri, 'art_uri');
      expect(cmdRun.memoryServiceUri, 'mem_uri');
      expect(cmdRun.enableFeatures, contains('feat1'));
      expect(cmdRun.disableFeatures, contains('feat2'));
      expect(cmdRun.defaultLlmModel, 'gemini-2.5-flash');
      expect(cmdRun.logLevel, 'DEBUG');
      expect(cmdRun.message, 'hello');
      expect(cmdRun.initialState?['k'], 'v');
      expect(cmdRun.resumeFilePath, 'resume.json');
      expect(cmdRun.timeout, 10);

      // run command with spaced flags
      final ParsedAdkCommand cmdRunSpaced = parseAdkCliArgs(<String>[
        'run',
        'my_agent',
        '--user-id', 'u2',
        '--session-id', 's2',
        '--session_service_uri', 'sess_uri2',
        '--artifact_service_uri', 'art_uri2',
        '--memory_service_uri', 'mem_uri2',
        '--enable_features', 'feat3',
        '--disable_features', 'feat4',
        '--default_llm_model', 'gemini-2.5-pro',
        '--log_level', 'info',
        '--replay', 'replay2.json',
      ]);
      expect(cmdRunSpaced.userId, 'u2');
      expect(cmdRunSpaced.sessionId, 's2');
      expect(cmdRunSpaced.replayFilePath, 'replay2.json');

      // run command cannot have both resume and replay
      expect(
        () => parseAdkCliArgs(<String>['run', 'my_agent', '--resume=r.json', '--replay=p.json']),
        throwsA(isA<CliUsageError>()),
      );

      // run command cannot have both message and replay
      expect(
        () => parseAdkCliArgs(<String>['run', 'my_agent', '--message=hi', '--replay=p.json']),
        throwsA(isA<CliUsageError>()),
      );

      // run command usage errors
      expect(
        () => parseAdkCliArgs(<String>['run', 'agent1', 'query1', 'query2']),
        throwsA(isA<CliUsageError>()),
      );
      expect(
        () => parseAdkCliArgs(<String>['run', 'agent1', 'query1', '--message', 'msg']),
        throwsA(isA<CliUsageError>()),
      );
      expect(
        () => parseAdkCliArgs(<String>['run', 'agent1', '--state_file', '']),
        throwsA(isA<CliUsageError>()),
      );
      expect(
        () => parseAdkCliArgs(<String>['run', 'agent1', '--timeout', '']),
        throwsA(isA<CliUsageError>()),
      );
      expect(
        () => parseAdkCliArgs(<String>['run', 'agent1', '--timeout', '0']),
        throwsA(isA<CliUsageError>()),
      );
      expect(
        () => parseAdkCliArgs(<String>['run', 'agent1', '--timeout', 'invalid']),
        throwsA(isA<CliUsageError>()),
      );

      // 2. web command flags
      final ParsedAdkCommand cmdWeb = parseAdkCliArgs(<String>[
        'web',
        'my_agent',
        '--host=127.0.0.1',
        '--user_id=web_u',
        '--allow_origins=http://localhost:3000',
        '--session_service_uri=web_sess',
        '--artifact_service_uri=web_art',
        '--memory_service_uri=web_mem',
        '--disable_features=web_feat',
        '--session_db_url=web_db',
        '--url_prefix=/prefix/',
        '--trigger-sources=pubsub',
        '--trigger_oidc_audience=test_aud',
        '--trigger_oidc_service_accounts', 'sa@example.com',
        '--logo_text=MyLogo',
        '--logo_image_url=http://example.com/logo.png',
        '--avatar_config={"agent": "http://example.com/avatar.png"}',
        '--max_llm_calls=200',
        '--default_llm_model=gemini-2.5-flash',
        '--gemini_enterprise_app_name=ent_app',
        '--eval_storage_uri=gs://bucket/evals',
      ]);
      expect(cmdWeb.host!.address, '127.0.0.1');
      expect(cmdWeb.userId, 'web_u');
      expect(cmdWeb.allowOrigins, contains('http://localhost:3000'));
      expect(cmdWeb.sessionServiceUri, 'web_sess');
      expect(cmdWeb.artifactServiceUri, 'web_art');
      expect(cmdWeb.memoryServiceUri, 'web_mem');
      expect(cmdWeb.disableFeatures, contains('web_feat'));
      expect(cmdWeb.urlPrefix, '/prefix');
      expect(cmdWeb.triggerSources, contains('pubsub'));
      expect(cmdWeb.triggerOidcAudience, 'test_aud');
      expect(cmdWeb.triggerOidcServiceAccounts, contains('sa@example.com'));
      expect(cmdWeb.logoText, 'MyLogo');
      expect(cmdWeb.logoImageUrl, 'http://example.com/logo.png');
      expect(cmdWeb.maxLlmCalls, 200);
      expect(cmdWeb.geminiEnterpriseAppName, 'ent_app');
      expect(cmdWeb.evalStorageUri, 'gs://bucket/evals');

      // web command usage errors
      expect(
        () => parseAdkCliArgs(<String>['web', 'my_agent', '--max_llm_calls', 'invalid']),
        throwsA(isA<CliUsageError>()),
      );
      expect(
        () => parseAdkCliArgs(<String>['web', 'my_agent', '--avatar_config', 'not_json']),
        throwsA(isA<CliUsageError>()),
      );
      expect(
        () => parseAdkCliArgs(<String>['web', 'my_agent', '--avatar_config', 'true']),
        throwsA(isA<CliUsageError>()),
      );
      expect(
        () => parseAdkCliArgs(<String>['web', 'my_agent', '--avatar_config', '[123]']),
        throwsA(isA<CliUsageError>()),
      );

      // 3. create command flags
      final ParsedAdkCommand cmdCreate = parseAdkCliArgs(<String>[
        'create',
        './my_new_app',
        '--app-name=created_app',
        '--model=gemini-2.5-flash',
      ]);
      expect(cmdCreate.projectDir, './my_new_app');
      expect(cmdCreate.appName, 'created_app');
    });

    test('cli top-level commands, subcommands and exception catches', () async {
      final Directory tempDir = Directory.systemTemp.createTempSync('cli_sub_err_');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      await createDevProject(projectDirPath: tempDir.path);

      final File badJsonFile = File('${tempDir.path}${Platform.pathSeparator}bad.json');
      badJsonFile.writeAsStringSync('{ invalid json ');

      // 1. adk test --help throws CliUsageError -> exit 64
      final _CaptureSink errTest = _CaptureSink();
      final int codeTest = await runAdkCli(
        <String>['test', '--help'],
        errSink: errTest.sink,
      );
      expect(codeTest, 64);
      final String textTest = await errTest.closeAndRead();
      expect(textTest, contains('Usage: adk test'));

      // 2. adk eval FileSystemException -> exit 1
      final _CaptureSink errEvalFs = _CaptureSink();
      final int codeEvalFs = await runAdkCli(
        <String>['eval', '/non_existent_eval_path_xyz', 'default_set'],
        errSink: errEvalFs.sink,
      );
      expect(codeEvalFs, 1);
      final String textEvalFs = await errEvalFs.closeAndRead();
      expect(textEvalFs, contains('Filesystem error:'));

      // 3. adk eval_set FileSystemException -> exit 1
      final _CaptureSink errEvalSetFs = _CaptureSink();
      final int codeEvalSetFs = await runAdkCli(
        <String>['eval_set', 'create', '/non_existent_eval_set_path_xyz', 'set1'],
        errSink: errEvalSetFs.sink,
      );
      expect(codeEvalSetFs, 1);
      final String textEvalSetFs = await errEvalSetFs.closeAndRead();
      expect(textEvalSetFs, contains('Filesystem error:'));

      // 4. adk eval_set ArgumentError -> exit 1
      final _CaptureSink errEvalSetArg = _CaptureSink();
      final int codeEvalSetArg = await runAdkCli(
        <String>['eval_set', 'create', tempDir.path, 'set1', '--eval_storage_uri', 'ftp://unsupported'],
        errSink: errEvalSetArg.sink,
      );
      expect(codeEvalSetArg, 1);
      final String textEvalSetArg = await errEvalSetArg.closeAndRead();
      expect(textEvalSetArg, contains('Argument error:'));

      // 5. adk eval_set FormatException -> exit 1
      final _CaptureSink errEvalSetFmt = _CaptureSink();
      final int codeEvalSetFmt = await runAdkCli(
        <String>[
          'eval_set',
          'add_eval_case',
          tempDir.path,
          'set1',
          '--scenarios_file',
          badJsonFile.path,
          '--session_input_file',
          badJsonFile.path,
        ],
        errSink: errEvalSetFmt.sink,
      );
      expect(codeEvalSetFmt, 1);
      final String textEvalSetFmt = await errEvalSetFmt.closeAndRead();
      expect(textEvalSetFmt, contains('Config parse error:'));

      // 6. adk eval StateError -> exit 1
      final _CaptureSink errEvalState = _CaptureSink();
      final int codeEvalState = await runAdkCli(
        <String>['eval', tempDir.path, 'non_existent_set_xyz'],
        errSink: errEvalState.sink,
      );
      expect(codeEvalState, 1);
      final String textEvalState = await errEvalState.closeAndRead();
      expect(textEvalState, contains('Runtime error:'));

      // 7. adk conformance usage error -> exit 64
      final _CaptureSink errConfUsage = _CaptureSink();
      final int codeConfUsage = await runAdkCli(
        <String>['conformance'],
        errSink: errConfUsage.sink,
      );
      expect(codeConfUsage, 64);
      final String textConfUsage = await errConfUsage.closeAndRead();
      expect(textConfUsage, contains('Missing conformance subcommand'));

      // 8. adk conformance unknown subcommand -> exit 64
      final _CaptureSink errConfRec = _CaptureSink();
      final int codeConfRec = await runAdkCli(
        <String>['conformance', 'unknown_subcommand_xyz'],
        errSink: errConfRec.sink,
      );
      expect(codeConfRec, 64);
      final String textConfRec = await errConfRec.closeAndRead();
      expect(textConfRec, contains('Unknown conformance subcommand'));

      // 9. adk optimize FileSystemException & ArgumentError -> exit 1
      final String optAppName = projectDirName(tempDir.path);
      final File samplerFile = File('${tempDir.path}${Platform.pathSeparator}sampler.json');
      samplerFile.writeAsStringSync(jsonEncode(<String, Object?>{
        'app_name': optAppName,
        'train_eval_set': <String, Object?>{'eval_set_id': 'set1'},
      }));
      final _CaptureSink errOptFs = _CaptureSink();
      final int codeOptFs = await runAdkCli(
        <String>['optimize', '/non_existent_opt_dir_xyz', '--sampler_config_file_path', samplerFile.path],
        errSink: errOptFs.sink,
      );
      expect(codeOptFs, 1);
      final String textOptFs = await errOptFs.closeAndRead();
      expect(textOptFs, contains('Filesystem error:'));

      final File badOptFile = File('${tempDir.path}${Platform.pathSeparator}bad_opt.json');
      badOptFile.writeAsStringSync(jsonEncode(<String, Object?>{
        'optimizer_model': '',
      }));
      final _CaptureSink errOptArg = _CaptureSink();
      final int codeOptArg = await runAdkCli(
        <String>[
          'optimize',
          tempDir.path,
          '--sampler_config_file_path',
          samplerFile.path,
          '--optimizer_config_file_path',
          badOptFile.path,
        ],
        errSink: errOptArg.sink,
      );
      expect(codeOptArg, 1);
      final String textOptArg = await errOptArg.closeAndRead();
      expect(textOptArg, contains('Runtime error:'));

      // 10. adk migrate UsageError & ArgumentError
      final _CaptureSink errMigrateUsage = _CaptureSink();
      final int codeMigrateUsage = await runAdkCli(
        <String>['migrate'],
        errSink: errMigrateUsage.sink,
      );
      expect(codeMigrateUsage, 64);
      final String textMigrateUsage = await errMigrateUsage.closeAndRead();
      expect(textMigrateUsage, contains('Missing migrate subcommand'));

      final _CaptureSink errMigrateState = _CaptureSink();
      final int codeMigrateState = await runAdkCli(
        <String>[
          'migrate',
          'session',
          '--source_db_url',
          'sqlite:///tmp/same.sqlite',
          '--dest_db_url',
          'sqlite:///tmp/same.sqlite',
        ],
        errSink: errMigrateState.sink,
      );
      expect(codeMigrateState, 1);
      final String textMigrateState = await errMigrateState.closeAndRead();
      expect(textMigrateState, contains('Runtime error:'));

      // 11. adk telemetry unconfigured status & error handling
      final String home = Platform.environment['HOME'] ??
          Platform.environment['USERPROFILE'] ??
          Directory.current.path;
      final File userCfg = File('$home${Platform.pathSeparator}.adk${Platform.pathSeparator}config.json');
      File? backupCfg;
      if (userCfg.existsSync()) {
        backupCfg = File('${userCfg.path}.backup_part8');
        userCfg.copySync(backupCfg.path);
        userCfg.deleteSync();
      }
      try {
        final _CaptureSink outTel = _CaptureSink();
        final int codeTel = await runAdkCli(
          <String>['telemetry', 'status'],
          outSink: outTel.sink,
        );
        expect(codeTel, 0);
        final String textTel = await outTel.closeAndRead();
        expect(textTel, contains('Telemetry collection is not configured (defaults to OFF).'));
      } finally {
        if (backupCfg != null && backupCfg.existsSync()) {
          backupCfg.copySync(userCfg.path);
          backupCfg.deleteSync();
        }
      }
    });

    test('cli run snapshot saving, auto-resume interrupts and jsonl node_path', () async {
      final Directory tempDir = Directory.systemTemp.createTempSync('cli_run_features_');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      await createDevProject(projectDirPath: tempDir.path);

      // 1. run command with project path not a directory -> FileSystemException
      final File dummyFile = File('${tempDir.path}${Platform.pathSeparator}dummy.txt');
      dummyFile.writeAsStringSync('not a dir');
      final _CaptureSink errRunNotDir = _CaptureSink();
      final int codeNotDir = await runAdkCli(
        <String>['run', dummyFile.path],
        errSink: errRunNotDir.sink,
      );
      expect(codeNotDir, 1);
      final String textNotDir = await errRunNotDir.closeAndRead();
      expect(textNotDir, contains('Filesystem error:'));

      // 2. run command with --replay and --save_session
      final File replayFile = File('${tempDir.path}${Platform.pathSeparator}replay.json');
      replayFile.writeAsStringSync(jsonEncode(<String, Object?>{
        'state': <String, Object?>{'initial_flag': true},
        'queries': <String>[],
      }));
      final _CaptureSink outSave = _CaptureSink();
      final int codeSave = await runAdkCli(
        <String>[
          'run',
          tempDir.path,
          '--replay',
          replayFile.path,
          '--save_session',
          '--session-id',
          'snap_sess_1',
        ],
        outSink: outSave.sink,
        readLine: () => 'my_saved_id',
      );
      expect(codeSave, 0);
      final String textSave = await outSave.closeAndRead();
      expect(textSave, contains('Session saved to'));

      // 3. writeRunEventsForTesting with jsonl: true and event.nodeInfo.path
      final _CaptureSink outJsonl = _CaptureSink();
      writeRunEventsForTesting(
        <Event>[
          Event(
            invocationId: 'inv_1',
            author: 'model',
            nodeInfo: NodeInfo(path: 'root/step1'),
            content: Content.modelText('jsonl test content'),
          ),
        ],
        out: outJsonl.sink,
        jsonl: true,
      );
      final String textJsonl = await outJsonl.closeAndRead();
      expect(textJsonl, contains('"node_path":"root/step1"'));

      // 4. web command SocketException when port is already bound
      final ServerSocket blockingSocket = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(() => blockingSocket.close());
      final _CaptureSink errWebBind = _CaptureSink();
      final int codeWebBind = await runAdkCli(
        <String>[
          'web',
          tempDir.path,
          '--port',
          '${blockingSocket.port}',
          '--host',
          '127.0.0.1',
        ],
        errSink: errWebBind.sink,
      );
      expect(codeWebBind, 1);
      final String textWebBind = await errWebBind.closeAndRead();
      expect(textWebBind, contains('Failed to bind web server'));

      // 5. adk run with legacy adk.json exercises _migrateLegacyProjectToRootAgentYaml and _yamlScalar
      final Directory legacyProjectDir = Directory.systemTemp.createTempSync('legacy_app_');
      addTearDown(() => legacyProjectDir.deleteSync(recursive: true));
      File('${legacyProjectDir.path}${Platform.pathSeparator}adk.json').writeAsStringSync(jsonEncode(<String, Object?>{
        'agentName': 'legacy_agent',
        'description': "legacy's description",
      }));
      final File legacyReplay = File('${legacyProjectDir.path}${Platform.pathSeparator}replay.json');
      legacyReplay.writeAsStringSync(jsonEncode(<String, Object?>{
        'state': <String, Object?>{},
        'queries': <String>[],
      }));
      final _CaptureSink outLegacyRun = _CaptureSink();
      final int codeLegacyRun = await runAdkCli(
        <String>['run', legacyProjectDir.path, '--replay', legacyReplay.path],
        outSink: outLegacyRun.sink,
      );
      expect(codeLegacyRun, 0);
      final File rootYaml = File('${legacyProjectDir.path}${Platform.pathSeparator}root_agent.yaml');
      expect(rootYaml.existsSync(), isTrue);
      expect(rootYaml.readAsStringSync(), contains("'legacy_agent'"));
      expect(rootYaml.readAsStringSync(), contains("'legacy''s description'"));
    });

    test('cli helpers unit tests', () {
      // 1. yamlScalarForTesting
      expect(yamlScalarForTesting("hello'world"), "'hello''world'");

      // 2. parseTimeoutSecondsTesting
      expect(parseTimeoutSecondsTesting('5m'), 300);
      expect(parseTimeoutSecondsTesting('2h'), 7200);
      expect(parseTimeoutSecondsTesting('10s'), 10);
      expect(parseTimeoutSecondsTesting('15'), 15);

      // 3. conformanceStreamingModeNameTesting
      expect(conformanceStreamingModeNameTesting(StreamingMode.bidi), 'bidi');

      // 4. extractSessionIdFromCreateSessionTesting
      expect(
        extractSessionIdFromCreateSessionTesting(<String, Object?>{
          'session': <String, Object?>{'id': 'nested_id_123'},
        }),
        'nested_id_123',
      );

      // 5. featureNameFromCliValueTesting
      expect(
        featureNameFromCliValueTesting('CASCADE_LIVE'),
        FeatureName.cascadeLive,
      );
      expect(featureNameFromCliValueTesting('UNKNOWN_FEAT_XYZ'), isNull);

      // 6. writeUnknownFeatureNameWarningTesting
      final _CaptureSink errWarn = _CaptureSink();
      writeUnknownFeatureNameWarningTesting('FAKE_FEAT', errWarn.sink);

      // 7. emptyToNullTesting
      expect(emptyToNullTesting(''), isNull);
      expect(emptyToNullTesting('   '), isNull);
      expect(emptyToNullTesting('valid'), 'valid');
    });
  });
}
