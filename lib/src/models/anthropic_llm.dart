import '../types/content.dart';
import 'base_llm.dart';
import 'llm_request.dart';
import 'llm_response.dart';

class AnthropicLlm extends BaseLlm {
  AnthropicLlm({
    super.model = 'claude-3-5-sonnet-20241022',
    AnthropicGenerateHook? generateHook,
  }) : _generateHook = generateHook;

  final AnthropicGenerateHook? _generateHook;

  static List<RegExp> supportedModels() {
    return <RegExp>[RegExp(r'claude-.*'), RegExp(r'anthropic\/.*')];
  }

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    final LlmRequest prepared = request.sanitizedForModelCall();
    prepared.model ??= model;
    maybeAppendUserContent(prepared);

    if (_generateHook != null) {
      yield* _generateHook(prepared, stream);
      return;
    }

    final String text = _extractUserText(prepared);
    yield LlmResponse(
      modelVersion: prepared.model,
      content: Content.modelText('Anthropic response: $text'),
      turnComplete: true,
    );
  }

  String _extractUserText(LlmRequest request) {
    for (int i = request.contents.length - 1; i >= 0; i -= 1) {
      final Content content = request.contents[i];
      if (content.role != 'user') {
        continue;
      }
      for (int j = content.parts.length - 1; j >= 0; j -= 1) {
        final String? text = content.parts[j].text;
        if (text != null && text.isNotEmpty) {
          return text;
        }
      }
    }
    return '';
  }
}

typedef AnthropicGenerateHook =
    Stream<LlmResponse> Function(LlmRequest request, bool stream);
typedef Claude = AnthropicLlm;
