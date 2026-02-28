import 'dart:async';

import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

class _CaptureRequestModel extends BaseLlm {
  _CaptureRequestModel({required String modelName}) : super(model: modelName);

  LlmRequest? lastRequest;

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    lastRequest = request;
    yield LlmResponse(content: Content.modelText('ok'));
  }
}

class _FakeLiveConnection extends BaseLlmConnection {
  final List<Content> historySent = <Content>[];
  final List<Content> contentsSent = <Content>[];
  final List<RealtimeBlob> realtimeSent = <RealtimeBlob>[];
  final StreamController<LlmResponse> _responses =
      StreamController<LlmResponse>();

  Future<void> Function(Content content)? onSendContent;
  int closeCount = 0;

  @override
  Future<void> sendHistory(List<Content> history) async {
    historySent.addAll(
      history.map((Content content) => content.copyWith()).toList(),
    );
  }

  @override
  Future<void> sendContent(Content content) async {
    contentsSent.add(content.copyWith());
    if (onSendContent != null) {
      await onSendContent!(content);
    }
  }

  @override
  Future<void> sendRealtime(RealtimeBlob blob) async {
    realtimeSent.add(
      RealtimeBlob(mimeType: blob.mimeType, data: List<int>.from(blob.data)),
    );
  }

  @override
  Stream<LlmResponse> receive() => _responses.stream;

  void emit(LlmResponse response) {
    if (!_responses.isClosed) {
      _responses.add(response);
    }
  }

  @override
  Future<void> close() async {
    closeCount += 1;
    if (!_responses.isClosed) {
      await _responses.close();
    }
  }
}

class _NonIdempotentCloseConnection extends _FakeLiveConnection {
  @override
  Future<void> close() async {
    if (closeCount >= 1) {
      throw StateError('close called multiple times');
    }
    await super.close();
  }
}

class _LiveConnectModel extends BaseLlm {
  _LiveConnectModel({required this.connection}) : super(model: 'live-connect');

  final _FakeLiveConnection connection;
  LlmRequest? connectedRequest;

  BaseLlmConnection connect(LlmRequest request) {
    connectedRequest = request.sanitizedForModelCall();
    return connection;
  }

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) {
    throw StateError('generateContent should not be used in live-connect mode');
  }
}

class _PassthroughSessionService extends BaseSessionService {
  @override
  Future<Session> createSession({
    required String appName,
    required String userId,
    Map<String, Object?>? state,
    String? sessionId,
  }) async {
    return Session(
      id: sessionId ?? 's_passthrough',
      appName: appName,
      userId: userId,
      state: state ?? <String, Object?>{},
    );
  }

  @override
  Future<Session?> getSession({
    required String appName,
    required String userId,
    required String sessionId,
    GetSessionConfig? config,
  }) async {
    return null;
  }

  @override
  Future<ListSessionsResponse> listSessions({
    required String appName,
    String? userId,
  }) async {
    return ListSessionsResponse();
  }

  @override
  Future<void> deleteSession({
    required String appName,
    required String userId,
    required String sessionId,
  }) async {}
}

InvocationContext _newInvocationContext({
  required BaseAgent agent,
  required String invocationId,
  BaseArtifactService? artifactService,
  List<Event>? events,
}) {
  return InvocationContext(
    sessionService: _PassthroughSessionService(),
    artifactService: artifactService,
    invocationId: invocationId,
    agent: agent,
    session: Session(
      id: 's_$invocationId',
      appName: 'app',
      userId: 'user',
      events: events,
    ),
  );
}

Map<String, dynamic> _transferEnumSchema(LlmRequest request) {
  final List<ToolDeclaration> declarations =
      request.config.tools ?? const <ToolDeclaration>[];
  for (final ToolDeclaration declaration in declarations) {
    for (final FunctionDeclaration function
        in declaration.functionDeclarations) {
      if (function.name == 'transfer_to_agent') {
        final Map<String, dynamic> parameters = function.parameters;
        final Map<String, dynamic> properties =
            parameters['properties'] as Map<String, dynamic>;
        return properties['agent_name'] as Map<String, dynamic>;
      }
    }
  }
  throw StateError('transfer_to_agent declaration not found.');
}

