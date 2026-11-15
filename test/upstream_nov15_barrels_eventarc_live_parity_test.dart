import 'dart:async';
import 'dart:typed_data';

import 'package:adk_dart/adk_core.dart' as adk_core;
import 'package:adk_dart/adk_dart.dart' as adk;
import 'package:adk_dart/integrations.dart' as integrations;
import 'package:adk_dart/live.dart' as live;
import 'package:adk_dart/src/labs/openai.dart' as labs_openai;
import 'package:adk_dart/tools.dart' as tools;
import 'package:test/test.dart';

class _DummyPayload {
  const _DummyPayload({required this.userId, required this.action});

  final String userId;
  final String action;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'user_id': userId,
    'action': action,
  };
}

class _HttpStatusError implements Exception {
  _HttpStatusError(this.code, this.message);
  final int code;
  final String message;

  @override
  String toString() => 'HttpStatusError($code: $message)';
}

Uint8List _buildWavBytes({
  required List<int> pcmPayload,
  int sampleRate = 24000,
  int channels = 1,
  int bitsPerSample = 16,
  bool includeJunkChunk = false,
}) {
  final BytesBuilder builder = BytesBuilder();

  void writeAscii(String s) => builder.add(s.codeUnits);
  void writeUint16Le(int v) => builder.add(<int>[v & 0xFF, (v >> 8) & 0xFF]);
  void writeUint32Le(int v) => builder.add(<int>[
    v & 0xFF,
    (v >> 8) & 0xFF,
    (v >> 16) & 0xFF,
    (v >> 24) & 0xFF,
  ]);

  final int junkBytesLen = includeJunkChunk ? (8 + 4) : 0;
  final int riffSize = 4 + junkBytesLen + (8 + 16) + (8 + pcmPayload.length);

  writeAscii('RIFF');
  writeUint32Le(riffSize);
  writeAscii('WAVE');

  if (includeJunkChunk) {
    writeAscii('JUNK');
    writeUint32Le(4);
    builder.add(const <int>[0, 0, 0, 0]);
  }

  final int byteRate = sampleRate * channels * (bitsPerSample ~/ 8);
  final int blockAlign = channels * (bitsPerSample ~/ 8);
  writeAscii('fmt ');
  writeUint32Le(16);
  writeUint16Le(1); // PCM format
  writeUint16Le(channels);
  writeUint32Le(sampleRate);
  writeUint32Le(byteRate);
  writeUint16Le(blockAlign);
  writeUint16Le(bitsPerSample);

  writeAscii('data');
  writeUint32Le(pcmPayload.length);
  builder.add(pcmPayload);

  return builder.toBytes();
}

class _ScriptedLiveConnection extends adk.BaseLlmConnection {
  _ScriptedLiveConnection({this.onRealtime});

  final void Function(
    _ScriptedLiveConnection conn,
    adk.RealtimeBlob blob,
  )?
  onRealtime;

  final StreamController<adk.LlmResponse> _responses =
      StreamController<adk.LlmResponse>.broadcast();
  final List<adk.RealtimeBlob> sentBlobs = <adk.RealtimeBlob>[];
  bool activityStarted = false;
  bool activityEnded = false;
  bool closed = false;

  void emit(adk.LlmResponse response) {
    if (!_responses.isClosed) {
      _responses.add(response);
    }
  }

  void emitError(Object error, [StackTrace? stackTrace]) {
    if (!_responses.isClosed) {
      _responses.addError(error, stackTrace);
    }
  }

  @override
  Stream<adk.LlmResponse> receive() => _responses.stream;

  @override
  Future<void> sendHistory(List<adk.Content> history) async {}

  @override
  Future<void> sendContent(adk.Content content) async {}

  @override
  Future<void> sendActivityStart() async {
    activityStarted = true;
  }

  @override
  Future<void> sendActivityEnd() async {
    activityEnded = true;
  }

  @override
  Future<void> sendRealtime(adk.RealtimeBlob blob) async {
    sentBlobs.add(
      adk.RealtimeBlob(
        mimeType: blob.mimeType,
        data: List<int>.from(blob.data),
      ),
    );
    onRealtime?.call(this, blob);
  }

  @override
  Future<void> close() async {
    closed = true;
    if (!_responses.isClosed) {
      await _responses.close();
    }
  }
}

class _ScriptedSttLlm extends adk.BaseLlm {
  _ScriptedSttLlm({required this.connectionFactory})
    : super(model: 'gemini-3.5-transcribe-live');

  final FutureOr<_ScriptedLiveConnection> Function(
    int attempt,
    adk.LlmRequest request,
  )
  connectionFactory;

  final List<_ScriptedLiveConnection> sessions = <_ScriptedLiveConnection>[];
  final List<adk.LlmRequest> connectRequests = <adk.LlmRequest>[];
  int connectAttempts = 0;

