import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:adk_dart/src/models/gemini_rest_api_client.dart';
import 'package:adk_dart/src/models/llm_request.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

void main() {
  group('GeminiRestHttpTransport', () {
    test(
      'retries failed non-stream calls when retry options are configured',
      () async {
        final _SequencedClient client = _SequencedClient(
          responses: <http.StreamedResponse>[
            _jsonResponse(
              statusCode: 500,
              payload: <String, Object?>{
                'error': <String, Object?>{'message': 'temporary'},
              },
            ),
            _jsonResponse(
              statusCode: 200,
              payload: <String, Object?>{
                'candidates': <Object?>[
                  <String, Object?>{
                    'content': <String, Object?>{
                      'parts': <Object?>[
                        <String, Object?>{'text': 'ok'},
                      ],
                    },
                    'finishReason': 'STOP',
                  },
                ],
              },
            ),
          ],
        );
        final GeminiRestHttpTransport transport = GeminiRestHttpTransport(
          httpClient: client,
        );

        final Map<String, Object?> response = await transport.generateContent(
          model: 'gemini-2.5-flash',
          apiKey: 'test-key',
          payload: <String, Object?>{
            'contents': <Object?>[
              <String, Object?>{
                'parts': <Object?>[
                  <String, Object?>{'text': 'hello'},
                ],
              },
            ],
          },
          retryOptions: HttpRetryOptions(
            attempts: 2,
            initialDelay: 0,
            maxDelay: 0,
            expBase: 1,
            httpStatusCodes: <int>[500],
          ),
        );

        expect(response, isA<Map<String, Object?>>());
        expect(client.requestCount, 2);
      },
    );

    test(
      'keeps required headers authoritative when custom headers conflict',
      () async {
        final _SequencedClient client = _SequencedClient(
          responses: <http.StreamedResponse>[
            _jsonResponse(
              statusCode: 200,
              payload: <String, Object?>{
                'candidates': <Object?>[
                  <String, Object?>{
                    'content': <String, Object?>{
                      'parts': <Object?>[
                        <String, Object?>{'text': 'ok'},
                      ],
                    },
                    'finishReason': 'STOP',
                  },
                ],
              },
            ),
          ],
        );
        final GeminiRestHttpTransport transport = GeminiRestHttpTransport(
          httpClient: client,
        );

        await transport.generateContent(
          model: 'gemini-2.5-flash',
          apiKey: 'transport-api-key',
          payload: <String, Object?>{
            'contents': <Object?>[
              <String, Object?>{
                'parts': <Object?>[
                  <String, Object?>{'text': 'hello'},
                ],
              },
            ],
          },
          headers: <String, String>{
            'content-type': 'text/plain',
            'Content-Type': 'text/plain',
            'x-goog-api-key': 'custom-key',
            'X-Goog-Api-Key': 'custom-key-uppercase',
            'x-custom-header': 'custom-value',
          },
        );

        final Map<String, String>? requestHeaders = client.lastRequestHeaders;
        expect(requestHeaders, isNotNull);
        expect(requestHeaders!['content-type'], 'application/json');
        expect(requestHeaders['x-goog-api-key'], 'transport-api-key');
        expect(requestHeaders['x-custom-header'], 'custom-value');
      },
    );

    test('preserves caller-provided accept header for stream requests', () async {
      final _SequencedClient client = _SequencedClient(
        responses: <http.StreamedResponse>[
          http.StreamedResponse(
            Stream<List<int>>.fromIterable(<List<int>>[
              utf8.encode(
                'data: {"candidates":[{"content":{"parts":[{"text":"ok"}]},"finishReason":"STOP"}]}\n\n',
              ),
            ]),
            200,
            headers: <String, String>{'content-type': 'text/event-stream'},
          ),
        ],
      );
      final GeminiRestHttpTransport transport = GeminiRestHttpTransport(
        httpClient: client,
      );

      await transport
          .streamGenerateContent(
            model: 'gemini-2.5-flash',
            apiKey: 'test-key',
            payload: <String, Object?>{
              'contents': <Object?>[
                <String, Object?>{
                  'parts': <Object?>[
                    <String, Object?>{'text': 'hello'},
                  ],
                },
              ],
            },
            headers: <String, String>{'Accept': 'application/custom-sse'},
          )
          .toList();

      final Map<String, String>? requestHeaders = client.lastRequestHeaders;
      expect(requestHeaders, isNotNull);
      expect(requestHeaders!['accept'], 'application/custom-sse');
    });

    test('throws a clear error when non-stream JSON is malformed', () async {
      final _SequencedClient client = _SequencedClient(
        responses: <http.StreamedResponse>[
          _bytesResponse(
            statusCode: 200,
            bodyBytes: utf8.encode('{"candidates": [}'),
          ),
        ],
      );
      final GeminiRestHttpTransport transport = GeminiRestHttpTransport(
        httpClient: client,
      );

      await expectLater(
        transport.generateContent(
          model: 'gemini-2.5-flash',
          apiKey: 'test-key',
          payload: <String, Object?>{
            'contents': <Object?>[
              <String, Object?>{
                'parts': <Object?>[
                  <String, Object?>{'text': 'hello'},
                ],
              },
            ],
          },
        ),
        throwsA(
          isA<GeminiRestApiException>().having(
            (GeminiRestApiException error) => error.message,
            'message',
            contains('not valid JSON'),
          ),
        ),
      );
    });

    test('retries stream connection failures before first chunk', () async {
      final _SequencedClient client = _SequencedClient(
        responses: <http.StreamedResponse>[
          _jsonResponse(
            statusCode: 503,
            payload: <String, Object?>{
              'error': <String, Object?>{'message': 'unavailable'},
            },
          ),
          http.StreamedResponse(
            Stream<List<int>>.fromIterable(<List<int>>[
              utf8.encode(
                'data: {"candidates":[{"content":{"parts":[{"text":"ok"}]},"finishReason":"STOP"}]}\n\n',
              ),
            ]),
            200,
            headers: <String, String>{'content-type': 'text/event-stream'},
          ),
        ],
      );
      final GeminiRestHttpTransport transport = GeminiRestHttpTransport(
        httpClient: client,
      );

      final List<Map<String, Object?>> chunks = await transport
          .streamGenerateContent(
            model: 'gemini-2.5-flash',
            apiKey: 'test-key',
            payload: <String, Object?>{
              'contents': <Object?>[
                <String, Object?>{
                  'parts': <Object?>[
                    <String, Object?>{'text': 'hello'},
                  ],
                },
              ],
            },
            retryOptions: HttpRetryOptions(
              attempts: 2,
              initialDelay: 0,
              maxDelay: 0,
              expBase: 1,
              httpStatusCodes: <int>[503],
            ),
          )
          .toList();

      expect(chunks, hasLength(1));
      expect(client.requestCount, 2);
    });

    test(
      'retries stream HTTP errors even when error body contains invalid UTF-8',
      () async {
        final _SequencedClient client = _SequencedClient(
          responses: <http.StreamedResponse>[
            _bytesResponse(statusCode: 503, bodyBytes: <int>[0xc3, 0x28]),
            http.StreamedResponse(
              Stream<List<int>>.fromIterable(<List<int>>[
                utf8.encode(
                  'data: {"candidates":[{"content":{"parts":[{"text":"ok"}]},"finishReason":"STOP"}]}\n\n',
                ),
              ]),
              200,
              headers: <String, String>{'content-type': 'text/event-stream'},
            ),
          ],
        );
        final GeminiRestHttpTransport transport = GeminiRestHttpTransport(
          httpClient: client,
        );

        final List<Map<String, Object?>> chunks = await transport
            .streamGenerateContent(
              model: 'gemini-2.5-flash',
              apiKey: 'test-key',
              payload: <String, Object?>{
                'contents': <Object?>[
                  <String, Object?>{
                    'parts': <Object?>[
                      <String, Object?>{'text': 'hello'},
                    ],
                  },
                ],
              },
              retryOptions: HttpRetryOptions(
                attempts: 2,
                initialDelay: 0,
                maxDelay: 0,
                expBase: 1,
                httpStatusCodes: <int>[503],
              ),
            )
            .toList();

        expect(chunks, hasLength(1));
        expect(client.requestCount, 2);
      },
    );

    test('does not retry stream failures after first chunk is emitted', () async {
      final _SequencedClient client = _SequencedClient(
        responses: <http.StreamedResponse>[
          http.StreamedResponse(
            _sseWithFailureAfterFirstChunk(),
            200,
            headers: <String, String>{'content-type': 'text/event-stream'},
          ),
          http.StreamedResponse(
            Stream<List<int>>.fromIterable(<List<int>>[
              utf8.encode(
                'data: {"candidates":[{"content":{"parts":[{"text":"should-not-arrive"}]},"finishReason":"STOP"}]}\n\n',
              ),
            ]),
            200,
            headers: <String, String>{'content-type': 'text/event-stream'},
          ),
        ],
      );
      final GeminiRestHttpTransport transport = GeminiRestHttpTransport(
        httpClient: client,
      );

      await expectLater(
        transport
            .streamGenerateContent(
              model: 'gemini-2.5-flash',
              apiKey: 'test-key',
              payload: <String, Object?>{
                'contents': <Object?>[
                  <String, Object?>{
                    'parts': <Object?>[
                      <String, Object?>{'text': 'hello'},
                    ],
                  },
                ],
              },
              retryOptions: HttpRetryOptions(
                attempts: 2,
                initialDelay: 0,
                maxDelay: 0,
                expBase: 1,
                httpStatusCodes: <int>[503],
              ),
            )
            .toList(),
        throwsA(isA<SocketException>()),
      );
      expect(client.requestCount, 1);
    });

    test(
      'throws a clear error when SSE data contains malformed JSON',
      () async {
        final _SequencedClient client = _SequencedClient(
          responses: <http.StreamedResponse>[
            http.StreamedResponse(
              Stream<List<int>>.fromIterable(<List<int>>[
                utf8.encode('data: {"candidates":[}\n\n'),
              ]),
              200,
              headers: <String, String>{'content-type': 'text/event-stream'},
            ),
          ],
        );
        final GeminiRestHttpTransport transport = GeminiRestHttpTransport(
          httpClient: client,
        );

        await expectLater(
          transport
              .streamGenerateContent(
                model: 'gemini-2.5-flash',
                apiKey: 'test-key',
                payload: <String, Object?>{
                  'contents': <Object?>[
                    <String, Object?>{
                      'parts': <Object?>[
                        <String, Object?>{'text': 'hello'},
                      ],
                    },
                  ],
                },
              )
              .toList(),
          throwsA(
            isA<GeminiRestApiException>().having(
              (GeminiRestApiException error) => error.message,
              'message',
              contains('malformed JSON'),
            ),
          ),
        );
        expect(client.requestCount, 1);
      },
    );

    test(
      'throws a clear error when stream response is not valid SSE',
      () async {
        final _SequencedClient client = _SequencedClient(
          responses: <http.StreamedResponse>[
            http.StreamedResponse(
              Stream<List<int>>.fromIterable(<List<int>>[
                utf8.encode(
                  '{"candidates":[{"content":{"parts":[{"text":"ok"}]}}]}',
                ),
              ]),
              200,
              headers: <String, String>{'content-type': 'application/json'},
            ),
          ],
        );
        final GeminiRestHttpTransport transport = GeminiRestHttpTransport(
          httpClient: client,
        );

        await expectLater(
          transport
              .streamGenerateContent(
                model: 'gemini-2.5-flash',
                apiKey: 'test-key',
                payload: <String, Object?>{
                  'contents': <Object?>[
                    <String, Object?>{
                      'parts': <Object?>[
                        <String, Object?>{'text': 'hello'},
                      ],
                    },
                  ],
                },
              )
              .toList(),
          throwsA(
            isA<GeminiRestApiException>().having(
              (GeminiRestApiException error) => error.message,
              'message',
              contains('not a valid event stream'),
            ),
          ),
        );
      },
    );

    test('adds eventType field for interactions SSE stream', () async {
      final _SequencedClient client = _SequencedClient(
        responses: <http.StreamedResponse>[
          http.StreamedResponse(
            Stream<List<int>>.fromIterable(<List<int>>[
              utf8.encode(
                'event: content.delta\n'
                'data: {"delta":{"type":"text","text":"hello"}}\n\n',
              ),
            ]),
            200,
            headers: <String, String>{'content-type': 'text/event-stream'},
          ),
        ],
      );
      final GeminiRestHttpTransport transport = GeminiRestHttpTransport(
        httpClient: client,
      );

      final List<Map<String, Object?>> events = await transport
          .streamCreateInteraction(
            apiKey: 'test-key',
            payload: <String, Object?>{
              'model': 'gemini-2.5-flash',
              'input': <Object?>[],
              'stream': true,
            },
          )
          .toList();

      expect(events, hasLength(1));
      expect(events.single['eventType'], 'content.delta');
    });
  });
}

