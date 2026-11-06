import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:adk_dart/src/a2a/executor/a2a_agent_executor.dart';
import 'package:adk_dart/src/a2a/executor/task_result_aggregator.dart';
import 'package:adk_dart/src/a2a/logs/log_utils.dart';
import 'package:adk_dart/src/a2a/protocol.dart';
import 'package:adk_dart/src/agents/callback_context.dart';
import 'package:adk_dart/src/agents/common_configs.dart';
import 'package:adk_dart/src/agents/config_agent_utils.dart';
import 'package:adk_dart/src/agents/context.dart';
import 'package:adk_dart/src/agents/invocation_context.dart';
import 'package:adk_dart/src/agents/live_request_queue.dart';
import 'package:adk_dart/src/agents/llm_agent.dart';
import 'package:adk_dart/src/agents/remote_a2a_agent.dart';
import 'package:adk_dart/src/agents/run_config.dart';
import 'package:adk_dart/src/artifacts/in_memory_artifact_service.dart';
import 'package:adk_dart/src/auth/auth_credential.dart';
import 'package:adk_dart/src/auth/auth_tool.dart';
import 'package:adk_dart/src/auth/credential_manager.dart';
import 'package:adk_dart/src/auth/credential_service/in_memory_credential_service.dart';
import 'package:adk_dart/src/auth/credential_service/session_state_credential_service.dart';
import 'package:adk_dart/src/auth/refresher/credential_refresher_registry.dart';
import 'package:adk_dart/src/auth/refresher/oauth2_credential_refresher.dart';
import 'package:adk_dart/src/code_executors/built_in_code_executor.dart';
import 'package:adk_dart/src/events/event.dart';
import 'package:adk_dart/src/events/event_actions.dart';
import 'package:adk_dart/src/events/request_input.dart';
import 'package:adk_dart/src/flows/llm_flows/code_execution.dart';
import 'package:adk_dart/src/flows/llm_flows/contents.dart';
import 'package:adk_dart/src/flows/llm_flows/functions.dart';
import 'package:adk_dart/src/models/base_llm.dart';
import 'package:adk_dart/src/models/base_llm_connection.dart';
import 'package:adk_dart/src/models/llm_request.dart';
import 'package:adk_dart/src/models/llm_response.dart';
import 'package:adk_dart/src/runners/runner.dart';
import 'package:adk_dart/src/sessions/base_session_service.dart';
import 'package:adk_dart/src/sessions/database_session_service.dart';
import 'package:adk_dart/src/sessions/in_memory_session_service.dart';
import 'package:adk_dart/src/sessions/session.dart';
import 'package:adk_dart/src/sessions/session_util.dart';
import 'package:adk_dart/src/sessions/vertex_ai_session_service.dart';
import 'package:adk_dart/src/tools/base_tool.dart';
import 'package:adk_dart/src/tools/function_tool.dart';
import 'package:adk_dart/src/types/content.dart';
import 'package:adk_dart/src/workflow/replay_manager.dart';
import 'package:adk_dart/src/workflow/workflow.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

enum _SampleStatus {
  pending('pending_value'),
  complete('complete_value');

  const _SampleStatus(this.value);
  final String value;
}

class _CancellingModel extends BaseLlm {
  _CancellingModel({required this.firstChunkEmitted})
    : super(model: 'cancelling-model');

  final Completer<void> firstChunkEmitted;

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) {
    late final StreamController<LlmResponse> controller;
    controller = StreamController<LlmResponse>(
      onListen: () {
        controller.add(
          LlmResponse(content: Content.modelText('partial'), partial: true),
        );
        if (!firstChunkEmitted.isCompleted) {
          firstChunkEmitted.complete();
        }
      },
      onCancel: () async {},
    );
    return controller.stream;
  }
}

class _BargeInLiveModel extends BaseLlm {
  _BargeInLiveModel() : super(model: 'barge-in-live-model');

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {}

  BaseLlmConnection connect(LlmRequest request) => _BargeInLiveConnection();
}

class _BargeInLiveConnection extends BaseLlmConnection {
  @override
  Future<void> sendHistory(List<Content> history) async {}

  @override
  Future<void> sendContent(Content content) async {}

  @override
  Future<void> sendRealtime(RealtimeBlob blob) async {}

