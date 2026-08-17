/// OpenAPI specification parser and endpoint metadata models.
library;

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

const Set<String> _allowedHttpMethods = <String>{
  'get',
  'post',
  'put',
  'delete',
  'patch',
  'head',
  'options',
  'trace',
};

/// Endpoint metadata resolved from an OpenAPI path/method entry.
class OperationEndpoint {
  /// Creates an HTTP endpoint description for an OpenAPI operation.
  OperationEndpoint({
    required this.baseUrl,
    required this.path,
    required this.method,
  });

  /// The server base URL.
  final String baseUrl;

  /// The path template of the operation.
  final String path;

  /// The HTTP method in lowercase form.
  final String method;

  /// A JSON map representation of this endpoint.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'base_url': baseUrl,
      'path': path,
      'method': method,
    };
  }

  /// Creates an [OperationEndpoint] from serialized [value].
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

/// Fully parsed OpenAPI operation model used to build ADK tools.
class ParsedOperation {
  /// Creates a parsed OpenAPI operation model.
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

  /// The generated function name for this operation.
  final String name;

  /// The operation description used by tools.
  final String description;

  /// The resolved endpoint metadata.
  final OperationEndpoint endpoint;

  /// The normalized raw operation object from the OpenAPI document.
  final Map<String, Object?> operation;

  /// Parsed input parameters for this operation.
  final List<ApiParameter> parameters;

  /// Parsed return schema for this operation.
  final ApiParameter returnValue;

  /// The resolved authentication scheme, when available.
  final Object? authScheme;

  /// Optional credential instance bound to the operation.
  final AuthCredential? authCredential;

  /// Additional operation context captured during parsing.
  final Object? additionalContext;

  /// A JSON map representation of this parsed operation.
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

  /// Creates a [ParsedOperation] from serialized [value].
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

/// Parser that converts OpenAPI documents into [ParsedOperation] entries.
class OpenApiSpecParser {
  /// Creates an OpenAPI parser.
  OpenApiSpecParser({
    this.preservePropertyNames = false,
    this.externalDocuments = const <String, Map<String, Object?>>{},
  });

  /// Whether parameter/property names should keep their source casing.
  final bool preservePropertyNames;

  /// External referenced OpenAPI / JSON Schema documents mapped by URL or relative path.
  final Map<String, Map<String, Object?>> externalDocuments;

  /// Parses [openapiSpecDict] into normalized [ParsedOperation] values.
  List<ParsedOperation> parse(Map<String, Object?> openapiSpecDict) {
    final Map<String, Object?> resolved = _resolveReferences(openapiSpecDict);
    final Map<String, Object?> sanitized = _sanitizeSchemaTypes(resolved);
    return _collectOperations(sanitized);
  }

  List<ParsedOperation> _collectOperations(Map<String, Object?> openapiSpec) {
    final List<ParsedOperation> operations = <ParsedOperation>[];

    String baseUrl = '';
    final List<Object?> servers = _readList(openapiSpec['servers']);
    if (servers.isNotEmpty) {
      baseUrl = _readString(_readMap(servers.first)['url']) ?? '';
    }

    String? globalSchemeName;
    final Map<String, Object?> globalSecurity = _readMap(
      _readList(openapiSpec['security']).firstOrNull,
    );
    if (globalSecurity.isNotEmpty) {
      globalSchemeName = globalSecurity.keys.first;
    }

    final Map<String, Object?> components = _readMap(openapiSpec['components']);
    final Map<String, Object?> authSchemes = _readMap(
      components['securitySchemes'] ?? components['security_schemes'],
    );

    final Map<String, Object?> paths = _readMap(openapiSpec['paths']);
    for (final MapEntry<String, Object?> pathEntry in paths.entries) {
      final Map<String, Object?> pathObject = _readMap(pathEntry.value);
      final List<Object?> pathParameters = _readList(pathObject['parameters']);

      for (final MapEntry<String, Object?> opEntry in pathObject.entries) {
        final String method = opEntry.key.toLowerCase();
        if (!_allowedHttpMethods.contains(method)) {
          continue;
        }

        final Map<String, Object?> operationDict = _readMap(opEntry.value);
        final List<Object?> operationParameters = _readList(
          operationDict['parameters'],
        );
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

        final OperationParser parser = OperationParser(
          normalizedOperation,
          preservePropertyNames: preservePropertyNames,
        );

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
            additionalContext: null,
          ),
        );
      }
    }

