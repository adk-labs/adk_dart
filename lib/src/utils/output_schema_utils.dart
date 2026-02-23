import '../models/base_llm.dart';
import 'model_name_utils.dart';
import 'variant_utils.dart';

bool canUseOutputSchemaWithTools(
  Object model, {
  Map<String, String>? environment,
}) {
  final String modelString = switch (model) {
    String value => value,
    BaseLlm llm => llm.model,
    _ => '',
  };
  return getGoogleLlmVariant(environment: environment) ==
          GoogleLLMVariant.vertexAi &&
      isGemini2OrAbove(modelString);
}
