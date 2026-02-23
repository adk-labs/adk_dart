import '../../_gemini_schema_util.dart';

String renamePythonKeywords(String value, {String prefix = 'param_'}) {
  const Set<String> reserved = <String>{
    'if',
    'for',
    'while',
    'switch',
    'case',
    'default',
    'class',
    'enum',
    'mixin',
    'extension',
    'import',
    'export',
    'part',
    'library',
    'return',
    'continue',
    'break',
    'assert',
    'throw',
    'try',
    'catch',
    'finally',
    'const',
    'final',
    'var',
    'void',
    'dynamic',
    'with',
    'is',
    'in',
    'on',
    'as',
    'new',
    'this',
    'super',
    'true',
    'false',
    'null',
  };
  if (reserved.contains(value)) {
    return '$prefix$value';
  }
  return value;
}

class ApiParameter {
  ApiParameter({
    required this.originalName,
    required this.paramLocation,
    required Map<String, Object?> paramSchema,
    this.description = '',
    String? pyName,
    this.required = false,
  }) : paramSchema = Map<String, Object?>.from(paramSchema),
       pyName = pyName == null || pyName.isEmpty
           ? _defaultPyNameFor(originalName, paramLocation)
           : pyName;

  final String originalName;
  final String paramLocation;
  final Map<String, Object?> paramSchema;
  final String description;
  final String pyName;
  final bool required;

  String get typeHint => TypeHintHelper.getTypeHint(paramSchema);

  String toArgString() => '$pyName: $pyName';

  String toDictProperty() => '"$pyName": $pyName';

  String toPydocString() => PydocHelper.generateParamDoc(this);

  static String _defaultPyNameFor(String originalName, String location) {
    final String normalized = renamePythonKeywords(toSnakeCase(originalName));
    if (normalized.isNotEmpty) {
      return normalized;
    }
    switch (location) {
      case 'body':
        return 'body';
      case 'query':
        return 'query_param';
      case 'path':
        return 'path_param';
      case 'header':
        return 'header_param';
      case 'cookie':
        return 'cookie_param';
      default:
        return 'value';
    }
  }
}

class TypeHintHelper {
  static String getTypeHint(Map<String, Object?> schema) {
    final Object? type = schema['type'];
    if (type == 'integer') {
      return 'int';
    }
    if (type == 'number') {
      return 'double';
    }
    if (type == 'boolean') {
      return 'bool';
    }
    if (type == 'string') {
      return 'String';
    }
    if (type == 'array') {
      final Map<String, Object?> items = _readMap(schema['items']);
      return 'List<${getTypeHint(items)}>';
    }
    if (type == 'object') {
      return 'Map<String, Object?>';
    }
    return 'Object?';
  }
}

class PydocHelper {
  static String generateParamDoc(ApiParameter param) {
    final String description = param.description.trim();
    return '${param.pyName} (${param.typeHint}): $description';
  }

  static String generateReturnDoc(Map<String, Object?> responses) {
    final List<MapEntry<String, Object?>> sorted = responses.entries.toList()
      ..sort((MapEntry<String, Object?> a, MapEntry<String, Object?> b) {
        return a.key.compareTo(b.key);
      });
    final MapEntry<String, Object?> qualified = sorted.firstWhere(
      (MapEntry<String, Object?> entry) =>
          entry.key.startsWith('2') &&
          _readMap(entry.value).containsKey('content'),
      orElse: () => const MapEntry<String, Object?>('', <String, Object?>{}),
    );
    if (qualified.key.isEmpty) {
      return '';
    }

    final Map<String, Object?> response = _readMap(qualified.value);
    final String description = '${response['description'] ?? ''}'.trim();
    final Map<String, Object?> content = _readMap(response['content']);
    final Map<String, Object?> first = content.isEmpty
        ? <String, Object?>{}
        : _readMap(content.values.first);
    final String hint = TypeHintHelper.getTypeHint(_readMap(first['schema']));
    return 'Returns ($hint): $description';
  }
}

Map<String, Object?> _readMap(Object? value) {
  if (value is Map<String, Object?>) {
    return value;
  }
  if (value is Map) {
    return value.map((Object? key, Object? item) => MapEntry('$key', item));
  }
  return <String, Object?>{};
}
