import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

Future<Context> _newToolContext() async {
  final InMemorySessionService sessionService = InMemorySessionService();
  final Session session = await sessionService.createSession(
    appName: 'test_app',
    userId: 'user_1',
  );

  final Agent agent = Agent(name: 'agent', model: _NoopModel());
  final InvocationContext invocationContext = InvocationContext(
    invocationId: 'inv_1',
    agent: agent,
    session: session,
    sessionService: sessionService,
  );

  return Context(invocationContext);
}

class _NoopModel extends BaseLlm {
  _NoopModel() : super(model: 'noop');

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {}
}

void main() {
  group('LongRunningFunctionTool', () {
    test('marks tool as long-running and appends warning in declaration', () {
      String sample(String value) => value;

      final LongRunningFunctionTool tool = LongRunningFunctionTool(
        func: sample,
        name: 'sample',
        description: 'Sample tool',
      );

      expect(tool.isLongRunning, isTrue);
      final FunctionDeclaration? declaration = tool.getDeclaration();
      expect(declaration, isNotNull);
      expect(
        declaration!.description.contains(
          'NOTE: This is a long-running operation.',
        ),
        isTrue,
      );
    });
  });

  group('TransferToAgentTool', () {
    test('adds enum constraint for agent_name', () {
      final TransferToAgentTool tool = TransferToAgentTool(
        agentNames: <String>['agent_a', 'agent_b'],
      );

      final FunctionDeclaration? declaration = tool.getDeclaration();
      expect(declaration, isNotNull);
      final Map<String, dynamic> parameters = declaration!.parameters;
      final Map<String, dynamic> properties =
          parameters['properties'] as Map<String, dynamic>;
      final Map<String, dynamic> agentName =
          properties['agent_name'] as Map<String, dynamic>;

      expect(agentName['enum'], <String>['agent_a', 'agent_b']);
      expect(parameters['required'], <String>['agent_name']);
    });

    test('run sets transferToAgent action', () async {
      final TransferToAgentTool tool = TransferToAgentTool(
        agentNames: <String>['agent_a', 'agent_b'],
      );
      final Context toolContext = await _newToolContext();

      await tool.run(
        args: <String, dynamic>{'agent_name': 'agent_b'},
        toolContext: toolContext,
      );

      expect(toolContext.actions.transferToAgent, 'agent_b');
    });
  });

  test('exitLoop sets escalate and skipSummarization', () async {
    final Context toolContext = await _newToolContext();
    exitLoop(toolContext: toolContext);
    expect(toolContext.actions.escalate, isTrue);
    expect(toolContext.actions.skipSummarization, isTrue);
  });
}
