import '../models/llm_request.dart';
import '../utils/model_name_utils.dart';
import 'base_tool.dart';
import 'tool_context.dart';

class UrlContextTool extends BaseTool {
  UrlContextTool({bool Function()? modelIdCheckDisabledResolver})
    : _modelIdCheckDisabledResolver =
          modelIdCheckDisabledResolver ?? isGeminiModelIdCheckDisabled,
      super(name: 'url_context', description: 'url_context');

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
    final bool modelCheckDisabled = _modelIdCheckDisabledResolver();
    final String model = (llmRequest.model ?? '').trim();
    final bool isGemini1 = model.startsWith('gemini-1');
    final bool isGemini2OrAbove =
        model.startsWith('gemini-2') ||
        model.startsWith('gemini-3') ||
        model.startsWith('gemini-4');

    if (isGemini1) {
      throw ArgumentError('Url context tool cannot be used in Gemini 1.x.');
    }
    if (!isGemini2OrAbove && !modelCheckDisabled) {
      throw ArgumentError('Url context tool is not supported for model $model');
    }

    llmRequest.config.tools ??= <ToolDeclaration>[];
    llmRequest.config.tools!.add(
      ToolDeclaration(urlContext: const <String, Object?>{}),
    );
  }
}

final UrlContextTool urlContext = UrlContextTool();