void main() {
  group('agent transfer processor parity', () {
    test('AutoFlow injects transfer instructions and tool schema', () async {
      final _CaptureRequestModel rootModel = _CaptureRequestModel(
        modelName: 'root-model',
      );
      final _CaptureRequestModel childModel = _CaptureRequestModel(
        modelName: 'child-model',
      );
      final _CaptureRequestModel peerModel = _CaptureRequestModel(
        modelName: 'peer-model',
      );

      final LlmAgent childAgent = LlmAgent(name: 'child', model: childModel);
      final LlmAgent peerAgent = LlmAgent(name: 'peer', model: peerModel);
      final LlmAgent rootAgent = LlmAgent(
        name: 'root',
        model: rootModel,
        subAgents: <BaseAgent>[childAgent, peerAgent],
        disallowTransferToParent: true,
        disallowTransferToPeers: true,
      );
      expect(rootAgent.subAgents, hasLength(2));

      final InvocationContext context = _newInvocationContext(
        agent: childAgent,
        invocationId: 'inv_auto_transfer',
        events: <Event>[
          Event(
            invocationId: 'inv_auto_transfer',
            author: 'user',
            content: Content.userText('route this task'),
          ),
        ],
      );

      final List<Event> events = await AutoFlow().runAsync(context).toList();
      expect(events, isNotEmpty);

      final LlmRequest request = childModel.lastRequest!;
      expect(request.toolsDict.containsKey('transfer_to_agent'), isTrue);

      final String instruction = request.config.systemInstruction ?? '';
      expect(
        instruction,
        contains('You have a list of other agents to transfer to:'),
      );
      expect(instruction, contains('Agent name: root'));
      expect(instruction, contains('Agent name: peer'));

      final Map<String, dynamic> agentNameSchema = _transferEnumSchema(request);
      final List<dynamic> enumValues = agentNameSchema['enum'] as List<dynamic>;
      expect(enumValues, containsAll(<String>['root', 'peer']));
    });

    test('SingleFlow does not inject transfer instructions/tool', () async {
      final _CaptureRequestModel rootModel = _CaptureRequestModel(
        modelName: 'root-model',
      );
      final _CaptureRequestModel childModel = _CaptureRequestModel(
        modelName: 'child-model',
      );
      final _CaptureRequestModel peerModel = _CaptureRequestModel(
        modelName: 'peer-model',
      );

      final LlmAgent childAgent = LlmAgent(name: 'child', model: childModel);
      final LlmAgent peerAgent = LlmAgent(name: 'peer', model: peerModel);
      LlmAgent(
        name: 'root',
        model: rootModel,
        subAgents: <BaseAgent>[childAgent, peerAgent],
        disallowTransferToParent: true,
        disallowTransferToPeers: true,
      );

      final InvocationContext context = _newInvocationContext(
        agent: childAgent,
        invocationId: 'inv_single_transfer',
        events: <Event>[
          Event(
            invocationId: 'inv_single_transfer',
            author: 'user',
            content: Content.userText('route this task'),
          ),
        ],
      );

      final List<Event> events = await SingleFlow().runAsync(context).toList();
      expect(events, isNotEmpty);

      final LlmRequest request = childModel.lastRequest!;
      expect(request.toolsDict.containsKey('transfer_to_agent'), isFalse);
      expect(
        request.config.systemInstruction ?? '',
        isNot(contains('You have a list of other agents to transfer to:')),
      );
    });

    test('getTransferTargets honors parent and peer transfer flags', () {
      final LlmAgent child = LlmAgent(name: 'child', model: 'gemini-2.5-flash');
      final LlmAgent peer = LlmAgent(name: 'peer', model: 'gemini-2.5-flash');
      LlmAgent(
        name: 'root',
        model: 'gemini-2.5-flash',
        subAgents: <BaseAgent>[child, peer],
        disallowTransferToParent: true,
        disallowTransferToPeers: true,
      );

      child.disallowTransferToParent = true;
      child.disallowTransferToPeers = false;
      expect(
        getTransferTargets(child).map((BaseAgent a) => a.name),
        containsAll(<String>['peer']),
      );
      expect(
        getTransferTargets(child).map((BaseAgent a) => a.name),
        isNot(contains('root')),
      );

      child.disallowTransferToParent = false;
      child.disallowTransferToPeers = true;
      expect(
        getTransferTargets(child).map((BaseAgent a) => a.name),
        contains('root'),
      );
      expect(
        getTransferTargets(child).map((BaseAgent a) => a.name),
        isNot(contains('peer')),
      );
    });
  });

  group('live queue and streaming parity', () {
    test(
      'BaseLlmFlow live mode does not execute partial function-call chunks',
      () async {
        int toolCalls = 0;
        final _FakeLiveConnection connection = _FakeLiveConnection();
        connection.onSendContent = (Content _) async {
          connection.emit(
            LlmResponse(
              content: Content(
                role: 'model',
                parts: <Part>[
                  Part.fromFunctionCall(
                    name: 'echo_tool',
                    id: 'call_partial',
                    args: <String, dynamic>{'value': 'hello'},
                  ),
                ],
              ),
              partial: true,
            ),
          );
        };

        final _LiveConnectModel model = _LiveConnectModel(
          connection: connection,
        );
        final LlmAgent agent = LlmAgent(
          name: 'agent',
          model: model,
          tools: <Object>[
            FunctionTool(
              name: 'echo_tool',
              func: ({required String value}) {
                toolCalls += 1;
                return <String, Object?>{'value': value};
              },
            ),
          ],
        );
        final InvocationContext context = _newInvocationContext(
          agent: agent,
          invocationId: 'inv_live_partial_function_call',
        );
        context.liveRequestQueue = LiveRequestQueue()
          ..sendContent(Content.userText('call tool'))
          ..close();

        final List<Event> events = await BaseLlmFlow()
            .runLive(context)
            .toList();

        expect(
          events.where((Event event) => event.getFunctionCalls().isNotEmpty),
          isNotEmpty,
        );
        expect(
          events.expand((Event event) => event.getFunctionResponses()),
          isEmpty,
        );
        expect(toolCalls, 0);
      },
    );

    test(
      'BaseLlmFlow live mode fans out requests and updates resumption handle',
      () async {
        final _FakeLiveConnection connection = _FakeLiveConnection();
        connection.onSendContent = (Content content) async {
          connection.emit(
            LlmResponse(
              customMetadata: <String, dynamic>{
                'live_session_resumption_update': <String, Object?>{
                  'new_handle': 'updated-handle',
                },
              },
            ),
          );
          connection.emit(LlmResponse(content: Content.modelText('live:ok')));
        };

        final _LiveConnectModel model = _LiveConnectModel(
          connection: connection,
        );
        final LlmAgent agent = LlmAgent(name: 'agent', model: model);
        final InvocationContext context = _newInvocationContext(
          agent: agent,
          invocationId: 'inv_live_queue_parity',
          events: <Event>[
            Event(
              invocationId: 'inv_live_queue_parity',
              author: 'user',
              content: Content.userText('history'),
            ),
          ],
        );

        final LiveRequestQueue rootQueue = LiveRequestQueue()
          ..sendContent(Content.userText('live input'))
          ..close();
        final LiveRequestQueue mirroredQueue = LiveRequestQueue();
        context.liveRequestQueue = rootQueue;
        context.activeStreamingTools = <String, ActiveStreamingTool>{
          'tool': ActiveStreamingTool(stream: mirroredQueue),
        };
        context.liveSessionResumptionHandle = 'resume-token';

        final List<Event> events = await BaseLlmFlow()
            .runLive(context)
            .toList();

        expect(connection.historySent, isNotEmpty);
        expect(connection.historySent.first.parts.first.text, 'history');
        expect(connection.contentsSent, hasLength(1));
        expect(connection.contentsSent.first.parts.first.text, 'live input');
        expect(
          events.any(
            (Event event) =>
                event.content?.parts.first.text?.contains('live:ok') == true,
          ),
          isTrue,
        );

        final LiveRequest mirroredContent = await mirroredQueue.get();
        final LiveRequest mirroredClose = await mirroredQueue.get();
        expect(mirroredContent.content?.parts.first.text, 'live input');
        expect(mirroredClose.close, isTrue);

        expect(context.liveSessionResumptionHandle, 'updated-handle');
        expect(model.connectedRequest, isNotNull);
        final Object? sessionResumption =
            model.connectedRequest!.liveConnectConfig.sessionResumption;
        expect(sessionResumption, isA<Map>());
        final Map<dynamic, dynamic> sessionResumptionMap =
            sessionResumption as Map<dynamic, dynamic>;
        expect(sessionResumptionMap['handle'], 'resume-token');
        expect(sessionResumptionMap['transparent'], isTrue);
      },
    );

    test(
      'BaseLlmFlow live mode closes connection once for terminal close',
      () async {
        final _NonIdempotentCloseConnection connection =
            _NonIdempotentCloseConnection();
        final _LiveConnectModel model = _LiveConnectModel(
          connection: connection,
        );
        final LlmAgent agent = LlmAgent(name: 'agent', model: model);
        final InvocationContext context = _newInvocationContext(
          agent: agent,
          invocationId: 'inv_live_close_once',
        );
        context.liveRequestQueue = LiveRequestQueue()
          ..sendContent(Content.userText('close after one turn'))
          ..close();

        await BaseLlmFlow().runLive(context).toList();

        expect(connection.closeCount, 1);
      },
    );
  });

  group('live audio/transcription parity modules', () {
    test('AudioCacheManager caches and flushes input/output audio', () async {
      final LlmAgent agent = LlmAgent(name: 'agent', model: 'gemini-2.5-flash');
      final InvocationContext context = _newInvocationContext(
        agent: agent,
        invocationId: 'inv_audio_cache',
        artifactService: InMemoryArtifactService(),
      );

      final AudioCacheManager manager = AudioCacheManager();
      manager.cacheAudio(
        context,
        InlineData(mimeType: 'audio/wav', data: <int>[1, 2]),
        cacheType: 'input',
      );
      manager.cacheAudio(
        context,
        InlineData(mimeType: 'audio/wav', data: <int>[3]),
        cacheType: 'output',
      );

      expect(manager.getCacheStats(context), containsPair('total_chunks', 2));
      expect(manager.getCacheStats(context), containsPair('total_bytes', 3));

      final List<Event> flushed = await manager.flushCaches(context);
      expect(flushed, hasLength(2));

      final Event inputEvent = flushed.firstWhere(
        (Event event) => event.content?.role == 'user',
      );
      final Event outputEvent = flushed.firstWhere(
        (Event event) => event.content?.role == 'model',
      );

      expect(
        inputEvent.content!.parts.first.fileData!.fileUri,
        contains('/_adk_live/adk_live_audio_storage_input_audio_'),
      );
      expect(outputEvent.author, agent.name);
      expect(context.inputRealtimeCache, isEmpty);
      expect(context.outputRealtimeCache, isEmpty);

      expect(
        () => manager.cacheAudio(
          context,
          InlineData(mimeType: 'audio/wav', data: <int>[9]),
          cacheType: 'invalid',
        ),
        throwsArgumentError,
      );
    });

    test(
      'AudioTranscriber bundles consecutive speaker audio segments',
      () async {
        final LlmAgent agent = LlmAgent(
          name: 'agent',
          model: 'gemini-2.5-flash',
        );
        final InvocationContext context = _newInvocationContext(
          agent: agent,
          invocationId: 'inv_transcriber',
        );

        final List<List<int>> capturedAudio = <List<int>>[];
        final AudioTranscriber transcriber = AudioTranscriber(
          recognizer: (List<int> audioData) async {
            capturedAudio.add(List<int>.from(audioData));
            if (audioData.length == 2) {
              return <String>['hello user'];
            }
            return <String>['follow up'];
          },
        );

        context.transcriptionCache = <Object?>[
          TranscriptionEntry(
            role: 'user',
            data: InlineData(mimeType: 'audio/wav', data: <int>[1]),
          ),
          TranscriptionEntry(
            role: 'user',
            data: InlineData(mimeType: 'audio/wav', data: <int>[2]),
          ),
          TranscriptionEntry(
            role: 'model',
            data: Content.modelText('already text'),
          ),
          TranscriptionEntry(
            role: 'user',
            data: InlineData(mimeType: 'audio/wav', data: <int>[3]),
          ),
        ];

        final List<Content> contents = await transcriber.transcribeFile(
          context,
        );
        expect(capturedAudio, hasLength(2));
        expect(capturedAudio.first, <int>[1, 2]);
        expect(capturedAudio.last, <int>[3]);
        expect(contents.length, 3);
        expect(contents[0].role, 'user');
        expect(contents[0].parts.first.text, 'hello user');
        expect(contents[1].parts.first.text, 'already text');
        expect(contents[2].parts.first.text, 'follow up');
        expect(context.transcriptionCache, isEmpty);

        context.transcriptionCache = <Object?>[
          TranscriptionEntry(
            role: 'user',
            data: InlineData(mimeType: 'audio/wav', data: <int>[4]),
          ),
        ];
        expect(
          () => AudioTranscriber().transcribeFile(context),
          throwsStateError,
        );
      },
    );

    test('TranscriptionManager creates events and reports stats', () async {
      final LlmAgent agent = LlmAgent(name: 'agent', model: 'gemini-2.5-flash');
      final InvocationContext context = _newInvocationContext(
        agent: agent,
        invocationId: 'inv_transcription_manager',
      );

      final TranscriptionManager manager = TranscriptionManager();
      final Event inputEvent = await manager.handleInputTranscription(
        context,
        <String, Object?>{'text': 'hi'},
      );
      final Event outputEvent = await manager.handleOutputTranscription(
        context,
        <String, Object?>{'text': 'hello'},
      );

      expect(inputEvent.author, 'user');
      expect(inputEvent.inputTranscription, isNotNull);
      expect(inputEvent.outputTranscription, isNull);

      expect(outputEvent.author, 'agent');
      expect(outputEvent.inputTranscription, isNull);
      expect(outputEvent.outputTranscription, isNotNull);

      context.session.events.addAll(<Event>[inputEvent, outputEvent]);
      expect(manager.getTranscriptionStats(context), <String, int>{
        'input_transcriptions': 1,
        'output_transcriptions': 1,
        'total_transcriptions': 2,
      });
    });
  });
}
