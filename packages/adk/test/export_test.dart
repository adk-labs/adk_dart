import 'package:adk/adk.dart';
import 'package:test/test.dart';

void main() {
  group('package:adk comprehensive export coverage', () {
    test('exports core agent primitives and workflows', () {
      final BaseLlm model = _MockModel('mock response');
      final Agent rootAgent = Agent(name: 'root_agent', model: model);
      expect(rootAgent.name, 'root_agent');

      final SequentialAgent seqAgent = SequentialAgent(
        name: 'seq_agent',
        subAgents: <BaseAgent>[Agent(name: 'seq_sub', model: model)],
      );
      expect(seqAgent.subAgents.length, 1);

      final ParallelAgent parAgent = ParallelAgent(
        name: 'par_agent',
        subAgents: <BaseAgent>[Agent(name: 'par_sub', model: model)],
      );
      expect(parAgent.subAgents.length, 1);

      final LoopAgent loopAgent = LoopAgent(
        name: 'loop_agent',
        subAgents: <BaseAgent>[Agent(name: 'loop_sub', model: model)],
        maxIterations: 2,
      );
      expect(loopAgent.maxIterations, 2);
    });

    test('exports tools and toolsets', () {
      final FunctionTool tool = FunctionTool(
        name: 'calculate',
        description: 'Calculate numbers',
        func: (Map<String, dynamic> args) => 42,
      );
      expect(tool.name, 'calculate');

      final Agent subAgent = Agent(name: 'sub', model: _MockModel(''));
      final AgentTool agentTool = AgentTool(agent: subAgent);
      expect(agentTool.name, 'sub');
    });

    test('exports runners, sessions, and events', () async {
      final Agent agent = Agent(name: 'echo_agent', model: _MockModel('Echo reply'));
      final InMemoryRunner runner = InMemoryRunner(agent: agent);
      final Session session = await runner.sessionService.createSession(
        appName: runner.appName,
        userId: 'user_1',
        sessionId: 'session_1',
      );

      expect(session.id, 'session_1');
      expect(session.userId, 'user_1');

      final List<Event> events = await runner
          .runAsync(
            userId: 'user_1',
            sessionId: session.id,
            newMessage: Content.userText('Hello ADK'),
          )
          .toList();

      expect(events, isNotEmpty);
      expect(events.last.content?.parts.first.text, 'Echo reply');
    });

    test('exports workflow 2.0 primitives', () {
      final Workflow workflow = Workflow(name: 'test_workflow', nodes: <BaseNode>[]);
      expect(workflow.name, 'test_workflow');
    });
  });
}

class _MockModel extends BaseLlm {
  _MockModel(this.replyText) : super(model: 'mock-model');

  final String replyText;

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    yield LlmResponse(content: Content.modelText(replyText));
  }
}
