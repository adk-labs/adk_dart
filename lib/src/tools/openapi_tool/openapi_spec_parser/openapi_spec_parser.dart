import 'dart:convert';

import '../../_gemini_schema_util.dart';
import '../../../auth/auth_credential.dart';
import '../../../auth/auth_schemes.dart';
import '../common/common.dart';
import '../auth/auth_helpers.dart';
import 'operation_parser.dart';

const Set<String> _validSchemaTypes = <String>{
  'array',
  'boolean',
  'integer',
  'null',
  'number',
  'object',
  'string',
};

const Set<String> _schemaContainerKeys = <String>{'schema', 'schemas'};

class OperationEndpoint {
  OperationEndpoint({
    required this.baseUrl,
    required this.path,
    required this.method,
  });

  final String baseUrl;
  final String path;
  final String method;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'base_url': baseUrl,
      'path': path,
      'method': method,
    };
  }

  factory OperationEndpoint.fromJson(Object? value) {
    final Map<String, Object?> data = _readMap(value);
    return OperationEndpoint(
      baseUrl:
          _readString(data['base_url']) ?? _readString(data['baseUrl']) ?? '',
      path: _readString(data['path']) ?? '',
      method: _readString(data['method']) ?? '',
    );
  }
}

class ParsedOperation {
  ParsedOperation({
    required this.name,
    required this.description,
    required this.endpoint,
    required this.operation,
    required this.parameters,
    required this.returnValue,
    this.authScheme,
    this.authCredential,
    this.additionalContext,
  });

  final String name;
  final String description;
  final OperationEndpoint endpoint;
  final Map<String, Object?> operation;
  final List<ApiParameter> parameters;
  final ApiParameter returnValue;
  final Object? authScheme;
  final AuthCredential? authCredential;
  final Object? additionalContext;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'name': name,
      'description': description,
      'endpoint': endpoint.toJson(),
      'operation': operation,
      'parameters': parameters
          .map(
            (ApiParameter parameter) => <String, Object?>{
              'original_name': parameter.originalName,
              'param_location': parameter.paramLocation,
              'param_schema': parameter.paramSchema,
              'description': parameter.description,
              'py_name': parameter.pyName,
              'required': parameter.required,
            },
          )
          .toList(growable: false),
      'return_value': <String, Object?>{
        'original_name': returnValue.originalName,
        'param_location': returnValue.paramLocation,
        'param_schema': returnValue.paramSchema,
        'description': returnValue.description,
        'py_name': returnValue.pyName,
        'required': returnValue.required,
      },
      if (authScheme != null) 'auth_scheme': _authSchemeToJson(authScheme),
      if (authCredential != null) 'auth_credential': authCredential,
      if (additionalContext != null) 'additional_context': additionalContext,
    };
  }

  factory ParsedOperation.fromJson(Object? value) {
    final Map<String, Object?> data = _readMap(value);
    final List<ApiParameter> parsedParameters = _readList(
      data['parameters'],
    ).map(_apiParameterFromObject).toList(growable: false);

    final ApiParameter parsedReturn = _apiParameterFromObject(
      data['return_value'] ?? data['returnValue'],
    );

    final Object? rawAuthScheme = data['auth_scheme'] ?? data['authScheme'];

    return ParsedOperation(
      name: _readString(data['name']) ?? '',
      description: _readString(data['description']) ?? '',
      endpoint: OperationEndpoint.fromJson(data['endpoint']),
      operation: _readMap(data['operation']),
      parameters: parsedParameters,
      returnValue: parsedReturn,
      authScheme: rawAuthScheme is Map<String, Object?>
          ? dictToAuthScheme(rawAuthScheme)
          : rawAuthScheme,
      authCredential: _readAuthCredential(
        data['auth_credential'] ?? data['authCredential'],
      ),
      additionalContext:
          data['additional_context'] ?? data['additionalContext'],
    );
  }
}

class OpenApiSpecParser {
  List<ParsedOperation> parse(Map<String, Object?> openapiSpecDict) {
    final Map<String, Object?> resolved = _resolveReferences(openapiSpecDict);
    final Map<String, Object?> sanitized = _sanitizeSchemaTypes(resolved);
    return _collectOperations(sanitized);
  }

  Map<String, Object?> sanitizeSchemaTypes(Map<String, Object?> openapiSpec) {
    return _sanitizeSchemaTypes(openapiSpec);
  }

