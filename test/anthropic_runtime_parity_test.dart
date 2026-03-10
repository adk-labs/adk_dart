import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

class _RecordingAnthropicTransport implements AnthropicRestTransport {
  Map<String, Object?>? lastRequest;
  String? lastApiKey;
  String? lastBaseUrl;
  String? lastApiVersion;
  Map<String, String>? lastHeaders;

  @override
  Future<Map<String, Object?>> createMessage({
    required Map<String, Object?> request,
    required String apiKey,
    required String baseUrl,
    required String apiVersion,
    required Map<String, String> headers,
  }) async {
    lastRequest = Map<String, Object?>.from(request);
    lastApiKey = apiKey;
    lastBaseUrl = baseUrl;
    lastApiVersion = apiVersion;
    lastHeaders = Map<String, String>.from(headers);
    return <String, Object?>{
      'content': <Object?>[
        <String, Object?>{'type': 'text', 'text': 'transport-ok'},
      ],
      'usage': <String, Object?>{'input_tokens': 3, 'output_tokens': 4},
      'stop_reason': 'end_turn',
    };
  }

  @override
  Stream<Map<String, Object?>> streamMessage({
    required Map<String, Object?> request,
    required String apiKey,
    required String baseUrl,
    required String apiVersion,
    required Map<String, String> headers,
  }) {
    throw UnimplementedError();
  }
}

void main() {
  group('anthropic runtime parity', () {
    test(
      'non-streaming transport omits stream flag and returns runtime output',
      () async {
        final _RecordingAnthropicTransport transport =
            _RecordingAnthropicTransport();
        final AnthropicLlm llm = AnthropicLlm(
          model: 'claude-sonnet-4-20250514',
          restTransport: transport,
          environment: <String, String>{'ANTHROPIC_API_KEY': 'test-key'},
        );

        final List<LlmResponse> responses = await llm
            .generateContent(
              LlmRequest(
                model: 'claude-sonnet-4-20250514',
                contents: <Content>[Content.userText('hello')],
                config: GenerateContentConfig(systemInstruction: 'be helpful'),
              ),
            )
            .toList();

        expect(responses, hasLength(1));
        expect(responses.single.content?.parts.single.text, 'transport-ok');
        expect(responses.single.turnComplete, isTrue);
        expect(transport.lastRequest, isNotNull);
        expect(transport.lastRequest!.containsKey('stream'), isFalse);
        expect(transport.lastRequest!['system'], 'be helpful');
        expect(transport.lastApiKey, 'test-key');
        expect(transport.lastBaseUrl, 'https://api.anthropic.com/v1');
        expect(transport.lastApiVersion, '2023-06-01');
      },
    );

    test(
      'streaming text yields partial chunks and a final aggregated response',
      () async {
        final AnthropicLlm llm = AnthropicLlm(
          model: 'claude-sonnet-4-20250514',
          streamInvoker: ({required Map<String, Object?> request}) {
            expect(request['stream'], isTrue);
            return Stream<Map<String, Object?>>.fromIterable(
              <Map<String, Object?>>[
                <String, Object?>{
                  'type': 'message_start',
                  'message': <String, Object?>{
                    'usage': <String, Object?>{
                      'input_tokens': 10,
                      'output_tokens': 0,
                    },
                  },
                },
                <String, Object?>{
                  'type': 'content_block_start',
                  'index': 0,
                  'content_block': <String, Object?>{
                    'type': 'text',
                    'text': '',
                  },
                },
                <String, Object?>{
                  'type': 'content_block_delta',
                  'index': 0,
                  'delta': <String, Object?>{
                    'type': 'text_delta',
                    'text': 'Hello ',
                  },
                },
                <String, Object?>{
                  'type': 'content_block_delta',
                  'index': 0,
                  'delta': <String, Object?>{
                    'type': 'text_delta',
                    'text': 'world!',
                  },
                },
                <String, Object?>{
                  'type': 'message_delta',
                  'usage': <String, Object?>{'output_tokens': 5},
                },
                <String, Object?>{'type': 'message_stop'},
              ],
            );
          },
        );

        final List<LlmResponse> responses = await llm
            .generateContent(
              LlmRequest(
                model: 'claude-sonnet-4-20250514',
                contents: <Content>[Content.userText('Hi')],
                config: GenerateContentConfig(systemInstruction: 'Test'),
              ),
              stream: true,
            )
            .toList();

        expect(responses, hasLength(3));
        expect(responses[0].partial, isTrue);
        expect(responses[0].content?.parts.single.text, 'Hello ');
        expect(responses[1].partial, isTrue);
        expect(responses[1].content?.parts.single.text, 'world!');
        expect(responses[2].partial, isFalse);
        expect(responses[2].turnComplete, isTrue);
        expect(responses[2].content?.parts.single.text, 'Hello world!');
        expect(responses[2].usageMetadata, <String, Object?>{
          'prompt_token_count': 10,
          'candidates_token_count': 5,
          'total_token_count': 15,
        });
      },
    );

    test(
      'streaming tool use accumulates final function call arguments',
      () async {
        final AnthropicLlm llm = AnthropicLlm(
          model: 'claude-sonnet-4-20250514',
          streamInvoker: ({required Map<String, Object?> request}) {
            expect(request['stream'], isTrue);
            return Stream<Map<String, Object?>>.fromIterable(
              <Map<String, Object?>>[
                <String, Object?>{
                  'type': 'message_start',
                  'message': <String, Object?>{
                    'usage': <String, Object?>{
                      'input_tokens': 20,
                      'output_tokens': 0,
                    },
                  },
                },
                <String, Object?>{
                  'type': 'content_block_start',
                  'index': 0,
                  'content_block': <String, Object?>{
                    'type': 'text',
                    'text': '',
                  },
                },
                <String, Object?>{
                  'type': 'content_block_delta',
                  'index': 0,
                  'delta': <String, Object?>{
                    'type': 'text_delta',
                    'text': 'Checking.',
                  },
                },
                <String, Object?>{
                  'type': 'content_block_start',
                  'index': 1,
                  'content_block': <String, Object?>{
                    'type': 'tool_use',
                    'id': 'toolu_abc',
                    'name': 'get_weather',
                  },
                },
                <String, Object?>{
                  'type': 'content_block_delta',
                  'index': 1,
                  'delta': <String, Object?>{
                    'type': 'input_json_delta',
                    'partial_json': '{"city":"Paris"}',
                  },
                },
                <String, Object?>{
                  'type': 'message_delta',
                  'usage': <String, Object?>{'output_tokens': 12},
                },
                <String, Object?>{'type': 'message_stop'},
              ],
            );
          },
        );

        final List<LlmResponse> responses = await llm
            .generateContent(
              LlmRequest(
                model: 'claude-sonnet-4-20250514',
                contents: <Content>[Content.userText('Weather?')],
                config: GenerateContentConfig(systemInstruction: 'Test'),
              ),
              stream: true,
            )
            .toList();

        expect(responses, hasLength(2));
        expect(responses.first.partial, isTrue);
        expect(responses.first.content?.parts.single.text, 'Checking.');
        expect(responses.last.partial, isFalse);
        expect(responses.last.content?.parts, hasLength(2));
        expect(responses.last.content?.parts[0].text, 'Checking.');
        expect(
          responses.last.content?.parts[1].functionCall?.name,
          'get_weather',
        );
        expect(responses.last.content?.parts[1].functionCall?.id, 'toolu_abc');
        expect(
          responses.last.content?.parts[1].functionCall?.args,
          <String, dynamic>{'city': 'Paris'},
        );
      },
    );
  });
}
