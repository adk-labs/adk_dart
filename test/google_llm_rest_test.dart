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
  });
}

class _FakeGeminiRestTransport implements GeminiRestTransport {
  _FakeGeminiRestTransport({
    this.nonStreamResponse,
    List<Map<String, Object?>>? streamResponses,
  }) : _streamResponses = streamResponses ?? const <Map<String, Object?>>[];

  final Map<String, Object?>? nonStreamResponse;
  final List<Map<String, Object?>> _streamResponses;

  int generateContentCallCount = 0;
  int streamGenerateContentCallCount = 0;
  String? lastModel;
  String? lastApiKey;
  Map<String, Object?>? lastPayload;
  String? lastApiVersion;
  String? lastBaseUrl;
  Map<String, String>? lastHeaders;

  @override
  Future<Map<String, Object?>> generateContent({
    required String model,
    required String apiKey,
    required Map<String, Object?> payload,
    String? baseUrl,
    String apiVersion = 'v1beta',
    Map<String, String>? headers,
  }) async {
    generateContentCallCount += 1;
    lastModel = model;
    lastApiKey = apiKey;
    lastPayload = payload;
    lastApiVersion = apiVersion;
    lastBaseUrl = baseUrl;
    lastHeaders = headers;
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
  }) async* {
    streamGenerateContentCallCount += 1;
    lastModel = model;
    lastApiKey = apiKey;
    lastPayload = payload;
    lastApiVersion = apiVersion;
    lastBaseUrl = baseUrl;
    lastHeaders = headers;
    for (final Map<String, Object?> chunk in _streamResponses) {
      yield chunk;
    }
  }
}
