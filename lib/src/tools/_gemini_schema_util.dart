import 'dart:convert';

String toSnakeCase(String text) {
  String value = text.replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '_');
  value = value.replaceAllMapped(
    RegExp(r'([a-z0-9])([A-Z])'),
    (Match m) => '${m.group(1)}_${m.group(2)}',
  );
  value = value.replaceAllMapped(
    RegExp(r'([A-Z]+)([A-Z][a-z])'),
    (Match m) => '${m.group(1)}_${m.group(2)}',
  );
  value = value.toLowerCase();
  value = value.replaceAll(RegExp(r'_+'), '_');
  value = value.replaceAll(RegExp(r'^_+|_+$'), '');
  return value;
}

Map<String, dynamic> dereferenceSchema(Map<String, dynamic> schema) {
  final Map<String, dynamic> defs = _castMap(schema[r'$defs']);

  dynamic resolveRefs(dynamic node) {
    if (node is Map) {
      final Map<String, dynamic> map = _castMap(node);
      if (map.containsKey(r'$ref')) {
        final String ref = '${map[r'$ref']}';
        final String refKey = ref.split('/').last;
        if (defs.containsKey(refKey)) {
          final Map<String, dynamic> resolved = _castMap(defs[refKey]);
          final Map<String, dynamic> merged = <String, dynamic>{
            ...resolved,
            ...map,
          };
          merged.remove(r'$ref');
          return resolveRefs(merged);
        }
      }
      return map.map((String key, dynamic value) {
        return MapEntry(key, resolveRefs(value));
      });
    }
    if (node is List) {
      return node.map(resolveRefs).toList(growable: false);
    }
    return node;
  }

  final Map<String, dynamic> result = _castMap(resolveRefs(schema));
  result.remove(r'$defs');
  return result;
}

Map<String, dynamic> sanitizeSchemaFormatsForGemini(
  Map<String, dynamic> schema, {
  bool preserveNullType = false,
}) {
  dynamic sanitize(dynamic node, {bool preserveNull = false}) {
    if (node is List) {
      return node
          .map((dynamic item) => sanitize(item, preserveNull: preserveNull))
          .toList(growable: false);
    }
    if (node is bool) {
      return <String, dynamic>{'type': 'object'};
    }
    if (node is! Map) {
      return node;
    }

    final Map<String, dynamic> source = _castMap(node);
    final Map<String, dynamic> out = <String, dynamic>{};

    source.forEach((String rawFieldName, dynamic rawFieldValue) {
      final String fieldName = toSnakeCase(rawFieldName);
      switch (fieldName) {
        case 'items':
          out[fieldName] = sanitize(rawFieldValue);
          break;
        case 'any_of':
          if (rawFieldValue is List) {
            out[fieldName] = rawFieldValue
                .map((dynamic item) => sanitize(item, preserveNull: true))
                .toList(growable: false);
          }
          break;
        case 'properties':
        case 'defs':
          if (rawFieldValue is Map) {
            out[fieldName] = rawFieldValue.map((Object? key, Object? value) {
              return MapEntry('$key', sanitize(value));
            });
          }
          break;
        case 'format':
          final String? type = source['type'] is String
              ? source['type'] as String
              : null;
          if (type == 'integer' || type == 'number') {
            if (rawFieldValue == 'int32' || rawFieldValue == 'int64') {
              out[fieldName] = rawFieldValue;
            }
          } else if (type == 'string') {
            if (rawFieldValue == 'date-time' || rawFieldValue == 'enum') {
              out[fieldName] = rawFieldValue;
            }
          }
          break;
        case 'additional_properties':
          break;
        default:
          if (rawFieldValue != null) {
            out[fieldName] = rawFieldValue;
          }
      }
    });

    return sanitizeSchemaType(out, preserveNullType: preserveNull);
  }

  return _castMap(sanitize(schema, preserveNull: preserveNullType));
}

Map<String, dynamic> sanitizeSchemaType(
  Map<String, dynamic> schema, {
  bool preserveNullType = false,
}) {
  if (schema.isEmpty) {
    schema['type'] = 'object';
  }

  final Object? type = schema['type'];
  if (type is List) {
    final List<Object?> withoutNull = type
        .where((Object? value) => value != 'null')
        .toList();
    final bool nullable = withoutNull.length != type.length;
    Object nonNullType = withoutNull.isNotEmpty ? withoutNull.first! : 'object';
    if (withoutNull.contains('array')) {
      nonNullType = 'array';
    }
    schema['type'] = nullable ? <Object>[nonNullType, 'null'] : nonNullType;
  } else if (type == 'null' && !preserveNullType) {
    schema['type'] = <String>['object', 'null'];
  }

  final Object? schemaType = schema['type'];
  final bool isArray =
      schemaType == 'array' ||
      (schemaType is List && schemaType.contains('array'));
  if (isArray) {
    schema.putIfAbsent('items', () => <String, dynamic>{'type': 'string'});
  }
  return schema;
}

Map<String, dynamic> toGeminiSchema(Map<String, dynamic> openApiSchema) {
  final Map<String, dynamic> dereferenced = dereferenceSchema(openApiSchema);
  return sanitizeSchemaFormatsForGemini(dereferenced);
}

Map<String, dynamic> _castMap(Object? value) {
  if (value is Map) {
    return value.map((Object? key, Object? item) => MapEntry('$key', item));
  }
  return <String, dynamic>{};
}

String encodeSchemaJson(Map<String, dynamic> schema) {
  return jsonEncode(schema);
}
