import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

class _ChildModel extends BaseLlm {
  _ChildModel() : super(model: 'child-model');

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    final String query = request.contents
        .where((Content content) => content.role == 'user')
        .expand((Content content) => content.parts)
        .where((Part part) => part.text != null)
        .map((Part part) => part.text!)
        .join(' ')
        .trim();
    yield LlmResponse(content: Content.modelText('child:$query'));
  }
}

void main() {
  test('AgentTool runs wrapped agent and returns merged text', () async {
    final Agent childAgent = Agent(
      name: 'child_agent',
      model: _ChildModel(),
      disallowTransferToParent: true,
      disallowTransferToPeers: true,
    );
    final AgentTool tool = AgentTool(agent: childAgent);

    final InvocationContext invocationContext = InvocationContext(
      sessionService: InMemorySessionService(),
      invocationId: 'inv_agent_tool',
      agent: Agent(
        name: 'root_agent',
        model: _ChildModel(),
        disallowTransferToParent: true,
        disallowTransferToPeers: true,
      ),
      session: Session(id: 's_agent_tool', appName: 'app', userId: 'u1'),
      artifactService: InMemoryArtifactService(),
      memoryService: InMemoryMemoryService(),
    );

    final Context toolContext = Context(invocationContext);
    final Object? result = await tool.run(
      args: <String, dynamic>{'request': 'ping'},
      toolContext: toolContext,
    );

    expect('$result', contains('child:'));
    expect('$result', contains('ping'));
  });
}
