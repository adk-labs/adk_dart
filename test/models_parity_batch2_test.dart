import 'dart:async';

import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

class _FakeGeminiCacheClient implements GeminiCacheClient {
  int createCalls = 0;
  int deleteCalls = 0;
  String? deletedName;

  @override
  Future<GeminiCreatedCache> createCache({
    required String model,
    required List<Content> contents,
    required String ttl,
    required String displayName,
    String? systemInstruction,
    List<ToolDeclaration>? tools,
    LlmToolConfig? toolConfig,
  }) async {
    createCalls += 1;
    return GeminiCreatedCache(name: 'caches/cache-$createCalls');
  }

  @override
  Future<void> deleteCache({required String cacheName}) async {
    deleteCalls += 1;
    deletedName = cacheName;
  }
}

class _FakeLiveSession implements GeminiLiveSession {
  final StreamController<GeminiLiveSessionMessage> controller =
      StreamController<GeminiLiveSessionMessage>();
  List<Content>? lastSentTurns;
  bool? lastTurnComplete;
  List<FunctionResponse>? lastFunctionResponses;
  RealtimeBlob? lastRealtimeBlob;
  bool closed = false;

  @override
  Future<void> sendContent({
    required List<Content> turns,
    required bool turnComplete,
  }) async {
    lastSentTurns = turns.map((Content c) => c.copyWith()).toList();
    lastTurnComplete = turnComplete;
  }

  @override
  Future<void> sendRealtimeInput({required RealtimeBlob blob}) async {
    lastRealtimeBlob = blob;
  }

  @override
  Future<void> sendToolResponses({
    required List<FunctionResponse> functionResponses,
  }) async {
    lastFunctionResponses = functionResponses
        .map((FunctionResponse f) => f.copyWith())
        .toList();
  }

  @override
  Stream<GeminiLiveSessionMessage> receive() => controller.stream;

  @override
  Future<void> close() async {
    closed = true;
    await controller.close();
  }
}

class _FakeApigeeCompletionsClient implements ApigeeCompletionsClient {
  Map<String, Object?>? lastPayload;
  bool? lastStream;
  String? lastBaseUrl;
  Map<String, String>? lastHeaders;

  @override
  Stream<LlmResponse> generateContent({
    required LlmRequest request,
    required bool stream,
    required String baseUrl,
    required Map<String, String> headers,
  }) async* {
    lastPayload = ApigeeLlm.buildChatCompletionsPayload(
      request,
      stream: stream,
    );
    lastStream = stream;
    lastBaseUrl = baseUrl;
    lastHeaders = headers;
    yield ApigeeLlm.parseChatCompletionsResponse(<String, Object?>{
      'id': 'resp-1',
      'model': request.model,
      'choices': <Object?>[
        <String, Object?>{
          'finish_reason': 'stop',
          'message': <String, Object?>{
            'role': 'assistant',
            'content': 'apigee-result',
          },
        },
      ],
      'usage': <String, Object?>{
        'prompt_tokens': 3,
        'completion_tokens': 4,
        'total_tokens': 7,
      },
    });
  }
}

