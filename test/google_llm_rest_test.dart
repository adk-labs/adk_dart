import 'dart:convert';

import 'package:adk_dart/src/models/gemini_rest_api_client.dart';
import 'package:adk_dart/src/models/google_llm.dart';
import 'package:adk_dart/src/models/llm_request.dart';
import 'package:adk_dart/src/models/llm_response.dart';
import 'package:adk_dart/src/types/content.dart';
import 'package:test/test.dart';

void main() {
  group('Gemini REST integration', () {
    test('non-stream requests are routed through REST transport', () async {
      final _FakeGeminiRestTransport transport = _FakeGeminiRestTransport(
        nonStreamResponse: <String, Object?>{
          'modelVersion': 'gemini-2.5-flash',
          'candidates': <Object?>[
            <String, Object?>{
              'content': <String, Object?>{
                'role': 'model',
                'parts': <Object?>[
                  <String, Object?>{'text': 'rest-result'},
                ],
              },
              'finishReason': 'STOP',
            },
          ],
          'usageMetadata': <String, Object?>{
            'promptTokenCount': 3,
            'candidatesTokenCount': 4,
            'totalTokenCount': 7,
          },
        },
      );

      final Gemini model = Gemini(
        restTransport: transport,
        environment: <String, String>{'GEMINI_API_KEY': 'test-key'},
      );

      final List<LlmResponse> responses = await model
          .generateContent(
            LlmRequest(
              model: 'gemini-2.5-flash',
              contents: <Content>[Content.userText('hello')],
              config: GenerateContentConfig(
                temperature: 0.2,
                topK: 32,
                responseMimeType: 'application/json',
                tools: <ToolDeclaration>[
                  ToolDeclaration(
                    functionDeclarations: <FunctionDeclaration>[
                      FunctionDeclaration(
                        name: 'lookup',
                        description: 'lookup data',
                        parameters: <String, dynamic>{
                          'type': 'object',
                          'properties': <String, dynamic>{
                            'q': <String, dynamic>{'type': 'string'},
                          },
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          )
          .toList();

      expect(transport.generateContentCallCount, 1);
      expect(transport.streamGenerateContentCallCount, 0);
      expect(transport.lastApiKey, 'test-key');
      expect(transport.lastModel, 'gemini-2.5-flash');
      expect(transport.lastPayload?['contents'], isA<List<Object?>>());
      expect(
        transport.lastPayload?['generationConfig'],
        isA<Map<String, Object?>>(),
      );
      expect(
        (transport.lastPayload?['generationConfig']
            as Map<String, Object?>?)?['topK'],
        32,
      );
      expect(responses.single.content?.parts.single.text, 'rest-result');
      expect(responses.single.finishReason, 'STOP');
      expect(responses.single.usageMetadata, isA<Map<String, Object?>>());
    });

    test('throws when API key is missing', () async {
      final _FakeGeminiRestTransport transport = _FakeGeminiRestTransport(
        nonStreamResponse: <String, Object?>{
          'candidates': <Object?>[
            <String, Object?>{
              'content': <String, Object?>{
                'role': 'model',
                'parts': <Object?>[
                  <String, Object?>{'text': 'should-not-be-used'},
                ],
              },
            },
          ],
        },
      );
      final Gemini model = Gemini(
        restTransport: transport,
        environment: const <String, String>{},
      );

      await expectLater(
        model
            .generateContent(
              LlmRequest(
                model: 'gemini-2.5-flash',
                contents: <Content>[Content.userText('hello')],
              ),
            )
            .toList(),
        throwsA(
          isA<StateError>().having(
            (StateError error) => '${error.message}',
            'message',
            contains('GEMINI_API_KEY or GOOGLE_API_KEY'),
          ),
        ),
      );
      expect(transport.generateContentCallCount, 0);
      expect(transport.streamGenerateContentCallCount, 0);
    });

    test(
      'stream requests emit partial responses from REST transport',
      () async {
        final _FakeGeminiRestTransport transport = _FakeGeminiRestTransport(
          streamResponses: <Map<String, Object?>>[
            <String, Object?>{
              'candidates': <Object?>[
                <String, Object?>{
                  'content': <String, Object?>{
                    'role': 'model',
                    'parts': <Object?>[
                      <String, Object?>{'text': 'Hel'},
                    ],
                  },
                },
              ],
            },
            <String, Object?>{
              'candidates': <Object?>[
                <String, Object?>{
                  'content': <String, Object?>{
                    'role': 'model',
                    'parts': <Object?>[
                      <String, Object?>{'text': 'lo'},
                    ],
                  },
                  'finishReason': 'STOP',
                },
              ],
            },
          ],
        );

        final Gemini model = Gemini(
          restTransport: transport,
          environment: <String, String>{'GEMINI_API_KEY': 'test-key'},
        );

        final List<LlmResponse> responses = await model
            .generateContent(
              LlmRequest(
                model: 'gemini-2.5-flash',
                contents: <Content>[Content.userText('hello')],
              ),
              stream: true,
            )
            .toList();

        expect(transport.generateContentCallCount, 0);
        expect(transport.streamGenerateContentCallCount, 1);
        expect(responses, hasLength(3));
        expect(responses.first.partial, isTrue);
        expect(responses.first.turnComplete, isFalse);
        expect(responses.first.content?.parts.single.text, 'Hel');
        expect(responses[1].partial, isTrue);
        expect(responses[1].turnComplete, isTrue);
        expect(responses[1].content?.parts.single.text, 'lo');
        expect(responses[1].finishReason, 'STOP');
        expect(responses[2].partial, isFalse);
        expect(responses[2].turnComplete, isTrue);
        expect(responses[2].content?.parts.single.text, 'Hello');
        expect(responses[2].finishReason, 'STOP');
      },
    );

    test(
      'serializes thought signatures and function call streaming fields in request payload',
      () async {
        final _FakeGeminiRestTransport transport = _FakeGeminiRestTransport(
          nonStreamResponse: <String, Object?>{
            'modelVersion': 'gemini-2.5-flash',
            'candidates': <Object?>[
              <String, Object?>{
                'content': <String, Object?>{
                  'role': 'model',
                  'parts': <Object?>[
                    <String, Object?>{'text': 'ok'},
                  ],
                },
                'finishReason': 'STOP',
              },
            ],
          },
        );
        final Gemini model = Gemini(
          restTransport: transport,
          environment: <String, String>{'GEMINI_API_KEY': 'test-key'},
        );

        final Part signedThought = Part.text(
          'chain-of-thought',
          thought: true,
          thoughtSignature: <int>[1, 2, 3, 4],
        );
        final Part functionCall = Part.fromFunctionCall(
          name: 'lookup_city',
          args: <String, dynamic>{'city': 'Seoul'},
          partialArgs: <Map<String, Object?>>[
            <String, Object?>{'json_path': r'$.city', 'string_value': 'Seoul'},
          ],
          willContinue: false,
          thoughtSignature: <int>[9, 8, 7],
        );

        await model
            .generateContent(
              LlmRequest(
                model: 'gemini-2.5-flash',
                contents: <Content>[
                  Content(
                    role: 'model',
                    parts: <Part>[signedThought, functionCall],
                  ),
                ],
              ),
            )
            .toList();

        final List<Object?> contents =
            transport.lastPayload?['contents'] as List<Object?>;
        final Map<String, Object?> modelTurn = contents
            .map((Object? value) => value as Map<String, Object?>)
            .firstWhere(
              (Map<String, Object?> value) => value['role'] == 'model',
            );
        final List<Object?> parts = modelTurn['parts'] as List<Object?>;
        final Map<String, Object?> thoughtPart =
            parts.first as Map<String, Object?>;
        final Map<String, Object?> functionPart =
            parts[1] as Map<String, Object?>;

        expect(
          thoughtPart['thoughtSignature'],
          base64Encode(<int>[1, 2, 3, 4]),
        );
        expect(
          (functionPart['functionCall'] as Map<String, Object?>)['partialArgs'],
          isA<List<Object?>>(),
        );
        expect(
          (functionPart['functionCall']
              as Map<String, Object?>)['willContinue'],
          isFalse,
        );
        expect(functionPart['thoughtSignature'], base64Encode(<int>[9, 8, 7]));
      },
    );

    test(
      'parses grounding metadata and thought signature from response',
      () async {
        final _FakeGeminiRestTransport transport = _FakeGeminiRestTransport(
          nonStreamResponse: <String, Object?>{
            'interactionId': 'ix-1',
            'candidates': <Object?>[
              <String, Object?>{
                'content': <String, Object?>{
                  'role': 'model',
                  'parts': <Object?>[
                    <String, Object?>{
                      'text': 'reasoning',
                      'thought': true,
                      'thoughtSignature': base64Encode(<int>[5, 6, 7]),
                    },
                    <String, Object?>{
                      'functionCall': <String, Object?>{
                        'name': 'check_weather',
                        'args': <String, Object?>{
                          'city': 'Seoul',
                          'partial_args': <Object?>[
                            <String, Object?>{
                              'json_path': r'$.city',
                              'string_value': 'Seoul',
                            },
                          ],
                          'will_continue': true,
                        },
                        'id': 'call-1',
                      },
                      'thoughtSignature': base64Encode(<int>[8, 8, 8]),
                    },
                  ],
                },
                'finishReason': 'STOP',
                'groundingMetadata': <String, Object?>{
                  'searchEntryPoint': <String, Object?>{
                    'renderedContent': '<div>grounded</div>',
                  },
                },
              },
            ],
          },
        );

        final Gemini model = Gemini(
          restTransport: transport,
          environment: <String, String>{'GEMINI_API_KEY': 'test-key'},
        );
        final LlmResponse response =
            (await model
                    .generateContent(
                      LlmRequest(
                        model: 'gemini-2.5-flash',
                        contents: <Content>[Content.userText('hello')],
                      ),
                    )
                    .toList())
                .single;

        expect(response.interactionId, 'ix-1');
        expect(response.groundingMetadata, isA<Map<String, Object?>>());
        expect(response.content?.parts.first.thoughtSignature, <int>[5, 6, 7]);
        expect(response.content?.parts[1].thoughtSignature, <int>[8, 8, 8]);
        expect(
          response.content?.parts[1].functionCall?.partialArgs,
          isA<List<Map<String, Object?>>>(),
        );
        expect(response.content?.parts[1].functionCall?.willContinue, isTrue);
      },
    );

    test(
      'does not synthesize interaction id from previous interaction id',
      () async {
        final _FakeGeminiRestTransport transport = _FakeGeminiRestTransport(
          nonStreamResponse: <String, Object?>{
            'candidates': <Object?>[
              <String, Object?>{
                'content': <String, Object?>{
                  'role': 'model',
                  'parts': <Object?>[
                    <String, Object?>{'text': 'ok'},
                  ],
                },
                'finishReason': 'STOP',
              },
            ],
          },
        );
        final Gemini model = Gemini(
          restTransport: transport,
          environment: <String, String>{'GEMINI_API_KEY': 'test-key'},
        );
        final LlmResponse response =
            (await model
                    .generateContent(
                      LlmRequest(
                        model: 'gemini-2.5-flash',
                        previousInteractionId: 'previous-id',
                        contents: <Content>[Content.userText('hello')],
                      ),
                    )
                    .toList())
                .single;

        expect(response.interactionId, isNull);
      },
    );

    test(
      'routes interactions API calls through interactions endpoint',
      () async {
        final _FakeGeminiRestTransport transport = _FakeGeminiRestTransport(
          interactionResponse: <String, Object?>{
            'id': 'interaction-2',
            'status': 'completed',
            'outputs': <Object?>[
              <String, Object?>{'type': 'text', 'text': 'interactions-result'},
            ],
            'usage': <String, Object?>{
              'total_input_tokens': 3,
              'total_output_tokens': 5,
            },
          },
        );
        final Gemini model = Gemini(
          useInteractionsApi: true,
          restTransport: transport,
          environment: <String, String>{'GEMINI_API_KEY': 'test-key'},
        );

        final List<LlmResponse> responses = await model
            .generateContent(
              LlmRequest(
                model: 'gemini-2.5-flash',
                previousInteractionId: 'interaction-1',
                contents: <Content>[
                  Content.modelText('call_tool'),
                  Content.userText('tool result'),
                ],
              ),
            )
            .toList();

        expect(transport.createInteractionCallCount, 1);
        expect(transport.generateContentCallCount, 0);
        expect(
          transport.lastInteractionPayload?['previous_interaction_id'],
          'interaction-1',
        );
        expect(responses, hasLength(1));
        expect(
          responses.single.content?.parts.single.text,
          'interactions-result',
        );
        expect(responses.single.interactionId, 'interaction-2');
        expect(responses.single.turnComplete, isTrue);
        expect(responses.single.finishReason, 'STOP');
      },
    );

    test('forwards retry options to REST transport', () async {
      final _FakeGeminiRestTransport transport = _FakeGeminiRestTransport(
        nonStreamResponse: <String, Object?>{
          'candidates': <Object?>[
            <String, Object?>{
              'content': <String, Object?>{
                'role': 'model',
                'parts': <Object?>[
                  <String, Object?>{'text': 'ok'},
                ],
              },
              'finishReason': 'STOP',
            },
          ],
        },
      );
      final Gemini model = Gemini(
        restTransport: transport,
        retryOptions: HttpRetryOptions(
          attempts: 4,
          initialDelay: 1.5,
          maxDelay: 20.0,
          expBase: 2.5,
          httpStatusCodes: <int>[429, 500],
        ),
        environment: <String, String>{'GEMINI_API_KEY': 'test-key'},
      );

      await model
          .generateContent(
            LlmRequest(
              model: 'gemini-2.5-flash',
              contents: <Content>[Content.userText('hello')],
            ),
          )
          .toList();
      expect(transport.lastRetryOptions?.attempts, 4);
      expect(transport.lastRetryOptions?.httpStatusCodes, <int>[429, 500]);

      await model
          .generateContent(
            LlmRequest(
              model: 'gemini-2.5-flash',
              contents: <Content>[Content.userText('hello')],
              config: GenerateContentConfig(
                httpOptions: HttpOptions(
                  retryOptions: HttpRetryOptions(attempts: 2),
                ),
              ),
            ),
          )
          .toList();
      expect(transport.lastRetryOptions?.attempts, 2);
    });

    test('serializes built-in Gemini tools in REST payload', () async {
      final _FakeGeminiRestTransport transport = _FakeGeminiRestTransport(
        nonStreamResponse: <String, Object?>{
          'candidates': <Object?>[
            <String, Object?>{
              'content': <String, Object?>{
                'role': 'model',
                'parts': <Object?>[
                  <String, Object?>{'text': 'ok'},
                ],
              },
              'finishReason': 'STOP',
            },
          ],
        },
      );
      final Gemini model = Gemini(
        restTransport: transport,
        environment: <String, String>{'GEMINI_API_KEY': 'test-key'},
      );

      await model
          .generateContent(
            LlmRequest(
              model: 'gemini-2.5-flash',
              contents: <Content>[Content.userText('hello')],
              config: GenerateContentConfig(
                tools: <ToolDeclaration>[
                  ToolDeclaration(googleSearch: const <String, Object?>{}),
                  ToolDeclaration(urlContext: const <String, Object?>{}),
                  ToolDeclaration(codeExecution: const <String, Object?>{}),
                  ToolDeclaration(
                    enterpriseWebSearch: const <String, Object?>{},
                  ),
                  ToolDeclaration(googleMaps: const <String, Object?>{}),
                  ToolDeclaration(
                    retrieval: <String, Object?>{
                      'vertexAiSearch': <String, Object?>{
                        'engine': 'engines/e',
                      },
                    },
                  ),
                  ToolDeclaration(
                    computerUse: <String, Object?>{
                      'environment': 'ENVIRONMENT_BROWSER',
                    },
                  ),
                ],
              ),
            ),
          )
          .toList();

      final List<Object?> tools =
          transport.lastPayload?['tools'] as List<Object?>;
      expect(
        tools.any(
          (Object? tool) =>
              (tool as Map<String, Object?>).containsKey('googleSearch'),
        ),
        isTrue,
      );
      expect(
        tools.any(
          (Object? tool) =>
              (tool as Map<String, Object?>).containsKey('urlContext'),
        ),
        isTrue,
      );
      expect(
        tools.any(
          (Object? tool) =>
              (tool as Map<String, Object?>).containsKey('codeExecution'),
        ),
        isTrue,
      );
      expect(
        tools.any(
          (Object? tool) =>
              (tool as Map<String, Object?>).containsKey('enterpriseWebSearch'),
        ),
        isTrue,
      );
      expect(
        tools.any(
          (Object? tool) =>
              (tool as Map<String, Object?>).containsKey('googleMaps'),
        ),
        isTrue,
      );
      expect(
        tools.any(
          (Object? tool) =>
              (tool as Map<String, Object?>).containsKey('retrieval'),
        ),
        isTrue,
      );
      expect(
        tools.any(
          (Object? tool) =>
              (tool as Map<String, Object?>).containsKey('computerUse'),
        ),
        isTrue,
      );
    });

    test(
      'converts interactions built-in tools to interactions tool types',
      () async {
        final _FakeGeminiRestTransport transport = _FakeGeminiRestTransport(
          interactionResponse: <String, Object?>{
            'id': 'ix-tools',
            'status': 'completed',
            'outputs': <Object?>[
              <String, Object?>{'type': 'text', 'text': 'ok'},
            ],
          },
        );
        final Gemini model = Gemini(
          useInteractionsApi: true,
          restTransport: transport,
          environment: <String, String>{'GEMINI_API_KEY': 'test-key'},
        );

        await model
            .generateContent(
              LlmRequest(
                model: 'gemini-2.5-flash',
                contents: <Content>[Content.userText('hello')],
                config: GenerateContentConfig(
                  tools: <ToolDeclaration>[
                    ToolDeclaration(
                      googleSearch: const <String, Object?>{},
                      urlContext: const <String, Object?>{},
                      codeExecution: const <String, Object?>{},
                      computerUse: const <String, Object?>{},
                    ),
                  ],
                ),
              ),
            )
            .toList();

        final List<Object?> tools =
            transport.lastInteractionPayload?['tools'] as List<Object?>;
        expect(
          tools.map((Object? item) => (item as Map<String, Object?>)['type']),
          containsAll(<String>[
            'google_search',
            'url_context',
            'code_execution',
            'computer_use',
          ]),
        );
      },
    );
  });
}

class _FakeGeminiRestTransport implements GeminiRestTransport {
  _FakeGeminiRestTransport({
    this.nonStreamResponse,
    List<Map<String, Object?>>? streamResponses,
    this.interactionResponse,
    List<Map<String, Object?>>? interactionStreamResponses,
  }) : _streamResponses = streamResponses ?? const <Map<String, Object?>>[],
       _interactionStreamResponses =
           interactionStreamResponses ?? const <Map<String, Object?>>[];

  final Map<String, Object?>? nonStreamResponse;
  final List<Map<String, Object?>> _streamResponses;
  final Map<String, Object?>? interactionResponse;
  final List<Map<String, Object?>> _interactionStreamResponses;

  int generateContentCallCount = 0;
  int streamGenerateContentCallCount = 0;
  int createInteractionCallCount = 0;
  int streamCreateInteractionCallCount = 0;
  String? lastModel;
  String? lastApiKey;
  Map<String, Object?>? lastPayload;
  Map<String, Object?>? lastInteractionPayload;
  String? lastApiVersion;
  String? lastBaseUrl;
  Map<String, String>? lastHeaders;
  HttpRetryOptions? lastRetryOptions;

  @override
  Future<Map<String, Object?>> generateContent({
    required String model,
    required String apiKey,
    required Map<String, Object?> payload,
    String? baseUrl,
    String apiVersion = 'v1beta',
    Map<String, String>? headers,
    HttpRetryOptions? retryOptions,
  }) async {
    generateContentCallCount += 1;
    lastModel = model;
    lastApiKey = apiKey;
    lastPayload = payload;
    lastApiVersion = apiVersion;
    lastBaseUrl = baseUrl;
    lastHeaders = headers;
    lastRetryOptions = retryOptions;
    return nonStreamResponse ?? <String, Object?>{};
  }

  @override
  Stream<Map<String, Object?>> streamGenerateContent({
    required String model,
    required String apiKey,
    required Map<String, Object?> payload,
    String? baseUrl,
    String apiVersion = 'v1beta',
    Map<String, String>? headers,
    HttpRetryOptions? retryOptions,
  }) async* {
    streamGenerateContentCallCount += 1;
    lastModel = model;
    lastApiKey = apiKey;
    lastPayload = payload;
    lastApiVersion = apiVersion;
    lastBaseUrl = baseUrl;
    lastHeaders = headers;
    lastRetryOptions = retryOptions;
    for (final Map<String, Object?> chunk in _streamResponses) {
      yield chunk;
    }
  }

  @override
  Future<Map<String, Object?>> createInteraction({
    required String apiKey,
    required Map<String, Object?> payload,
    String? baseUrl,
    String apiVersion = 'v1beta',
    Map<String, String>? headers,
    HttpRetryOptions? retryOptions,
  }) async {
    createInteractionCallCount += 1;
    lastApiKey = apiKey;
    lastInteractionPayload = payload;
    lastApiVersion = apiVersion;
    lastBaseUrl = baseUrl;
    lastHeaders = headers;
    lastRetryOptions = retryOptions;
    return interactionResponse ?? <String, Object?>{};
  }

  @override
  Stream<Map<String, Object?>> streamCreateInteraction({
    required String apiKey,
    required Map<String, Object?> payload,
    String? baseUrl,
    String apiVersion = 'v1beta',
    Map<String, String>? headers,
    HttpRetryOptions? retryOptions,
  }) async* {
    streamCreateInteractionCallCount += 1;
    lastApiKey = apiKey;
    lastInteractionPayload = payload;
    lastApiVersion = apiVersion;
    lastBaseUrl = baseUrl;
    lastHeaders = headers;
    lastRetryOptions = retryOptions;
    for (final Map<String, Object?> chunk in _interactionStreamResponses) {
      yield chunk;
    }
  }
}