  @override
  Stream<adk.LlmResponse> generateContent(
    adk.LlmRequest request, {
    bool stream = false,
  }) async* {}

  Future<adk.BaseLlmConnection> connect(adk.LlmRequest request) async {
    final int attempt = connectAttempts++;
    connectRequests.add(request);
    final _ScriptedLiveConnection session = await connectionFactory(
      attempt,
      request,
    );
    sessions.add(session);
    return session;
  }
}

class _ControlledTtsLlm extends adk.BaseLlm {
  _ControlledTtsLlm() : super(model: 'gemini-3.8-flash-lite-tts');

  final List<String> requestedTexts = <String>[];
  final List<String> cancelledOrClosedTexts = <String>[];
  final Map<String, Completer<void>> held = <String, Completer<void>>{};
  final Map<String, List<Object>> errorsBeforeAudio = <String, List<Object>>{};
  final Map<String, Object> errorsAfterAudio = <String, Object>{};
  final Map<String, adk.InlineData> customAudioByText =
      <String, adk.InlineData>{};
  final Set<String> silentTexts = <String>{};

  @override
  Stream<adk.LlmResponse> generateContent(
    adk.LlmRequest request, {
    bool stream = false,
  }) {
    final String prompt = request.contents.first.parts.first.text ?? '';
    requestedTexts.add(prompt);

    late final StreamController<adk.LlmResponse> controller;
    bool streamCancelled = false;

    controller = StreamController<adk.LlmResponse>(
      onCancel: () {
        streamCancelled = true;
        if (!cancelledOrClosedTexts.contains(prompt)) {
          cancelledOrClosedTexts.add(prompt);
        }
      },
    );

    Future<void> run() async {
      try {
        final List<Object>? pendingErrors = errorsBeforeAudio[prompt];
        if (pendingErrors != null && pendingErrors.isNotEmpty) {
          final Object err = pendingErrors.removeAt(0);
          controller.addError(err);
          return;
        }

        final Completer<void>? hold = held[prompt];
        if (hold != null && !hold.isCompleted) {
          await hold.future;
        }
        if (streamCancelled || controller.isClosed) {
          return;
        }

        if (!silentTexts.contains(prompt)) {
          final adk.InlineData blob =
              customAudioByText[prompt] ??
              adk.InlineData(
                mimeType: 'audio/l16; rate=24000; channels=1',
                data: prompt.codeUnits,
              );
          controller.add(
            adk.LlmResponse(
              content: adk.Content(
                role: 'model',
                parts: <adk.Part>[adk.Part(inlineData: blob)],
              ),
            ),
          );
        }

        await Future<void>.delayed(Duration.zero);
        if (streamCancelled || controller.isClosed) {
          return;
        }

        final Object? afterError = errorsAfterAudio[prompt];
        if (afterError != null) {
          controller.addError(afterError);
          return;
        }
      } finally {
        if (!cancelledOrClosedTexts.contains(prompt)) {
          cancelledOrClosedTexts.add(prompt);
        }
        if (!controller.isClosed) {
          await controller.close();
        }
      }
    }

    unawaited(run());
    return controller.stream;
  }
}

adk.Context _makeToolContext() {
  final adk.LlmAgent agent = adk.LlmAgent(
    name: 'eventarc_agent',
    model: 'gemini-2.5-flash',
    instruction: 'Publish events.',
  );
  return adk.Context(
    adk.InvocationContext(
      invocationId: 'inv-123',
      agent: agent,
      session: adk.Session(
        id: 'session-456',
        appName: 'eventarc-app',
        userId: 'user-1',
      ),
      sessionService: adk.InMemorySessionService(),
    ),
  );
}