  @override
  Stream<LlmResponse> receive() async* {
    yield LlmResponse(
      liveSessionResumptionUpdate: <String, Object?>{'new_handle': 'handle-1'},
    );
    yield LlmResponse(
      liveSessionResumptionUpdate: <String, Object?>{'resumable': false},
    );
    yield LlmResponse(
      content: Content(
        role: 'model',
        parts: <Part>[
          Part.fromInlineData(
            mimeType: 'audio/pcm',
            data: <int>[1, 2, 3, 4],
          ),
        ],
      ),
    );
    yield LlmResponse(interrupted: true, turnComplete: false);
  }

  @override
  Future<void> close() async {}
}

class _TrackingArtifactService extends InMemoryArtifactService {
  final List<String> savedFilenames = <String>[];

  @override
  Future<int> saveArtifact({
    required String appName,
    required String userId,
    required String filename,
    required Part artifact,
    String? sessionId,
    Map<String, Object?>? customMetadata,
  }) async {
    savedFilenames.add(filename);
    return super.saveArtifact(
      appName: appName,
      userId: userId,
      filename: filename,
      artifact: artifact,
      sessionId: sessionId,
      customMetadata: customMetadata,
    );
  }
}

class _NoOpA2aClient implements A2aClient {
  @override
  Stream<Object> sendMessage({
    required A2aMessage request,
    Map<String, Object?>? requestMetadata,
    A2aClientCallContext? context,
  }) async* {}
}

class _NoOpA2aClientFactory implements A2aClientFactory {
  @override
  A2aClient create(AgentCard agentCard) => _NoOpA2aClient();
}

