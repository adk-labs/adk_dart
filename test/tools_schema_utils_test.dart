import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

class _SchemaTool extends BaseTool {
  _SchemaTool() : super(name: 'schema_tool', description: 'schema');

  @override
  FunctionDeclaration? getDeclaration() {
    return FunctionDeclaration(
      name: name,
      description: description,
      parameters: <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'a': <String, dynamic>{'type': 'string'},
          'b': <String, dynamic>{'type': 'integer'},
        },
        'required': <String>['a', 'b'],
      },
    );
  }

  @override
  Future<Object?> run({
    required Map<String, dynamic> args,
    required ToolContext toolContext,
  }) async {
    return args;
  }
}

void main() {
  group('tools schema utils', () {
    test('function parameter parse compatibility helpers', () {
      expect(jsonSchemaTypeForValue('x'), 'string');
      expect(jsonSchemaTypeForValue(1), 'integer');
      expect(isDefaultValueCompatible(1, int), isTrue);
      expect(isDefaultValueCompatible('x', int), isFalse);
      expect(
        addUnevaluatedItemsToFixedLenTupleSchema(<String, dynamic>{
          'type': 'array',
          'prefixItems': <Object>[1, 2],
          'maxItems': 2,
        })['unevaluatedItems'],
        isFalse,
      );
    });

    test('automatic function declaration removes ignored params', () {
      final FunctionDeclaration declaration = buildFunctionDeclaration(
        _SchemaTool(),
        ignoreParams: <String>['b'],
      );
      final Map<String, dynamic> properties =
          declaration.parameters['properties'] as Map<String, dynamic>;
      expect(properties.containsKey('a'), isTrue);
      expect(properties.containsKey('b'), isFalse);
      expect(declaration.parameters['required'], <String>['a']);
    });

    test('gemini schema util converts casing and dereferences', () {
      expect(toSnakeCase('UpperCamelCase Value'), 'upper_camel_case_value');
      final Map<String, dynamic> schema = <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'item': <String, dynamic>{r'$ref': r'#/$defs/MyType'},
        },
        r'$defs': <String, dynamic>{
          'MyType': <String, dynamic>{'type': 'string', 'format': 'enum'},
        },
      };
      final Map<String, dynamic> converted = toGeminiSchema(schema);
      final Map<String, dynamic> properties =
          converted['properties'] as Map<String, dynamic>;
      final Map<String, dynamic> item =
          properties['item'] as Map<String, dynamic>;
      expect(item['type'], 'string');
      expect(item['format'], 'enum');
    });

    test('gemini schema util handles boolean schemas without crashing', () {
      final Map<String, dynamic> schema = <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{'allow_any': true, 'reject_all': false},
      };
      final Map<String, dynamic> converted = toGeminiSchema(schema);
      final Map<String, dynamic> properties =
          converted['properties'] as Map<String, dynamic>;
      expect(
        (properties['allow_any'] as Map<String, dynamic>)['type'],
        'object',
      );
      expect(
        (properties['reject_all'] as Map<String, dynamic>)['type'],
        'object',
      );
    });
  });
}
