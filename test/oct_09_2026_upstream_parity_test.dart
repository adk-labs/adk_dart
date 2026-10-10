import 'dart:async';

import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

class _FakeCascadeLlm extends BaseLlm {
  _FakeCascadeLlm(this._responses) : super(model: 'fake-cascade-llm');

  final List<List<LlmResponse>> _responses;
  int _turnIndex = 0;
  final List<LlmRequest> capturedRequests = <LlmRequest>[];

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    capturedRequests.add(request);
    final List<LlmResponse> turn = _turnIndex < _responses.length
        ? _responses[_turnIndex++]
        : <LlmResponse>[];
    for (final LlmResponse response in turn) {
      yield response;
    }
  }
}

class _FakeStt extends LiveIngress {
  _FakeStt(this._events);

  final List<IngressEvent> _events;
  final List<InlineData> receivedAudio = <InlineData>[];

  @override
  Stream<IngressEvent> call(Stream<InlineData> audio) async* {
    await for (final InlineData chunk in audio) {
      receivedAudio.add(chunk);
    }
    for (final IngressEvent event in _events) {
      yield event;
    }
  }
}

class _FakeTts extends LiveEgress {
  final List<String> receivedText = <String>[];

  @override
  Stream<EgressEvent> call(
    Stream<String> text, {
    required CancelSignal cancel,
  }) async* {
    final StringBuffer buffer = StringBuffer();
    await for (final String delta in text) {
      if (cancel.isSet) {
        return;
      }
      receivedText.add(delta);
      buffer.write(delta);
    }
    final String fullText = buffer.toString().trim();
    if (fullText.isNotEmpty) {
      yield AgentSpokenOutput(text: fullText);
      yield AudioChunk(
        blob: InlineData(
          mimeType: 'audio/pcm;rate=24000',
          data: <int>[1, 2, 3, 4],
        ),
      );
    }
  }
}

class _SlowComputer extends BaseComputer {
  int initCount = 0;
  int closeCount = 0;

  @override
  Future<void> initialize() async {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    initCount++;
  }

  @override
  Future<void> close() async {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    closeCount++;
  }

  @override
  Future<(int, int)> screenSize() async => (1280, 720);

  @override
  Future<ComputerEnvironment> environment() async =>
      ComputerEnvironment.environmentBrowser;

  @override
  Future<ComputerState> openWebBrowser() async => ComputerState();

  @override
  Future<ComputerState> clickAt(int x, int y) async => ComputerState();

  @override
  Future<ComputerState> hoverAt(int x, int y) async => ComputerState();

  @override
  Future<ComputerState> typeTextAt(
    int x,
    int y,
    String text, {
    bool pressEnter = true,
    bool clearBeforeTyping = true,
  }) async => ComputerState();

  @override
  Future<ComputerState> scrollDocument(String direction) async =>
      ComputerState();

  @override
  Future<ComputerState> scrollAt(
    int x,
    int y,
    String direction,
    int magnitude,
  ) async => ComputerState();

  @override
  Future<ComputerState> wait(int seconds) async => ComputerState();

  @override
  Future<ComputerState> goBack() async => ComputerState();

  @override
  Future<ComputerState> goForward() async => ComputerState();

  @override
  Future<ComputerState> search() async => ComputerState();

  @override
  Future<ComputerState> navigate(String url) async => ComputerState();

  @override
  Future<ComputerState> keyCombination(List<String> keys) async =>
      ComputerState();

  @override
  Future<ComputerState> dragAndDrop(
    int x,
    int y,
    int destinationX,
    int destinationY,
  ) async => ComputerState();

  @override
  Future<ComputerState> currentState() async => ComputerState();
}

class _SlowEnvironment extends BaseEnvironment {
  int initCount = 0;
  int closeCount = 0;

  @override
  Future<void> initialize() async {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    initCount++;
  }

  @override
  Future<void> close() async {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    closeCount++;
  }

  @override
  Future<EnvironmentExecutionResult> execute(
    String command, {
    Duration timeout = const Duration(seconds: 30),
  }) async => const EnvironmentExecutionResult(exitCode: 0);

  @override
  Future<List<int>> readFile(Object path) async => const <int>[];

  @override
  Future<void> writeFile(Object path, String content) async {}
}