  List<ParsedOperation> _collectOperations(Map<String, Object?> openapiSpec) {
    final List<ParsedOperation> operations = <ParsedOperation>[];

    String baseUrl = '';
    final List<Object?> servers = _readList(openapiSpec['servers']);
    if (servers.isNotEmpty) {
      baseUrl = _readString(_readMap(servers.first)['url']) ?? '';
    }

    String? globalSchemeName;
    final List<Object?> security = _readList(openapiSpec['security']);
    if (security.isNotEmpty) {
      final Map<String, Object?> firstSecurity = _readMap(security.first);
      if (firstSecurity.isNotEmpty) {
        globalSchemeName = firstSecurity.keys.first;
      }
    }

    final Map<String, Object?> authSchemes = _readMap(
      _readMap(openapiSpec['components'])['securitySchemes'],
    );

    final Map<String, Object?> paths = _readMap(openapiSpec['paths']);
    for (final MapEntry<String, Object?> pathEntry in paths.entries) {
      final Map<String, Object?> pathItem = _readMap(pathEntry.value);
      if (pathItem.isEmpty && pathEntry.value == null) {
        continue;
      }

      for (final String method in const <String>[
        'get',
        'post',
        'put',
        'delete',
        'patch',
        'head',
        'options',
        'trace',
      ]) {
        final Map<String, Object?> operationDict = _readMap(pathItem[method]);
        if (operationDict.isEmpty) {
          continue;
        }

        final List<Object?> operationParameters = _readList(
          operationDict['parameters'],
        );
        final List<Object?> pathParameters = _readList(pathItem['parameters']);

        final Map<String, Object?> normalizedOperation =
            Map<String, Object?>.from(operationDict)
              ..['parameters'] = <Object?>[
                ...operationParameters,
                ...pathParameters,
              ];

        if (_readString(normalizedOperation['operationId']) == null) {
          normalizedOperation['operationId'] = toSnakeCase(
            '${pathEntry.key}_$method',
          );
        }

        final OperationEndpoint endpoint = OperationEndpoint(
          baseUrl: baseUrl,
          path: pathEntry.key,
          method: method,
        );

        final OperationParser parser = OperationParser(normalizedOperation);

        final String localSchemeName = parser.getAuthSchemeName();
        final String? authSchemeName = localSchemeName.isNotEmpty
            ? localSchemeName
            : globalSchemeName;

        final Object? rawAuthScheme = authSchemeName == null
            ? null
            : authSchemes[authSchemeName];
        final Object? authScheme = rawAuthScheme is Map<String, Object?>
            ? dictToAuthScheme(rawAuthScheme)
            : (rawAuthScheme is Map
                  ? dictToAuthScheme(
                      rawAuthScheme.map(
                        (Object? key, Object? value) => MapEntry('$key', value),
                      ),
                    )
                  : rawAuthScheme);

        operations.add(
          ParsedOperation(
            name: parser.getFunctionName(),
            description:
                _readString(normalizedOperation['description']) ??
                _readString(normalizedOperation['summary']) ??
                '',
            endpoint: endpoint,
            operation: normalizedOperation,
            parameters: parser.getParameters(),
            returnValue:
                parser.getReturnValue() ??
                ApiParameter(
                  originalName: '',
                  paramLocation: '',
                  paramSchema: <String, Object?>{},
                ),
            authScheme: authScheme,
            authCredential: null,
            additionalContext: <String, Object?>{},
          ),
        );
      }
    }

    return operations;
  }

  Map<String, Object?> _sanitizeSchemaTypes(Map<String, Object?> openapiSpec) {
    final Map<String, Object?> copy = _deepCopyMap(openapiSpec);

    Object? sanitizeRecursive(Object? value, {required bool inSchema}) {
      if (value is Map) {
        final Map<String, Object?> map = _readMap(value);
        if (inSchema) {
          _sanitizeTypeField(map);
        }

        for (final MapEntry<String, Object?> entry in Map<String, Object?>.from(
          map,
        ).entries) {
          map[entry.key] = sanitizeRecursive(
            entry.value,
            inSchema: inSchema || _schemaContainerKeys.contains(entry.key),
          );
        }
        return map;
      }
      if (value is List) {
        return value
            .map((Object? item) => sanitizeRecursive(item, inSchema: inSchema))
            .toList(growable: false);
      }
      return value;
    }

    return _readMap(sanitizeRecursive(copy, inSchema: false));
  }

  void _sanitizeTypeField(Map<String, Object?> schema) {
    if (!schema.containsKey('type')) {
      return;
    }

    final Object? typeValue = schema['type'];
    if (typeValue is String) {
      final String normalized = typeValue.toLowerCase();
      if (_validSchemaTypes.contains(normalized)) {
        schema['type'] = normalized;
      } else {
        schema.remove('type');
      }
      return;
    }

    if (typeValue is List) {
      final List<String> valid = <String>[];
      for (final Object? item in typeValue) {
        if (item is! String) {
          continue;
        }
        final String normalized = item.toLowerCase();
        if (!_validSchemaTypes.contains(normalized)) {
          continue;
        }
        if (!valid.contains(normalized)) {
          valid.add(normalized);
        }
      }
      if (valid.isEmpty) {
        schema.remove('type');
      } else {
        schema['type'] = valid;
      }
    }
  }

