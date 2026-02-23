import 'base_llm.dart';
import 'llm_request.dart';
import 'llm_response.dart';
import 'google_llm.dart';

class GemmaLlm extends BaseLlm {
  GemmaLlm({super.model = 'gemma-3-27b-it', GeminiGenerateHook? generateHook})
    : _delegate = Gemini(model: model, generateHook: generateHook);

  final Gemini _delegate;

  static List<RegExp> supportedModels() {
    return <RegExp>[RegExp(r'gemma-.*'), RegExp(r'google\/gemma-.*')];
  }

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) {
    request.model ??= model;
    return _delegate.generateContent(request, stream: stream);
  }
}
