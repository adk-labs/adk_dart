import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

void main() {
  group('OpenAILlm labs parity', () {
    test('uses OPENAI_API_KEY and strips openai provider prefix', () async {
      final _CaptureCompletionsClient client = _CaptureCompletionsClient();
      final OpenAILlm model = OpenAILlm(
        model: 'openai/gpt-4o',
        environment: const <String, String>{'OPENAI_API_KEY': 'test-key'},
        completionsClient: client,
      );

      final List<LlmResponse> responses = await model
          .generateContent(
            LlmRequest(
              model: 'openai/gpt-4o',
              contents: <Content>[Content.userText('hello')],
            ),
            stream: true,
          )
          .toList();

      expect(client.lastRequest?.model, 'gpt-4o');
      expect(client.lastStream, isTrue);
      expect(client.lastBaseUrl, 'https://api.openai.com/v1/chat/completions');
      expect(client.lastHeaders['Authorization'], 'Bearer test-key');
      expect(responses.single.content?.parts.single.text, 'openai-result');
    });

    test('requires API key', () async {
      final OpenAILlm model = OpenAILlm(
        model: 'gpt-4o',
        environment: const <String, String>{},
        completionsClient: _CaptureCompletionsClient(),
      );

      expect(
        () => model
            .generateContent(
              LlmRequest(contents: <Content>[Content.userText('hello')]),
            )
            .toList(),
        throwsArgumentError,
      );
    });
  });
}

class _CaptureCompletionsClient implements ApigeeCompletionsClient {
  LlmRequest? lastRequest;
  bool? lastStream;
  String? lastBaseUrl;
  Map<String, String> lastHeaders = const <String, String>{};

  @override
  Stream<LlmResponse> generateContent({
    required LlmRequest request,
    required bool stream,
    required String baseUrl,
    required Map<String, String> headers,
  }) async* {
    lastRequest = request;
    lastStream = stream;
    lastBaseUrl = baseUrl;
    lastHeaders = Map<String, String>.from(headers);
    yield LlmResponse(
      modelVersion: request.model,
      content: Content.modelText('openai-result'),
      turnComplete: true,
    );
  }
}
