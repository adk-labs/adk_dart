/// Tool used to set final structured model responses.
library;

import '../models/llm_request.dart';
import 'base_tool.dart';
import 'tool_context.dart';

/// Tool used when output schema must coexist with other tools.
class SetModelResponseTool extends BaseTool {
  /// Creates a tool that captures the final structured model response.
  SetModelResponseTool(this.outputSchema)
    : super(
        name: 'set_model_response',
        description:
            'Set the final structured model response. Use this for the final answer.',
      );

  /// Output schema used to build the tool declaration parameters.
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
      return _deepCopySchema(schema);
    }
    if (schema is Map) {
      final Map<String, dynamic> converted = <String, dynamic>{
        for (final MapEntry<Object?, Object?> entry in schema.entries)
          if (entry.key is String) entry.key as String: entry.value,
      };
      return _deepCopySchema(converted);
    }
    return <String, dynamic>{
      'type': 'object',
      'properties': <String, dynamic>{
        'response': <String, dynamic>{
          'type': 'string',
          'description': 'The model response payload.',
        },
      },
      'required': <String>['response'],
    };
  }

  Map<String, dynamic> _deepCopySchema(Map<String, dynamic> schema) {
    final Map<String, dynamic> copy = <String, dynamic>{};
    for (final MapEntry<String, dynamic> entry in schema.entries) {
      final Object? value = entry.value;
      if (value is Map<String, dynamic>) {
        copy[entry.key] = _deepCopySchema(value);
      } else if (value is Map) {
        copy[entry.key] = _deepCopySchema(
          value.map((Object? k, Object? v) => MapEntry('$k', v)),
        );
      } else if (value is List) {
        copy[entry.key] = value.map((Object? item) {
          if (item is Map<String, dynamic>) {
            return _deepCopySchema(item);
          } else if (item is Map) {
            return _deepCopySchema(
              item.map((Object? k, Object? v) => MapEntry('$k', v)),
            );
          }
          return item;
        }).toList();
      } else {
        copy[entry.key] = value;
      }
    }
    return copy;
  }
}