void main() {
  group('2026-10-09 Upstream ADK Parity Tests', () {
    test('CascadeLive drives STT -> LLM -> TTS pipeline and emits transcriptions', () async {
      final _FakeCascadeLlm fakeLlm = _FakeCascadeLlm(<List<LlmResponse>>[
        <LlmResponse>[
          LlmResponse(
            content: Content.modelText('Hello '),
            partial: true,
          ),
          LlmResponse(
            content: Content.modelText('from CascadeLive!'),
            partial: true,
          ),
          LlmResponse(
            content: Content.modelText('Hello from CascadeLive!'),
            partial: false,
          ),
        ],
      ]);
      final _FakeStt stt = _FakeStt(<IngressEvent>[
        const PartialTranscript(text: 'Hi'),
        const UserTurnFinished(text: 'Hi there'),
      ]);
      final _FakeTts tts = _FakeTts();

      final CascadeLive cascadeLive = CascadeLive(
        model: fakeLlm,
        stt: stt,
        tts: tts,
      );
      expect(isFeatureEnabled(FeatureName.cascadeLive), isTrue);
      expect(isFeatureEnabled(FeatureName.elevenLabs), isTrue);

      final BaseLlmConnection connection = cascadeLive.connect(LlmRequest());
      final List<LlmResponse> emitted = <LlmResponse>[];
      final Completer<void> turnDone = Completer<void>();

      final StreamSubscription<LlmResponse> sub = connection.receive().listen((
        LlmResponse response,
      ) {
        emitted.add(response);
        if (response.turnComplete == true && !turnDone.isCompleted) {
          turnDone.complete();
        }
      });

      await connection.sendRealtime(
        RealtimeBlob(mimeType: 'audio/pcm;rate=16000', data: <int>[10, 20]),
      );
      await connection.sendActivityEnd();

      await turnDone.future.timeout(const Duration(seconds: 5));
      await connection.close();
      await sub.cancel();

      expect(stt.receivedAudio, hasLength(1));
      expect(tts.receivedText.join(), equals('Hello from CascadeLive!'));
      expect(
        emitted.any((LlmResponse r) => r.inputTranscription != null),
        isTrue,
      );
      expect(
        emitted.any((LlmResponse r) => r.outputTranscription != null),
        isTrue,
      );
      expect(
        emitted.any(
          (LlmResponse r) =>
              r.content?.parts.any((Part p) => p.inlineData != null) ?? false,
        ),
        isTrue,
      );
    });

    test('ElevenLabs TTS sentence splitter and STT audio MIME parser match upstream', () async {
      expect(
        parseElevenLabsSttAudioMime('audio/pcm;rate=16000'),
        equals(16000),
      );
      expect(
        parseElevenLabsSttAudioMime('audio/l16;rate=24000'),
        equals(24000),
      );
      expect(
        () => parseElevenLabsSttAudioMime('audio/mp3'),
        throwsArgumentError,
      );

      final ElevenLabsTTS tts = ElevenLabsTTS(sampleRate: 24000);
      expect(tts.outputFormat, equals('pcm_24000'));
      expect(tts.outputMimeType, equals('audio/pcm;rate=24000'));

      final List<String> sentences = await splitElevenLabsTtsSentences(
        Stream<String>.fromIterable(<String>[
          'First sentence. ',
          'Second sentence! ',
          'Third?',
        ]),
      ).toList();
      expect(
        sentences.map((String s) => s.trim()).toList(),
        equals(<String>['First sentence.', 'Second sentence!', 'Third?']),
      );
    });

    test('Skill tools dynamically update active telemetry span name when confirmed', () async {
      final Skill skill = Skill(
        frontmatter: Frontmatter(
          name: 'weather-skill',
          description: 'Weather lookup skill',
        ),
        instructions: 'Fetch weather details.',
        resources: Resources(
          references: <String, String>{'guide.md': '# Weather Guide'},
        ),
      );
      final SkillToolset toolset = SkillToolset(skills: <Skill>[skill]);
      final List<BaseTool> tools = await toolset.getTools();
      final BaseTool loadSkillTool = tools.firstWhere(
        (BaseTool t) => t.name == 'load_skill',
      );
      final BaseTool loadResourceTool = tools.firstWhere(
        (BaseTool t) => t.name == 'load_skill_resource',
      );

      final InMemorySessionService sessionService = InMemorySessionService();
      final Session session = await sessionService.createSession(
        appName: 'app',
        userId: 'user',
      );
      final InvocationContext invocationContext = InvocationContext(
        sessionService: sessionService,
        invocationId: 'inv_1',
        agent: Agent(
          name: 'root',
          model: _FakeCascadeLlm(<List<LlmResponse>>[]),
        ),
        session: session,
      );
      final Context toolContext = Context(invocationContext);

      final TraceSpanRecord span1 = tracer.startAsCurrentSpan(
        'execute_tool load_skill',
      );
      try {
        await loadSkillTool.run(
          args: <String, dynamic>{'name': 'weather-skill'},
          toolContext: toolContext,
        );
      } finally {
        tracer.endSpan(span1);
      }
      expect(span1.name, equals('execute_tool load_skill weather-skill'));

      final TraceSpanRecord span2 = tracer.startAsCurrentSpan(
        'execute_tool load_skill_resource',
      );
      try {
        await loadResourceTool.run(
          args: <String, dynamic>{
            'skill_name': 'weather-skill',
            'file_path': 'references/guide.md',
          },
          toolContext: toolContext,
        );
      } finally {
        tracer.endSpan(span2);
      }
      expect(
        span2.name,
        equals(
          'execute_tool load_skill_resource weather-skill references/guide.md',
        ),
      );
    });

    test('clientFunctionCallNames and mcpReservedToolNames use canonical ADK tool names', () {
      expect(
        clientFunctionCallNames,
        equals(<String>{
          'adk_request_credential',
          'adk_request_confirmation',
          'adk_request_input',
        }),
      );
      expect(mcpReservedToolNames, containsAll(clientFunctionCallNames));
      expect(mcpReservedToolNames, contains('set_model_response'));
      expect(mcpReservedToolNames, contains('transfer_to_agent'));
    });

    test('RestApiTool returns structured error when required path param is missing', () async {
      final OpenAPIToolset toolset = OpenAPIToolset(
        specDict: <String, Object?>{
          'openapi': '3.0.0',
          'info': <String, Object?>{'title': 'Test API', 'version': '1.0.0'},
          'servers': <Object?>[
            <String, Object?>{'url': 'https://example.com'},
          ],
          'paths': <String, Object?>{
            '/users/{userId}/items': <String, Object?>{
              'get': <String, Object?>{
                'operationId': 'getUserItems',
                'parameters': <Object?>[
                  <String, Object?>{
                    'name': 'userId',
                    'in': 'path',
                    'required': true,
                    'schema': <String, Object?>{'type': 'string'},
                  },
                ],
                'responses': <String, Object?>{
                  '200': <String, Object?>{'description': 'OK'},
                },
              },
            },
          },
        },
      );
      final List<BaseTool> tools = await toolset.getTools();
      final RestApiTool tool = tools.single as RestApiTool;

      final Map<String, Object?> result = await tool.call(
        args: <String, dynamic>{},
      );
      expect(result['error'], isA<String>());
      expect(
        result['error'] as String,
        contains("Missing required path parameter 'user_id'."),
      );
    });

    test('LiteLlm keeps all text parts of an assistant message joined by newline', () {
      final LlmRequest request = LlmRequest(
        model: 'openai/gpt-4o-mini',
        contents: <Content>[
          Content(
            role: 'model',
            parts: <Part>[
              Part.text('First part'),
              Part.text('thought', thought: true),
              Part.text('Second part'),
            ],
          ),
        ],
      );
      final Map<String, Object?> payload = LiteLlm.buildPayload(
        request,
        stream: false,
      );
      final List<Map<String, Object?>> messages =
          payload['messages'] as List<Map<String, Object?>>;
      expect(messages.single['role'], equals('assistant'));
      expect(messages.single['content'], equals('First part\nSecond part'));
    });

    test('ApigeeLlm preserves text sent alongside a function response', () {
      final LlmRequest request = LlmRequest(
        model: 'apigee/gemini-2.5-flash',
        contents: <Content>[
          Content(
            role: 'user',
            parts: <Part>[
              Part.fromFunctionResponse(
                name: 'lookup',
                id: 'call_1',
                response: <String, dynamic>{'status': 'ok'},
              ),
              Part.text('Here is extra context alongside the tool result.'),
            ],
          ),
        ],
      );
      final Map<String, Object?> payload =
          ApigeeLlm.buildChatCompletionsPayload(request, stream: false);
      final List<Map<String, Object?>> messages =
          (payload['messages'] as List).cast<Map<String, Object?>>();
      expect(messages, hasLength(2));
      expect(messages[0]['role'], equals('tool'));
      expect(messages[1]['role'], equals('user'));
      expect(
        messages[1]['content'],
        equals('Here is extra context alongside the tool result.'),
      );
    });

    test('ComputerUseToolset and EnvironmentToolset guard concurrent lazy initialization and close', () async {
      final _SlowComputer computer = _SlowComputer();
      final ComputerUseToolset computerToolset = ComputerUseToolset(
        computer: computer,
      );
      await Future.wait(<Future<Object?>>[
        computerToolset.getTools(),
        computerToolset.getTools(),
        computerToolset.getTools(),
      ]);
      expect(computer.initCount, equals(1));

      await Future.wait(<Future<void>>[
        computerToolset.close(),
        computerToolset.close(),
      ]);
      expect(computer.closeCount, equals(1));

      final _SlowEnvironment env = _SlowEnvironment();
      final EnvironmentToolset envToolset = EnvironmentToolset(
        environment: env,
      );
      await Future.wait(<Future<Object?>>[
        envToolset.getTools(),
        envToolset.getTools(),
      ]);
      expect(env.initCount, equals(1));

      await Future.wait(<Future<void>>[
        envToolset.close(),
        envToolset.close(),
      ]);
      expect(env.closeCount, equals(1));
    });

    test('SqliteSessionService keeps state numbers exact and replaces top-level nested maps', () async {
      final SqliteSessionService service = SqliteSessionService(
        'sqlite:///:memory:',
      );
      final Session session = await service.createSession(
        appName: 'app',
        userId: 'u1',
        state: <String, Object?>{
          'ratio': 0.1 + 0.2,
          'nested': <String, Object?>{'a': 1, 'b': 2},
        },
      );

      await service.appendEvent(
        session: session,
        event: Event(
          invocationId: 'inv_1',
          author: 'agent',
          actions: EventActions(
            stateDelta: <String, Object?>{
              'ratio': 0.30000000000000004,
              'nested': <String, Object?>{'a': 99},
              'nullable': null,
            },
          ),
        ),
      );

      final Session? reloaded = await service.getSession(
        appName: 'app',
        userId: 'u1',
        sessionId: session.id,
      );
      expect(reloaded, isNotNull);
      expect(reloaded!.state['ratio'], equals(0.30000000000000004));
      expect(reloaded.state['nested'], equals(<String, Object?>{'a': 99}));
      expect(reloaded.state.containsKey('nullable'), isTrue);
      expect(reloaded.state['nullable'], isNull);
    });

    test('InMemoryMemoryService normalizes combining marks and punctuation in search', () async {
      final InMemoryMemoryService memory = InMemoryMemoryService();
      await memory.addEventsToMemory(
        appName: 'app',
        userId: 'u1',
        events: <Event>[
          Event(
            invocationId: 'inv_1',
            author: 'user',
            content: Content.userText(
              'We discussed nai\u0308ve Bayes and हिंदी ❤️!',
            ),
          ),
        ],
      );

      final SearchMemoryResponse decomposedMatch = await memory.searchMemory(
        appName: 'app',
        userId: 'u1',
        query: 'nai\u0308ve',
      );
      expect(decomposedMatch.memories, hasLength(1));

      final SearchMemoryResponse indicMatch = await memory.searchMemory(
        appName: 'app',
        userId: 'u1',
        query: 'हिंदी',
      );
      expect(indicMatch.memories, hasLength(1));

      final SearchMemoryResponse emojiOnly = await memory.searchMemory(
        appName: 'app',
        userId: 'u1',
        query: '❤️',
      );
      expect(emojiOnly.memories, isEmpty);
    });

    test('GoogleApiToOpenApiConverter extracts {+name} path parameters with custom verbs', () async {
      final GoogleApiToOpenApiConverter converter =
          GoogleApiToOpenApiConverter(
            'testapi',
            'v1',
            discoverySpec: <String, Object?>{
              'name': 'testapi',
              'version': 'v1',
              'rootUrl': 'https://example.googleapis.com/',
              'servicePath': '',
              'resources': <String, Object?>{
                'operations': <String, Object?>{
                  'methods': <String, Object?>{
                    'cancel': <String, Object?>{
                      'id': 'testapi.operations.cancel',
                      'path': 'v1/{+name}:cancel',
                      'httpMethod': 'POST',
                      'parameters': <String, Object?>{},
                    },
                  },
                },
              },
            },
          );
      final Map<String, Object?> spec = await converter.convert();
      final Map<String, Object?> paths =
          spec['paths'] as Map<String, Object?>;
      final Map<String, Object?> pathItem =
          paths['/v1/{+name}:cancel'] as Map<String, Object?>;
      final Map<String, Object?> postOp =
          pathItem['post'] as Map<String, Object?>;
      final List<Object?> params = postOp['parameters'] as List<Object?>;
      expect(
        params.any(
          (Object? p) =>
              p is Map && p['name'] == 'name' && p['in'] == 'path',
        ),
        isTrue,
      );
    });
  });
}
