/// Capability checks for structured output schema support.
library;

import '../models/base_llm.dart';
import '../models/lite_llm.dart';
import 'model_name_utils.dart';
import 'variant_utils.dart';

/// Whether [model] can use output schema together with tool calling.
///
/// This requires Vertex AI variant and Gemini 2+ models.
bool canUseOutputSchemaWithTools(
  Object model, {
  Map<String, String>? environment,
}) {
  if (model is LiteLlm) {
    return true;
  }
  final String modelString = switch (model) {
    String value => value,
    BaseLlm llm => llm.model,
    _ => '',
  };
  return getGoogleLlmVariant(environment: environment) ==
          GoogleLLMVariant.vertexAi &&
      isGemini2OrAbove(modelString);
}
