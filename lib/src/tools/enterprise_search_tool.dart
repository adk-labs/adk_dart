import '../models/llm_request.dart';
import '../utils/model_name_utils.dart';
import 'base_tool.dart';
import 'tool_context.dart';

class EnterpriseWebSearchTool extends BaseTool {
  EnterpriseWebSearchTool()
    : super(
        name: 'enterprise_web_search',
        description: 'enterprise_web_search',
      );

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

    if (isGeminiModel(modelName) || modelCheckDisabled) {
      if (isGemini1Model(modelName) && llmRequest.config.tools!.isNotEmpty) {
        throw ArgumentError(
          'Enterprise Web Search tool cannot be used with other tools in Gemini 1.x.',
        );
      }
      llmRequest.config.tools!.add(
        ToolDeclaration(enterpriseWebSearch: const <String, Object?>{}),
      );
      llmRequest.config.labels['adk_enterprise_web_search_tool'] =
          'enterprise_web_search';
      return;
    }

    throw ArgumentError(
      'Enterprise Web Search tool is not supported for model ${llmRequest.model}',
    );
  }
}

final EnterpriseWebSearchTool enterpriseWebSearchTool =
    EnterpriseWebSearchTool();
final EnterpriseWebSearchTool enterprise_web_search = enterpriseWebSearchTool;
