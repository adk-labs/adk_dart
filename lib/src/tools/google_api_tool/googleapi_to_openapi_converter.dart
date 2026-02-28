import 'dart:convert';
import 'dart:io';

typedef GoogleDiscoverySpecFetcher =
    Future<Map<String, Object?>> Function(String apiName, String apiVersion);

class GoogleApiToOpenApiConverter {
  GoogleApiToOpenApiConverter(
    this.apiName,
    this.apiVersion, {
    GoogleDiscoverySpecFetcher? specFetcher,
    Map<String, Object?>? discoverySpec,
  }) : _specFetcher = specFetcher,
       _googleApiSpec = discoverySpec == null
           ? null
           : Map<String, Object?>.from(discoverySpec);

  final String apiName;
  final String apiVersion;
  final GoogleDiscoverySpecFetcher? _specFetcher;
  Map<String, Object?>? _googleApiSpec;
  final Map<String, Object?> _openApiSpec = <String, Object?>{
    'openapi': '3.0.0',
    'info': <String, Object?>{},
    'servers': <Object?>[],
    'paths': <String, Object?>{},
    'components': <String, Object?>{
      'schemas': <String, Object?>{},
      'securitySchemes': <String, Object?>{},
    },
  };

  Future<void> fetchGoogleApiSpec() async {
    if (_googleApiSpec != null) {
      return;
    }
    final GoogleDiscoverySpecFetcher fetcher =
        _specFetcher ?? _defaultGoogleDiscoverySpecFetcher;
    _googleApiSpec = await fetcher(apiName, apiVersion);
  }

  Future<Map<String, Object?>> convert() async {
    await fetchGoogleApiSpec();
    final Map<String, Object?> spec = _googleApiSpec!;

    _convertInfo(spec);
    _convertServers(spec);
    _convertSecuritySchemes(spec);
    _convertSchemas(spec);
    _convertResources(_readMap(spec['resources']));
    _convertMethods(_readMap(spec['methods']), '/');

    return _openApiSpec;
  }

  void _convertInfo(Map<String, Object?> spec) {
    _openApiSpec['info'] = <String, Object?>{
      'title': spec['title'] ?? '$apiName API',
      'description': spec['description'] ?? '',
      'version': spec['version'] ?? apiVersion,
      'contact': <String, Object?>{},
      'termsOfService': spec['documentationLink'] ?? '',
    };

    final Object? docsLink = spec['documentationLink'];
    if (docsLink is String && docsLink.isNotEmpty) {
      _openApiSpec['externalDocs'] = <String, Object?>{
        'description': 'API Documentation',
        'url': docsLink,
      };
    }
  }

  void _convertServers(Map<String, Object?> spec) {
    final String rootUrl = '${spec['rootUrl'] ?? ''}';
    final String servicePath = '${spec['servicePath'] ?? ''}';
    String baseUrl = '$rootUrl$servicePath';
    if (baseUrl.endsWith('/')) {
      baseUrl = baseUrl.substring(0, baseUrl.length - 1);
    }

    _openApiSpec['servers'] = <Object?>[
      <String, Object?>{
        'url': baseUrl,
        'description': '$apiName $apiVersion API',
      },
    ];
  }

  void _convertSecuritySchemes(Map<String, Object?> spec) {
    final Map<String, Object?> auth = _readMap(spec['auth']);
    final Map<String, Object?> oauth2 = _readMap(auth['oauth2']);
    final Map<String, Object?> components = _readMap(
      _openApiSpec['components'],
    );
    final Map<String, Object?> securitySchemes = _readMap(
      components['securitySchemes'],
    );

    final Map<String, String> formattedScopes = <String, String>{};
    if (oauth2.isNotEmpty) {
      final Map<String, Object?> scopes = _readMap(oauth2['scopes']);
      for (final MapEntry<String, Object?> entry in scopes.entries) {
        final Map<String, Object?> scopeInfo = _readMap(entry.value);
        formattedScopes[entry.key] = '${scopeInfo['description'] ?? ''}';
      }

      securitySchemes['oauth2'] = <String, Object?>{
        'type': 'oauth2',
        'description': 'OAuth 2.0 authentication',
        'flows': <String, Object?>{
          'authorizationCode': <String, Object?>{
            'authorizationUrl': 'https://accounts.google.com/o/oauth2/auth',
            'tokenUrl': 'https://oauth2.googleapis.com/token',
            'scopes': formattedScopes,
          },
        },
      };
    }

    securitySchemes['apiKey'] = <String, Object?>{
      'type': 'apiKey',
      'in': 'query',
      'name': 'key',
      'description': 'API key for accessing this API',
    };

    _openApiSpec['security'] = <Object?>[
      if (oauth2.isNotEmpty)
        <String, Object?>{'oauth2': formattedScopes.keys.toList()},
      <String, Object?>{'apiKey': const <Object?>[]},
    ];
  }