  Map<String, Object?> _resolveReferences(Map<String, Object?> openapiSpec) {
    final Map<String, Object?> copy = _deepCopyMap(openapiSpec);
    final Map<String, Object?> resolvedCache = <String, Object?>{};

    Object? resolveRef(String ref, Map<String, Object?> document) {
      final List<String> parts = ref.split('/');
      if (parts.isEmpty || parts.first != '#') {
        throw ArgumentError('External references not supported: $ref');
      }

      Object? current = document;
      for (int i = 1; i < parts.length; i += 1) {
        if (current is! Map) {
          return null;
        }
        final Map<String, Object?> map = _readMap(current);
        if (!map.containsKey(parts[i])) {
          return null;
        }
        current = map[parts[i]];
      }
      return current;
    }

    Object? recursiveResolve(
      Object? value,
      Map<String, Object?> document,
      Set<String> seenRefs,
    ) {
      if (value is Map) {
        final Map<String, Object?> map = _readMap(value);
        final String? ref = _readString(map[r'$ref']);
        if (ref != null) {
          if (seenRefs.contains(ref) && !resolvedCache.containsKey(ref)) {
            final Map<String, Object?> clone = Map<String, Object?>.from(map)
              ..remove(r'$ref');
            return clone;
          }

          seenRefs.add(ref);
          if (resolvedCache.containsKey(ref)) {
            return _deepCopyObject(resolvedCache[ref]);
          }

          final Object? resolvedValue = resolveRef(ref, document);
          if (resolvedValue == null) {
            return map;
          }

          final Object? nested = recursiveResolve(
            resolvedValue,
            document,
            seenRefs,
          );
          resolvedCache[ref] = _deepCopyObject(nested);
          return _deepCopyObject(nested);
        }

        final Map<String, Object?> output = <String, Object?>{};
        for (final MapEntry<String, Object?> entry in map.entries) {
          output[entry.key] = recursiveResolve(entry.value, document, seenRefs);
        }
        return output;
      }

      if (value is List) {
        return value
            .map((Object? item) => recursiveResolve(item, document, seenRefs))
            .toList(growable: false);
      }
      return value;
    }

    return _readMap(recursiveResolve(copy, copy, <String>{}));
  }
}

Map<String, Object?> _deepCopyMap(Map<String, Object?> input) {
  return _readMap(_deepCopyObject(input));
}

Object? _deepCopyObject(Object? value) {
  if (value is Map) {
    final Map<String, Object?> source = _readMap(value);
    return source.map(
      (String key, Object? item) => MapEntry(key, _deepCopyObject(item)),
    );
  }
  if (value is List) {
    return value.map(_deepCopyObject).toList(growable: false);
  }
  return value;
}

Object? _authSchemeToJson(Object? authScheme) {
  if (authScheme == null) {
    return null;
  }
  if (authScheme is SecurityScheme) {
    return authScheme.toJson();
  }
  if (authScheme is Map) {
    return _readMap(authScheme);
  }
  return authScheme;
}

ApiParameter _apiParameterFromObject(Object? value) {
  final Map<String, Object?> data = _readMap(value);
  return ApiParameter(
    originalName:
        _readString(data['original_name']) ??
        _readString(data['originalName']) ??
        '',
    paramLocation:
        _readString(data['param_location']) ??
        _readString(data['paramLocation']) ??
        '',
    paramSchema: _readMap(data['param_schema'] ?? data['paramSchema']),
    description: _readString(data['description']) ?? '',
    pyName: _readString(data['py_name']) ?? _readString(data['pyName']),
    required: _readBool(data['required']),
  );
}

AuthCredential? _readAuthCredential(Object? value) {
  if (value is AuthCredential) {
    return value.copyWith();
  }
  return null;
}

Map<String, Object?> _readMap(Object? value) {
  if (value is Map<String, Object?>) {
    return Map<String, Object?>.from(value);
  }
  if (value is Map) {
    return value.map((Object? key, Object? item) => MapEntry('$key', item));
  }
  return <String, Object?>{};
}

List<Object?> _readList(Object? value) {
  if (value is List<Object?>) {
    return List<Object?>.from(value);
  }
  if (value is List) {
    return value.cast<Object?>();
  }
  return <Object?>[];
}

String? _readString(Object? value) {
  if (value == null) {
    return null;
  }
  final String text = '$value';
  return text.isEmpty ? null : text;
}

bool _readBool(Object? value) {
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

ParsedOperation parsedOperationFromJsonString(String source) {
  final Object? data = jsonDecode(source);
  return ParsedOperation.fromJson(data);
}
