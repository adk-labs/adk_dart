import 'package:adk_dart/src/tools/openapi_tool/openapi_spec_parser/openapi_spec_parser.dart';
import 'package:test/test.dart';

void main() {
  group(r'OpenApiSpecParser External $ref Tests', () {
    test('resolves local #/components/schemas references', () {
      final parser = OpenApiSpecParser();
      final spec = {
        'openapi': '3.0.0',
        'info': {'title': 'Pet API', 'version': '1.0.0'},
        'paths': {
          '/pets': {
            'get': {
              'operationId': 'getPets',
              'responses': {
                '200': {
                  'description': 'Pet list',
                  'content': {
                    'application/json': {
                      'schema': {r'$ref': '#/components/schemas/Pet'}
                    }
                  }
                }
              }
            }
          }
        },
        'components': {
          'schemas': {
            'Pet': {
              'type': 'object',
              'properties': {
                'id': {'type': 'integer'},
                'name': {'type': 'string'}
              }
            }
          }
        }
      };

      final operations = parser.parse(spec);
      expect(operations.length, equals(1));
      expect(operations.first.name, equals('get_pets'));
      final returnSchema = operations.first.returnValue.paramSchema;
      expect(returnSchema['type'], equals('object'));
      expect((returnSchema['properties'] as Map)['name']['type'], equals('string'));
    });

    test(r'resolves external documents and remote URL $ref references', () {
      final externalDoc = {
        'definitions': {
          'User': {
            'type': 'object',
            'properties': {
              'userId': {'type': 'string'},
              'email': {'type': 'string'}
            }
          }
        }
      };

      final parser = OpenApiSpecParser(
        externalDocuments: {
          'https://example.com/schemas/user.json': externalDoc,
          './models/user.json': externalDoc,
        },
      );

      final spec = {
        'openapi': '3.0.0',
        'info': {'title': 'User API', 'version': '1.0.0'},
        'paths': {
          '/users/{id}': {
            'get': {
              'operationId': 'getUser',
              'parameters': [
                {
                  'name': 'id',
                  'in': 'path',
                  'required': true,
                  'schema': {'type': 'string'}
                }
              ],
              'responses': {
                '200': {
                  'description': 'User details',
                  'content': {
                    'application/json': {
                      'schema': {
                        r'$ref': 'https://example.com/schemas/user.json#/definitions/User'
                      }
                    }
                  }
                }
              }
            }
          }
        }
      };

      final operations = parser.parse(spec);
      expect(operations.length, equals(1));
      expect(operations.first.name, equals('get_user'));
      final returnSchema = operations.first.returnValue.paramSchema;
      expect(returnSchema['type'], equals('object'));
      expect((returnSchema['properties'] as Map)['email']['type'], equals('string'));
    });
  });
}
