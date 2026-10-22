/// Internal tool that preloads memory snippets into prompts.
library;

import '../memory/memory_entry.dart';
import '../models/llm_request.dart';
import '../utils/content_utils.dart';
import 'base_tool.dart';
import 'tool_context.dart';

/// Internal tool that preloads relevant memories into prompt instructions.
class PreloadMemoryTool extends BaseTool {
  /// Creates a preload-memory tool.
  PreloadMemoryTool()
    : super(
        name: 'preload_memory',
        description: 'Preloads relevant memories into system instructions.',
      );

  /// Returns `null` because this tool is not directly model-invokable.
  @override
  FunctionDeclaration? getDeclaration() {
    // This tool is executed internally during request preprocessing and is not
    // intended for direct model function-calling.
    return null;
  }

  /// Returns a no-op success payload.
  @override
  Future<Object?> run({
    required Map<String, dynamic> args,
    required ToolContext toolContext,
  }) async {
    return <String, Object?>{'status': 'ok'};
  }

  /// Appends relevant past-conversation context into [llmRequest].
  @override
  Future<void> processLlmRequest({
    required ToolContext toolContext,
    required LlmRequest llmRequest,
  }) async {
    final String query =
        (extractTextFromContent(toolContext.userContent) ?? '').trim();
    if (query.isEmpty) {
      return;
    }

    final response = await toolContext.searchMemory(query);
    if (response.memories.isEmpty) {
      return;
    }

    final String memoryText = response.memories
        .map((MemoryEntry memory) => _memoryAsText(memory))
        .where((String line) => line.isNotEmpty)
        .join('\n');
    if (memoryText.isEmpty) {
      return;
    }

    llmRequest.appendInstructions(<String>[
      '''The following content is from your previous conversations with the user.
They may be useful for answering the user's current query.
<PAST_CONVERSATIONS>
$memoryText
</PAST_CONVERSATIONS>
''',
    ]);
  }
}

String _memoryAsText(MemoryEntry memory) {
  final String text = (extractTextFromContent(memory.content) ?? '').trim();
  if (text.isEmpty) {
    return '';
  }
  if (memory.timestamp != null && memory.timestamp!.isNotEmpty) {
    final String timeText = 'Time: ${memory.timestamp}';
    if (memory.author != null && memory.author!.isNotEmpty) {
      return '$timeText\n${memory.author}: $text';
    }
    return '$timeText\n$text';
  }
  if (memory.author != null && memory.author!.isNotEmpty) {
    return '${memory.author}: $text';
  }
  return text;
}
