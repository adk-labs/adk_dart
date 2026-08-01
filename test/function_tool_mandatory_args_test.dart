import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

class _CustomDeclFunctionTool extends FunctionTool {
  _CustomDeclFunctionTool({required super.func, required this.declaration});

  final FunctionDeclaration declaration;

  @override
  FunctionDeclaration? getDeclaration() => declaration;
}

void main() {
  group('FunctionTool mandatory parameter validation', () {
    test('returns error feedback map when mandatory parameter is missing', () async {
      final tool = _CustomDeclFunctionTool(
        func: ({required String param1, required String param2}) => 'ok',
        declaration: FunctionDeclaration(
          name: 'test_func',
          description: 'test function',
          parameters: <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{
              'param1': <String, String>{'type': 'string'},
              'param2': <String, String>{'type': 'string'},
            },
            'required': <String>['param1', 'param2'],
          },
        ),
      );

      final invocationContext = InvocationContext(
        invocationId: 'inv_1',
        session: Session(id: 's_1', appName: 'app', userId: 'user'),
        agent: LlmAgent(name: 'test_agent'),
        sessionService: InMemorySessionService(),
      );
      final context = Context(
        invocationContext,
        functionCallId: 'call_1',
      );

      final result = await tool.run(
        args: <String, dynamic>{'param1': 'value1'},
        toolContext: context,
      );

      expect(result, isA<Map<String, Object?>>());
      final map = result as Map<String, Object?>;
      expect(map['error'], contains('param2'));
      expect(map['error'], contains('missing'));
    });
  });
}
