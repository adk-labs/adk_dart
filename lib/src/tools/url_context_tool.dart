import '../models/llm_request.dart';
import 'base_tool.dart';
import 'tool_context.dart';

class UrlContextTool extends BaseTool {
  UrlContextTool() : super(name: 'url_context', description: 'url_context');

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
    final String model = (llmRequest.model ?? '').trim();
    final bool isGemini1 = model.startsWith('gemini-1');
    final bool isGemini2OrAbove =
        model.startsWith('gemini-2') ||
        model.startsWith('gemini-3') ||
        model.startsWith('gemini-4');

    if (isGemini1) {
      throw ArgumentError('Url context tool cannot be used in Gemini 1.x.');
    }
    if (model.isNotEmpty && !isGemini2OrAbove) {
      throw ArgumentError('Url context tool is not supported for model $model');
    }

    llmRequest.config.tools ??= <ToolDeclaration>[];
    llmRequest.config.tools!.add(
      ToolDeclaration(
        functionDeclarations: <FunctionDeclaration>[
          FunctionDeclaration(
            name: name,
            description:
                'Built-in URL context retrieval; model may invoke automatically.',
            parameters: <String, dynamic>{
              'type': 'object',
              'properties': <String, dynamic>{},
            },
          ),
        ],
      ),
    );
  }
}

final UrlContextTool urlContext = UrlContextTool();
