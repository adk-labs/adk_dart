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

InvocationContext _newInvocationContext({
  required BaseAgent agent,
  required String invocationId,
  BaseArtifactService? artifactService,
  List<Event>? events,
}) {
  return InvocationContext(
    sessionService: InMemorySessionService(),
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