void main() {
  group('gemini context cache manager parity', () {
    test('returns fingerprint-only metadata on first request', () async {
      final GeminiContextCacheManager manager = GeminiContextCacheManager();
      final LlmRequest request = LlmRequest(
        model: 'gemini-2.5-flash',
        contents: <Content>[Content.userText('hello')],
        cacheConfig: ContextCacheConfig(),
      );

      final CacheMetadata? metadata = await manager.handleContextCaching(
        request,
      );

      expect(metadata, isNotNull);
      expect(metadata!.cacheName, isNull);
      expect(metadata.contentsCount, 1);
      expect(request.cacheMetadata, isA<CacheMetadata>());
    });

    test(
      'reuses valid cache and applies cached-content request mutation',
      () async {
        final GeminiContextCacheManager manager = GeminiContextCacheManager();
        final LlmRequest request = LlmRequest(
          model: 'gemini-2.5-flash',
          contents: <Content>[Content.userText('hello')],
          cacheConfig: ContextCacheConfig(),
        );
        final String fingerprint = manager.fingerprintCacheableContents(
          request,
        );
        request.cacheMetadata = CacheMetadata(
          cacheName: 'caches/existing',
          expireTime: DateTime.now().millisecondsSinceEpoch / 1000.0 + 300,
          fingerprint: fingerprint,
          invocationsUsed: 0,
          contentsCount: 1,
        );

        final CacheMetadata? metadata = await manager.handleContextCaching(
          request,
        );

        expect(metadata, isNotNull);
        expect(metadata!.cacheName, 'caches/existing');
        expect(metadata.invocationsUsed, 1);
        expect(request.config.cachedContent, 'caches/existing');
        expect(request.config.systemInstruction, isNull);
        expect(request.contents, isEmpty);
      },
    );

    test(
      'invalid cache triggers cleanup and recreation when fingerprint matches',
      () async {
        final _FakeGeminiCacheClient client = _FakeGeminiCacheClient();
        final GeminiContextCacheManager manager = GeminiContextCacheManager(
          cacheClient: client,
        );
        final LlmRequest request = LlmRequest(
          model: 'gemini-2.5-flash',
          contents: <Content>[Content.userText('hello')],
          cacheConfig: ContextCacheConfig(minTokens: 10),
        );
        final String fingerprint = manager.fingerprintCacheableContents(
          request,
        );
        request.cacheableContentsTokenCount = 20;
        request.cacheMetadata = CacheMetadata(
          cacheName: 'caches/expired',
          expireTime: DateTime.now().millisecondsSinceEpoch / 1000.0 - 1,
          fingerprint: fingerprint,
          invocationsUsed: 0,
          contentsCount: 1,
        );

        final CacheMetadata? metadata = await manager.handleContextCaching(
          request,
        );

        expect(metadata, isNotNull);
        expect(metadata!.cacheName, startsWith('caches/cache-'));
        expect(client.deleteCalls, 1);
        expect(client.createCalls, 1);
        expect(request.config.cachedContent, metadata.cacheName);
      },
    );
  });

  group('gemini live connection parity', () {
    test('filters audio from history and routes tool responses', () async {
      final _FakeLiveSession session = _FakeLiveSession();
      final GeminiLlmConnection connection = GeminiLlmConnection(
        model: Gemini(),
        liveSession: session,
      );

      await connection.sendHistory(<Content>[
        Content(
          role: 'user',
          parts: <Part>[
            Part.fromInlineData(mimeType: 'audio/wav', data: <int>[1]),
            Part.text('hello'),
          ],
        ),
      ]);
      expect(session.lastSentTurns, isNotNull);
      expect(session.lastSentTurns!.single.parts, hasLength(1));
      expect(session.lastSentTurns!.single.parts.single.text, 'hello');

      await connection.sendContent(
        Content(
          role: 'user',
          parts: <Part>[
            Part.fromFunctionResponse(
              name: 'tool',
              response: <String, dynamic>{'ok': true},
              id: 'call-1',
            ),
          ],
        ),
      );
      expect(session.lastFunctionResponses, hasLength(1));

      await connection.close();
      expect(session.closed, isTrue);
    });

    test(
      'emits partial/final text and transcription flush for gemini api',
      () async {
        final _FakeLiveSession session = _FakeLiveSession();
        final GeminiLlmConnection connection = GeminiLlmConnection(
          model: Gemini(),
          liveSession: session,
          apiBackend: GoogleLLMVariant.geminiApi,
        );
        final List<LlmResponse> responses = <LlmResponse>[];
        final StreamSubscription<LlmResponse> sub = connection.receive().listen(
          responses.add,
        );

        await connection.sendContent(Content.userText('hello'));
        session.controller.add(
          GeminiLiveSessionMessage(
            serverContent: GeminiServerContentPayload(
              modelTurn: Content.modelText('Hel'),
              inputTranscription: GeminiTranscriptionEvent(
                text: 'in-',
                finished: false,
              ),
            ),
          ),
        );
        session.controller.add(
          GeminiLiveSessionMessage(
            serverContent: GeminiServerContentPayload(
              modelTurn: Content.modelText('lo'),
              generationComplete: true,
              turnComplete: true,
            ),
            toolCall: GeminiToolCallPayload(
              functionCalls: <FunctionCall>[FunctionCall(name: 'do_work')],
            ),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(
          responses.any(
            (LlmResponse r) => r.content?.parts.first.text == 'Hel',
          ),
          isTrue,
        );
        expect(
          responses.any(
            (LlmResponse r) => r.content?.parts.first.text == 'Hello',
          ),
          isTrue,
        );
        expect(
          responses.any((LlmResponse r) => r.turnComplete == true),
          isTrue,
        );
        expect(
          responses.any((LlmResponse r) => r.inputTranscription != null),
          isTrue,
        );

        await sub.cancel();
        await connection.close();
      },
    );
  });

  group('google llm parity', () {
    test('gemini api preprocess removes labels and display_name', () async {
      final Gemini model = Gemini(
        apiBackendOverride: GoogleLLMVariant.geminiApi,
        generateHook: (LlmRequest request, bool stream) async* {
          expect(request.config.labels, isEmpty);
          expect(
            request.contents.first.parts.first.inlineData!.displayName,
            isNull,
          );
          yield LlmResponse(content: Content.modelText('ok'));
        },
      );
      final LlmRequest request = LlmRequest(
        model: 'gemini-2.5-flash',
        contents: <Content>[
          Content(
            role: 'user',
            parts: <Part>[
              Part.fromInlineData(
                mimeType: 'image/png',
                data: <int>[1, 2],
                displayName: 'image',
              ),
            ],
          ),
        ],
        config: GenerateContentConfig(labels: <String, String>{'env': 'test'}),
      );

      final List<LlmResponse> responses = await model
          .generateContent(request)
          .toList();
      expect(responses.single.content?.parts.single.text, 'ok');
    });

    test(
      'connect injects live config and uses provided live session factory',
      () async {
        final _FakeLiveSession session = _FakeLiveSession();
        LlmRequest? captured;
        final Gemini model = Gemini(
          apiBackendOverride: GoogleLLMVariant.vertexAi,
          liveSessionFactory: (LlmRequest request) {
            captured = request;
            return session;
          },
        );
        final BaseLlmConnection connection = model.connect(
          LlmRequest(
            model: 'gemini-2.5-flash',
            config: GenerateContentConfig(
              systemInstruction: 'be concise',
              tools: <ToolDeclaration>[
                ToolDeclaration(
                  functionDeclarations: <FunctionDeclaration>[
                    FunctionDeclaration(name: 'tool_a'),
                  ],
                ),
              ],
            ),
          ),
        );

        expect(captured, isNotNull);
        expect(captured!.liveConnectConfig.httpOptions?.apiVersion, 'v1beta1');
        expect(captured!.liveConnectConfig.tools, isNotNull);
        expect(captured!.liveConnectConfig.systemInstruction, isA<Content>());
        expect(connection, isA<GeminiLlmConnection>());
      },
    );
  });

  group('apigee llm parity', () {
    test('model parsing helpers follow python formats', () {
      expect(ApigeeLlm.validateModelString('apigee/gemini-2.5-flash'), isTrue);
      expect(
        ApigeeLlm.validateModelString('apigee/vertex_ai/v1/gemini-2.5-flash'),
        isTrue,
      );
      expect(ApigeeLlm.validateModelString('gemini-2.5-flash'), isFalse);
      expect(
        ApigeeLlm.identifyApiVersion('apigee/vertex_ai/v1/gemini-2.5-flash'),
        'v1',
      );
      expect(ApigeeLlm.getModelId('apigee/openai/gpt-4o-mini'), 'gpt-4o-mini');
    });

    test('chat completions payload maps config/tools', () {
      final LlmRequest request = LlmRequest(
        model: 'gpt-4o-mini',
        contents: <Content>[Content.userText('hello')],
        config: GenerateContentConfig(
          temperature: 0.2,
          topP: 0.7,
          maxOutputTokens: 256,
          stopSequences: <String>['END'],
          responseMimeType: 'application/json',
          tools: <ToolDeclaration>[
            ToolDeclaration(
              functionDeclarations: <FunctionDeclaration>[
                FunctionDeclaration(
                  name: 'weather',
                  description: 'Get weather',
                  parameters: <String, dynamic>{
                    'type': 'object',
                    'properties': <String, dynamic>{},
                  },
                ),
              ],
            ),
          ],
          toolConfig: LlmToolConfig(
            functionCallingConfig: FunctionCallingConfig(
              mode: FunctionCallingConfigMode.any,
            ),
          ),
        ),
      );
      final Map<String, Object?> payload =
          ApigeeLlm.buildChatCompletionsPayload(request, stream: false);

      expect(payload['temperature'], 0.2);
      expect(payload['top_p'], 0.7);
      expect(payload['max_tokens'], 256);
      expect(payload['tool_choice'], 'required');
      expect(payload['tools'], isA<List<Object?>>());
    });

    test('chat completions response parser maps text/tool calls/usage', () {
      final LlmResponse response = ApigeeLlm.parseChatCompletionsResponse(
        <String, Object?>{
          'model': 'gpt-4o-mini',
          'choices': <Object?>[
            <String, Object?>{
              'finish_reason': 'tool_calls',
              'message': <String, Object?>{
                'role': 'assistant',
                'content': 'answer',
                'tool_calls': <Object?>[
                  <String, Object?>{
                    'id': 'call-1',
                    'type': 'function',
                    'function': <String, Object?>{
                      'name': 'lookup',
                      'arguments': '{"q":"x"}',
                    },
                  },
                ],
              },
            },
          ],
          'usage': <String, Object?>{
            'prompt_tokens': 1,
            'completion_tokens': 2,
            'total_tokens': 3,
          },
        },
      );

      expect(response.finishReason, 'STOP');
      expect(response.content?.parts.length, 2);
      expect(response.usageMetadata, isNotNull);
    });

    test(
      'generateContent routes to chat completions client for openai models',
      () async {
        final _FakeApigeeCompletionsClient client =
            _FakeApigeeCompletionsClient();
        final ApigeeLlm model = ApigeeLlm(
          model: 'apigee/openai/gpt-4o-mini',
          proxyUrl: 'https://proxy.example.com',
          completionsClient: client,
          environment: <String, String>{},
        );
        final List<LlmResponse> responses = await model
            .generateContent(
              LlmRequest(
                model: 'apigee/openai/gpt-4o-mini',
                contents: <Content>[Content.userText('hello')],
              ),
            )
            .toList();

        expect(responses.single.content?.parts.single.text, 'apigee-result');
        expect(client.lastBaseUrl, 'https://proxy.example.com');
        expect(client.lastPayload, isNotNull);
      },
    );
  });

  group('anthropic llm parity', () {
    test('content/part conversions map tool and image blocks', () {
      expect(AnthropicLlm.toClaudeRole('model'), 'assistant');
      expect(AnthropicLlm.toGoogleFinishReason('tool_use'), 'STOP');

      final Map<String, Object?> block = AnthropicLlm.partToMessageBlock(
        Part.fromFunctionCall(
          name: 'lookup',
          args: <String, dynamic>{'q': 'x'},
        ),
      );
      expect(block['type'], 'tool_use');

      final Map<String, Object?> message = AnthropicLlm.contentToMessageParam(
        Content(role: 'user', parts: <Part>[Part.text('hello')]),
      );
      expect(message['role'], 'user');
    });

    test('message response parser produces llm response with usage', () {
      final LlmResponse response = AnthropicLlm.messageToLlmResponse(
        <String, Object?>{
          'content': <Object?>[
            <String, Object?>{'type': 'text', 'text': 'hello'},
          ],
          'usage': <String, Object?>{'input_tokens': 2, 'output_tokens': 3},
          'stop_reason': 'end_turn',
        },
      );
      expect(response.content?.parts.single.text, 'hello');
      expect(response.finishReason, 'STOP');
      expect(response.usageMetadata, isNotNull);
    });
  });

  group('lite llm parity', () {
    test('payload and parser map openai-style schema', () {
      final LlmRequest request = LlmRequest(
        model: 'openai/gpt-4o-mini',
        contents: <Content>[Content.userText('hello')],
        config: GenerateContentConfig(
          responseMimeType: 'application/json',
          stopSequences: <String>['END'],
        ),
      );
      final Map<String, Object?> payload = LiteLlm.buildPayload(
        request,
        stream: false,
      );
      expect(payload['response_format'], isNotNull);
      expect(payload['stop'], <String>['END']);

      final LlmResponse parsed = LiteLlm.parseCompletionResponse(
        <String, Object?>{
          'model': 'openai/gpt-4o-mini',
          'choices': <Object?>[
            <String, Object?>{
              'finish_reason': 'length',
              'message': <String, Object?>{
                'role': 'assistant',
                'content': 'ok',
              },
            },
          ],
          'usage': <String, Object?>{
            'prompt_tokens': 1,
            'completion_tokens': 2,
            'total_tokens': 3,
          },
        },
      );
      expect(parsed.finishReason, 'MAX_TOKENS');
      expect(parsed.content?.parts.single.text, 'ok');
    });
  });
}
