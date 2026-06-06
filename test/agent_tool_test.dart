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

class _FinishTaskModel extends BaseLlm {
  _FinishTaskModel({Map<String, dynamic>? finishArgs})
    : finishArgs = finishArgs ?? <String, dynamic>{'result': 'task done'},
      super(model: 'finish-task-model');

  final Map<String, dynamic> finishArgs;
  final List<String> seenUserPrompts = <String>[];
  int calls = 0;

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    calls += 1;
    seenUserPrompts.add(
      request.contents
          .where((Content content) => content.role == 'user')
          .expand((Content content) => content.parts)
          .where((Part part) => part.text != null)
          .map((Part part) => part.text!)
          .join('\n'),
    );
    yield LlmResponse(
      content: Content(
        role: 'model',
        parts: <Part>[
          Part.fromFunctionCall(
            name: finishTaskToolName,
            id: 'finish_call_$calls',
            args: finishArgs,
          ),
        ],
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

class _StateCaptureAgent extends BaseAgent {
  _StateCaptureAgent() : super(name: 'state_child');

  Map<String, Object?>? seenSessionState;

  @override
  Stream<Event> runAsyncImpl(InvocationContext context) async* {
    seenSessionState = Map<String, Object?>.from(context.session.state);
    yield Event(
      invocationId: context.invocationId,
      author: name,
      content: Content.modelText('ok'),
    );
  }
}

class _NamedTool extends BaseTool {
  _NamedTool(String name) : super(name: name, description: 'named tool');

  @override
  Future<Object?> run({
    required Map<String, dynamic> args,
    required ToolContext toolContext,
  }) async {
    return <String, Object?>{'ok': true};
  }
}

class _DeferredNullTool extends BaseTool {
  _DeferredNullTool()
    : super(
        name: 'deferred_tool',
        description: 'defers response',
        defersResponse: true,
      );

  @override
  Future<Object?> run({
    required Map<String, dynamic> args,
    required ToolContext toolContext,
  }) async {
    return null;
  }
}

class _CloseRecordingPlugin extends BasePlugin {
  _CloseRecordingPlugin() : super(name: 'close_recorder');

  int closeCalls = 0;

  @override
  Future<void> close() async {
    closeCalls += 1;
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
    'AgentTool does not propagate temp state to child agent session',
    () async {
      final _StateCaptureAgent childAgent = _StateCaptureAgent();
      final AgentTool tool = AgentTool(agent: childAgent);

      final InvocationContext invocationContext = InvocationContext(
        sessionService: InMemorySessionService(),
        invocationId: 'inv_agent_tool_temp_state',
        agent: Agent(name: 'root_agent', model: _ChildModel()),
        session: Session(
          id: 's_agent_tool_temp_state',
          appName: 'app',
          userId: 'u1',
          state: <String, Object?>{
            'normalKey': 'parentValue',
            'temp:transient': 'tempValue',
          },
        ),
        artifactService: InMemoryArtifactService(),
        memoryService: InMemoryMemoryService(),
      );

      final Object? result = await tool.run(
        args: <String, dynamic>{'request': 'hello'},
        toolContext: Context(invocationContext),
      );

      expect(result, 'ok');
      expect(childAgent.seenSessionState, isNotNull);
      expect(
        childAgent.seenSessionState,
        containsPair('normalKey', 'parentValue'),
      );
      expect(childAgent.seenSessionState, isNot(contains('temp:transient')));
    },
  );

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

  test('AgentTool does not close inherited parent plugins', () async {
    final _CloseRecordingPlugin plugin = _CloseRecordingPlugin();
    final Agent childAgent = Agent(
      name: 'child_agent',
      model: _ChildModel(),
      disallowTransferToParent: true,
      disallowTransferToPeers: true,
    );
    final AgentTool tool = AgentTool(agent: childAgent);

    final InvocationContext invocationContext = InvocationContext(
      sessionService: InMemorySessionService(),
      invocationId: 'inv_agent_tool_plugins',
      agent: Agent(name: 'root_agent', model: _ChildModel()),
      session: Session(
        id: 's_agent_tool_plugins',
        appName: 'app',
        userId: 'u1',
      ),
      artifactService: InMemoryArtifactService(),
      memoryService: InMemoryMemoryService(),
      pluginManager: PluginManager(plugins: <BasePlugin>[plugin]),
    );

    final Object? result = await tool.run(
      args: <String, dynamic>{'request': 'ping'},
      toolContext: Context(invocationContext),
    );

    expect('$result', contains('ping'));
    expect(plugin.closeCalls, 0);
  });

  test('deferred response tools skip automatic function response', () async {
    final _DeferredNullTool tool = _DeferredNullTool();

    final Event? event = await handleFunctionCallListAsync(
      _invocationContext(),
      <FunctionCall>[
        FunctionCall(
          name: tool.name,
          id: 'call_deferred',
          args: <String, dynamic>{},
        ),
      ],
      <String, BaseTool>{tool.name: tool},
    );

    expect(event, isNull);
  });

  group('sub-agent mode wrappers', () {
    test('adds single-turn sub-agent wrapper automatically', () async {
      final Agent childAgent = Agent(
        name: 'single_turn_child',
        model: _ChildModel(),
        mode: 'single_turn',
      );
      final Agent rootAgent = Agent(
        name: 'root_agent',
        model: _ChildModel(),
        subAgents: <BaseAgent>[childAgent],
      );

      final List<BaseTool> tools = await rootAgent.canonicalTools();

      expect(tools, hasLength(1));
      expect(tools.single, isA<SingleTurnAgentTool>());
      expect((tools.single as SingleTurnAgentTool).agent, same(childAgent));
    });

    test('adds task sub-agent wrapper with default request schema', () async {
      final Agent childAgent = Agent(
        name: 'task_child',
        description: 'Handles a delegated task.',
        model: _ChildModel(),
        mode: 'task',
      );
      final Agent rootAgent = Agent(
        name: 'root_agent',
        model: _ChildModel(),
        subAgents: <BaseAgent>[childAgent],
      );

      final List<BaseTool> tools = await rootAgent.canonicalTools();
      final TaskAgentTool tool = tools.whereType<TaskAgentTool>().single;
      final FunctionDeclaration declaration = tool.getDeclaration()!;

      expect(tool.defersResponse, isTrue);
      expect(tool.agent, same(childAgent));
      expect(declaration.name, 'task_child');
      expect(
        declaration.description,
        contains('Do NOT call this tool in parallel with any other tools.'),
      );
      expect(declaration.parameters['properties'], contains('request'));
      expect(
        (declaration.parameters['properties']
            as Map<String, Object?>)['request'],
        containsPair(
          'description',
          'Detailed instructions or context for the task sub-agent.',
        ),
      );
    });

    test('task wrapper uses child input schema when provided', () async {
      final Agent childAgent = Agent(
        name: 'task_child',
        model: _ChildModel(),
        mode: 'task',
        inputSchema: <String, Object?>{
          'type': 'object',
          'properties': <String, Object?>{
            'city': <String, Object?>{'type': 'string'},
          },
          'required': <String>['city'],
        },
      );
      final Agent rootAgent = Agent(
        name: 'root_agent',
        model: _ChildModel(),
        subAgents: <BaseAgent>[childAgent],
      );

      final TaskAgentTool tool = (await rootAgent.canonicalTools())
          .whereType<TaskAgentTool>()
          .single;
      final FunctionDeclaration declaration = tool.getDeclaration()!;

      expect(declaration.parameters['properties'], contains('city'));
      expect(declaration.parameters['properties'], isNot(contains('request')));
    });

    test('sets unspecified LlmAgent sub-agent mode to chat', () async {
      final Agent childAgent = Agent(name: 'chat_child', model: _ChildModel());
      final Agent rootAgent = Agent(
        name: 'root_agent',
        model: _ChildModel(),
        subAgents: <BaseAgent>[childAgent],
      );

      expect(childAgent.mode, 'chat');
      expect(await rootAgent.canonicalTools(), isEmpty);
    });

    test('does not duplicate an explicit same-name sub-agent tool', () async {
      final Agent childAgent = Agent(
        name: 'task_child',
        model: _ChildModel(),
        mode: 'task',
      );
      final Agent rootAgent = Agent(
        name: 'root_agent',
        model: _ChildModel(),
        subAgents: <BaseAgent>[childAgent],
        tools: <Object>[_NamedTool('task_child')],
      );

      final List<BaseTool> tools = await rootAgent.canonicalTools();

      expect(tools, hasLength(1));
      expect(tools.single, isA<_NamedTool>());
    });

    test('clone installs wrappers for cloned sub-agents', () async {
      final Agent childAgent = Agent(
        name: 'task_child',
        model: _ChildModel(),
        mode: 'task',
      );
      final Agent rootAgent = Agent(
        name: 'root_agent',
        model: _ChildModel(),
        subAgents: <BaseAgent>[childAgent],
      );

      final LlmAgent cloned = rootAgent.clone();
      final TaskAgentTool clonedTool = cloned.tools
          .whereType<TaskAgentTool>()
          .single;

      expect(identical(cloned.subAgents.single, childAgent), isFalse);
      expect(clonedTool.agent, same(cloned.subAgents.single));
      expect(clonedTool.agent, isNot(same(childAgent)));
    });

    test('single-turn wrapper runs child in parent session branch', () async {
      final Agent childAgent = Agent(
        name: 'single_turn_child',
        model: _ChildModel(),
        mode: 'single_turn',
      );
      final Agent rootAgent = Agent(
        name: 'root_agent',
        model: _ChildModel(),
        subAgents: <BaseAgent>[childAgent],
      );
      final InMemorySessionService sessionService = InMemorySessionService();
      final Session session = await sessionService.createSession(
        appName: 'app',
        userId: 'u1',
        sessionId: 's_single_turn',
      );
      final InvocationContext invocationContext = InvocationContext(
        sessionService: sessionService,
        invocationId: 'inv_single_turn',
        agent: rootAgent,
        session: session,
        artifactService: InMemoryArtifactService(),
        memoryService: InMemoryMemoryService(),
      );
      final SingleTurnAgentTool tool = SingleTurnAgentTool(agent: childAgent);

      final Object? result = await tool.run(
        args: <String, dynamic>{'request': 'handle this once'},
        toolContext: Context(invocationContext),
      );

      expect('$result', contains('handle this once'));
      expect(
        session.events.any(
          (Event event) =>
              event.author == 'user' &&
              event.branch == 'root_agent.single_turn_child',
        ),
        isTrue,
      );
      expect(
        session.events.any(
          (Event event) =>
              event.author == 'single_turn_child' &&
              event.branch == 'root_agent.single_turn_child',
        ),
        isTrue,
      );
    });

    test(
      'task wrapper runs child in isolation scope and returns output',
      () async {
        final _FinishTaskModel taskModel = _FinishTaskModel();
        final Agent childAgent = Agent(
          name: 'task_child',
          model: taskModel,
          mode: 'task',
        );
        final Agent rootAgent = Agent(
          name: 'root_agent',
          model: _ChildModel(),
          subAgents: <BaseAgent>[childAgent],
        );
        final InMemorySessionService sessionService = InMemorySessionService();
        final Session session = await sessionService.createSession(
          appName: 'app',
          userId: 'u1',
          sessionId: 's_task_tool',
        );
        final InvocationContext invocationContext = InvocationContext(
          sessionService: sessionService,
          invocationId: 'inv_task_tool',
          agent: rootAgent,
          session: session,
          artifactService: InMemoryArtifactService(),
          memoryService: InMemoryMemoryService(),
        );
        await sessionService.appendEvent(
          session: session,
          event: Event(
            invocationId: invocationContext.invocationId,
            author: rootAgent.name,
            content: Content(
              role: 'model',
              parts: <Part>[
                Part.fromFunctionCall(
                  name: childAgent.name,
                  id: 'task_call_1',
                  args: <String, dynamic>{'request': 'ship it'},
                ),
              ],
            ),
          ),
        );
        final TaskAgentTool tool = TaskAgentTool(agent: childAgent);

        final Object? result = await tool.run(
          args: <String, dynamic>{'request': 'ship it'},
          toolContext: Context(
            invocationContext,
            functionCallId: 'task_call_1',
          ),
        );

        expect(result, <String, dynamic>{'result': 'task done'});
        expect(taskModel.seenUserPrompts.single, contains('ship it'));
        final List<Event> childEvents = session.events
            .where((Event event) => event.author == childAgent.name)
            .toList();
        expect(childEvents, isNotEmpty);
        expect(
          childEvents.every(
            (Event event) => event.isolationScope == 'task_call_1',
          ),
          isTrue,
        );
        expect(
          session.events.any(
            (Event event) => event.getFunctionResponses().any(
              (FunctionResponse response) => response.name == 'finish_task',
            ),
          ),
          isTrue,
        );
      },
    );

    test('task wrapper unwraps primitive finish_task output', () async {
      final _FinishTaskModel taskModel = _FinishTaskModel(
        finishArgs: <String, dynamic>{'result': 'primitive done'},
      );
      final Agent childAgent = Agent(
        name: 'primitive_task_child',
        model: taskModel,
        mode: 'task',
        outputSchema: String,
      );
      final Agent rootAgent = Agent(
        name: 'root_agent',
        model: _ChildModel(),
        subAgents: <BaseAgent>[childAgent],
      );
      final InMemorySessionService sessionService = InMemorySessionService();
      final Session session = await sessionService.createSession(
        appName: 'app',
        userId: 'u1',
        sessionId: 's_primitive_task_tool',
      );
      final InvocationContext invocationContext = InvocationContext(
        sessionService: sessionService,
        invocationId: 'inv_primitive_task_tool',
        agent: rootAgent,
        session: session,
        artifactService: InMemoryArtifactService(),
        memoryService: InMemoryMemoryService(),
      );
      await sessionService.appendEvent(
        session: session,
        event: Event(
          invocationId: invocationContext.invocationId,
          author: rootAgent.name,
          content: Content(
            role: 'model',
            parts: <Part>[
              Part.fromFunctionCall(
                name: childAgent.name,
                id: 'task_call_primitive',
                args: <String, dynamic>{'request': 'finish primitive'},
              ),
            ],
          ),
        ),
      );
      final TaskAgentTool tool = TaskAgentTool(agent: childAgent);

      final Object? result = await tool.run(
        args: <String, dynamic>{'request': 'finish primitive'},
        toolContext: Context(
          invocationContext,
          functionCallId: 'task_call_primitive',
        ),
      );

      expect(result, 'primitive done');
    });
  });
}

InvocationContext _invocationContext() {
  return InvocationContext(
    sessionService: InMemorySessionService(),
    invocationId: 'inv_task_agent_tool',
    agent: Agent(name: 'root_agent', model: _ChildModel()),
    session: Session(id: 's_task_agent_tool', appName: 'app', userId: 'u1'),
    artifactService: InMemoryArtifactService(),
    memoryService: InMemoryMemoryService(),
  );
}
