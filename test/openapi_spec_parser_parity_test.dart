import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

Map<String, Object?> _minimalOpenApiSpec() {
  return <String, Object?>{
    'openapi': '3.1.0',
    'info': <String, Object?>{'title': 'Minimal API', 'version': '1.0.0'},
    'paths': <String, Object?>{
      '/test': <String, Object?>{
        'get': <String, Object?>{
          'summary': 'Test GET endpoint',
          'operationId': 'testGet',
          'responses': <String, Object?>{
            '200': <String, Object?>{
              'description': 'Successful response',
              'content': <String, Object?>{
                'application/json': <String, Object?>{
                  'schema': <String, Object?>{'type': 'string'},
                },
              },
            },
          },
        },
      },
    },
  };
}

void main() {
  group('openapi spec parser parity', () {
    test('parses minimal spec and operation metadata', () {
      final OpenApiSpecParser parser = OpenApiSpecParser();
      final List<ParsedOperation> operations = parser.parse(
        _minimalOpenApiSpec(),
      );

      expect(operations, hasLength(1));
      expect(operations.single.name, 'test_get');
      expect(operations.single.endpoint.path, '/test');
      expect(operations.single.endpoint.method, 'get');
      expect(operations.single.returnValue.typeValue, String);
    });

    test('auto-generates operation id when missing', () {
      final Map<String, Object?> spec = _minimalOpenApiSpec();
      final Map<String, Object?> operation =
          ((spec['paths'] as Map)['/test'] as Map)['get']
              as Map<String, Object?>;
      operation.remove('operationId');

      final List<ParsedOperation> operations = OpenApiSpecParser().parse(spec);
      expect(operations.single.name, 'test_get');
    });

    test('combines operation and path-level parameters', () {
      final Map<String, Object?> spec = <String, Object?>{
        'openapi': '3.1.0',
        'info': <String, Object?>{'title': 'Combine', 'version': '1.0.0'},
        'paths': <String, Object?>{
          '/test': <String, Object?>{
            'parameters': <Object?>[
              <String, Object?>{
                'name': 'global_param',
                'in': 'query',
                'schema': <String, Object?>{'type': 'string'},
              },
            ],
            'get': <String, Object?>{
              'operationId': 'testGet',
              'parameters': <Object?>[
                <String, Object?>{
                  'name': 'local_param',
                  'in': 'header',
                  'schema': <String, Object?>{'type': 'integer'},
                },
              ],
              'responses': <String, Object?>{
                '200': <String, Object?>{'description': 'ok'},
              },
            },
          },
        },
      };

      final ParsedOperation operation = OpenApiSpecParser().parse(spec).single;
      expect(operation.parameters, hasLength(2));
      expect(
        operation.parameters
            .where((ApiParameter value) => value.originalName == 'global_param')
            .single
            .paramLocation,
        'query',
      );
      expect(
        operation.parameters
            .where((ApiParameter value) => value.originalName == 'local_param')
            .single
            .paramLocation,
        'header',
      );
    });

    test('applies global and local security schemes', () {
      final Map<String, Object?> spec = _minimalOpenApiSpec();
      spec['security'] = <Object?>[
        <String, Object?>{'api_key': <Object?>[]},
      ];
      spec['components'] = <String, Object?>{
        'securitySchemes': <String, Object?>{
          'api_key': <String, Object?>{
            'type': 'apiKey',
            'in': 'header',
            'name': 'X-API-Key',
          },
          'local_auth': <String, Object?>{'type': 'http', 'scheme': 'bearer'},
        },
      };

      ParsedOperation global = OpenApiSpecParser().parse(spec).single;
      expect(global.authScheme, isA<SecurityScheme>());
      expect((global.authScheme as SecurityScheme).type, AuthSchemeType.apiKey);

      (((spec['paths'] as Map)['/test'] as Map)['get']
          as Map<String, Object?>)['security'] = <Object?>[
        <String, Object?>{'local_auth': <Object?>[]},
      ];
      global = OpenApiSpecParser().parse(spec).single;
      expect((global.authScheme as SecurityScheme).type, AuthSchemeType.http);
      expect((global.authScheme as SecurityScheme).scheme, 'bearer');
    });

    test('raises on external references', () {
      final Map<String, Object?> spec = <String, Object?>{
        'openapi': '3.1.0',
        'info': <String, Object?>{'title': 'External', 'version': '1.0.0'},
        'paths': <String, Object?>{
          '/x': <String, Object?>{
            'get': <String, Object?>{
              'responses': <String, Object?>{
                '200': <String, Object?>{
                  'description': 'ok',
                  'content': <String, Object?>{
                    'application/json': <String, Object?>{
                      'schema': <String, Object?>{
                        r'$ref': 'external.json#/components/schemas/X',
                      },
                    },
                  },
                },
              },
            },
          },
        },
      };

      expect(() => OpenApiSpecParser().parse(spec), throwsArgumentError);
    });

    test(
      'sanitizes invalid schema types but preserves security scheme type',
      () {
        final OpenApiSpecParser parser = OpenApiSpecParser();
        final Map<String, Object?> sanitized = parser.sanitizeSchemaTypes(
          <String, Object?>{
            'components': <String, Object?>{
              'schemas': <String, Object?>{
                'Invalid': <String, Object?>{'type': 'Any'},
                'Valid': <String, Object?>{'type': 'string'},
              },
              'securitySchemes': <String, Object?>{
                'api_key': <String, Object?>{
                  'type': 'apiKey',
                  'in': 'header',
                  'name': 'X-API-Key',
                },
              },
            },
          },
        );

        final Map<String, Object?> schemas =
            ((sanitized['components'] as Map)['schemas'] as Map)
                .cast<String, Object?>();
        final Map<String, Object?> securitySchemes =
            ((sanitized['components'] as Map)['securitySchemes'] as Map)
                .cast<String, Object?>();

        expect((schemas['Invalid'] as Map).containsKey('type'), isFalse);
        expect((schemas['Valid'] as Map)['type'], 'string');
        expect((securitySchemes['api_key'] as Map)['type'], 'apiKey');
      },
    );

    test('dedupes duplicate parameter names between query and body', () {
      final Map<String, Object?> spec = <String, Object?>{
        'openapi': '3.1.0',
        'info': <String, Object?>{'title': 'Duplicate', 'version': '1.0.0'},
        'paths': <String, Object?>{
          '/duplicate': <String, Object?>{
            'post': <String, Object?>{
              'operationId': 'createWithDuplicate',
              'parameters': <Object?>[
                <String, Object?>{
                  'name': 'name',
                  'in': 'query',
                  'schema': <String, Object?>{'type': 'string'},
                },
              ],
              'requestBody': <String, Object?>{
                'content': <String, Object?>{
                  'application/json': <String, Object?>{
                    'schema': <String, Object?>{
                      'type': 'object',
                      'properties': <String, Object?>{
                        'name': <String, Object?>{'type': 'integer'},
                      },
                    },
                  },
                },
              },
              'responses': <String, Object?>{
                '200': <String, Object?>{'description': 'ok'},
              },
            },
          },
        },
      };

      final ParsedOperation operation = OpenApiSpecParser().parse(spec).single;
      expect(operation.parameters, hasLength(2));
      expect(operation.parameters[0].pyName, 'name');
      expect(operation.parameters[1].pyName, 'name_0');
    });
  });

  group('operation parser parity', () {
    test('supports body schema variants and annotation helpers', () {
      final OperationParser parser = OperationParser(<String, Object?>{
        'operationId': 'my.operation',
        'summary': 'summary',
        'parameters': <Object?>[
          <String, Object?>{
            'name': 'param1',
            'in': 'query',
            'required': true,
            'schema': <String, Object?>{'type': 'string'},
            'description': 'Parameter 1',
          },
        ],
        'requestBody': <String, Object?>{
          'description': 'body description',
          'content': <String, Object?>{
            'application/json': <String, Object?>{
              'schema': <String, Object?>{
                'type': 'object',
                'properties': <String, Object?>{
                  'prop1': <String, Object?>{
                    'type': 'integer',
                    'description': 'Property 1',
                  },
                },
              },
            },
          },
        },
        'responses': <String, Object?>{
          '200': <String, Object?>{
            'description': 'Success',
            'content': <String, Object?>{
              'application/json': <String, Object?>{
                'schema': <String, Object?>{'type': 'boolean'},
              },
            },
          },
        },
        'security': <Object?>[
          <String, Object?>{'oauth2': <Object?>[]},
        ],
      });

      expect(parser.getFunctionName(), 'my_operation');
      expect(parser.getReturnTypeHint(), 'bool');
      expect(parser.getReturnTypeValue(), bool);
      expect(parser.getAuthSchemeName(), 'oauth2');
      expect(parser.getPydocString(), contains('Args:'));
      expect(parser.getJsonSchema()['title'], 'my.operation_Arguments');
      expect(parser.getSignatureParameters(), hasLength(2));
      expect(parser.getAnnotations()['return'], bool);
    });
  });

  group('openapi toolset parity', () {
    test('loads from dict/yaml and exposes tools', () async {
      final Map<String, Object?> spec = <String, Object?>{
        'openapi': '3.0.0',
        'servers': <Object?>[
          <String, Object?>{'url': 'https://example.com/v1'},
        ],
        'paths': <String, Object?>{
          '/items/{itemId}': <String, Object?>{
            'get': <String, Object?>{
              'operationId': 'items.get',
              'description': 'Get item',
              'parameters': <Object?>[
                <String, Object?>{
                  'name': 'itemId',
                  'in': 'path',
                  'required': true,
                  'schema': <String, Object?>{'type': 'string'},
                },
              ],
              'responses': <String, Object?>{
                '200': <String, Object?>{'description': 'ok'},
              },
            },
          },
        },
      };

      final OpenAPIToolset fromDict = OpenAPIToolset(specDict: spec);
      final List<BaseTool> dictTools = await fromDict.getTools();
      expect(dictTools, hasLength(1));
      expect(dictTools.single.name, 'items_get');
      expect(fromDict.getTool('items_get'), isNotNull);

      final String yamlSpec = '''
openapi: 3.0.0
servers:
  - url: https://example.com/v1
paths:
  /items:
    post:
      operationId: items.create
      description: Create item
      responses:
        "200":
          description: ok
''';
      final OpenAPIToolset fromYaml = OpenAPIToolset(
        specStr: yamlSpec,
        specStrType: 'yaml',
        toolNamePrefix: 'pref',
      );
      final List<BaseTool> prefixed = await fromYaml.getToolsWithPrefix();
      expect(prefixed, hasLength(1));
      expect(prefixed.single.name, 'pref_items_create');
    });

    test('returns auth config when auth scheme is configured', () {
      final OpenAPIToolset toolset = OpenAPIToolset(
        specDict: _minimalOpenApiSpec(),
        authScheme: SecurityScheme(type: AuthSchemeType.apiKey, name: 'x'),
        authCredential: AuthCredential(
          authType: AuthCredentialType.apiKey,
          apiKey: 'token',
        ),
        credentialKey: 'stable_key',
      );

      final AuthConfig? authConfig = toolset.getAuthConfig();
      expect(authConfig, isNotNull);
      expect(authConfig!.credentialKey, 'stable_key');
      expect(authConfig.rawAuthCredential?.apiKey, 'token');
    });
  });
}
