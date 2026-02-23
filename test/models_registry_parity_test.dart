import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

class _FakeGeminiModel extends BaseLlm {
  _FakeGeminiModel() : super(model: 'fake-gemini');

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    yield LlmResponse(content: Content.modelText('fake'));
  }
}

void main() {
  group('LLMRegistry default registration parity', () {
    setUp(() {
      LLMRegistry.clear();
    });

    test(
      'registers built-in providers lazily and resolves canonical models',
      () {
        expect(LLMRegistry.newLlm('gemini-2.5-flash'), isA<Gemini>());
        expect(LLMRegistry.newLlm('gemma-3-27b-it'), isA<GemmaLlm>());
        expect(LLMRegistry.newLlm('apigee/gemini-2.5-flash'), isA<ApigeeLlm>());
        expect(
          LLMRegistry.newLlm('claude-3-5-sonnet-20241022'),
          isA<AnthropicLlm>(),
        );
        expect(LLMRegistry.newLlm('openai/gpt-4o-mini'), isA<LiteLlm>());
      },
    );

    test('keeps caller-registered models ahead of lazy defaults', () {
      LLMRegistry.register(
        supportedModels: <RegExp>[RegExp(r'gemini-.*')],
        factory: (String _) => _FakeGeminiModel(),
      );

      final BaseLlm model = LLMRegistry.newLlm('gemini-2.5-flash');
      expect(model, isA<_FakeGeminiModel>());
    });
  });
}
