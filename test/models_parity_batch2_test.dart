import 'dart:convert';
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

    test(
      'emits standalone grounding metadata from live server content',
      () async {
        final _FakeLiveSession session = _FakeLiveSession();
        final GeminiLlmConnection connection = GeminiLlmConnection(
          model: Gemini(),
          liveSession: session,
        );
        final List<LlmResponse> responses = <LlmResponse>[];
        final StreamSubscription<LlmResponse> sub = connection.receive().listen(
          responses.add,
        );

        await connection.sendContent(Content.userText('hello'));
        session.controller.add(
          GeminiLiveSessionMessage(
            serverContent: GeminiServerContentPayload(
              groundingMetadata: <String, Object?>{
                'searchEntryPoint': <String, Object?>{
                  'renderedContent': '<p>Google</p>',
                },
              },
            ),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(responses, hasLength(1));
        expect(responses.single.groundingMetadata, isA<Map<String, Object?>>());
        expect(responses.single.content, isNull);

        await sub.cancel();
        await connection.close();
      },
    );

    test('preserves grounding metadata attached to live content', () async {
      final _FakeLiveSession session = _FakeLiveSession();
      final GeminiLlmConnection connection = GeminiLlmConnection(
        model: Gemini(),
        liveSession: session,
      );
      final List<LlmResponse> responses = <LlmResponse>[];
      final StreamSubscription<LlmResponse> sub = connection.receive().listen(
        responses.add,
      );

      await connection.sendContent(Content.userText('hello'));
      session.controller.add(
        GeminiLiveSessionMessage(
          serverContent: GeminiServerContentPayload(
            modelTurn: Content.modelText('response text'),
            groundingMetadata: <String, Object?>{
              'searchEntryPoint': <String, Object?>{
                'renderedContent': '<p>Google</p>',
              },
            },
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(responses, hasLength(1));
      expect(responses.single.content?.parts.single.text, 'response text');
      expect(responses.single.groundingMetadata, isA<Map<String, Object?>>());

      await sub.cancel();
      await connection.close();
    });

    test(
      'preserves grounding metadata after live tool call and audio payload',
      () async {
        final _FakeLiveSession session = _FakeLiveSession();
        final GeminiLlmConnection connection = GeminiLlmConnection(
          model: Gemini(),
          liveSession: session,
        );
        final List<LlmResponse> responses = <LlmResponse>[];
        final StreamSubscription<LlmResponse> sub = connection.receive().listen(
          responses.add,
        );

        await connection.sendContent(Content.userText('hello'));
        session.controller.add(
          GeminiLiveSessionMessage(
            toolCall: GeminiToolCallPayload(
              functionCalls: <FunctionCall>[
                FunctionCall(
                  name: 'enterprise_web_search',
                  args: <String, Object?>{'query': 'Google stock price today'},
                ),
              ],
            ),
          ),
        );
        session.controller.add(
          GeminiLiveSessionMessage(
            serverContent: GeminiServerContentPayload(
              modelTurn: Content(
                role: 'model',
                parts: <Part>[
                  Part.fromInlineData(
                    mimeType: 'audio/pcm',
                    data: <int>[0, 255],
                  ),
                ],
              ),
              groundingMetadata: <String, Object?>{
                'searchEntryPoint': <String, Object?>{
                  'renderedContent': '<p>Google</p>',
                },
              },
            ),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(responses, hasLength(2));
        expect(
          responses.first.content?.parts.single.functionCall?.name,
          'enterprise_web_search',
        );
        expect(responses.first.groundingMetadata, isNull);
        expect(
          responses.last.content?.parts.single.inlineData?.mimeType,
          'audio/pcm',
        );
        expect(responses.last.groundingMetadata, isA<Map<String, Object?>>());

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
            'completion_tokens_details': <String, Object?>{
              'reasoning_tokens': 4,
            },
          },
        },
      );

      expect(response.finishReason, 'STOP');
      expect(response.content?.parts.length, 2);
      expect(response.usageMetadata, isNotNull);
      expect(
        (response.usageMetadata!
            as Map<String, Object?>)['thoughts_token_count'],
        4,
      );
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

    test('function declaration tool params lowercase nested schema types', () {
      final Map<String, Object?> toolParam =
          AnthropicLlm.functionDeclarationToToolParam(
            FunctionDeclaration(
              name: 'validate_payload',
              description: 'Validates a payload with schema combinators.',
              parameters: <String, Object?>{
                'type': 'OBJECT',
                'properties': <String, Object?>{
                  'choice': <String, Object?>{
                    'oneOf': <Object?>[
                      <String, Object?>{'type': 'STRING'},
                      <String, Object?>{'type': 'INTEGER'},
                    ],
                  },
                  'config': <String, Object?>{
                    'allOf': <Object?>[
                      <String, Object?>{
                        'type': 'OBJECT',
                        'properties': <String, Object?>{
                          'enabled': <String, Object?>{'type': 'BOOLEAN'},
                        },
                      },
                    ],
                  },
                  'metadata': <String, Object?>{
                    'type': 'OBJECT',
                    'additionalProperties': <String, Object?>{'type': 'STRING'},
                  },
                  'blocked': <String, Object?>{
                    'not': <String, Object?>{'type': 'NULL'},
                  },
                },
              },
            ),
          );

      final Map<String, Object?> inputSchema =
          toolParam['input_schema']! as Map<String, Object?>;
      expect(inputSchema['type'], 'object');
      final Map<String, Object?> choice =
          (inputSchema['properties'] as Map<String, Object?>)['choice']
              as Map<String, Object?>;
      expect(choice['oneOf'], <Object?>[
        <String, Object?>{'type': 'string'},
        <String, Object?>{'type': 'integer'},
      ]);
      final Map<String, Object?> config =
          (inputSchema['properties'] as Map<String, Object?>)['config']
              as Map<String, Object?>;
      expect((config['allOf'] as List).single, <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'enabled': <String, Object?>{'type': 'boolean'},
        },
      });
      final Map<String, Object?> metadata =
          (inputSchema['properties'] as Map<String, Object?>)['metadata']
              as Map<String, Object?>;
      expect(metadata['additionalProperties'], <String, Object?>{
        'type': 'string',
      });
      final Map<String, Object?> blocked =
          (inputSchema['properties'] as Map<String, Object?>)['blocked']
              as Map<String, Object?>;
      expect(blocked['not'], <String, Object?>{'type': 'null'});
    });

    test('unknown outbound part is converted to text fallback', () {
      final Map<String, Object?> block = AnthropicLlm.partToMessageBlock(
        Part.fromFileData(
          fileUri: 'gs://bucket/sample.csv',
          mimeType: 'text/csv',
          displayName: 'sample.csv',
        ),
      );
      expect(block['type'], 'text');
      expect(
        '${block['text']}',
        contains('Unsupported anthropic part payload'),
      );
      expect('${block['text']}', contains('gs://bucket/sample.csv'));
    });

    test(
      'pdf inline data maps to document blocks and assistant turns skip it',
      () {
        final Map<String, Object?> block = AnthropicLlm.partToMessageBlock(
          Part.fromInlineData(
            mimeType: 'application/pdf; charset=binary',
            data: <int>[1, 2, 3],
            displayName: 'sample.pdf',
          ),
        );
        expect(block['type'], 'document');
        expect(
          (block['source'] as Map<String, Object?>)['media_type'],
          contains('application/pdf'),
        );

        final Map<String, Object?> assistantMessage =
            AnthropicLlm.contentToMessageParam(
              Content(
                role: 'model',
                parts: <Part>[
                  Part.fromInlineData(
                    mimeType: 'application/pdf',
                    data: <int>[7, 8, 9],
                  ),
                ],
              ),
            );
        expect(assistantMessage['role'], 'assistant');
        expect(assistantMessage['content'], isEmpty);
      },
    );

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

    test('structured tool results are serialized as JSON content', () {
      final Map<String, Object?> mapBlock = AnthropicLlm.partToMessageBlock(
        Part.fromFunctionResponse(
          name: 'search',
          id: 'tool_1',
          response: <String, dynamic>{
            'result': <String, Object?>{
              'results': <Object?>[
                <String, Object?>{
                  'id': 1,
                  'tags': <String>['a', 'b'],
                },
              ],
              'has_more': false,
            },
          },
        ),
      );
      expect(mapBlock['type'], 'tool_result');
      expect(jsonDecode('${mapBlock['content']}'), <String, Object?>{
        'results': <Object?>[
          <String, Object?>{
            'id': 1,
            'tags': <String>['a', 'b'],
          },
        ],
        'has_more': false,
      });

      final Map<String, Object?> listBlock = AnthropicLlm.partToMessageBlock(
        Part.fromFunctionResponse(
          name: 'list_tool',
          id: 'tool_2',
          response: <String, dynamic>{'result': <Object?>[]},
        ),
      );
      expect(listBlock['content'], '[]');
    });

    test('unknown inbound content blocks are preserved as text', () {
      final LlmResponse response = AnthropicLlm.messageToLlmResponse(
        <String, Object?>{
          'content': <Object?>[
            <String, Object?>{
              'type': 'thinking',
              'summary': 'token-efficient reasoning block',
            },
            'raw-non-map-block',
          ],
          'usage': <String, Object?>{'input_tokens': 1, 'output_tokens': 1},
          'stop_reason': 'end_turn',
        },
      );

      expect(response.content?.parts, hasLength(2));
      expect(
        response.content?.parts.first.text,
        contains('Unsupported anthropic content block'),
      );
      expect(response.content?.parts.last.text, 'raw-non-map-block');
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
      expect(parsed.errorCode, 'MAX_TOKENS');
      expect(parsed.errorMessage, 'Maximum tokens reached');
      expect(parsed.content?.parts.single.text, 'ok');
    });

    test('captures reasoning token usage metadata', () {
      final LlmResponse
      parsed = LiteLlm.parseCompletionResponse(<String, Object?>{
        'model': 'openai/gpt-4o-mini',
        'choices': <Object?>[
          <String, Object?>{
            'finish_reason': 'stop',
            'message': <String, Object?>{'role': 'assistant', 'content': 'ok'},
          },
        ],
        'usage': <String, Object?>{
          'prompt_tokens': 1,
          'completion_tokens': 2,
          'total_tokens': 3,
          'completion_tokens_details': <String, Object?>{'reasoning_tokens': 5},
        },
      });

      expect(parsed.usageMetadata, isA<Map<String, Object?>>());
      final Map<String, Object?> usage =
          parsed.usageMetadata! as Map<String, Object?>;
      expect(usage['thoughts_token_count'], 5);
    });

    test('parses reasoning_content and reasoning fields as thought parts', () {
      final LlmResponse parsed = LiteLlm.parseCompletionResponse(
        <String, Object?>{
          'model': 'openai/gpt-4o-mini',
          'choices': <Object?>[
            <String, Object?>{
              'finish_reason': 'stop',
              'message': <String, Object?>{
                'role': 'assistant',
                'reasoning_content': 'legacy-thought',
                'reasoning': 'new-thought',
                'content': 'final-answer',
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

      expect(parsed.content?.parts, hasLength(3));
      expect(parsed.content?.parts[0].text, 'legacy-thought');
      expect(parsed.content?.parts[0].thought, isTrue);
      expect(parsed.content?.parts[1].text, 'new-thought');
      expect(parsed.content?.parts[1].thought, isTrue);
      expect(parsed.content?.parts[2].text, 'final-answer');
      expect(parsed.content?.parts[2].thought, isFalse);
    });

    test('parses anthropic thinking_blocks as thought parts with signatures', () {
      final LlmResponse parsed = LiteLlm.parseCompletionResponse(
        <String, Object?>{
          'model': 'anthropic/claude-4-sonnet',
          'choices': <Object?>[
            <String, Object?>{
              'finish_reason': 'stop',
              'message': <String, Object?>{
                'role': 'assistant',
                'thinking_blocks': <Object?>[
                  <String, Object?>{
                    'type': 'thinking',
                    'thinking': 'step 1',
                    'signature': 'sig_one',
                  },
                  <String, Object?>{
                    'type': 'redacted',
                    'thinking': 'hidden',
                    'signature': 'sig_two',
                  },
                ],
                'content': 'done',
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

      expect(parsed.content?.parts, hasLength(2));
      expect(parsed.content?.parts.first.text, 'step 1');
      expect(parsed.content?.parts.first.thought, isTrue);
      expect(parsed.content?.parts.first.thoughtSignature, utf8.encode('sig_one'));
      expect(parsed.content?.parts.last.text, 'done');
    });

    test('builds anthropic thinking_blocks from thought parts with signatures', () {
      final Map<String, Object?> payload = LiteLlm.buildPayload(
        LlmRequest(
          model: 'anthropic/claude-4-sonnet',
          contents: <Content>[
            Content(
              role: 'model',
              parts: <Part>[
                Part.text(
                  'Let me reason...',
                  thought: true,
                ).copyWith(thoughtSignature: utf8.encode('sig_round_trip')),
                Part.text('Final answer'),
              ],
            ),
          ],
        ),
        stream: false,
      );

      final Map<String, Object?> message =
          (payload['messages'] as List<Object?>).single as Map<String, Object?>;
      expect(message['thinking_blocks'], <Object?>[
        <String, Object?>{
          'type': 'thinking',
          'thinking': 'Let me reason...',
          'signature': 'sig_round_trip',
        },
      ]);
      expect(message['content'], 'Final answer');
      expect(message.containsKey('reasoning_content'), isFalse);
    });

    test('enforces strict OpenAI schema for structured outputs', () {
      final LlmRequest request = LlmRequest(
        model: 'openai/gpt-4o-mini',
        contents: <Content>[Content.userText('hello')],
        config: GenerateContentConfig(
          responseJsonSchema: <String, Object?>{
            'title': 'MySchema',
            'type': 'object',
            'properties': <String, Object?>{
              'nested': <String, Object?>{
                'type': 'object',
                'properties': <String, Object?>{
                  'value': <String, Object?>{'type': 'string'},
                },
              },
              'refProp': <String, Object?>{
                r'$ref': r'#/$defs/Inner',
                'description': 'should be removed',
              },
            },
            r'$defs': <String, Object?>{
              'Inner': <String, Object?>{
                'type': 'object',
                'properties': <String, Object?>{
                  'id': <String, Object?>{'type': 'integer'},
                },
              },
            },
          },
        ),
      );

      final Map<String, Object?> payload = LiteLlm.buildPayload(
        request,
        stream: false,
      );
      final Map<String, Object?> responseFormat =
          payload['response_format'] as Map<String, Object?>;
      expect(responseFormat['type'], 'json_schema');
      final Map<String, Object?> jsonSchema =
          responseFormat['json_schema'] as Map<String, Object?>;
      expect(jsonSchema['name'], 'MySchema');
      expect(jsonSchema['strict'], isTrue);

      final Map<String, Object?> schema =
          jsonSchema['schema'] as Map<String, Object?>;
      expect(schema['additionalProperties'], isFalse);
      expect(schema['required'], <String>['nested', 'refProp']);

      final Map<String, Object?> nested =
          (schema['properties'] as Map<String, Object?>)['nested']
              as Map<String, Object?>;
      expect(nested['additionalProperties'], isFalse);
      expect(nested['required'], <String>['value']);

      final Map<String, Object?> refProp =
          (schema['properties'] as Map<String, Object?>)['refProp']
              as Map<String, Object?>;
      expect(refProp.keys, <String>[r'$ref']);
    });

    test('uses gemini response_schema format for gemini models', () {
      final LlmRequest request = LlmRequest(
        model: 'gemini/gemini-2.5-pro',
        contents: <Content>[Content.userText('hello')],
        config: GenerateContentConfig(
          responseJsonSchema: <String, Object?>{
            'type': 'object',
            'properties': <String, Object?>{
              'answer': <String, Object?>{'type': 'string'},
            },
          },
        ),
      );
      final Map<String, Object?> payload = LiteLlm.buildPayload(
        request,
        stream: false,
      );
      final Map<String, Object?> responseFormat =
          payload['response_format'] as Map<String, Object?>;
      expect(responseFormat['type'], 'json_object');
      expect(responseFormat['response_schema'], isA<Map<String, Object?>>());
    });

    test('preserves thought signature on tool call round trip', () {
      final List<int> thoughtSignature = <int>[1, 2, 3, 4];
      final Map<String, Object?> payload = LiteLlm.buildPayload(
        LlmRequest(
          model: 'vertex_ai/gemini-2.5-pro',
          contents: <Content>[
            Content(
              role: 'model',
              parts: <Part>[
                Part.fromFunctionCall(
                  name: 'load_skill',
                  args: <String, dynamic>{'skill': 'my_skill'},
                  id: 'call_rt',
                ).copyWith(thoughtSignature: thoughtSignature),
              ],
            ),
          ],
        ),
        stream: false,
      );

      final Map<String, Object?> message =
          (payload['messages'] as List<Object?>).single as Map<String, Object?>;
      final Map<String, Object?> toolCall =
          (message['tool_calls'] as List<Object?>).single
              as Map<String, Object?>;
      expect(toolCall['provider_specific_fields'], <String, Object?>{
        'thought_signature': base64Encode(thoughtSignature),
      });
      expect(toolCall['extra_content'], <String, Object?>{
        'google': <String, Object?>{
          'thought_signature': base64Encode(thoughtSignature),
        },
      });

      final LlmResponse parsed = LiteLlm.parseCompletionResponse(
        <String, Object?>{
          'model': 'vertex_ai/gemini-2.5-pro',
          'choices': <Object?>[
            <String, Object?>{
              'finish_reason': 'tool_calls',
              'message': <String, Object?>{
                'role': 'assistant',
                'tool_calls': <Object?>[
                  <String, Object?>{
                    'id': 'call_rt',
                    'type': 'function',
                    'function': <String, Object?>{
                      'name': 'load_skill',
                      'arguments': '{"skill":"my_skill"}',
                    },
                    'extra_content': <String, Object?>{
                      'google': <String, Object?>{
                        'thought_signature': base64Encode(thoughtSignature),
                      },
                    },
                  },
                ],
              },
            },
          ],
          'usage': <String, Object?>{
            'prompt_tokens': 0,
            'completion_tokens': 0,
            'total_tokens': 0,
          },
        },
      );

      expect(parsed.content?.parts.single.functionCall?.name, 'load_skill');
      expect(parsed.content?.parts.single.thoughtSignature, thoughtSignature);
    });
  });
}
