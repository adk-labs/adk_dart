import '../agents/callback_context.dart';
import '../models/llm_request.dart';
import '../models/llm_response.dart';
import '../tools/base_tool.dart';
import '../tools/tool_context.dart';
import '../types/content.dart';
import 'base_plugin.dart';

const String partsReturnedByToolsStateKey = 'temp:PARTS_RETURNED_BY_TOOLS_ID';

List<Part>? _extractParts(Object? value) {
  if (value is Part) {
    return <Part>[value];
  }
  if (value is List) {
    if (value.isEmpty) {
      return null;
    }
    if (value.every((Object? item) => item is Part)) {
      return value.cast<Part>().toList(growable: false);
    }
  }
  return null;
}

class MultimodalToolResultsPlugin extends BasePlugin {
  MultimodalToolResultsPlugin({super.name = 'multimodal_tool_results_plugin'});

  @override
  Future<Map<String, dynamic>?> afterToolCallback({
    required BaseTool tool,
    required Map<String, dynamic> toolArgs,
    required ToolContext toolContext,
    required Map<String, dynamic> result,
  }) async {
    List<Part>? parts = _extractParts(result);
    parts ??= _extractParts(result['result']);

    if (parts == null) {
      return result;
    }

    final Object? saved = toolContext.state[partsReturnedByToolsStateKey];
    final List<Part> merged = <Part>[];
    final List<Part>? existing = _extractParts(saved);
    if (existing != null) {
      merged.addAll(existing);
    }
    merged.addAll(parts.map((Part part) => part.copyWith()));
    toolContext.state[partsReturnedByToolsStateKey] = merged;

    return null;
  }

  @override
  Future<LlmResponse?> beforeModelCallback({
    required CallbackContext callbackContext,
    required LlmRequest llmRequest,
  }) async {
    final List<Part>? savedParts = _extractParts(
      callbackContext.state[partsReturnedByToolsStateKey],
    );
    if (savedParts == null ||
        savedParts.isEmpty ||
        llmRequest.contents.isEmpty) {
      return null;
    }

    llmRequest.contents.last.parts.addAll(
      savedParts.map((Part part) => part.copyWith()),
    );
    callbackContext.state[partsReturnedByToolsStateKey] = <Part>[];
    return null;
  }
}
