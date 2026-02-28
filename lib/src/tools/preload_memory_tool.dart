import '../memory/memory_entry.dart';
import '../models/llm_request.dart';
import 'base_tool.dart';
import 'tool_context.dart';

class PreloadMemoryTool extends BaseTool {
  PreloadMemoryTool()
    : super(
        name: 'preload_memory',
        description: 'Preloads relevant memories into system instructions.',
      );

  @override
  FunctionDeclaration? getDeclaration() {
    // This tool is executed internally during request preprocessing and is not
    // intended for direct model function-calling.
    return null;
  }

  @override
  Future<Object?> run({
    required Map<String, dynamic> args,
    required ToolContext toolContext,
  }) async {
    return <String, Object?>{'status': 'ok'};
  }

  @override
  Future<void> processLlmRequest({
    required ToolContext toolContext,
    required LlmRequest llmRequest,
  }) async {
    final userContent = toolContext.userContent;
    if (userContent == null || userContent.parts.isEmpty) {
      return;
    }

    final String query = userContent.parts
        .where((part) => part.text != null && part.text!.trim().isNotEmpty)
        .map((part) => part.text!.trim())
        .join(' ')
        .trim();
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
      '''
The following content is from your previous conversations with the user.
They may be useful for answering the user's current query.
<PAST_CONVERSATIONS>
$memoryText
</PAST_CONVERSATIONS>
''',
    ]);
  }
}

String _memoryAsText(MemoryEntry memory) {
  final String text = memory.content.parts
      .where((part) => part.text != null && part.text!.trim().isNotEmpty)
      .map((part) => part.text!.trim())
      .join('\n');
  if (text.isEmpty) {
    return '';
  }
  final String author = memory.author ?? 'memory';
  if (memory.timestamp != null && memory.timestamp!.isNotEmpty) {
    return 'Time: ${memory.timestamp}\n$author: $text';
  }
  return '$author: $text';
}
