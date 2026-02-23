import '../../models/llm_request.dart';
import '../base_tool.dart';

Map<String, Object?> adkToMcpToolType(BaseTool tool) {
  final FunctionDeclaration? declaration = tool.getDeclaration();
  final Map<String, Object?> inputSchema = declaration == null
      ? <String, Object?>{}
      : geminiToJsonSchema(declaration.parameters);
  return <String, Object?>{
    'name': tool.name,
    'description': tool.description,
    'inputSchema': inputSchema,
  };
}

Map<String, Object?> geminiToJsonSchema(Map<String, dynamic> geminiSchema) {
  return _convertSchemaNode(geminiSchema);
}

Map<String, Object?> _convertSchemaNode(Map<String, dynamic> schema) {
  final Map<String, Object?> result = <String, Object?>{};
  schema.forEach((String key, dynamic value) {
    switch (key) {
      case 'type':
        if (value is String) {
          result['type'] = value.toLowerCase();
        } else {
          result['type'] = value;
        }
        break;
      case 'properties':
        if (value is Map) {
          result['properties'] = value.map((
            Object? propName,
            Object? propValue,
          ) {
            if (propValue is Map<String, dynamic>) {
              return MapEntry('$propName', _convertSchemaNode(propValue));
            }
            if (propValue is Map) {
              return MapEntry(
                '$propName',
                _convertSchemaNode(
                  propValue.map(
                    (Object? k, Object? v) => MapEntry('$k', v as dynamic),
                  ),
                ),
              );
            }
            return MapEntry('$propName', propValue);
          });
        }
        break;
      case 'items':
        if (value is Map<String, dynamic>) {
          result['items'] = _convertSchemaNode(value);
        } else if (value is Map) {
          result['items'] = _convertSchemaNode(
            value.map((Object? k, Object? v) => MapEntry('$k', v as dynamic)),
          );
        } else {
          result['items'] = value;
        }
        break;
      case 'anyOf':
        if (value is List) {
          result['anyOf'] = value
              .map((Object? item) {
                if (item is Map<String, dynamic>) {
                  return _convertSchemaNode(item);
                }
                if (item is Map) {
                  return _convertSchemaNode(
                    item.map(
                      (Object? k, Object? v) => MapEntry('$k', v as dynamic),
                    ),
                  );
                }
                return item;
              })
              .toList(growable: false);
        }
        break;
      default:
        result[key] = value;
        break;
    }
  });
  return result;
}
