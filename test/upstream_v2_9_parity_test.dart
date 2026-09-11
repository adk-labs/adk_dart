import 'dart:async';

import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

class _MockLlm extends BaseLlm {
  _MockLlm({super.model = 'mock-model'});

  final List<LlmResponse> responses = <LlmResponse>[];
  int _index = 0;

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    if (_index < responses.length) {
      yield responses[_index++];
    } else {
      yield LlmResponse(content: Content(role: 'model', parts: <Part>[Part.text('ok')]));
    }
  }
}

class _MockToolWithRequired extends BaseTool {
  _MockToolWithRequired()
      : super(name: 'mock_tool', description: 'Mock tool with required params');

  Map<String, dynamic>? lastArgs;

  @override
  FunctionDeclaration? getDeclaration() {
    return FunctionDeclaration(
      name: name,
      description: description,
      parameters: <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'param_a': <String, dynamic>{'type': 'string'},
          'param_b': <String, dynamic>{'type': 'string'},
        },
        'required': <String>['param_a', 'param_b'],
      },
    );
  }

  @override
  Future<Object?> run({
    required Map<String, dynamic> args,
    required ToolContext toolContext,
  }) async {
    lastArgs = Map<String, dynamic>.from(args);
    return args;
  }
}

class _MockStateDeltaTool extends BaseTool {
  _MockStateDeltaTool()
      : super(name: 'state_delta_tool', description: 'Tool that updates state');

  @override
  Future<Object?> run({
    required Map<String, dynamic> args,
    required ToolContext toolContext,
  }) async {
    toolContext.actions.stateDelta['tool_flag'] = 'updated_by_tool';
    return {'status': 'ok'};
  }
}

