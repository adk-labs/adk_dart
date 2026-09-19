import '../agents/llm_agent.dart';
import '../models/base_llm.dart';
import '../models/lite_llm.dart';
import 'model_name_utils.dart';
import 'variant_utils.dart';

/// Single source of truth for whether output schema can be set natively on LlmRequest.
bool canSetNativeOutputSchema(LlmAgent agent) {
  if (agent.outputSchema == null) {
    return false;
  }
  if (agent.tools.isEmpty) {
    return true;
  }
  return canUseOutputSchemaWithTools(agent.canonicalModel);
}

/// Whether [model] can use output schema together with tool calling.
///
/// This requires Vertex AI variant and Gemini 2+ models.
bool canUseOutputSchemaWithTools(
  Object model, {
  Map<String, String>? environment,
}) {
  if (model is BaseLlm) {
    if (model.capabilities.outputSchemaAndTools) {
      return true;
    }
  }
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
      isGeminiEapOr2OrAbove(modelString);
}
