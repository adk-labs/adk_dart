import '../models/llm_request.dart';
import '../utils/model_name_utils.dart';
import 'base_tool.dart';
import 'tool_context.dart';

class GoogleMapsGroundingTool extends BaseTool {
  GoogleMapsGroundingTool()
    : super(name: 'google_maps', description: 'google_maps');

  @override
  Future<Object?> run({
    required Map<String, dynamic> args,
    required ToolContext toolContext,
  }) async {
    return null;
  }

  @override
  Future<void> processLlmRequest({
    required ToolContext toolContext,
    required LlmRequest llmRequest,
  }) async {
    final bool modelCheckDisabled = isGeminiModelIdCheckDisabled();
    final String? modelName = llmRequest.model;
    llmRequest.config.tools ??= <ToolDeclaration>[];

    if (isGemini1Model(modelName)) {
      throw ArgumentError(
        'Google Maps grounding tool cannot be used with Gemini 1.x models.',
      );
    }

    if (isGeminiModel(modelName) || modelCheckDisabled) {
      llmRequest.config.tools!.add(
        ToolDeclaration(googleMaps: const <String, Object?>{}),
      );
      llmRequest.config.labels['adk_google_maps_grounding_tool'] =
          'google_maps';
      return;
    }

    throw ArgumentError(
      'Google maps tool is not supported for model ${llmRequest.model}',
    );
  }
}

final GoogleMapsGroundingTool googleMapsGrounding = GoogleMapsGroundingTool();
final GoogleMapsGroundingTool google_maps_grounding = googleMapsGrounding;