void main() {
  group('LlmAgent BaseNode in tools', () {
    test('adapts BaseNode in tools list into NodeTool', () {
      final FunctionNode node = FunctionNode(
        name: 'my_node',
        description: 'Test node description',
        function: (WorkflowContext ctx, Object? input) => 'node_result',
      );

      final LlmAgent agent = LlmAgent(
        name: 'test_agent',
        tools: <Object>[node],
      );

      expect(agent.tools.length, 1);
      expect(agent.tools.first, isA<NodeTool>());
      final NodeTool nodeTool = agent.tools.first as NodeTool;
      expect(nodeTool.node, equals(node));
      expect(nodeTool.name, 'my_node');
      expect(nodeTool.description, 'Test node description');
    });

    test('rejects BaseAgent in tools list with ArgumentError', () {
      final LlmAgent subAgent = LlmAgent(name: 'sub_agent');

      expect(
        () => LlmAgent(name: 'parent', tools: <Object>[subAgent]),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError e) => e.message,
            'message',
            contains("cannot be used directly as a tool"),
          ),
        ),
      );
    });
  });

  group('Workflow and NodeTool parity', () {
    test('buildNode unwraps NodeTool to underlying BaseNode', () {
      final FunctionNode innerNode = FunctionNode(
        name: 'inner',
        function: (WorkflowContext ctx, Object? input) => input,
      );
      final NodeTool tool = NodeTool(node: innerNode);

      final BaseNode unwrapped = buildNode(tool);
      expect(unwrapped, equals(innerNode));
      expect(unwrapped is ToolNode, isFalse);
    });

    test('ToolNode falls back to session state for missing required parameters', () async {
      final _MockToolWithRequired tool = _MockToolWithRequired();
      final ToolNode toolNode = ToolNode(tool: tool);

      final InMemorySessionService sessionService = InMemorySessionService();
      final Session session = await sessionService.createSession(
        appName: 'app',
        userId: 'user',
        sessionId: 'sess',
        state: <String, Object?>{'param_a': 'from_state'},
      );
      final InvocationContext ic = InvocationContext(
        sessionService: sessionService,
        session: session,
        agent: LlmAgent(name: 'agent'),
        invocationId: 'inv_1',
      );
      final WorkflowContext wfContext = WorkflowContext(invocationContext: ic);

      await toolNode.run(wfContext, {'param_b': 'explicit'});

      expect(tool.lastArgs, isNotNull);
      expect(tool.lastArgs!['param_a'], 'from_state');
      expect(tool.lastArgs!['param_b'], 'explicit');
    });

    test('ToolNode merges tool stateDelta into session state', () async {
      final _MockStateDeltaTool tool = _MockStateDeltaTool();
      final ToolNode toolNode = ToolNode(tool: tool);

      final InMemorySessionService sessionService = InMemorySessionService();
      final Session session = await sessionService.createSession(
        appName: 'app',
        userId: 'user',
        sessionId: 'sess',
      );
      final InvocationContext ic = InvocationContext(
        sessionService: sessionService,
        session: session,
        agent: LlmAgent(name: 'agent'),
        invocationId: 'inv_1',
      );
      final WorkflowContext wfContext = WorkflowContext(invocationContext: ic);

      await toolNode.run(wfContext, {});

      expect(session.state['tool_flag'], 'updated_by_tool');
    });
  });

  group('LoadArtifactsTool scope guard', () {
    test('loads only listed artifacts and ignores unlisted names', () async {
      final LoadArtifactsTool tool = LoadArtifactsTool();
      final InMemorySessionService sessionService = InMemorySessionService();
      final Session session = await sessionService.createSession(
        appName: 'app',
        userId: 'user',
        sessionId: 'sess',
      );
      final InMemoryArtifactService artifactService = InMemoryArtifactService();
      await artifactService.saveArtifact(
        appName: 'app',
        userId: 'user',
        sessionId: 'sess',
        filename: 'listed.txt',
        artifact: Part.text('valid content'),
      );
      // Save an out-of-scope artifact that exists in the backend but is not listed for session
      await artifactService.saveArtifact(
        appName: 'app',
        userId: 'user',
        sessionId: 'other_sess',
        filename: 'secret.txt',
        artifact: Part.text('secret content'),
      );

      final InvocationContext ic = InvocationContext(
        sessionService: sessionService,
        session: session,
        agent: LlmAgent(name: 'agent'),
        artifactService: artifactService,
        invocationId: 'inv_1',
      );
      final ToolContext toolContext = ToolContext(ic);

      // Model requested both listed.txt and unlisted secret.txt
      final LlmRequest request = LlmRequest(
        model: 'model',
        contents: <Content>[
          Content(
            role: 'model',
            parts: <Part>[
              Part.fromFunctionResponse(
                name: 'load_artifacts',
                response: {
                  'artifact_names': ['listed.txt', 'secret.txt'],
                },
              ),
            ],
          ),
        ],
      );

      await tool.processLlmRequest(toolContext: toolContext, llmRequest: request);

      // Only listed.txt should be appended to request.contents
      expect(request.contents.length, 2);
      expect(request.contents.last.parts.first.text, 'Artifact listed.txt is:');
      expect(request.contents.last.parts.last.text, 'valid content');
    });

    test('resolves listed user-scoped artifact when model omits prefix', () async {
      final LoadArtifactsTool tool = LoadArtifactsTool();
      final InMemorySessionService sessionService = InMemorySessionService();
      final Session session = await sessionService.createSession(
        appName: 'app',
        userId: 'user',
        sessionId: 'sess',
      );
      final InMemoryArtifactService artifactService = InMemoryArtifactService();
      await artifactService.saveArtifact(
        appName: 'app',
        userId: 'user',
        sessionId: null, // user-scoped
        filename: 'user:notes.txt',
        artifact: Part.text('notes content'),
      );

      final InvocationContext ic = InvocationContext(
        sessionService: sessionService,
        session: session,
        agent: LlmAgent(name: 'agent'),
        artifactService: artifactService,
        invocationId: 'inv_1',
      );
      final ToolContext toolContext = ToolContext(ic);

      final LlmRequest request = LlmRequest(
        model: 'model',
        contents: <Content>[
          Content(
            role: 'model',
            parts: <Part>[
              Part.fromFunctionResponse(
                name: 'load_artifacts',
                response: {
                  'artifact_names': ['notes.txt'],
                },
              ),
            ],
          ),
        ],
      );

      await tool.processLlmRequest(toolContext: toolContext, llmRequest: request);

      expect(request.contents.length, 2);
      expect(request.contents.last.parts.first.text, 'Artifact notes.txt is:');
      expect(request.contents.last.parts.last.text, 'notes content');
    });
  });

  group('Runner state delta on resume without new message', () {
    test('applies stateDelta when resuming by invocationId without newMessage', () async {
      final InMemorySessionService sessionService = InMemorySessionService();
      final _MockLlm model = _MockLlm();
      final LlmAgent agent = LlmAgent(name: 'test_agent', model: model);

      final App app = App(
        name: 'app',
        rootAgent: agent,
        resumabilityConfig: ResumabilityConfig(isResumable: true),
      );

      final Runner runner = Runner(
        app: app,
        sessionService: sessionService,
      );

      // Initial run
      await sessionService.createSession(
        appName: 'app',
        userId: 'user',
        sessionId: 'sess',
      );
      final List<Event> initialEvents = await runner.runAsync(
        userId: 'user',
        sessionId: 'sess',
        newMessage: Content(role: 'user', parts: <Part>[Part.text('hello')]),
      ).toList();

      final String invocationId = initialEvents.first.invocationId;

      // Resume with state delta and null newMessage
      await runner.runAsync(
        userId: 'user',
        sessionId: 'sess',
        invocationId: invocationId,
        newMessage: null,
        stateDelta: {'resumed_key': 'resumed_value'},
      ).drain();

      final Session? loaded = await sessionService.getSession(
        appName: 'app',
        userId: 'user',
        sessionId: 'sess',
      );
      expect(loaded, isNotNull);
      expect(loaded!.state['resumed_key'], equals('resumed_value'));
      final Event deltaEvent = loaded.events.firstWhere(
        (Event e) =>
            e.actions.stateDelta.containsKey('resumed_key') &&
            e.content == null,
      );
      expect(deltaEvent.actions.stateDelta['resumed_key'], equals('resumed_value'));
    });
  });

  group('Workflow failure rehydration', () {
    test('rehydrates failed node as failed and clears output', () {
      final Workflow wf = Workflow(
        name: 'wf',
        nodes: <BaseNode>[
          FunctionNode(
            name: 'node_a',
            function: (WorkflowContext ctx, Object? input) => 'out',
          ),
        ],
      );

      final Event errorEvent = Event(
        invocationId: 'inv_1',
        author: 'node_a',
        nodeInfo: NodeInfo(path: 'wf@1/node_a@1'),
        errorCode: 'ValueError',
        errorMessage: 'something failed',
      );

      final WorkflowResult result = wf.rehydrateResultFromEvents(
        <Event>[errorEvent],
        invocationId: 'inv_1',
      );

      expect(result.nodeStates['node_a']?.status, equals(NodeStatus.failed));
      expect(result.outputs.containsKey('node_a'), isFalse);
    });

    test('succeeded attempt clears prior error and marks completed', () {
      final Workflow wf = Workflow(
        name: 'wf',
        nodes: <BaseNode>[
          FunctionNode(
            name: 'node_a',
            function: (WorkflowContext ctx, Object? input) => 'out',
          ),
        ],
      );

      final Event errorEvent = Event(
        invocationId: 'inv_1',
        author: 'node_a',
        nodeInfo: NodeInfo(path: 'wf@1/node_a@1'),
        errorCode: 'ValueError',
        errorMessage: 'failed first',
      );
      final Event outputEvent = Event(
        invocationId: 'inv_1',
        author: 'node_a',
        nodeInfo: NodeInfo(path: 'wf@1/node_a@1'),
        output: 'succeeded now',
      );

      final WorkflowResult result = wf.rehydrateResultFromEvents(
        <Event>[errorEvent, outputEvent],
        invocationId: 'inv_1',
      );

      expect(result.nodeStates['node_a']?.status, equals(NodeStatus.completed));
      expect(result.nodeStates['node_a']?.error, isNull);
      expect(result.outputs['node_a'], equals('succeeded now'));
    });
  });

  group('Contents orphaned function calls pruning', () {
    test('prunes unanswered function call when turn is interrupted', () {
      final Event userPrompt = Event(
        invocationId: 'inv_1',
        author: 'user',
        content: Content(role: 'user', parts: <Part>[Part.text('calculate')]),
      );
      final Event modelToolCall = Event(
        invocationId: 'inv_1',
        author: 'agent',
        content: Content(
          role: 'model',
          parts: <Part>[
            Part.fromFunctionCall(name: 'my_tool', id: 'call_orphan'),
          ],
        ),
      );
      // Turn was interrupted: user enters new message before tool response
      final Event userFollowup = Event(
        invocationId: 'inv_1',
        author: 'user',
        content: Content(role: 'user', parts: <Part>[Part.text('nevermind')]),
      );

      final List<Content> contents = getContents(
        currentBranch: null,
        agentName: 'agent',
        events: <Event>[userPrompt, modelToolCall, userFollowup],
      );

      // The orphaned call should be pruned so providers do not reject with HTTP 400
      final bool hasOrphanCall = contents.any(
        (Content c) => c.parts.any((Part p) => p.functionCall?.id == 'call_orphan'),
      );
      expect(hasOrphanCall, isFalse);
    });

    test('preserves long-running tool call even without response', () {
      final Event modelToolCall = Event(
        invocationId: 'inv_1',
        author: 'agent',
        longRunningToolIds: <String>{'call_hitl'},
        content: Content(
          role: 'model',
          parts: <Part>[
            Part.fromFunctionCall(name: 'hitl_tool', id: 'call_hitl'),
          ],
        ),
      );

      final List<Content> contents = getContents(
        currentBranch: null,
        agentName: 'agent',
        events: <Event>[modelToolCall],
      );

      final bool hasHitlCall = contents.any(
        (Content c) => c.parts.any((Part p) => p.functionCall?.id == 'call_hitl'),
      );
      expect(hasHitlCall, isTrue);
    });
  });
}
