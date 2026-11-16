/// Internal tool that preloads memory snippets into prompts.
library;

import 'dart:developer' as developer;

import '../memory/base_memory_service.dart';
import '../memory/memory_entry.dart';
import '../models/llm_request.dart';
import '../types/content.dart';
import '../utils/content_utils.dart';
import '_memory_entry_utils.dart' as memory_entry_utils;
import 'base_tool.dart';
import 'tool_context.dart';

/// Internal tool that preloads relevant memories into prompt context.
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

  /// Inserts relevant past-conversation context into [llmRequest].
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

    final SearchMemoryResponse response;
    try {
      response = await toolContext.searchMemory(query);
    } on Exception catch (error, stackTrace) {
      developer.log(
        'Failed to preload memory (query length: ${query.length})',
        name: 'adk_dart.tools.preload_memory_tool',
        error: error,
        stackTrace: stackTrace,
      );
      return;
    }
    if (response.memories.isEmpty) {
      return;
    }

    final List<String> memoryTextLines = <String>[];
    for (final MemoryEntry memory in response.memories) {
      final String memoryText = memory_entry_utils.extractText(memory).trim();
      if (memoryText.isEmpty) {
        continue;
      }
      if (memory.timestamp != null && memory.timestamp!.isNotEmpty) {
        memoryTextLines.add('Time: ${memory.timestamp}');
      }
      if (memory.author != null && memory.author!.isNotEmpty) {
        memoryTextLines.add('${memory.author}: $memoryText');
      } else {
        memoryTextLines.add(memoryText);
      }
    }
    if (memoryTextLines.isEmpty) {
      return;
    }

    final String fullMemoryText = memoryTextLines.join('\n');
    final String memoryContext =
        '''The following content is from your previous conversations with the user.
They may be useful for answering the user's current query.
<PAST_CONVERSATIONS>
$fullMemoryText
</PAST_CONVERSATIONS>
''';

    llmRequest.insertTransientUserContent(<Content>[
      Content(role: 'user', parts: <Part>[Part.text(memoryContext)]),
    ]);
  }
}
