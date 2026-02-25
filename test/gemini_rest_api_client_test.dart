import 'dart:async';
import 'dart:collection';
import 'dart:convert';

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

class _SequencedClient extends http.BaseClient {
  _SequencedClient({required List<http.StreamedResponse> responses})
    : _responses = Queue<http.StreamedResponse>.from(responses);

  final Queue<http.StreamedResponse> _responses;
  int requestCount = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requestCount += 1;
    if (_responses.isEmpty) {
      throw StateError('No queued response for request #$requestCount.');
    }
    return _responses.removeFirst();
  }
}
