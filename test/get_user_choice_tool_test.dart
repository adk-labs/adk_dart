import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

void main() {
  group('GetUserChoiceTool', () {
    test('declares get_user_choice tool signature', () {
      final tool = GetUserChoiceTool();
      final decl = tool.getDeclaration();
      expect(decl, isNotNull);
      expect(decl!.name, equals('get_user_choice'));
      expect(decl.parameters!['required'], contains('options'));
    });

    test('run sets skipSummarization and returns null', () async {
      final tool = GetUserChoiceTool();
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
        args: <String, dynamic>{
          'options': <String>['Option A', 'Option B'],
        },
        toolContext: context,
      );

      expect(result, isNull);
      expect(context.actions.skipSummarization, isTrue);
    });
  });
}
