import '../../models/llm_request.dart';
import '../base_tool.dart';

abstract class BaseRetrievalTool extends BaseTool {
  BaseRetrievalTool({required super.name, required super.description});

  @override
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
