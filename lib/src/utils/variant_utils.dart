import 'env_utils.dart';

const String _googleLlmVariantVertexAi = 'VERTEX_AI';
const String _googleLlmVariantGeminiApi = 'GEMINI_API';

enum GoogleLLMVariant {
  vertexAi(_googleLlmVariantVertexAi),
  geminiApi(_googleLlmVariantGeminiApi);

  const GoogleLLMVariant(this.value);

  final String value;
}

GoogleLLMVariant getGoogleLlmVariant({Map<String, String>? environment}) {
  return isEnvEnabled('GOOGLE_GENAI_USE_VERTEXAI', environment: environment)
      ? GoogleLLMVariant.vertexAi
      : GoogleLLMVariant.geminiApi;
}
