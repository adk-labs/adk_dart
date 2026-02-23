import '../models/llm_request.dart';
import 'base_tool.dart';
import 'tool_context.dart';

/// Tool used when output schema must coexist with other tools.
class SetModelResponseTool extends BaseTool {
  SetModelResponseTool(this.outputSchema)
    : super(
        name: 'set_model_response',
        description:
            'Set the final structured model response. Use this for the final answer.',
      );

  final Object outputSchema;

  @override
  FunctionDeclaration? getDeclaration() {
    final Object parameters = _normalizeParameters(outputSchema);
    return FunctionDeclaration(
      name: name,
      description: description,
      parameters: parameters is Map<String, dynamic>
          ? parameters
          : <String, dynamic>{
              'type': 'object',
              'properties': <String, dynamic>{
                'response': <String, dynamic>{'type': 'string'},
              },
            },
    );
  }

  @override
  Future<Object?> run({
    required Map<String, dynamic> args,
    required ToolContext toolContext,
  }) async {
    return Map<String, dynamic>.from(args);
  }

  Object _normalizeParameters(Object schema) {
    if (schema is Map<String, dynamic>) {
      return Map<String, dynamic>.from(schema);
    }
    if (schema is Map) {
      return <String, dynamic>{
        for (final MapEntry<Object?, Object?> entry in schema.entries)
          if (entry.key is String) entry.key as String: entry.value,
      };
    }
    return <String, dynamic>{
      'type': 'object',
      'properties': <String, dynamic>{
        'response': <String, dynamic>{'type': 'string'},
      },
      'required': <String>['response'],
    };
  }
}
