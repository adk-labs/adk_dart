import '../memory/memory_entry.dart';
import '../models/llm_request.dart';
import 'base_tool.dart';
import 'tool_context.dart';

class LoadMemoryTool extends BaseTool {
  LoadMemoryTool()
    : super(
        name: 'load_memory',
        description: 'Loads memories for the current user by query.',
      );

  @override
  FunctionDeclaration? getDeclaration() {
    return FunctionDeclaration(
      name: name,
      description: description,
      parameters: <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'query': <String, dynamic>{'type': 'string'},
        },
        'required': <String>['query'],
      },
    );
  }

  @override
  Future<Object?> run({
    required Map<String, dynamic> args,
    required ToolContext toolContext,
  }) async {
    final String query = '${args['query'] ?? ''}'.trim();
    if (query.isEmpty) {
      return <String, Object?>{
        'memories': <Map<String, Object?>>[],
        'error': 'query is required',
      };
    }

    final response = await toolContext.searchMemory(query);
    return <String, Object?>{
      'memories': response.memories
          .map((MemoryEntry memory) => _memoryToJson(memory))
          .toList(growable: false),
    };
  }

  @override
  Future<void> processLlmRequest({
    required ToolContext toolContext,
    required LlmRequest llmRequest,
  }) async {
    await super.processLlmRequest(
      toolContext: toolContext,
      llmRequest: llmRequest,
    );
    llmRequest.appendInstructions(<String>[
      '''
You have memory. You can use it to answer questions. If any questions need
you to look up the memory, you should call load_memory function with a query.
''',
    ]);
  }
}

Map<String, Object?> _memoryToJson(MemoryEntry memory) {
  final String text = memory.content.parts
      .where((part) => part.text != null && part.text!.trim().isNotEmpty)
      .map((part) => part.text!.trim())
      .join('\n');

  return <String, Object?>{
    'id': memory.id,
    'author': memory.author,
    'timestamp': memory.timestamp,
    'text': text,
    'custom_metadata': Map<String, Object?>.from(memory.customMetadata),
  };
}
