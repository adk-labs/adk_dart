String? jsonSchemaTypeForValue(Object? value) {
  if (value == null) {
    return 'null';
  }
  if (value is String) {
    return 'string';
  }
  if (value is int) {
    return 'integer';
  }
  if (value is num) {
    return 'number';
  }
  if (value is bool) {
    return 'boolean';
  }
  if (value is List) {
    return 'array';
  }
  if (value is Map) {
    return 'object';
  }
  return null;
}

Map<String, dynamic> addUnevaluatedItemsToFixedLenTupleSchema(
  Map<String, dynamic> jsonSchema,
) {
  final Object? maxItems = jsonSchema['maxItems'];
  final Object? prefixItems = jsonSchema['prefixItems'];
  if (jsonSchema['type'] == 'array' &&
      maxItems is int &&
      prefixItems is List &&
      prefixItems.length == maxItems) {
    jsonSchema['unevaluatedItems'] = false;
  }
  return jsonSchema;
}

bool isDefaultValueCompatible(Object? defaultValue, Object? annotation) {
  if (annotation == null) {
    return true;
  }
  if (defaultValue == null) {
    return true;
  }
  if (annotation is Type) {
    return _isInstanceOfType(defaultValue, annotation);
  }
  if (annotation is String) {
    return _isCompatibleWithTypeName(defaultValue, annotation);
  }
  if (annotation is List) {
    for (final Object? value in annotation) {
      if (isDefaultValueCompatible(defaultValue, value)) {
        return true;
      }
    }
    return false;
  }
  return true;
}

Map<String, dynamic> parseParameterSchema({
  required String name,
  Object? annotation,
  Object? defaultValue,
}) {
  final String inferredType =
      _schemaTypeFromAnnotation(annotation) ??
      jsonSchemaTypeForValue(defaultValue) ??
      'object';
  final Map<String, dynamic> schema = <String, dynamic>{'type': inferredType};
  if (defaultValue != null) {
    schema['default'] = defaultValue;
  }
  return <String, dynamic>{name: schema};
}

String? _schemaTypeFromAnnotation(Object? annotation) {
  if (annotation is String) {
    final String normalized = annotation.toLowerCase();
    switch (normalized) {
      case 'string':
      case 'str':
        return 'string';
      case 'int':
      case 'integer':
        return 'integer';
      case 'double':
      case 'num':
      case 'float':
      case 'number':
        return 'number';
      case 'bool':
      case 'boolean':
        return 'boolean';
      case 'list':
      case 'array':
        return 'array';
      case 'map':
      case 'dict':
      case 'object':
        return 'object';
      case 'null':
        return 'null';
    }
  }
  if (annotation is Type) {
    if (annotation == String) {
      return 'string';
    }
    if (annotation == int) {
      return 'integer';
    }
    if (annotation == double || annotation == num) {
      return 'number';
    }
    if (annotation == bool) {
      return 'boolean';
    }
    if (annotation == List) {
      return 'array';
    }
    if (annotation == Map) {
      return 'object';
    }
  }
  return null;
}

bool _isInstanceOfType(Object value, Type type) {
  if (type == String) {
    return value is String;
  }
  if (type == int) {
    return value is int;
  }
  if (type == double) {
    return value is double;
  }
  if (type == num) {
    return value is num;
  }
  if (type == bool) {
    return value is bool;
  }
  if (type == List) {
    return value is List;
  }
  if (type == Map) {
    return value is Map;
  }
  return true;
}

bool _isCompatibleWithTypeName(Object value, String typeName) {
  final String normalized = typeName.toLowerCase();
  switch (normalized) {
    case 'string':
    case 'str':
      return value is String;
    case 'int':
    case 'integer':
      return value is int;
    case 'double':
    case 'float':
    case 'number':
      return value is num;
    case 'bool':
    case 'boolean':
      return value is bool;
    case 'array':
    case 'list':
      return value is List;
    case 'object':
    case 'map':
    case 'dict':
      return value is Map;
    default:
      return true;
  }
}
