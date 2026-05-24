import 'dart:async';
import 'dart:convert';

import 'package:adk_dart/adk_dart.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

void main() {
  group('ChatCompletionsHttpClient', () {
    test('posts non-streaming chat completions payload', () async {
      late Map<String, Object?> capturedPayload;
      late Map<String, String> capturedHeaders;
      final ChatCompletionsHttpClient client = ChatCompletionsHttpClient(
        httpClient: _FakeHttpClient((http.BaseRequest request) async {
          capturedHeaders = Map<String, String>.from(request.headers);
          capturedPayload =
              jsonDecode((request as http.Request).body)
                  as Map<String, Object?>;
          return _jsonResponse(request, <String, Object?>{
            'id': 'chatcmpl-1',
            'model': 'gpt-4o-mini',
            'choices': <Object?>[
              <String, Object?>{
                'finish_reason': 'stop',
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
          });
        }),
      );

      final List<LlmResponse> responses = await client
          .generateContent(
            request: LlmRequest(
              model: 'gpt-4o-mini',
              contents: <Content>[Content.userText('hello')],
            ),
            stream: false,
            baseUrl: 'https://api.example.test/v1/chat/completions',
            headers: <String, String>{'Authorization': 'Bearer test'},
          )
          .toList();

      expect(capturedPayload['model'], 'gpt-4o-mini');
      expect(capturedPayload['stream'], isFalse);
      expect(capturedHeaders['Authorization'], 'Bearer test');
      expect(capturedHeaders['Content-Type'], 'application/json');
      expect(responses.single.content?.parts.single.text, 'ok');
      expect(responses.single.finishReason, 'STOP');
    });

    test('parses streaming SSE deltas and emits final response', () async {
      final ChatCompletionsHttpClient client = ChatCompletionsHttpClient(
        httpClient: _FakeHttpClient((http.BaseRequest request) async {
          expect(request.headers['Accept'], 'text/event-stream');
          return _sseResponse(request, <String>[
            _sse(<String, Object?>{
              'id': 'chatcmpl-2',
              'model': 'gpt-4o-mini',
              'choices': <Object?>[
                <String, Object?>{
                  'delta': <String, Object?>{
                    'role': 'assistant',
                    'content': 'Hel',
                  },
                },
              ],
            }),
            _sse(<String, Object?>{
              'id': 'chatcmpl-2',
              'model': 'gpt-4o-mini',
              'choices': <Object?>[
                <String, Object?>{
                  'delta': <String, Object?>{'content': 'lo'},
                },
              ],
            }),
            _sse(<String, Object?>{
              'id': 'chatcmpl-2',
              'model': 'gpt-4o-mini',
              'choices': <Object?>[
                <String, Object?>{
                  'delta': <String, Object?>{},
                  'finish_reason': 'stop',
                },
              ],
              'usage': <String, Object?>{
                'prompt_tokens': 1,
                'completion_tokens': 1,
                'total_tokens': 2,
              },
            }),
            'data: [DONE]\n\n',
          ]);
        }),
      );

      final List<LlmResponse> responses = await client
          .generateContent(
            request: LlmRequest(
              model: 'gpt-4o-mini',
              contents: <Content>[Content.userText('hello')],
            ),
            stream: true,
            baseUrl: 'https://api.example.test/v1/chat/completions',
            headers: const <String, String>{},
          )
          .toList();

      expect(
        responses.where((LlmResponse value) => value.partial == true),
        hasLength(3),
      );
      expect(responses.last.turnComplete, isTrue);
      expect(responses.last.content?.parts.single.text, 'Hello');
      expect(responses.last.usageMetadata, isA<Map<String, Object?>>());
    });

    test('accumulates streaming tool call arguments', () async {
      final ChatCompletionsHttpClient client = ChatCompletionsHttpClient(
        httpClient: _FakeHttpClient((http.BaseRequest request) async {
          return _sseResponse(request, <String>[
            _sse(<String, Object?>{
              'model': 'gpt-4o-mini',
              'choices': <Object?>[
                <String, Object?>{
                  'delta': <String, Object?>{
                    'role': 'assistant',
                    'tool_calls': <Object?>[
                      <String, Object?>{
                        'index': 0,
                        'id': 'call-1',
                        'type': 'function',
                        'function': <String, Object?>{
                          'name': 'lookup',
                          'arguments': '{"q"',
                        },
                      },
                    ],
                  },
                },
              ],
            }),
            _sse(<String, Object?>{
              'model': 'gpt-4o-mini',
              'choices': <Object?>[
                <String, Object?>{
                  'delta': <String, Object?>{
                    'tool_calls': <Object?>[
                      <String, Object?>{
                        'index': 0,
                        'function': <String, Object?>{'arguments': ':"x"}'},
                      },
                    ],
                  },
                  'finish_reason': 'tool_calls',
                },
              ],
            }),
          ]);
        }),
      );

      final List<LlmResponse> responses = await client
          .generateContent(
            request: LlmRequest(
              model: 'gpt-4o-mini',
              contents: <Content>[Content.userText('hello')],
            ),
            stream: true,
            baseUrl: 'https://api.example.test/v1/chat/completions',
            headers: const <String, String>{},
          )
          .toList();

      final FunctionCall call = responses.last.getFunctionCalls().single;
      expect(call.id, 'call-1');
      expect(call.name, 'lookup');
      expect(call.args, <String, dynamic>{'q': 'x'});
      expect(responses.last.finishReason, 'STOP');
    });
  });
}

typedef _RequestHandler =
    FutureOr<http.StreamedResponse> Function(http.BaseRequest request);

class _FakeHttpClient extends http.BaseClient {
  _FakeHttpClient(this._handler);

  final _RequestHandler _handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return _handler(request);
  }
}

http.StreamedResponse _jsonResponse(
  http.BaseRequest request,
  Map<String, Object?> payload, {
  int statusCode = 200,
}) {
  return http.StreamedResponse(
    Stream<List<int>>.value(utf8.encode(jsonEncode(payload))),
    statusCode,
    request: request,
    headers: const <String, String>{'content-type': 'application/json'},
  );
}

http.StreamedResponse _sseResponse(
  http.BaseRequest request,
  List<String> chunks,
) {
  return http.StreamedResponse(
    Stream<List<int>>.fromIterable(chunks.map(utf8.encode)),
    200,
    request: request,
    headers: const <String, String>{'content-type': 'text/event-stream'},
  );
}

String _sse(Map<String, Object?> payload) {
  return 'data: ${jsonEncode(payload)}\n\n';
}
