/// Shared OpenAPI parsing utilities and identifier normalization helpers.
library;

import '../../_gemini_schema_util.dart';

/// Renames reserved identifiers by prefixing [value] with [prefix].
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

/// A normalized parameter model used by OpenAPI tool generation.
class ApiParameter {
  /// Creates a normalized API parameter descriptor.
  ApiParameter({
    required this.originalName,
    required this.paramLocation,
    required Map<String, Object?> paramSchema,
    this.description = '',
    String? pyName,
    this.required = false,
    this.style,
    this.explode,
  }) : paramSchema = Map<String, Object?>.from(paramSchema),
       pyName = pyName == null || pyName.isEmpty
           ? _defaultPyNameFor(originalName, paramLocation)
           : pyName;

  /// The parameter name from the source OpenAPI document.
  final String originalName;

  /// The parameter location such as `path`, `query`, or `body`.
  final String paramLocation;

  /// The parameter JSON schema.
  final Map<String, Object?> paramSchema;

  /// The parameter description.
  final String description;

  /// The generated safe argument name.
  final String pyName;

  /// Whether this parameter is required.
  final bool required;

  /// Optional OpenAPI serialization style (for example `form`, `deepObject`, `spaceDelimited`, `pipeDelimited`).
  final String? style;

  /// Optional OpenAPI explode flag controlling array and object query parameter expansion.
  final bool? explode;

  /// The Dart type hint string inferred from [paramSchema].
  String get typeHint => TypeHintHelper.getTypeHint(paramSchema);

  /// The Dart type inferred from [paramSchema].
  Type get typeValue => TypeHintHelper.getTypeValue(paramSchema);

  /// A named-argument forwarding snippet.
  String toArgString() => '$pyName: $pyName';

  /// A JSON property snippet for generated argument maps.
  String toDictProperty() => '"$pyName": $pyName';

  /// A Python-style docstring line for this parameter.
  String toPydocString() => PydocHelper.generateParamDoc(this);

  /// Serializes this parameter into a JSON-compatible map, preserving [required].
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'original_name': originalName,
      'param_location': paramLocation,
      'param_schema': Map<String, Object?>.from(paramSchema),
      'description': description,
      'py_name': pyName,
      'required': required,
      if (style != null) 'style': style,
      if (explode != null) 'explode': explode,
    };
  }

  /// Creates an [ApiParameter] from a serialized JSON map.
  factory ApiParameter.fromJson(Object? value) {
    final Map<String, Object?> data = _readMap(value);
    final Object? rawName = data['original_name'] ?? data['originalName'];
    final Object? rawLocation = data['param_location'] ?? data['paramLocation'];
    final Object? rawPyName = data['py_name'] ?? data['pyName'];
    final Object? rawRequired = data['required'];
    final Object? rawExplode = data['explode'];
    return ApiParameter(
      originalName: rawName == null ? '' : '$rawName',
      paramLocation: rawLocation == null ? '' : '$rawLocation',
      paramSchema: _readMap(data['param_schema'] ?? data['paramSchema']),
      description: data['description'] == null ? '' : '${data['description']}',
      pyName: rawPyName == null || '$rawPyName'.isEmpty ? null : '$rawPyName',
      required: _readParameterBool(rawRequired),
      style: data['style'] == null || '${data['style']}'.isEmpty
          ? null
          : '${data['style']}',
      explode: rawExplode == null ? null : _readParameterBool(rawExplode),
    );
  }

  /// Returns a copy with selectively replaced fields.
  ApiParameter copyWith({
    Object? originalName = _sentinel,
    Object? paramLocation = _sentinel,
    Map<String, Object?>? paramSchema,
    Object? description = _sentinel,
    Object? pyName = _sentinel,
    Object? required = _sentinel,
    Object? style = _sentinel,
    Object? explode = _sentinel,
  }) {
    return ApiParameter(
      originalName: identical(originalName, _sentinel)
          ? this.originalName
          : originalName as String,
      paramLocation: identical(paramLocation, _sentinel)
          ? this.paramLocation
          : paramLocation as String,
      paramSchema: paramSchema ?? this.paramSchema,
      description: identical(description, _sentinel)
          ? this.description
          : description as String,
      pyName: identical(pyName, _sentinel) ? this.pyName : pyName as String,
      required: identical(required, _sentinel)
          ? this.required
          : required as bool,
      style: identical(style, _sentinel) ? this.style : style as String?,
      explode: identical(explode, _sentinel) ? this.explode : explode as bool?,
    );
  }

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

/// Type inference helpers for OpenAPI schema fragments.
class TypeHintHelper {
  /// Returns a Dart type hint string from OpenAPI [schema].
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

  /// Returns a Dart [Type] from OpenAPI [schema].
  static Type getTypeValue(Map<String, Object?> schema) {
    final Object? type = schema['type'];
    if (type == 'integer') {
      return int;
    }
    if (type == 'number') {
      return double;
    }
    if (type == 'boolean') {
      return bool;
    }
    if (type == 'string') {
      return String;
    }
    if (type == 'array') {
      return List;
    }
    if (type == 'object') {
      return Map;
    }
    return Object;
  }
}

/// Helpers that build Python-style docs from OpenAPI metadata.
class PydocHelper {
  /// Generates one parameter docstring line for [param].
  static String generateParamDoc(ApiParameter param) {
    final String description = param.description.trim();
    return '${param.pyName} (${param.typeHint}): $description';
  }

  /// Generates a return docstring section from OpenAPI [responses].
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

bool _readParameterBool(Object? value) {
  if (value is bool) {
    return value;
  }
  if (value is num) {
    return value != 0;
  }
  if (value is String) {
    final String normalized = value.toLowerCase();
    return normalized == 'true' || normalized == '1';
  }
  return false;
}

const Object _sentinel = Object();
