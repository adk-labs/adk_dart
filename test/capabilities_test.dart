import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

class _DummyLlm extends BaseLlm {
  _DummyLlm({required super.model, this.customCapabilities});

  final LlmCapabilities? customCapabilities;

  @override
  LlmCapabilities get capabilities =>
      customCapabilities ?? super.capabilities;

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {}
}

void main() {
  group('LlmCapabilities', () {
    test('default capabilities on BaseLlm', () {
      final llm = _DummyLlm(model: 'test_model');
      expect(llm.capabilities.outputSchemaAndTools, isFalse);
      expect(llm.capabilities.supportsAudioInput, isFalse);
      expect(llm.capabilities.supportsSystemInstruction, isTrue);
    });

    test('custom capabilities override', () {
      final llm = _DummyLlm(
        model: 'test_model',
        customCapabilities: const LlmCapabilities(
          outputSchemaAndTools: true,
          supportsAudioInput: true,
        ),
      );
      expect(llm.capabilities.outputSchemaAndTools, isTrue);
      expect(llm.capabilities.supportsAudioInput, isTrue);
    });
  });
}