    return operations;
  }

  Map<String, Object?> _sanitizeSchemaTypes(Map<String, Object?> openapiSpec) {
    final Map<String, Object?> copy = _deepCopyMap(openapiSpec);
    final List<Map<String, Object?>> schemas = <Map<String, Object?>>[];
    _collectSchemas(copy, schemas);

    for (final Map<String, Object?> schema in schemas) {
      _cleanSchemaType(schema);
    }
    return copy;
  }

  void _collectSchemas(
    Object? current,
    List<Map<String, Object?>> schemas, {
    String? currentKey,
  }) {
    if (current is Map) {
      final Map<String, Object?> map = _readMap(current);
      if (currentKey != null &&
          _schemaContainerKeys.contains(currentKey.toLowerCase())) {
        schemas.add(map);
      }
      for (final MapEntry<String, Object?> entry in map.entries) {
        _collectSchemas(entry.value, schemas, currentKey: entry.key);
      }
    } else if (current is List) {
      for (final Object? item in current) {
        _collectSchemas(item, schemas, currentKey: currentKey);
      }
    }
  }

  void _cleanSchemaType(Map<String, Object?> schema) {
    final Object? rawType = schema['type'];
    if (rawType is List) {
      final List<String> valid = <String>[];
      for (final Object? item in rawType) {
        if (item is String) {
          final String normalized = item.toLowerCase();
          if (_validSchemaTypes.contains(normalized)) {
            valid.add(normalized);
          }
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

    Object? resolvePointer(String pointer, Map<String, Object?> targetDoc) {
      final List<String> parts = pointer.split('/');
      Object? current = targetDoc;
      for (int i = 1; i < parts.length; i += 1) {
        if (current is! Map) {
          return null;
        }
        final Map<String, Object?> map = _readMap(current);
        final String decodedKey = parts[i].replaceAll('~1', '/').replaceAll('~0', '~');
        if (!map.containsKey(decodedKey)) {
          return null;
        }
        current = map[decodedKey];
      }
      return current;
    }

    (Object?, Map<String, Object?>) resolveRefWithDoc(String ref, Map<String, Object?> currentDoc) {
      if (ref.startsWith('#/')) {
        return (resolvePointer(ref, currentDoc), currentDoc);
      }

      // External ref format: "http(s)://...#/components/schemas/Pet" or "./models/pet.json#/Pet"
      final int hashIdx = ref.indexOf('#');
      final String docKey = hashIdx >= 0 ? ref.substring(0, hashIdx) : ref;
      final String fragment = hashIdx >= 0 ? ref.substring(hashIdx) : '#';

      Map<String, Object?>? extDoc = externalDocuments[docKey] ??
          externalDocuments[docKey.replaceFirst(RegExp(r'^\./'), '')];

      if (extDoc == null) {
        // Fallback: match by filename
        final String filename = docKey.split('/').last;
        for (final MapEntry<String, Map<String, Object?>> entry in externalDocuments.entries) {
          if (entry.key.endsWith(filename)) {
            extDoc = entry.value;
            break;
          }
        }
      }

      if (extDoc == null) {
        return (null, currentDoc);
      }

      if (fragment == '#' || fragment.isEmpty) {
        return (extDoc, extDoc);
      }

      return (resolvePointer(fragment, extDoc), extDoc);
    }

    Object? recursiveResolve(
      Object? value,
      Map<String, Object?> activeDoc,
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

          final (Object? resolvedValue, Map<String, Object?> sourceDoc) =
              resolveRefWithDoc(ref, activeDoc);
          if (resolvedValue == null) {
            return map;
          }

          final Object? nested = recursiveResolve(
            resolvedValue,
            sourceDoc,
            seenRefs,
          );
          resolvedCache[ref] = _deepCopyObject(nested);
          return _deepCopyObject(nested);
        }

        final Map<String, Object?> output = <String, Object?>{};
        for (final MapEntry<String, Object?> entry in map.entries) {
          output[entry.key] = recursiveResolve(entry.value, activeDoc, seenRefs);
        }
        return output;
      }

      if (value is List) {
        return value
            .map((Object? item) => recursiveResolve(item, activeDoc, seenRefs))
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

/// Parses a JSON [source] string into a [ParsedOperation].
ParsedOperation parsedOperationFromJsonString(String source) {
  final Object? data = jsonDecode(source);
  return ParsedOperation.fromJson(data);
}
