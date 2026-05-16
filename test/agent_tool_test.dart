import 'dart:convert';

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

class _JsonChildModel extends BaseLlm {
  _JsonChildModel() : super(model: 'child-json-model');

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
    yield LlmResponse(
      content: Content.modelText(
        jsonEncode(<String, Object?>{'answer': 'child:$query'}),
      ),
    );
  }
}

class _CodePartAgent extends BaseAgent {
  _CodePartAgent() : super(name: 'code_child');

  @override
  Stream<Event> runAsyncImpl(InvocationContext context) async* {
    yield Event(
      invocationId: context.invocationId,
      author: name,
      content: Content(
        role: 'model',
        parts: <Part>[
          Part(codeExecutionResult: <String, Object?>{'output': 'stdout\n'}),
          Part(executableCode: <String, Object?>{'code': 'print(1)'}),
        ],
      ),
    );
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

  test(
    'AgentTool uses child input schema and parses structured output',
    () async {
      final Agent childAgent = Agent(
        name: 'child_agent',
        model: _JsonChildModel(),
        inputSchema: <String, Object?>{
          'type': 'object',
          'properties': <String, Object?>{
            'city': <String, Object?>{'type': 'string'},
          },
          'required': <String>['city'],
        },
        outputSchema: <String, Object?>{
          'type': 'object',
          'properties': <String, Object?>{
            'answer': <String, Object?>{'type': 'string'},
          },
        },
        disallowTransferToParent: true,
        disallowTransferToPeers: true,
      );
      final AgentTool tool = AgentTool(agent: childAgent);

      final FunctionDeclaration declaration = tool.getDeclaration()!;
      expect(declaration.parameters['properties'], contains('city'));

      final InvocationContext invocationContext = InvocationContext(
        sessionService: InMemorySessionService(),
        invocationId: 'inv_agent_tool_schema',
        agent: Agent(name: 'root_agent', model: _ChildModel()),
        session: Session(
          id: 's_agent_tool_schema',
          appName: 'app',
          userId: 'u1',
        ),
        artifactService: InMemoryArtifactService(),
        memoryService: InMemoryMemoryService(),
      );

      final Object? result = await tool.run(
        args: <String, dynamic>{'city': 'Seoul'},
        toolContext: Context(invocationContext),
      );

      expect(result, isA<Map<String, Object?>>());
      expect((result! as Map<String, Object?>)['answer'], contains('Seoul'));
    },
  );

  test(
    'AgentTool merges code execution result and executable code parts',
    () async {
      final AgentTool tool = AgentTool(agent: _CodePartAgent());
      final InvocationContext invocationContext = InvocationContext(
        sessionService: InMemorySessionService(),
        invocationId: 'inv_agent_tool_code',
        agent: Agent(name: 'root_agent', model: _ChildModel()),
        session: Session(id: 's_agent_tool_code', appName: 'app', userId: 'u1'),
        artifactService: InMemoryArtifactService(),
        memoryService: InMemoryMemoryService(),
      );

      final Object? result = await tool.run(
        args: <String, dynamic>{'request': 'run code'},
        toolContext: Context(invocationContext),
      );

      expect(result, 'stdout\nprint(1)');
    },
  );
}