http.StreamedResponse _jsonResponse({
  required int statusCode,
  required Map<String, Object?> payload,
}) {
  return http.StreamedResponse(
    Stream<List<int>>.fromIterable(<List<int>>[
      utf8.encode(jsonEncode(payload)),
    ]),
    statusCode,
    headers: <String, String>{'content-type': 'application/json'},
  );
}

http.StreamedResponse _bytesResponse({
  required int statusCode,
  required List<int> bodyBytes,
}) {
  return http.StreamedResponse(
    Stream<List<int>>.fromIterable(<List<int>>[bodyBytes]),
    statusCode,
    headers: <String, String>{'content-type': 'application/json'},
  );
}

Stream<List<int>> _sseWithFailureAfterFirstChunk() async* {
  yield utf8.encode(
    'data: {"candidates":[{"content":{"parts":[{"text":"first"}]}}]}\n\n',
  );
  throw const SocketException('simulated socket close');
}

class _SequencedClient extends http.BaseClient {
  _SequencedClient({required List<http.StreamedResponse> responses})
    : _responses = Queue<http.StreamedResponse>.from(responses);

  final Queue<http.StreamedResponse> _responses;
  final List<http.BaseRequest> _requests = <http.BaseRequest>[];
  int requestCount = 0;

  Map<String, String>? get lastRequestHeaders {
    if (_requests.isEmpty) {
      return null;
    }
    return Map<String, String>.from(_requests.last.headers);
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requestCount += 1;
    _requests.add(request);
    if (_responses.isEmpty) {
      throw StateError('No queued response for request #$requestCount.');
    }
    return _responses.removeFirst();
  }
}