  void _convertSchemas(Map<String, Object?> spec) {
    final Map<String, Object?> schemas = _readMap(spec['schemas']);
    final Map<String, Object?> components = _readMap(
      _openApiSpec['components'],
    );
    final Map<String, Object?> openApiSchemas = _readMap(components['schemas']);

    for (final MapEntry<String, Object?> entry in schemas.entries) {
      openApiSchemas[entry.key] = _convertSchemaObject(_readMap(entry.value));
    }
  }

  Map<String, Object?> _convertSchemaObject(Map<String, Object?> schemaDef) {
    final Map<String, Object?> result = <String, Object?>{};
    final String? type = schemaDef['type'] as String?;
    if (type != null) {
      if (type == 'object') {
        result['type'] = 'object';
        final Map<String, Object?> properties = _readMap(
          schemaDef['properties'],
        );
        if (properties.isNotEmpty) {
          final Map<String, Object?> converted = <String, Object?>{};
          final List<String> required = <String>[];
          for (final MapEntry<String, Object?> entry in properties.entries) {
            final Map<String, Object?> propertyDef = _readMap(entry.value);
            final Map<String, Object?> value = _convertSchemaObject(propertyDef);
            converted[entry.key] = value;
            if (_readBool(propertyDef['required'])) {
              required.add(entry.key);
            }
          }
          result['properties'] = converted;
          if (required.isNotEmpty) {
            result['required'] = required;
          }
        }
      } else if (type == 'array') {
        result['type'] = 'array';
        final Map<String, Object?> items = _readMap(schemaDef['items']);
        if (items.isNotEmpty) {
          result['items'] = _convertSchemaObject(items);
        }
      } else if (type == 'any') {
        result['oneOf'] = <Object?>[
          <String, Object?>{'type': 'object'},
          <String, Object?>{'type': 'array'},
          <String, Object?>{'type': 'string'},
          <String, Object?>{'type': 'number'},
          <String, Object?>{'type': 'boolean'},
          <String, Object?>{'type': 'null'},
        ];
      } else {
        result['type'] = type;
      }
    }

    final String? ref = schemaDef['\$ref'] as String?;
    if (ref != null) {
      result['\$ref'] = ref.startsWith('#')
          ? ref.replaceFirst('#', '#/components/schemas/')
          : '#/components/schemas/$ref';
    }

    _copyIfPresent(schemaDef, result, 'format');
    _copyIfPresent(schemaDef, result, 'enum');
    _copyIfPresent(schemaDef, result, 'description');
    _copyIfPresent(schemaDef, result, 'pattern');
    _copyIfPresent(schemaDef, result, 'default');

    return result;
  }

  void _convertResources(
    Map<String, Object?> resources, [
    String parentPath = '',
  ]) {
    for (final MapEntry<String, Object?> entry in resources.entries) {
      final String resourcePath = '$parentPath/${entry.key}';
      final Map<String, Object?> resourceData = _readMap(entry.value);
      _convertMethods(_readMap(resourceData['methods']), resourcePath);
      final Map<String, Object?> nested = _readMap(resourceData['resources']);
      if (nested.isNotEmpty) {
        _convertResources(nested, resourcePath);
      }
    }
  }

  void _convertMethods(Map<String, Object?> methods, String resourcePath) {
    final Map<String, Object?> paths = _readMap(_openApiSpec['paths']);
    for (final MapEntry<String, Object?> entry in methods.entries) {
      final Map<String, Object?> methodData = _readMap(entry.value);
      final String httpMethod = '${methodData['httpMethod'] ?? 'GET'}'
          .toLowerCase();
      String restPath =
          '${methodData['flatPath'] ?? methodData['path'] ?? '/'}';
      if (!restPath.startsWith('/')) {
        restPath = '/$restPath';
      }
      final List<String> pathParams = _extractPathParameters(restPath);
      final Map<String, Object?> pathItem = _readMap(paths[restPath]);
      pathItem[httpMethod] = _convertOperation(methodData, pathParams);
      paths[restPath] = pathItem;
    }
  }

  List<String> _extractPathParameters(String path) {
    final List<String> params = <String>[];
    for (final String segment in path.split('/')) {
      if (segment.startsWith('{') && segment.endsWith('}')) {
        params.add(segment.substring(1, segment.length - 1));
      }
    }
    return params;
  }

