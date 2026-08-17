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

    test(r'resolves multi-hop chained external references (Spec -> DocA -> DocB)', () {
      final docB = {
        'definitions': {
          'Address': {
            'type': 'object',
            'properties': {
              'street': {'type': 'string'},
              'city': {'type': 'string'},
            }
          }
        }
      };

      final docA = {
        'definitions': {
          'Customer': {
            'type': 'object',
            'properties': {
              'name': {'type': 'string'},
              'address': {r'$ref': 'https://schemas.org/address.json#/definitions/Address'}
            }
          }
        }
      };

      final parser = OpenApiSpecParser(
        externalDocuments: {
          'https://schemas.org/customer.json': docA,
          'https://schemas.org/address.json': docB,
        },
      );

      final spec = {
        'openapi': '3.0.0',
        'info': {'title': 'Customer API', 'version': '1.0.0'},
        'paths': {
          '/customer': {
            'get': {
              'operationId': 'getCustomer',
              'responses': {
                '200': {
                  'description': 'Customer info',
                  'content': {
                    'application/json': {
                      'schema': {
                        r'$ref': 'https://schemas.org/customer.json#/definitions/Customer'
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
      expect(operations.first.name, equals('get_customer'));
      final returnSchema = operations.first.returnValue.paramSchema;
      expect(returnSchema['type'], equals('object'));
      final addressProp = (returnSchema['properties'] as Map)['address'] as Map;
      expect(addressProp['type'], equals('object'));
      expect((addressProp['properties'] as Map)['city']['type'], equals('string'));
    });

    test('handles circular references gracefully without stack overflow', () {
      final parser = OpenApiSpecParser();
      final spec = {
        'openapi': '3.0.0',
        'info': {'title': 'Tree API', 'version': '1.0.0'},
        'paths': {
          '/tree': {
            'get': {
              'operationId': 'getTree',
              'responses': {
                '200': {
                  'description': 'Tree node',
                  'content': {
                    'application/json': {
                      'schema': {r'$ref': '#/components/schemas/TreeNode'}
                    }
                  }
                }
              }
            }
          }
        },
        'components': {
          'schemas': {
            'TreeNode': {
              'type': 'object',
              'properties': {
                'value': {'type': 'string'},
                'child': {r'$ref': '#/components/schemas/TreeNode'}
              }
            }
          }
        }
      };

      final operations = parser.parse(spec);
      expect(operations.length, equals(1));
      expect(operations.first.name, equals('get_tree'));
      final returnSchema = operations.first.returnValue.paramSchema;
      expect(returnSchema['type'], equals('object'));
      expect((returnSchema['properties'] as Map)['value']['type'], equals('string'));
    });
  });
}
