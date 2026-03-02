import 'env_utils.dart';

const String _googleLlmVariantVertexAi = 'VERTEX_AI';
const String _googleLlmVariantGeminiApi = 'GEMINI_API';

/// Google LLM backend variants supported by ADK.
enum GoogleLLMVariant {
  vertexAi(_googleLlmVariantVertexAi),
  geminiApi(_googleLlmVariantGeminiApi);

  const GoogleLLMVariant(this.value);

  /// Serialized backend value used in metadata and logs.
  final String value;
}

/// Resolves the active Google LLM backend from environment flags.
GoogleLLMVariant getGoogleLlmVariant({Map<String, String>? environment}) {
  return isEnvEnabled('GOOGLE_GENAI_USE_VERTEXAI', environment: environment)
      ? GoogleLLMVariant.vertexAi
      : GoogleLLMVariant.geminiApi;
}