void main() {
  group('1. Barrel Exports & Canonical OpenAILlm Parity', () {
    test('package:adk_dart/live.dart exposes full live pipeline surface', () {
      final live.LiveRequestQueue queue = live.LiveRequestQueue();
      queue.sendContent(adk.Content.userText('ping'));
      expect(queue, isA<live.LiveRequestQueue>());

      const live.IngressEvent speechStarted = live.UserSpeechStarted();
      const live.IngressEvent partial = live.PartialTranscript(text: 'hi');
      const live.IngressEvent finished = live.UserTurnFinished(text: 'hi there');
      expect(speechStarted, isA<live.UserSpeechStarted>());
      expect(partial.text, 'hi');
      expect(finished.text, 'hi there');

      final live.EgressEvent chunk = live.AudioChunk(
        blob: adk.InlineData(mimeType: 'audio/pcm;rate=24000', data: <int>[1, 2]),
      );
      const live.EgressEvent spoken = live.AgentSpokenOutput(text: 'hello');
      expect(chunk, isA<live.AudioChunk>());
      expect(spoken, isA<live.AgentSpokenOutput>());

      final live.GeminiSTT stt = live.GeminiSTT();
      final live.GeminiTTS tts = live.GeminiTTS();
      expect(stt, isA<live.LiveIngress>());
      expect(tts, isA<live.LiveEgress>());

      final live.CascadeLive cascade = live.CascadeLive(
        model: 'gemini-2.5-flash',
        stt: stt,
        tts: tts,
      );
      expect(cascade, isA<live.CascadeLive>());
    });

    test('package:adk_dart/adk_core.dart exports RetryConfig and live surface without collisions', () {
      const adk_core.RetryConfig retry = adk_core.RetryConfig(
        maxAttempts: 4,
        initialDelay: Duration(milliseconds: 50),
      );
      expect(retry.maxAttempts, 4);

      final adk_core.GeminiSTT stt = adk_core.GeminiSTT();
      final adk_core.GeminiTTS tts = adk_core.GeminiTTS();
      final adk_core.CascadeLive cascade = adk_core.CascadeLive(
        model: 'gemini-2.5-flash',
        stt: stt,
        tts: tts,
      );
      expect(cascade, isA<adk_core.CascadeLive>());
    });

    test('package:adk_dart/integrations.dart exports ApiRegistry, CloudRun, CrewaiTool, and LangchainTool', () {
      final integrations.ApiRegistry registry = integrations.ApiRegistry(
        apiRegistryProjectId: 'proj-123',
      );
      expect(registry.apiRegistryProjectId, 'proj-123');

      final integrations.CloudRunSandboxCodeExecutor cloudRun =
          integrations.CloudRunSandboxCodeExecutor(
            sandboxBin: '/custom/bin/sandbox',
            allowEgress: true,
          );
      expect(cloudRun.sandboxBin, '/custom/bin/sandbox');
      expect(cloudRun.allowEgress, isTrue);

      final integrations.CrewaiTool crewTool = integrations.CrewaiTool(
        toolRunner: ({required String query}) => query,
        mandatoryArgs: <String>['query'],
        name: 'crew_search',
        description: 'Search via CrewAI',
      );
      expect(crewTool.name, 'crew_search');

      final integrations.LangchainTool lcTool = integrations.LangchainTool(
        toolRunner: ({required String input}) => input,
        name: 'lc_search',
        description: 'Search via LangChain',
      );
      expect(lcTool.name, 'lc_search');
    });

    test('ExecutionResult is exported in tools.dart and adk_dart.dart, and OpenAILlm is unified across barrels', () {
      const tools.ExecutionResult toolsRes = tools.ExecutionResult(
        exitCode: 0,
        stdout: 'ok',
      );
      const adk.ExecutionResult adkRes = adk.ExecutionResult(
        exitCode: 0,
        stdout: 'ok',
      );
      expect(toolsRes.stdout, 'ok');
      expect(adkRes, isA<adk.EnvironmentExecutionResult>());

      expect(identical(adk.OpenAILlm, integrations.OpenAILlm), isTrue);
      expect(identical(adk.OpenAILlm, labs_openai.OpenAILlm), isTrue);

      final adk.OpenAILlm canonicalLlm = adk.OpenAILlm(
        model: 'openai/gpt-4o',
        maxTokens: 2048,
        apiKey: 'sk-test',
      );
      expect(canonicalLlm.maxTokens, 2048);
      final Map<String, Object?> payload = canonicalLlm.buildRequestPayload(
        adk.LlmRequest(contents: <adk.Content>[adk.Content.userText('hi')]),
      );
      expect(payload['model'], 'gpt-4o');
      expect(payload['max_tokens'], 2048);
    });
  });

  group('2. Eventarc Domain-Specific Publishing Parity', () {
    test('validates mandatory bus, type, source, id, specversion, and custom attribute keys', () {
      final integrations.EventarcToolset toolset =
          integrations.EventarcToolset();

      expect(
        () => integrations.buildDomainSpecificTool(
          toolset: toolset,
          name: 'bad_bus_missing',
          description: 'desc',
          bus: integrations.MISSING,
          ceAttributesBinding: const integrations.CloudEventAttributesBinding(
            type: 'com.example.event',
            source: '//app',
          ),
        ),
        throwsArgumentError,
      );

      expect(
        () => integrations.buildDomainSpecificTool(
          toolset: toolset,
          name: 'bad_bus_omit',
          description: 'desc',
          bus: integrations.OMIT,
          ceAttributesBinding: const integrations.CloudEventAttributesBinding(
            type: 'com.example.event',
            source: '//app',
          ),
        ),
        throwsArgumentError,
      );

      expect(
        () => integrations.buildDomainSpecificTool(
          toolset: toolset,
          name: 'bad_type_omit',
          description: 'desc',
          bus: 'projects/p/locations/l/messageBuses/b',
          ceAttributesBinding: const integrations.CloudEventAttributesBinding(
            type: integrations.OMIT,
            source: '//app',
          ),
        ),
        throwsArgumentError,
      );

      for (final String field in const <String>['id', 'specversion']) {
        expect(
          () => integrations.buildDomainSpecificTool(
            toolset: toolset,
            name: 'bad_$field',
            description: 'desc',
            bus: 'projects/p/locations/l/messageBuses/b',
            ceAttributesBinding: integrations.CloudEventAttributesBinding(
              type: 'com.example.event',
              source: '//app',
              id: field == 'id' ? integrations.OMIT : integrations.MISSING,
              specversion: field == 'specversion'
                  ? integrations.OMIT
                  : integrations.MISSING,
            ),
          ),
          throwsArgumentError,
        );
      }

      for (final String invalidKey in const <String>[
        'self_',
        'my-key',
        'MyKey',
        'event_data',
        'type',
      ]) {
        expect(
          () => integrations.buildDomainSpecificTool(
            toolset: toolset,
            name: 'bad_custom',
            description: 'desc',
            bus: 'projects/p/locations/l/messageBuses/b',
            ceAttributesBinding: integrations.CloudEventAttributesBinding(
              type: 'com.example.event',
              source: '//app',
              customAttributes: <String, Object?>{
                invalidKey: const integrations.AgentProvided('desc'),
              },
            ),
          ),
          throwsArgumentError,
        );
      }

      expect(
        () => integrations.buildDomainSpecificTool(
          toolset: toolset,
          name: 'missing_custom',
          description: 'desc',
          bus: 'projects/p/locations/l/messageBuses/b',
          ceAttributesBinding: const integrations.CloudEventAttributesBinding(
            type: 'com.example.event',
            source: '//app',
            customAttributes: <String, Object?>{
              'mykey': integrations.MISSING,
            },
          ),
        ),
        throwsArgumentError,
      );
    });

    test('generates dynamic FunctionDeclaration schema and sanitizes keyword/digit parameter names', () {
      final integrations.DomainSpecificPublishTool tool =
          integrations.buildDomainSpecificTool(
            name: 'publish_order_event',
            description: 'Publishes order events',
            bus: 'projects/p/locations/l/messageBuses/orders',
            ceAttributesBinding: integrations.CloudEventAttributesBinding(
              type: const integrations.AgentProvided('Event type'),
              source: const integrations.AgentProvided(
                'Event source',
                defaultValue: '//orders/default',
              ),
              subject: integrations.AgentProvided(
                'Subject',
                defaultValue: (Object? _) => 'dyn-subject',
              ),
              time: const integrations.AgentProvided(
                'Timestamp',
                defaultValue: integrations.OMIT,
              ),
              customAttributes: const <String, Object?>{
                'self': integrations.AgentProvided('Self attr'),
                'cls': integrations.AgentProvided('Cls attr'),
                '123foo': integrations.AgentProvided('Digit attr'),
              },
            ),
            payloadSchema: <String, Object?>{
              'type': 'object',
              'properties': <String, Object?>{
                'user_id': <String, Object?>{'type': 'string'},
                'action': <String, Object?>{'type': 'string'},
              },
              'required': <String>['user_id', 'action'],
            },
          );

      final adk.FunctionDeclaration decl = tool.getDeclaration()!;
      final Map<String, dynamic> props =
          decl.parameters['properties'] as Map<String, dynamic>;
      final List<dynamic> required =
          decl.parameters['required'] as List<dynamic>;

      expect(required, containsAll(<String>['type', 'self_', 'cls_', '_123foo', 'event_data']));
      expect(required, isNot(contains('source')));
      expect(required, isNot(contains('subject')));
      expect(required, isNot(contains('time')));

      expect((props['source'] as Map<String, dynamic>)['default'], '//orders/default');
      expect((props['subject'] as Map<String, dynamic>).containsKey('default'), isFalse);
      expect((props['time'] as Map<String, dynamic>).containsKey('default'), isFalse);
      expect(tool.parameterDefaults['subject'], isNull);
      expect(tool.parameterDefaults['time'], isNull);
      expect(props.containsKey('event_data'), isTrue);

      final integrations.DomainSpecificPublishTool noPayloadTool =
          integrations.buildDomainSpecificTool(
            name: 'no_payload',
            description: 'No payload',
            bus: 'projects/p/locations/l/messageBuses/orders',
            ceAttributesBinding: const integrations.CloudEventAttributesBinding(
              type: 'com.example.ping',
              source: '//ping',
            ),
          );
      expect(noPayloadTool.getDeclaration()!.parameters, isEmpty);
    });

    test('evaluates static, payload, context, 2-arg, 0-arg, OMIT, and AgentProvided bindings at runtime', () async {
      final List<Map<String, dynamic>> capturedCalls = <Map<String, dynamic>>[];
      final adk.EventarcToolset toolset = adk.EventarcToolset(
        toolConfig: const adk.EventarcToolConfig(projectId: 'proj-test'),
        publishInvoker: (Map<String, dynamic> kwargs) async {
          capturedCalls.add(Map<String, dynamic>.from(kwargs));
          return <String, dynamic>{'status': 'SUCCESS', 'message_id': 'msg-1'};
        },
      );

      final adk.DomainSpecificPublishTool tool = toolset.createPublishTool(
        name: 'emit_user_action',
        description: 'Emits user action CloudEvent',
        bus: 'projects/proj-test/locations/us-central1/messageBuses/main',
        ceAttributesBinding: adk.CloudEventAttributesBinding(
          type: (_DummyPayload p) => 'action.${p.action}',
          source: (adk.Context ctx) => '//agent/${ctx.session.id}',
          subject: (_DummyPayload payload, adk.Context ctx) =>
              '${payload.userId}-${ctx.session.id}',
          id: (adk.Context c) => 'id-${c.session.id}',
          specversion: () => '1.0',
          time: adk.OMIT,
          datacontenttype: adk.OMIT,
          customAttributes: <String, Object?>{
            'ordertest': (adk.Context ctx, _DummyPayload payload) =>
                '${ctx.session.id}:${payload.action}',
            'self': const adk.AgentProvided('Self tag'),
            'omittedcustom': () => adk.OMIT,
          },
        ),
        payloadSchema: _DummyPayload,
      );

      final List<adk.BaseTool> registeredTools = await toolset.getTools();
      expect(
        registeredTools.map((adk.BaseTool t) => t.name),
        containsAll(<String>['publish_message', 'emit_user_action']),
      );

      final adk.Context ctx = _makeToolContext();
      final Map<String, dynamic> res = await tool.execute(
        args: <String, dynamic>{'self_': 'self-val'},
        eventData: const _DummyPayload(userId: 'user123', action: 'login'),
        toolContext: ctx,
      );

      expect(res['status'], 'SUCCESS');
      expect(capturedCalls, hasLength(1));
      final Map<String, dynamic> sent = capturedCalls.single;
      expect(sent['bus'], 'projects/proj-test/locations/us-central1/messageBuses/main');
      expect(sent['type'], 'action.login');
      expect(sent['source'], '//agent/session-456');
      expect(sent['subject'], 'user123-session-456');
      expect(sent['id'], 'id-session-456');
      expect(sent['specversion'], '1.0');
      expect(sent['time'], '');
      expect(sent['datacontenttype'], '');
      expect(sent['data'], <String, dynamic>{'user_id': 'user123', 'action': 'login'});
      expect(sent['custom_attributes'], <String, String>{
        'ordertest': 'session-456:login',
        'self': 'self-val',
      });

      // Missing mandatory AgentProvided throws ArgumentError on execute()
      expect(
        () => tool.execute(
          eventData: const _DummyPayload(userId: 'u', action: 'a'),
          toolContext: ctx,
        ),
        throwsArgumentError,
      );

      // Mandatory attribute callback evaluating to OMIT throws ArgumentError
      final adk.DomainSpecificPublishTool omitTypeTool =
          adk.buildDomainSpecificTool(
            name: 'bad_runtime_omit',
            description: 'desc',
            bus: 'projects/p/locations/l/messageBuses/b',
            ceAttributesBinding: adk.CloudEventAttributesBinding(
              type: () => adk.OMIT,
              source: '//src',
            ),
          );
      expect(() => omitTypeTool.execute(), throwsArgumentError);
    });
  });

  group('3. Cascade Live GeminiSTT Full Parity', () {
    test('parses dynamic PCM sample rates and scales replayBuffer capacity', () async {
      expect(live.sampleRateOfAudioMime('audio/pcm;rate=48000'), 48000);
      expect(live.sampleRateOfAudioMime('AUDIO/PCM; channels=1; rate=24000'), 24000);
      expect(live.sampleRateOfAudioMime('audio/pcm'), 16000);

      // At 24000 Hz (48 bytes/ms), maxReplayMs=100 retains at most 4800 bytes.
      // Send three 2400-byte chunks (total 7200 bytes), drop on chunk 3 -> only chunks 2 & 3 (4800 bytes) replay!
      final _ScriptedSttLlm llm = _ScriptedSttLlm(
        connectionFactory: (int attempt, adk.LlmRequest req) {
          return _ScriptedLiveConnection(
            onRealtime: (_ScriptedLiveConnection conn, adk.RealtimeBlob blob) {
              if (attempt == 0 && conn.sentBlobs.length == 3) {
                conn.emitError(
                  adk.RecoverableLiveConnectionException(
                    'connection reset',
                    code: 1006,
                  ),
                );
              }
            },
          );
        },
      );

      final live.GeminiSTT stt = live.GeminiSTT(
        model: llm,
        maxReplayMs: 100,
        reconnectBaseDelay: const Duration(milliseconds: 5),
      );

      final StreamController<adk.InlineData> audio =
          StreamController<adk.InlineData>();
      final Future<List<live.IngressEvent>> eventsFuture = stt(
        audio.stream,
      ).toList();

      for (int i = 1; i <= 3; i++) {
        audio.add(
          adk.InlineData(
            mimeType: 'audio/pcm;rate=24000',
            data: List<int>.filled(2400, i),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }
      await Future<void>.delayed(const Duration(milliseconds: 25));
      await audio.close();
      await eventsFuture;

      expect(llm.sessions, hasLength(2));
      final List<adk.RealtimeBlob> replayed = llm.sessions[1].sentBlobs;
      expect(replayed, hasLength(2));
      expect(replayed[0].mimeType, 'audio/pcm;rate=24000');
      expect(replayed[0].data.first, 2);
      expect(replayed[1].data.first, 3);
    });

    test('rotates session on sessionRotationSeconds timer, replays unfinalized audio, and clears finalized turns', () async {
      final _ScriptedSttLlm llm = _ScriptedSttLlm(
        connectionFactory: (int attempt, adk.LlmRequest req) {
          return _ScriptedLiveConnection(
            onRealtime: (_ScriptedLiveConnection conn, adk.RealtimeBlob blob) {
              if (attempt == 0 && blob.data.first == 10) {
                // Finalize turn 1 immediately -> should clear chunk [10] from replayBuffer!
                conn.emit(
                  adk.LlmResponse(
                    content: adk.Content(
                      role: 'model',
                      parts: <adk.Part>[adk.Part.text('first turn')],
                    ),
                  ),
                );
                conn.emit(adk.LlmResponse(turnComplete: true));
              } else if (attempt == 0 && blob.data.first == 20) {
                // Start turn 2 without completing before rotation timer fires
                conn.emit(
                  adk.LlmResponse(
                    content: adk.Content(
                      role: 'model',
                      parts: <adk.Part>[adk.Part.text('second')],
                    ),
                  ),
                );
              } else if (attempt == 1 && blob.data.first == 30) {
                conn.emit(
                  adk.LlmResponse(
                    content: adk.Content(
                      role: 'model',
                      parts: <adk.Part>[adk.Part.text('second turn complete')],
                    ),
                  ),
                );
                conn.emit(adk.LlmResponse(turnComplete: true));
              }
            },
          );
        },
      );

      final live.GeminiSTT stt = live.GeminiSTT(
        model: llm,
        sessionRotationSeconds: 0.04,
      );

      final StreamController<adk.InlineData> audio =
          StreamController<adk.InlineData>();
      final Future<List<live.IngressEvent>> eventsFuture = stt(
        audio.stream,
      ).toList();

      audio.add(
        adk.InlineData(mimeType: 'audio/pcm;rate=16000', data: <int>[10, 10]),
      );
      await Future<void>.delayed(const Duration(milliseconds: 5));
      audio.add(
        adk.InlineData(mimeType: 'audio/pcm;rate=16000', data: <int>[20, 20]),
      );

      // Wait for rotation timer (40ms) to rotate to session 2 and replay [20, 20] (NOT [10, 10]!)
      await Future<void>.delayed(const Duration(milliseconds: 65));
      audio.add(
        adk.InlineData(mimeType: 'audio/pcm;rate=16000', data: <int>[30, 30]),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await audio.close();

      final List<live.IngressEvent> events = await eventsFuture;
      expect(llm.sessions.length, greaterThanOrEqualTo(2));

      // Session 2 must NOT receive finalized chunk [10, 10], MUST receive replayed [20, 20] then [30, 30]
      final List<int> session2FirstBytes = llm.sessions[1].sentBlobs
          .map((adk.RealtimeBlob b) => b.data.first)
          .toList();
      expect(session2FirstBytes, isNot(contains(10)));
      expect(session2FirstBytes, equals(<int>[20, 30]));

      // UserSpeechStarted emitted once for turn 1 and once for turn 2 (not duplicated across rotation!)
      expect(events.whereType<live.UserSpeechStarted>(), hasLength(2));
      expect(
        events.whereType<live.UserTurnFinished>().map((live.UserTurnFinished e) => e.text).toList(),
        equals(<String>['first turn', 'second turn complete']),
      );
    });

    test('retries transient disconnects with backoff and fails immediately on non-transient errors', () async {
      final _ScriptedSttLlm transientLlm = _ScriptedSttLlm(
        connectionFactory: (int attempt, adk.LlmRequest req) {
          if (attempt == 0) {
            throw TimeoutException('handshake timed out');
          }
          return _ScriptedLiveConnection(
            onRealtime: (_ScriptedLiveConnection conn, adk.RealtimeBlob blob) {
              if (attempt == 1) {
                conn.emitError(
                  adk.RecoverableLiveConnectionException('server restart', code: 1012),
                );
              } else {
                conn.emit(
                  adk.LlmResponse(
                    content: adk.Content(
                      role: 'model',
                      parts: <adk.Part>[adk.Part.text('recovered transcript')],
                    ),
                    turnComplete: true,
                  ),
                );
              }
            },
          );
        },
      );

      final live.GeminiSTT stt = live.GeminiSTT(
        model: transientLlm,
        maxReconnects: 2,
        reconnectBaseDelay: const Duration(milliseconds: 5),
      );

      final List<live.IngressEvent> events = await stt(
        Stream<adk.InlineData>.fromIterable(<adk.InlineData>[
          adk.InlineData(mimeType: 'audio/pcm;rate=16000', data: <int>[42, 43]),
        ]),
      ).toList();

      expect(transientLlm.connectAttempts, 3);
      expect(
        events.whereType<live.UserTurnFinished>().single.text,
        'recovered transcript',
      );

      // Non-transient error (WebSocket 1008 policy violation) must NOT retry
      final _ScriptedSttLlm fatalLlm = _ScriptedSttLlm(
        connectionFactory: (int attempt, adk.LlmRequest req) {
          throw adk.RecoverableLiveConnectionException(
            'policy violation',
            code: 1008,
          );
        },
      );
      final live.GeminiSTT fatalStt = live.GeminiSTT(
        model: fatalLlm,
        maxReconnects: 2,
        reconnectBaseDelay: const Duration(milliseconds: 5),
      );
      await expectLater(
        fatalStt(
          Stream<adk.InlineData>.value(
            adk.InlineData(mimeType: 'audio/pcm;rate=16000', data: <int>[1]),
          ),
        ).toList(),
        throwsA(isA<adk.RecoverableLiveConnectionException>()),
      );
      expect(fatalLlm.connectAttempts, 1);
    });
  });

  group('4. Cascade Live GeminiTTS Full Parity', () {
    test('prefetches lookahead segments concurrently while delivering audio strictly in reply order', () async {
      final _ControlledTtsLlm llm = _ControlledTtsLlm();
      llm.held['One.'] = Completer<void>();

      final live.GeminiTTS tts = live.GeminiTTS(
        model: llm,
        prefetchSegments: 1,
        minSegmentChars: 0,
        retryDelays: const <Duration>[],
      );

      final Future<List<live.EgressEvent>> speaking = tts(
        Stream<String>.value('One. Two. Three.'),
        cancel: live.CancelSignal(),
      ).toList();

      // With prefetchSegments=1, 'One.' and 'Two.' start concurrently while 'One.' is held,
      // and 'Three.' waits behind the semaphore until 'One.' finishes!
      for (int i = 0; i < 30 && llm.requestedTexts.length < 2; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }
      expect(llm.requestedTexts, equals(<String>['One.', 'Two.']));

      // Wait for 'Two.' to finish synthesizing in the background before releasing 'One.'
      for (int i = 0; i < 30 && !llm.cancelledOrClosedTexts.contains('Two.'); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }
      expect(llm.cancelledOrClosedTexts, contains('Two.'));
      expect(llm.requestedTexts, equals(<String>['One.', 'Two.']));

      // Release 'One.' -> 'One.', 'Two.', and 'Three.' deliver in strict order!
      llm.held['One.']!.complete();
      final List<live.EgressEvent> events = await speaking;

      expect(llm.requestedTexts, equals(<String>['One.', 'Two.', 'Three.']));
      expect(
        events,
        equals(<live.EgressEvent>[
          live.AudioChunk(
            blob: adk.InlineData(
              mimeType: 'audio/pcm;rate=24000',
              data: 'One.'.codeUnits,
            ),
          ),
          const live.AgentSpokenOutput(text: 'One. '),
          live.AudioChunk(
            blob: adk.InlineData(
              mimeType: 'audio/pcm;rate=24000',
              data: 'Two.'.codeUnits,
            ),
          ),
          const live.AgentSpokenOutput(text: 'Two. '),
          live.AudioChunk(
            blob: adk.InlineData(
              mimeType: 'audio/pcm;rate=24000',
              data: 'Three.'.codeUnits,
            ),
          ),
          const live.AgentSpokenOutput(text: 'Three.'),
        ]),
      );
    });

    test('stream subscription cancellation on barge-in cancels active and prefetched segment streams', () async {
      final _ControlledTtsLlm llm = _ControlledTtsLlm();
      llm.held['Two.'] = Completer<void>();

      final live.GeminiTTS tts = live.GeminiTTS(
        model: llm,
        prefetchSegments: 1,
        minSegmentChars: 0,
      );

      final List<live.EgressEvent> received = <live.EgressEvent>[];
      final Completer<void> firstSpoken = Completer<void>();

      final StreamSubscription<live.EgressEvent> sub = tts(
        Stream<String>.value('One. Two. Three.'),
        cancel: live.CancelSignal(),
      ).listen((live.EgressEvent event) {
        received.add(event);
        if (event is live.AgentSpokenOutput && !firstSpoken.isCompleted) {
          firstSpoken.complete();
        }
      });

      await firstSpoken.future;
      for (int i = 0; i < 30 && !llm.requestedTexts.contains('Two.'); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }
      expect(llm.requestedTexts, contains('Two.'));

      // Cancel downstream subscription directly (without setting CancelSignal)
      await sub.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(llm.cancelledOrClosedTexts, contains('Two.'));
      expect(
        received.whereType<live.AgentSpokenOutput>().map((live.AgentSpokenOutput e) => e.text).toList(),
        equals(<String>['One. ']),
      );
    });

    test('strips RIFF/WAVE headers and normalizes audio/L16 and audio/wav to audio/pcm;rate=<rate>', () async {
      final List<int> rawPcm = <int>[10, 20, 30, 40, 50, 60];
      final Uint8List wavBytes = _buildWavBytes(
        pcmPayload: rawPcm,
        sampleRate: 16000,
        includeJunkChunk: true,
      );

      final _ControlledTtsLlm llm = _ControlledTtsLlm();
      llm.customAudioByText['Wav test.'] = adk.InlineData(
        mimeType: 'audio/wav',
        data: wavBytes,
      );
      llm.customAudioByText['L16 test.'] = adk.InlineData(
        mimeType: 'audio/L16;codec=pcm;rate=22050',
        data: <int>[9, 8, 7, 6],
      );

      final live.GeminiTTS tts = live.GeminiTTS(
        model: llm,
        minSegmentChars: 0,
      );

      final List<live.EgressEvent> events = await tts(
        Stream<String>.value('Wav test. L16 test.'),
        cancel: live.CancelSignal(),
      ).toList();

      final List<live.AudioChunk> chunks = events
          .whereType<live.AudioChunk>()
          .toList();
      expect(chunks, hasLength(2));
      expect(chunks[0].blob.mimeType, 'audio/pcm;rate=16000');
      expect(chunks[0].blob.data, equals(rawPcm));
      expect(chunks[1].blob.mimeType, 'audio/pcm;rate=22050');
      expect(chunks[1].blob.data, equals(<int>[9, 8, 7, 6]));
    });

    test('retries transient synthesis errors only before audio is emitted', () async {
      final _ControlledTtsLlm llm = _ControlledTtsLlm();
      llm.errorsBeforeAudio['Retry me.'] = <Object>[
        _HttpStatusError(503, 'Service Unavailable'),
        TimeoutException('transient timeout'),
      ];

      final live.GeminiTTS tts = live.GeminiTTS(
        model: llm,
        retryDelays: const <Duration>[
          Duration(milliseconds: 2),
          Duration(milliseconds: 4),
        ],
      );

      final List<live.EgressEvent> events = await tts(
        Stream<String>.value('Retry me.'),
        cancel: live.CancelSignal(),
      ).toList();

      expect(
        llm.requestedTexts,
        equals(<String>['Retry me.', 'Retry me.', 'Retry me.']),
      );
      expect(events.whereType<live.AgentSpokenOutput>().single.text, 'Retry me.');

      // Error AFTER audio chunk was already emitted must NOT retry
      final _ControlledTtsLlm afterAudioLlm = _ControlledTtsLlm();
      afterAudioLlm.errorsAfterAudio['Partial fail.'] = _HttpStatusError(
        503,
        'mid-stream drop',
      );
      final live.GeminiTTS afterAudioTts = live.GeminiTTS(
        model: afterAudioLlm,
        retryDelays: const <Duration>[Duration(milliseconds: 2)],
      );

      final List<live.EgressEvent> partialEvents = <live.EgressEvent>[];
      await expectLater(
        () async {
          await for (final live.EgressEvent ev in afterAudioTts(
            Stream<String>.value('Partial fail.'),
            cancel: live.CancelSignal(),
          )) {
            partialEvents.add(ev);
          }
        }(),
        throwsA(isA<_HttpStatusError>()),
      );
      expect(afterAudioLlm.requestedTexts, equals(<String>['Partial fail.']));
      expect(partialEvents.whereType<live.AudioChunk>(), hasLength(1));
      expect(partialEvents.whereType<live.AgentSpokenOutput>(), isEmpty);

      // Non-transient 400 error must NOT retry
      final _ControlledTtsLlm badReqLlm = _ControlledTtsLlm();
      badReqLlm.errorsBeforeAudio['Bad req.'] = <Object>[
        _HttpStatusError(400, 'Bad Request'),
      ];
      final live.GeminiTTS badReqTts = live.GeminiTTS(
        model: badReqLlm,
        retryDelays: const <Duration>[Duration(milliseconds: 2)],
      );
      await expectLater(
        badReqTts(
          Stream<String>.value('Bad req.'),
          cancel: live.CancelSignal(),
        ).toList(),
        throwsA(isA<_HttpStatusError>()),
      );
      expect(badReqLlm.requestedTexts, equals(<String>['Bad req.']));
    });
  });
}
