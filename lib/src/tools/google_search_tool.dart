import '../models/llm_request.dart';
import '../utils/model_name_utils.dart';
import 'base_tool.dart';
import 'tool_context.dart';

class GoogleSearchTool extends BaseTool {
  GoogleSearchTool({
    this.bypassMultiToolsLimit = false,
    this.model,
    bool Function()? modelIdCheckDisabledResolver,
  }) : _modelIdCheckDisabledResolver =
           modelIdCheckDisabledResolver ?? isGeminiModelIdCheckDisabled,
       super(name: 'google_search', description: 'google_search');

  final bool bypassMultiToolsLimit;
  final String? model;
  final bool Function() _modelIdCheckDisabledResolver;

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
    if (model != null) {
      llmRequest.model = model;
    }

    final String? modelName = llmRequest.model;
    final bool modelCheckDisabled = _modelIdCheckDisabledResolver();
    llmRequest.config.tools ??= <ToolDeclaration>[];
    if (isGemini1Model(modelName)) {
      if (!bypassMultiToolsLimit && llmRequest.config.tools!.isNotEmpty) {
        throw ArgumentError(
          'Google search tool cannot be used with other tools in Gemini 1.x.',
        );
      }
      llmRequest.config.tools!.add(
        ToolDeclaration(googleSearchRetrieval: const <String, Object?>{}),
      );
      llmRequest.config.labels['adk_google_search_tool'] =
          'google_search_retrieval';
      return;
    }

    if (isGeminiModel(modelName) || modelCheckDisabled) {
      llmRequest.config.tools!.add(
        ToolDeclaration(googleSearch: const <String, Object?>{}),
      );
      llmRequest.config.labels['adk_google_search_tool'] = 'google_search';
      return;
    }

    throw ArgumentError(
      'Google search tool is not supported for model ${llmRequest.model}',
    );
  }
}

final GoogleSearchTool googleSearch = GoogleSearchTool();
final GoogleSearchTool google_search = googleSearch;