  Map<String, Object?> _convertOperation(
    Map<String, Object?> methodData,
    List<String> pathParams,
  ) {
    final Map<String, Object?> operation = <String, Object?>{
      'operationId': methodData['id'] ?? '',
      'summary': methodData['description'] ?? '',
      'description': methodData['description'] ?? '',
      'parameters': <Object?>[],
      'responses': <String, Object?>{
        '200': <String, Object?>{'description': 'Successful operation'},
        '400': <String, Object?>{'description': 'Bad request'},
        '401': <String, Object?>{'description': 'Unauthorized'},
        '403': <String, Object?>{'description': 'Forbidden'},
        '404': <String, Object?>{'description': 'Not found'},
        '500': <String, Object?>{'description': 'Server error'},
      },
    };

    final List<Object?> parameters = <Object?>[];
    for (final String paramName in pathParams) {
      parameters.add(<String, Object?>{
        'name': paramName,
        'in': 'path',
        'required': true,
        'schema': <String, Object?>{'type': 'string'},
      });
    }

    final Map<String, Object?> methodParams = _readMap(
      methodData['parameters'],
    );
    for (final MapEntry<String, Object?> entry in methodParams.entries) {
      if (pathParams.contains(entry.key)) {
        continue;
      }
      final Map<String, Object?> paramData = _readMap(entry.value);
      parameters.add(<String, Object?>{
        'name': entry.key,
        'in': paramData['location'] ?? 'query',
        'description': paramData['description'] ?? '',
        'required': _readBool(paramData['required']),
        'schema': _convertParameterSchema(paramData),
      });
    }
    operation['parameters'] = parameters;

    final Map<String, Object?> request = _readMap(methodData['request']);
    final String? requestRef = request['\$ref'] as String?;
    if (requestRef != null && requestRef.isNotEmpty) {
      operation['requestBody'] = <String, Object?>{
        'description': 'Request body',
        'content': <String, Object?>{
          'application/json': <String, Object?>{
            'schema': <String, Object?>{
              '\$ref': requestRef.startsWith('#')
                  ? requestRef.replaceFirst('#', '#/components/schemas/')
                  : '#/components/schemas/$requestRef',
            },
          },
        },
        'required': true,
      };
    }

    final Map<String, Object?> response = _readMap(methodData['response']);
    final String? responseRef = response['\$ref'] as String?;
    if (responseRef != null && responseRef.isNotEmpty) {
      final Map<String, Object?> responses = _readMap(operation['responses']);
      final Map<String, Object?> success = _readMap(responses['200']);
      success['content'] = <String, Object?>{
        'application/json': <String, Object?>{
          'schema': <String, Object?>{
            '\$ref': responseRef.startsWith('#')
                ? responseRef.replaceFirst('#', '#/components/schemas/')
                : '#/components/schemas/$responseRef',
          },
        },
      };
      responses['200'] = success;
      operation['responses'] = responses;
    }

    final List<Object?> scopes = _readList(methodData['scopes']);
    if (scopes.isNotEmpty) {
      operation['security'] = <Object?>[
        <String, Object?>{'oauth2': scopes},
      ];
    }

    return operation;
  }

  Map<String, Object?> _convertParameterSchema(Map<String, Object?> paramData) {
    final Map<String, Object?> schema = <String, Object?>{
      'type': paramData['type'] ?? 'string',
    };
    _copyIfPresent(paramData, schema, 'enum');
    _copyIfPresent(paramData, schema, 'format');
    _copyIfPresent(paramData, schema, 'default');
    _copyIfPresent(paramData, schema, 'pattern');
    return schema;
  }

  String saveOpenApiSpec() {
    return const JsonEncoder.withIndent('  ').convert(_openApiSpec);
  }
}

Future<Map<String, Object?>> _defaultGoogleDiscoverySpecFetcher(
  String apiName,
  String apiVersion,
) async {
  final Uri uri = Uri.parse(
    'https://www.googleapis.com/discovery/v1/apis/$apiName/$apiVersion/rest',
  );
  final HttpClient client = HttpClient();
  try {
    final HttpClientRequest request = await client.getUrl(uri);
    final HttpClientResponse response = await request.close();
    final String body = await utf8.decodeStream(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'Google discovery request failed (${response.statusCode}): $body',
      );
    }
    final Object? decoded = jsonDecode(body);
    if (decoded is! Map) {
      throw StateError('Google discovery response is malformed.');
    }
    return decoded.map(
      (Object? key, Object? value) => MapEntry('$key', value),
    );
  } finally {
    client.close(force: true);
  }
}

void _copyIfPresent(
  Map<String, Object?> source,
  Map<String, Object?> target,
  String key,
) {
  if (source.containsKey(key)) {
    target[key] = source[key];
  }
}

bool _readBool(Object? value) {
  if (value is bool) {
    return value;
  }
  if (value is num) {
    return value != 0;
  }
  if (value is String) {
    return value.toLowerCase() == 'true';
  }
  return false;
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

List<Object?> _readList(Object? value) {
  if (value is List<Object?>) {
    return value;
  }
  if (value is List) {
    return value.cast<Object?>();
  }
  return <Object?>[];
}
