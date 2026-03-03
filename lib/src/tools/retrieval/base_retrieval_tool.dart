/// Base contracts for query-driven retrieval tools.
library;

import '../../models/llm_request.dart';
import '../base_tool.dart';

/// Base tool contract for retrieval-style tools that accept a text query.
abstract class BaseRetrievalTool extends BaseTool {
  /// Creates a retrieval tool with [name] and [description].
  BaseRetrievalTool({required super.name, required super.description});

  @override
  /// Returns the standard query-only function declaration schema.
  FunctionDeclaration? getDeclaration() {
    return FunctionDeclaration(
      name: name,
      description: description,
      parameters: <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'query': <String, Object?>{
            'type': 'string',
            'description': 'The query to retrieve.',
          },
        },
      },
    );
  }
}