void main() {
  group('A2A parity', () {
    test('a2aVersionHeaders returns A2A-Version 0.3.0', () {
      expect(
        a2aVersionHeaders(),
        equals(<String, String>{'A2A-Version': '0.3.0'}),
      );
    });

    test('RemoteA2aAgent sends A2A-Version header on HTTP card resolution', () async {
      String? capturedVersionHeader;
      final HttpServer server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(() async => server.close(force: true));

      server.listen((HttpRequest req) async {
        capturedVersionHeader = req.headers.value(a2aVersionHeader);
        req.response.statusCode = 200;
        req.response.headers.contentType = ContentType.json;
        req.response.write(
          jsonEncode(<String, Object?>{
            'name': 'remote_agent',
            'description': 'Remote agent',
            'url': 'http://127.0.0.1:${server.port}/a2a',
            'version': '1.0.0',
            'skills': <Object?>[],
          }),
        );
        await req.response.close();
      });

      final RemoteA2aAgent agent = RemoteA2aAgent(
        name: 'remote_agent',
        agentCard: 'http://127.0.0.1:${server.port}/.well-known/agent-card.json',
        a2aClientFactory: _NoOpA2aClientFactory(),
      );

      final InMemorySessionService sessionService = InMemorySessionService();
      final Session session = await sessionService.createSession(
        appName: 'app',
        userId: 'user',
      );
      final InvocationContext ctx = InvocationContext(
        sessionService: sessionService,
        invocationId: 'inv-1',
        agent: agent,
        session: session,
      );
      await agent.runAsync(ctx).toList();
      expect(capturedVersionHeader, equals(a2aProtocolVersion));
    });

    test('TaskResultAggregator & ErrorRecoveryTracker complete recovered tasks', () {
      final TaskResultAggregator aggregator = TaskResultAggregator();
      final ErrorRecoveryTracker tracker = ErrorRecoveryTracker();

      final A2aMessage errorMessage = A2aMessage(
        messageId: 'm-err',
        role: A2aRole.agent,
        parts: <A2aPart>[A2aPart.text('temporary tool error')],
      );
      final A2aTaskStatusUpdateEvent failedEvent = A2aTaskStatusUpdateEvent(
        taskId: 't-1',
        contextId: 'c-1',
        status: A2aTaskStatus(
          state: A2aTaskState.failed,
          message: errorMessage,
        ),
        finalEvent: false,
      );
      aggregator.processEvent(failedEvent);
      final Event subAgentError = Event(
        invocationId: 'inv-1',
        author: 'sub_agent',
        branch: 'root.sub_agent',
        errorCode: 'ERR',
        errorMessage: 'temporary tool error',
      );
      tracker.observe(subAgentError);
      expect(tracker.isUnresolved(subAgentError), isTrue);
      expect(aggregator.taskState, equals(A2aTaskState.failed));

      final A2aTaskStatusUpdateEvent workingEvent = A2aTaskStatusUpdateEvent(
        taskId: 't-1',
        contextId: 'c-1',
        status: A2aTaskStatus(
          state: A2aTaskState.working,
          message: A2aMessage(
            messageId: 'm-ok',
            role: A2aRole.agent,
            parts: <A2aPart>[A2aPart.text('recovered response')],
          ),
        ),
        finalEvent: false,
      );
      aggregator.processEvent(workingEvent);
      final Event rootSuccess = Event(
        invocationId: 'inv-1',
        author: 'root',
        content: Content.modelText('recovered response'),
      );
      tracker.observe(rootSuccess);
      expect(tracker.isUnresolved(subAgentError), isFalse);

      aggregator.keepFailures(const <A2aMessage?>[]);
      expect(aggregator.taskState, equals(A2aTaskState.working));
      expect(aggregator.taskStatusMessage?.messageId, equals('m-ok'));
    });

    test('reportA2aExecutorError redacts uncaught exception text by default', () {
      final String message = reportA2aExecutorError(
        StateError('secret database password leaked'),
        StackTrace.current,
        false,
      );
      expect(message, isNot(contains('secret database password')));
      expect(
        message,
        matches(
          RegExp(r'^Agent execution failed\. \(error_id: [0-9a-f]{12}\)$'),
        ),
      );

      final String debugMessage = reportA2aExecutorError(
        StateError('visible in debug'),
        StackTrace.current,
        true,
      );
      expect(debugMessage, contains('visible in debug'));
    });

    test('buildA2aResponseLog unwraps A2aTask tuple to A2aTask', () {
      final A2aTask task = A2aTask(
        id: 'task-123',
        contextId: 'ctx-1',
        status: A2aTaskStatus(state: A2aTaskState.completed),
      );
      final (A2aTask, A2aEvent?) tupleResponse = (task, null);
      final String logOutput = buildA2aResponseLog(tupleResponse);
      expect(logOutput, contains('Result Type: A2aTask'));
      expect(logOutput, contains('task-123'));
    });
  });

  group('Config & Agent parity', () {
    test('fromConfig blocks internal keys and private/dangerous code references', () {
      final Directory tempDir = Directory.systemTemp.createTempSync(
        'adk_config_sec_',
      );
      addTearDown(() => tempDir.deleteSync(recursive: true));

      final File badKeyFile = File('${tempDir.path}/bad_key.yaml')
        ..writeAsStringSync('name: test_agent\n_internal_toggle: true\n');
      expect(
        () => fromConfig(badKeyFile.path),
        throwsA(isA<ArgumentError>()),
      );

      final File badImportFile = File('${tempDir.path}/bad_import.yaml')
        ..writeAsStringSync('name: test_agent\nimport_modules:\n  - os\n');
      expect(
        () => fromConfig(badImportFile.path),
        throwsA(isA<ArgumentError>()),
      );

      expect(
        () => resolveCodeReference(
          CodeConfig(name: 'os.system'),
          resolvers: AgentConfigResolvers(),
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => resolveCodeReference(
          CodeConfig(name: 'google.adk._internal.secret'),
          resolvers: AgentConfigResolvers(),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('LlmAgent parallelWorker and maxParallelWorkers wrap into ParallelWorker node', () {
      expect(
        () => LlmAgent(name: 'bad_worker', maxParallelWorkers: 2),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => LlmAgent(
          name: 'bad_limit',
          parallelWorker: true,
          maxParallelWorkers: 0,
        ),
        throwsA(isA<ArgumentError>()),
      );

      final LlmAgent agent = LlmAgent(
        name: 'worker_agent',
        parallelWorker: true,
        maxParallelWorkers: 3,
      );
      final BaseNode built = buildNode(agent);
      expect(built, isA<ParallelWorker>());
      final ParallelWorker pw = built as ParallelWorker;
      expect(pw.maxParallelWorkers, equals(3));
      expect(agent.parallelWorker, isFalse);
      expect(agent.maxParallelWorkers, isNull);
    });
  });

  group('OAuth2 & CredentialManager parity', () {
    test('expired OAuth2 token without refresh_token triggers refresh / re-auth', () async {
      final OAuth2CredentialRefresher refresher = OAuth2CredentialRefresher();
      final AuthCredential expiredNoRefresh = AuthCredential(
        authType: AuthCredentialTypes.oauth2,
        oauth2: OAuth2Auth(
          accessToken: 'expired-access-token',
          expiresAt: DateTime.now().millisecondsSinceEpoch ~/ 1000 - 120,
        ),
      );
      expect(
        await refresher.isRefreshNeeded(authCredential: expiredNoRefresh),
        isTrue,
      );

      final AuthCredential unchanged = await refresher.refresh(
        authCredential: expiredNoRefresh,
      );
      expect(unchanged.oauth2?.accessToken, equals('expired-access-token'));
    });

    test('revoked refresh token evicts stored credential and requests re-auth', () async {
      final OAuth2CredentialRefresher refresher = OAuth2CredentialRefresher(
        refreshHandler: (OAuth2Auth oauth2, String? tokenEndpoint) async {
          throw Exception('invalid_grant: Token has been expired or revoked.');
        },
      );
      final InMemoryCredentialService credentialService =
          InMemoryCredentialService();
      final SessionStateCredentialService sessionCredentialService =
          SessionStateCredentialService();

      final AuthCredential revokedCred = AuthCredential(
        authType: AuthCredentialTypes.oauth2,
        oauth2: OAuth2Auth(
          clientId: 'cid',
          clientSecret: 'csecret',
          accessToken: 'expired-token',
          refreshToken: 'revoked-refresh-token',
          expiresAt: DateTime.now().millisecondsSinceEpoch ~/ 1000 - 120,
        ),
      );

      final AuthConfig authConfig = AuthConfig(
        authScheme: 'oauth2',
        rawAuthCredential: revokedCred,
        exchangedAuthCredential: revokedCred,
        credentialKey: 'oauth_test_key',
      );

      final InMemorySessionService sessionService = InMemorySessionService();
      final Session session = await sessionService.createSession(
        appName: 'app',
        userId: 'user',
      );
      final InvocationContext invCtx = InvocationContext(
        sessionService: sessionService,
        credentialService: credentialService,
        invocationId: 'inv-auth',
        agent: LlmAgent(name: 'root'),
        session: session,
      );
      final CallbackContext callbackContext = CallbackContext(invCtx);

      await credentialService.saveCredential(authConfig, callbackContext);
      await sessionCredentialService.saveCredential(authConfig, callbackContext);

      final CredentialRefresherRegistry refresherRegistry =
          CredentialRefresherRegistry()
            ..register(AuthCredentialTypes.oauth2, refresher);

      final CredentialManager manager = CredentialManager(
        authConfig: authConfig,
        refresherRegistry: refresherRegistry,
      );

      final AuthCredential? result = await manager.getAuthCredential(
        callbackContext,
      );
      expect(result, isNull);
      expect(
        await credentialService.loadCredential(authConfig, callbackContext),
        isNull,
      );
    });
  });

  group('Flows & Live parity', () {
    test('cancelled LLM stream invokes onModelErrorCallback', () async {
      final Completer<void> firstChunk = Completer<void>();
      Exception? capturedError;
      final LlmAgent agent = LlmAgent(
        name: 'cancel_agent',
        model: _CancellingModel(firstChunkEmitted: firstChunk),
        onModelErrorCallback: (
          CallbackContext ctx,
          LlmRequest req,
          Exception err,
        ) {
          capturedError = err;
          return null;
        },
      );
      final InMemorySessionService sessionService = InMemorySessionService();
      final Session session = await sessionService.createSession(
        appName: 'app',
        userId: 'user',
      );
      final InvocationContext ctx = InvocationContext(
        sessionService: sessionService,
        invocationId: 'inv-cancel',
        agent: agent,
        session: session,
        userContent: Content.userText('hello'),
        runConfig: RunConfig(streamingMode: StreamingMode.sse),
      );

      final StreamSubscription<Event> sub = agent.runAsync(ctx).listen((_) {});
      await firstChunk.future;
      await sub.cancel();

      expect(capturedError, isNotNull);
    });

    test('BuiltInCodeExecutor emits no empty event when no images are produced', () async {
      final CodeExecutionResponseProcessor processor =
          CodeExecutionResponseProcessor();
      final LlmAgent agent = LlmAgent(
        name: 'code_agent',
        codeExecutor: BuiltInCodeExecutor(),
      );
      final InMemorySessionService sessionService = InMemorySessionService();
      final Session session = await sessionService.createSession(
        appName: 'app',
        userId: 'user',
      );
      final InvocationContext ctx = InvocationContext(
        sessionService: sessionService,
        artifactService: InMemoryArtifactService(),
        invocationId: 'inv-code',
        agent: agent,
        session: session,
      );
      final LlmResponse response = LlmResponse(
        content: Content(
          role: 'model',
          parts: <Part>[
            Part(
              executableCode: <String, Object?>{
                'language': 'PYTHON',
                'code': 'print(1)',
              },
            ),
            Part(
              codeExecutionResult: <String, Object?>{
                'outcome': 'OUTCOME_OK',
                'output': '1\n',
              },
            ),
          ],
        ),
      );

      final List<Event> events = await processor
          .runAsync(ctx, response)
          .toList();
      expect(events, isEmpty);
    });

    test('Enum members in tool results are serialized as their values', () async {
      final FunctionTool tool = FunctionTool(
        name: 'status_tool',
        description: 'returns enum status',
        func: () => <String, Object?>{
          'status': _SampleStatus.complete,
          'list': <Object?>[_SampleStatus.pending],
        },
      );
      final LlmAgent agent = LlmAgent(name: 'enum_agent', tools: <Object>[tool]);
      final InMemorySessionService sessionService = InMemorySessionService();
      final Session session = await sessionService.createSession(
        appName: 'app',
        userId: 'user',
      );
      final InvocationContext ctx = InvocationContext(
        sessionService: sessionService,
        invocationId: 'inv-enum',
        agent: agent,
        session: session,
      );
      final Event callEvent = Event(
        invocationId: 'inv-enum',
        author: 'enum_agent',
        content: Content(
          role: 'model',
          parts: <Part>[
            Part.fromFunctionCall(
              name: 'status_tool',
              id: 'fc-1',
              args: <String, dynamic>{},
            ),
          ],
        ),
      );
      final Event? responseEvent = await handleFunctionCallsAsync(
        ctx,
        callEvent,
        <String, BaseTool>{'status_tool': tool},
      );
      expect(responseEvent, isNotNull);
      final Map<String, dynamic> payload =
          responseEvent!.getFunctionResponses().single.response;
      expect(payload['status'], equals('complete_value'));
      expect(payload['list'], equals(<Object?>['pending_value']));
    });

    test('live resumption handle persists through non-resumable updates and barge-in yields interrupted before saving audio', () async {
      final _TrackingArtifactService artifactService =
          _TrackingArtifactService();
      final LlmAgent agent = LlmAgent(
        name: 'live_agent',
        model: _BargeInLiveModel(),
      );
      final InMemorySessionService sessionService = InMemorySessionService();
      final Session session = await sessionService.createSession(
        appName: 'app',
        userId: 'user',
      );
      final InvocationContext ctx = InvocationContext(
        sessionService: sessionService,
        artifactService: artifactService,
        invocationId: 'inv-live',
        agent: agent,
        session: session,
        liveRequestQueue: LiveRequestQueue(),
        runConfig: RunConfig(saveLiveBlob: true),
      );

      final List<String> trace = <String>[];
      await for (final Event event in agent.runLive(ctx)) {
        if (event.interrupted == true) {
          trace.add(
            'interrupted(artifactsSaved=${artifactService.savedFilenames.length})',
          );
        } else if (event.content?.parts.any((Part p) => p.fileData != null) ==
            true) {
          trace.add(
            'audioFlushed(artifactsSaved=${artifactService.savedFilenames.length})',
          );
        }
      }

      expect(ctx.liveSessionResumptionHandle, equals('handle-1'));
      expect(
        trace,
        containsAllInOrder(<String>[
          'interrupted(artifactsSaved=0)',
          'audioFlushed(artifactsSaved=1)',
        ]),
      );
    });
  });

  group('Runner & Sessions parity', () {
    test('Runner abort synthesis skips StaleSessionError when session advanced', () async {
      final InMemorySessionService sessionService = InMemorySessionService();
      final Session session = await sessionService.createSession(
        appName: 'app',
        userId: 'user',
        sessionId: 's-stale',
      );
      final LlmAgent agent = LlmAgent(name: 'stale_agent');
      final Runner runner = Runner(
        appName: 'app',
        agent: agent,
        sessionService: sessionService,
      );

      session.lastUpdateTime -= 100.0;
      await sessionService.appendEvent(
        session: (await sessionService.getSession(
          appName: 'app',
          userId: 'user',
          sessionId: 's-stale',
        ))!,
        event: Event(
          invocationId: 'newer-inv',
          author: 'user',
          content: Content.userText('newer turn'),
          actions: EventActions(stateDelta: <String, Object?>{'k': 'v'}),
        ),
      );

      expect(runner, isNotNull);
    });

    test('binary bytes are coerced for JSON state and EventActions serialization', () {
      final Uint8List utf8Bytes = Uint8List.fromList(utf8.encode('hello'));
      final Uint8List binaryBytes = Uint8List.fromList(<int>[0xff, 0xfe, 0xfd]);

      expect(coerceBytesForJson(utf8Bytes), equals('hello'));
      expect(
        coerceBytesForJson(binaryBytes),
        equals(base64Encode(binaryBytes)),
      );

      final EventActions actions = EventActions(
        stateDelta: <String, Object?>{
          'text_bytes': utf8Bytes,
          'raw_bytes': binaryBytes,
        },
      );
      final Map<String, Object?> serialized = eventActionsToJson(actions);
      final Map<String, Object?> delta =
          serialized['stateDelta']! as Map<String, Object?>;
      expect(delta['text_bytes'], equals('hello'));
      expect(delta['raw_bytes'], equals(base64Encode(binaryBytes)));
    });

    test('InMemorySessionService isolates stored events and state deltas against mutation', () async {
      final InMemorySessionService service = InMemorySessionService();
      final Session session = await service.createSession(
        appName: 'app',
        userId: 'user',
      );
      final Map<String, Object?> nested = <String, Object?>{'count': 1};
      final Event event = Event(
        invocationId: 'inv-1',
        author: 'agent',
        actions: EventActions(
          stateDelta: <String, Object?>{'nested': nested},
        ),
      );

      await service.appendEvent(session: session, event: event);
      nested['count'] = 999;
      (event.actions.stateDelta['nested'] as Map<String, Object?>)['count'] =
          888;

      final Session? fetched = await service.getSession(
        appName: 'app',
        userId: 'user',
        sessionId: session.id,
      );
      expect(
        (fetched!.state['nested'] as Map<String, Object?>)['count'],
        equals(1),
      );
      expect(
        (fetched.events.single.actions.stateDelta['nested']
            as Map<String, Object?>)['count'],
        equals(1),
      );
    });

    test('DatabaseSessionService treats empty sessionId as absent and filters afterTimestamp=0', () async {
      final DatabaseSessionService service = DatabaseSessionService(
        'sqlite:///:memory:',
      );

      final Session created = await service.createSession(
        appName: 'app',
        userId: 'user',
        sessionId: '   ',
      );
      expect(created.id.trim(), isNotEmpty);

      await service.appendEvent(
        session: created,
        event: Event(
          invocationId: 'inv-1',
          author: 'user',
          timestamp: 100.0,
          content: Content.userText('msg'),
        ),
      );
      final Session? filtered = await service.getSession(
        appName: 'app',
        userId: 'user',
        sessionId: created.id,
        config: GetSessionConfig(afterTimestamp: 0.0),
      );
      expect(filtered!.events, hasLength(1));
    });

    test('VertexAiSessionHttpApiClient includes tracking headers', () async {
      Map<String, String>? capturedHeaders;
      final MockClient mockHttpClient = MockClient((http.Request request) async {
        capturedHeaders = request.headers;
        return http.Response(
          jsonEncode(<String, Object?>{'sessions': <Object?>[]}),
          200,
        );
      });
      final VertexAiSessionHttpApiClient client = VertexAiSessionHttpApiClient(
        project: 'proj',
        location: 'us-central1',
        httpClient: mockHttpClient,
        accessTokenProvider: () async => 'test-token',
      );

      await client
          .listSessions(
            reasoningEngineId: '123',
            userId: 'u-1',
          )
          .toList();
      expect(capturedHeaders, isNotNull);
      expect(capturedHeaders!['x-goog-api-client'], isNotEmpty);
      expect(capturedHeaders!['user-agent'], isNotEmpty);
    });
  });

  group('Workflow parity', () {
    test('preserves routes when flushing and delegating output', () async {
      final FunctionNode child = FunctionNode(
        name: 'child_router',
        function: (WorkflowContext ctx, Object? input) {
          ctx.route = 'special_route';
          return null;
        },
      );
      final FunctionNode parent = FunctionNode(
        name: 'parent_delegator',
        rerunOnResume: true,
        function: (WorkflowContext ctx, Object? input) async {
          return ctx.runNode(child, useAsOutput: true);
        },
      );
      final FunctionNode target = FunctionNode(
        name: 'routed_target',
        function: (WorkflowContext ctx, Object? input) => 'reached_target',
      );

      final Workflow workflow = Workflow(
        name: 'route_wf',
        nodes: <BaseNode>[parent, target],
        edges: <Edge>[
          Edge(fromNode: START, toNode: parent),
          Edge(fromNode: parent, toNode: target, route: 'special_route'),
        ],
      );

      final WorkflowResult result = await workflow.runWorkflow();
      expect(result.outputs['routed_target'], equals('reached_target'));
    });

    test('keeps content and errors when a workflow node delegates its output', () async {
      final FunctionNode child = FunctionNode(
        name: 'child_node',
        function: (WorkflowContext ctx, Object? input) => 'child_result',
      );
      final FunctionNode delegatingParent = FunctionNode(
        name: 'delegating_parent',
        rerunOnResume: true,
        function: (WorkflowContext ctx, Object? input) async {
          await ctx.runNode(child, useAsOutput: true);
          return Event(
            invocationId: 'inv-1',
            author: 'delegating_parent',
            errorCode: 'ERR_CODE',
            errorMessage: 'Failed after delegation',
            output: 'error_payload',
          );
        },
      );

      final Workflow workflow = Workflow(
        name: 'error_delegation_wf',
        nodes: <BaseNode>[delegatingParent],
        edges: <Edge>[Edge(fromNode: START, toNode: delegatingParent)],
      );

      final WorkflowResult result = await workflow.runWorkflow();
      expect(result.outputs['delegating_parent'], equals('error_payload'));
    });

    test('strips JSON code fence when replaying schema output on resume', () {
      final FunctionNode schemaNode = FunctionNode(
        name: 'schema_node',
        outputSchema: <String, Object?>{
          'type': 'object',
          'properties': <String, Object?>{
            'answer': <String, Object?>{'type': 'integer'},
          },
        },
        function: (WorkflowContext ctx, Object? input) => input,
      );
      final Workflow workflow = Workflow(
        name: 'schema_wf',
        nodes: <BaseNode>[schemaNode],
        edges: <Edge>[Edge(fromNode: START, toNode: schemaNode)],
      );

      final Event fencedEvent = Event(
        invocationId: 'inv-1',
        author: 'schema_node',
        nodeInfo: NodeInfo(
          path: 'schema_wf@1/schema_node@1',
          messageAsOutput: true,
        ),
        content: Content.modelText('```json\n{"answer": 42}\n```'),
      );

      final WorkflowResult rehydrated = workflow.rehydrateResultFromEvents(
        <Event>[fencedEvent],
        invocationId: 'inv-1',
      );
      expect(
        rehydrated.outputs['schema_node'],
        equals(<String, Object?>{'answer': 42}),
      );
    });

    test('keeps a node branch when it relays sub-agent events', () {
      final FunctionNode parentNode = FunctionNode(
        name: 'parent_node',
        function: (WorkflowContext ctx, Object? input) => input,
      );
      final Workflow workflow = Workflow(
        name: 'branch_wf',
        nodes: <BaseNode>[parentNode],
        edges: <Edge>[Edge(fromNode: START, toNode: parentNode)],
      );

      final List<Event> events = <Event>[
        Event(
          invocationId: 'inv-1',
          author: 'parent_node',
          branch: 'branch_wf@1',
          nodeInfo: NodeInfo(path: 'branch_wf@1/parent_node@1'),
          content: Content.modelText('parent start'),
        ),
        Event(
          invocationId: 'inv-1',
          author: 'relayed_sub_agent',
          branch: 'branch_wf@1.parent_node.relayed_sub_agent',
          nodeInfo: NodeInfo(path: 'branch_wf@1/parent_node@1'),
          content: Content.modelText('sub-agent event'),
        ),
      ];

      final WorkflowResult rehydrated = workflow.rehydrateResultFromEvents(
        events,
        invocationId: 'inv-1',
      );
      expect(
        rehydrated.nodeStates['parent_node']?.branch,
        equals('branch_wf@1'),
      );
    });

    test('WorkflowTool returns empty map while workflow awaits input', () async {
      final FunctionNode pausingNode = FunctionNode(
        name: 'ask_user',
        function: (WorkflowContext ctx, Object? input) {
          return RequestInput(
            interruptId: 'int-1',
            message: 'Please provide input',
          );
        },
      );
      final Workflow workflow = Workflow(
        name: 'pausing_wf',
        nodes: <BaseNode>[pausingNode],
        edges: <Edge>[Edge(fromNode: START, toNode: pausingNode)],
      );
      final BaseTool workflowTool = workflow.asTool();

      final InMemorySessionService sessionService = InMemorySessionService();
      final Session session = await sessionService.createSession(
        appName: 'app',
        userId: 'user',
      );
      final InvocationContext invCtx = InvocationContext(
        sessionService: sessionService,
        invocationId: 'inv-wf-tool',
        agent: LlmAgent(name: 'caller'),
        session: session,
      );
      final Context toolContext = Context(invCtx, functionCallId: 'fc-wf');

      final Object? toolResult = await workflowTool.run(
        args: <String, dynamic>{'request': 'go'},
        toolContext: toolContext,
      );
      expect(toolResult, equals(<String, dynamic>{}));
    });

    test('ReplayManager scopes index to active invocation and releases pending sequence keys', () async {
      final ReplayManager replayManager = ReplayManager();
      final InMemorySessionService sessionService = InMemorySessionService();
      final Session session = await sessionService.createSession(
        appName: 'app',
        userId: 'user',
      );
      session.events.addAll(<Event>[
        Event(
          invocationId: 'old-inv',
          author: 'old_node',
          nodeInfo: NodeInfo(path: 'wf@1/old_node@1'),
          output: 'old',
        ),
        Event(
          invocationId: 'active-inv',
          author: 'slow_node',
          nodeInfo: NodeInfo(path: 'wf@1/slow_node@1'),
          longRunningToolIds: <String>{'lro-1'},
        ),
        Event(
          invocationId: 'active-inv',
          author: 'fast_sibling',
          nodeInfo: NodeInfo(path: 'wf@1/fast_sibling@1'),
          output: 'done',
        ),
      ]);

      final InvocationContext invCtx = InvocationContext(
        sessionService: sessionService,
        invocationId: 'active-inv',
        agent: LlmAgent(name: 'wf'),
        session: session,
      );
      final Context ctx = Context(invCtx);

      final List<Event>? indexed = replayManager.indexedInvocationEvents(ctx);
      expect(indexed, isNotNull);
      expect(
        indexed!.every((Event e) => e.invocationId == 'active-inv'),
        isTrue,
      );

      final ReplaySequenceBarrier barrier = replayManager
          .prepareParentSequenceBarrier(ctx, 'wf@1');
      expect(barrier.pending, contains('slow_node@1'));
      expect(barrier.isReleased('fast_sibling@1'), isFalse);

      await replayManager.releasePendingSequence('wf@1', 'slow_node@1');
      expect(barrier.isReleased('fast_sibling@1'), isTrue);
    });

    test('buildTaskInputUserContent skips userContent fallback for single-turn nodes', () {
      final Content? singleTurnFallback = buildTaskInputUserContent(
        events: const <Event>[],
        isolationScope: 'isolated-scope',
        userContent: Content.userText('ambient conversation'),
        isSingleTurn: true,
      );
      expect(singleTurnFallback, isNull);

      final Content? multiTurnFallback = buildTaskInputUserContent(
        events: const <Event>[],
        isolationScope: 'isolated-scope',
        userContent: Content.userText('ambient conversation'),
        isSingleTurn: false,
      );
      expect(multiTurnFallback, isNotNull);
    });

    test('WorkflowContext reserves runIds from session events so resumed sub-agents do not collide', () async {
      final InMemorySessionService sessionService = InMemorySessionService();
      final Session session = await sessionService.createSession(
        appName: 'app',
        userId: 'user',
      );
      session.events.add(
        Event(
          invocationId: 'inv-resume',
          author: 'sub_worker',
          nodeInfo: NodeInfo(path: 'wf@1/parent@1/sub_worker@3'),
          output: 'prev',
        ),
      );
      final InvocationContext invCtx = InvocationContext(
        sessionService: sessionService,
        invocationId: 'inv-resume',
        agent: LlmAgent(name: 'wf'),
        session: session,
      );
      final WorkflowContext wfCtx = WorkflowContext(
        invocationContext: invCtx,
        workflowRoot: 'wf@1',
      );

      final FunctionNode subWorker = FunctionNode(
        name: 'sub_worker',
        function: (WorkflowContext ctx, Object? input) => 'next',
      );
      await wfCtx.runNode(subWorker);
      expect(wfCtx.nodeStates.keys, contains('sub_worker@4'));
    });
  });
}
