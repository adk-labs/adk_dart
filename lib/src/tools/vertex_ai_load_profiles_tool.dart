/// Tool that loads structured profiles from Vertex AI Memory Bank.
library;

import '../memory/base_memory_service.dart';
import '../memory/memory_entry.dart';
import '../models/llm_request.dart';
import '../types/content.dart';
import 'base_tool.dart';
import 'tool_context.dart';

/// A tool that loads a user's structured profiles from Vertex Memory Bank.
class VertexAiLoadProfilesTool extends BaseTool {
  /// Initializes the [VertexAiLoadProfilesTool].
  VertexAiLoadProfilesTool({
    required BaseMemoryService memoryService,
    String name = 'load_profiles',
    String description = 'Loads structured user profiles for the current user.',
  }) : _memoryService = memoryService,
       super(name: name, description: description);

  final BaseMemoryService _memoryService;

  @override
  FunctionDeclaration? getDeclaration() {
    return FunctionDeclaration(
      name: name,
      description: description,
      parameters: const <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{},
      },
    );
  }

  @override
  Future<Map<String, Object?>> run({
    required Map<String, dynamic> args,
    required ToolContext toolContext,
  }) async {
    final SearchMemoryResponse response = await _memoryService.searchMemory(
      appName: toolContext.session.appName,
      userId: toolContext.userId,
      query: '',
    );

    final List<String> profiles = response.memories
        .map((MemoryEntry m) {
          return m.content.parts
              .where((Part p) => p.text != null && p.text!.trim().isNotEmpty)
              .map((Part p) => p.text!.trim())
              .join(' ');
        })
        .where((String text) => text.isNotEmpty)
        .toList(growable: false);

    return <String, Object?>{
      'profiles': profiles,
    };
  }
}
