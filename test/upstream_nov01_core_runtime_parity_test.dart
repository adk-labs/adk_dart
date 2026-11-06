import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:adk_dart/adk_dart.dart';
import 'package:adk_dart/src/apps/compaction.dart' as app_compaction;
import 'package:test/test.dart';

class _SequentialFakeLlm extends BaseLlm {
  _SequentialFakeLlm(this.responses, {super.model = 'gemini-1.5-pro'});

  final List<LlmResponse> responses;
  final List<LlmRequest> requests = <LlmRequest>[];
  int _index = 0;

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    requests.add(
      LlmRequest(
        model: request.model,
        contents: request.contents
            .map((Content c) => c.copyWith())
            .toList(growable: false),
        config: request.config.copyWith(),
      ),
    );
    if (_index < responses.length) {
      yield responses[_index++];
    } else if (responses.isNotEmpty) {
      yield responses.last;
    }
  }
}

class _AfterRunObserverPlugin extends BasePlugin {
  _AfterRunObserverPlugin(this.onAfterRun) : super(name: 'after_run_observer');

  final void Function(InvocationContext invocationContext) onAfterRun;

  @override
  Future<void> afterRunCallback({
    required InvocationContext invocationContext,
  }) async {
    onAfterRun(invocationContext);
  }
}

class _BlockingSummarizer extends BaseEventsSummarizer {
  _BlockingSummarizer(this.started, this.blocker);

  final Completer<void> started;
  final Completer<Event?> blocker;

  @override
  Future<Event?> maybeSummarizeEvents({required List<Event> events}) {
    if (!started.isCompleted) {
      started.complete();
    }
    return blocker.future;
  }
}

class _TitleTool extends BaseTool {
  _TitleTool({
    required super.name,
    required super.description,
    super.title,
    super.customMetadata,
  });

  @override
  FunctionDeclaration? getDeclaration() => FunctionDeclaration(name: name);

  @override
  Future<Object?> run({
    required Map<String, dynamic> args,
    required ToolContext toolContext,
  }) async {
    return <String, Object?>{'ok': true};
  }
}

class _SerializableModel {
  _SerializableModel(this.id, this.count);

  final String id;
  final int count;

  Map<String, Object?> toJson() => <String, Object?>{'id': id, 'count': count};
}

class _FakeVertexSessionApiClient implements VertexAiSessionApiClient {
  Map<String, Object?>? lastCreateConfig;
  Map<String, Object?>? lastAppendConfig;
  int appendCallCount = 0;

  @override
  Future<Map<String, Object?>?> createSession({
    required String reasoningEngineId,
    required String userId,
    required Map<String, Object?> config,
  }) async {
    lastCreateConfig = Map<String, Object?>.from(config);
    return <String, Object?>{
      'name':
          'projects/p/locations/l/reasoningEngines/$reasoningEngineId/sessions/sess_1',
      'session_state': <String, Object?>{
        ...?config['session_state'] as Map<String, Object?>?,
        'temp:server_leak': 'should_be_dropped',
      },
      'update_time': '2026-01-01T00:00:00Z',
    };
  }

  @override
  Future<void> appendEvent({
    required String reasoningEngineId,
    required String sessionId,
    required String author,
    required String invocationId,
    required double timestamp,
    required Map<String, Object?> config,
  }) async {
    appendCallCount += 1;
    lastAppendConfig = Map<String, Object?>.from(config);
  }

  @override
  Future<void> deleteSession({
    required String reasoningEngineId,
    required String sessionId,
  }) async {}

  @override
  Future<Map<String, Object?>?> getSession({
    required String reasoningEngineId,
    required String sessionId,
  }) async => null;

  @override
  Stream<Map<String, Object?>> listEvents({
    required String reasoningEngineId,
    required String sessionId,
    double? afterTimestamp,
  }) => const Stream<Map<String, Object?>>.empty();

  @override
  Stream<Map<String, Object?>> listSessions({
    required String reasoningEngineId,
    String? userId,
  }) => const Stream<Map<String, Object?>>.empty();
}

class _FakeVertexMemoryBankApiClient implements VertexAiMemoryBankApiClient {
  final List<Map<String, Object?>> generatedEvents = <Map<String, Object?>>[];

  @override
  Future<void> generateFromEvents({
    required String agentEngineId,
    required String appName,
    required String userId,
    required List<Map<String, Object?>> events,
    required Map<String, Object?> config,
  }) async {
    generatedEvents.addAll(events);
  }

  @override
  Future<void> createMemory({
    required String agentEngineId,
    required String appName,
    required String userId,
    required String fact,
    required Map<String, Object?> config,
  }) async {}

  @override
  Future<void> generateFromDirectMemories({
    required String agentEngineId,
    required String appName,
    required String userId,
    required List<String> directMemories,
    required Map<String, Object?> config,
  }) async {}

  @override
  Stream<VertexAiRetrievedMemory> retrieve({
    required String agentEngineId,
    required String appName,
    required String userId,
    required String query,
  }) => const Stream<VertexAiRetrievedMemory>.empty();
}

class _NoopStt implements LiveIngress {
  @override
  Stream<IngressEvent> call(Stream<InlineData> audio) async* {}
}

class _PassthroughTts implements LiveEgress {
  @override
  Stream<EgressEvent> call(
    Stream<String> text, {
    required CancelSignal cancel,
  }) async* {
    await for (final String chunk in text) {
      yield AgentSpokenOutput(text: chunk);
    }
  }
}

void main() {
  group('A2aAgentExecutor & TaskResultAggregator cancellation (14765ab2b)', () {
    test('TaskResultAggregator prioritizes canceled over failed and working', () {
      final TaskResultAggregator aggregator = TaskResultAggregator();
      aggregator.processEvent(
        A2aTaskStatusUpdateEvent(
          taskId: 't1',
          contextId: 'c1',
          status: A2aTaskStatus(state: A2aTaskState.failed),
          finalEvent: false,
        ),
      );
      aggregator.processEvent(
        A2aTaskStatusUpdateEvent(
          taskId: 't1',
          contextId: 'c1',
          status: A2aTaskStatus(
            state: A2aTaskState.canceled,
            message: A2aMessage(
              messageId: 'm1',
              role: A2aRole.agent,
              parts: <A2aPart>[A2aPart.text('Canceled by client')],
            ),
          ),
          finalEvent: true,
        ),
      );

      expect(aggregator.taskState, A2aTaskState.canceled);
      expect(
        aggregator.taskStatusMessage?.parts.single.textPart?.text,
        'Canceled by client',
      );
    });

    test('A2aAgentExecutor cancels active in-flight run and emits canceled', () async {
      final Completer<void> toolStarted = Completer<void>();
      final Completer<void> toolNeverFinishes = Completer<void>();
      bool cancelCallbackInvoked = false;

      final FunctionTool slowTool = FunctionTool(
        func: () async {
          toolStarted.complete();
          await toolNeverFinishes.future;
          return 'done';
        },
        name: 'slow_tool',
        description: 'A slow tool',
      );

      final _SequentialFakeLlm llm = _SequentialFakeLlm(<LlmResponse>[
        LlmResponse(
          content: Content(
            role: 'model',
            parts: <Part>[
              Part.fromFunctionCall(
                name: 'slow_tool',
                args: const <String, dynamic>{},
                id: 'call_1',
              ),
            ],
          ),
        ),
      ]);

      final LlmAgent agent = LlmAgent(
        name: 'test_agent',
        model: llm,
        tools: <Object>[slowTool],
      );
      final InMemoryRunner runner = InMemoryRunner(
        agent: agent,
        appName: 'test_app',
        plugins: <BasePlugin>[
          _AfterRunObserverPlugin((InvocationContext ctx) {
            if (ctx.isAborted) {
              cancelCallbackInvoked = true;
            }
          }),
        ],
      );

      final A2aAgentExecutor executor = A2aAgentExecutor(runner: runner);
      final InMemoryA2aEventQueue execQueue = InMemoryA2aEventQueue();
      final InMemoryA2aEventQueue cancelQueue = InMemoryA2aEventQueue();

      final A2aRequestContext reqContext = A2aRequestContext(
        taskId: 'task-active-1',
        contextId: 'ctx-active-1',
        message: A2aMessage(
          messageId: 'msg-1',
          role: A2aRole.user,
          parts: <A2aPart>[A2aPart.text('run slow tool')],
        ),
      );

      final Future<void> execFuture = executor.execute(reqContext, execQueue);
      await toolStarted.future;

      await executor.cancel(reqContext, cancelQueue);
      await execFuture;

      expect(cancelCallbackInvoked, isTrue);
      expect(
        execQueue.events
            .whereType<A2aTaskStatusUpdateEvent>()
            .last
            .status
            .state,
        A2aTaskState.canceled,
      );
      expect(
        cancelQueue.events
            .whereType<A2aTaskStatusUpdateEvent>()
            .single
            .status
            .state,
        A2aTaskState.canceled,
      );
    });
  });

  group('Runner external stream cancellation & rewind state (eb0a77179, dfd534a88)', () {
    test('external stream subscription cancel seals dangling tool call in session', () async {
      final Completer<void> toolStarted = Completer<void>();
      final Completer<void> toolBlocker = Completer<void>();

      final FunctionTool slowTool = FunctionTool(
        func: () async {
          toolStarted.complete();
          await toolBlocker.future;
          return 'ok';
        },
        name: 'slow_tool',
        description: 'slow tool',
      );

      final _SequentialFakeLlm llm = _SequentialFakeLlm(<LlmResponse>[
        LlmResponse(
          content: Content(
            role: 'model',
            parts: <Part>[
              Part.fromFunctionCall(
                name: 'slow_tool',
                args: const <String, dynamic>{},
                id: 'call_ext_1',
              ),
            ],
          ),
        ),
      ]);

      final LlmAgent agent = LlmAgent(
        name: 'agent',
        model: llm,
        tools: <Object>[slowTool],
      );
      final InMemoryRunner runner = InMemoryRunner(
        agent: agent,
        appName: 'app',
      );
      final Session session = await runner.sessionService.createSession(
        appName: 'app',
        userId: 'u1',
        sessionId: 's1',
      );

      final StreamSubscription<Event> sub = runner
          .runAsync(
            userId: 'u1',
            sessionId: session.id,
            newMessage: Content.userText('go'),
          )
          .listen((Event _) {});

      await toolStarted.future;
      await sub.cancel();

      final Session? reloaded = await runner.sessionService.getSession(
        appName: 'app',
        userId: 'u1',
        sessionId: session.id,
      );
      expect(reloaded, isNotNull);
      final List<FunctionResponse> responses = reloaded!.events
          .expand((Event e) => e.getFunctionResponses())
          .toList();
      expect(responses.any((FunctionResponse r) => r.id == 'call_ext_1'), isTrue);
    });

    test('rewind preserves initial createSession state while restoring later deltas', () async {
      final InMemoryRunner runner = InMemoryRunner(
        agent: LlmAgent(
          name: 'agent',
          model: _SequentialFakeLlm(const <LlmResponse>[]),
        ),
        appName: 'app',
      );
      final Session session = await runner.sessionService.createSession(
        appName: 'app',
        userId: 'u1',
        sessionId: 's_rewind',
        state: <String, Object?>{'initial_key': 'initial_val'},
      );

      await runner.sessionService.appendEvent(
        session: session,
        event: Event(
          id: 'evt_1',
          invocationId: 'inv_1',
          author: 'user',
          content: Content.userText('turn 1'),
          actions: EventActions(
            stateDelta: <String, Object?>{
              'turn1_key': 't1',
              'overwritten_key': 'v1',
            },
          ),
        ),
      );
      await runner.sessionService.appendEvent(
        session: session,
        event: Event(
          id: 'evt_2',
          invocationId: 'inv_2',
          author: 'user',
          content: Content.userText('turn 2'),
          actions: EventActions(
            stateDelta: <String, Object?>{
              'overwritten_key': 'v2',
              'turn2_key': 't2',
            },
          ),
        ),
      );

      await runner.rewindAsync(
        userId: 'u1',
        sessionId: session.id,
        rewindBeforeInvocationId: 'inv_2',
      );

      final Session? rewound = await runner.sessionService.getSession(
        appName: 'app',
        userId: 'u1',
        sessionId: session.id,
      );
      expect(rewound, isNotNull);
      expect(rewound!.state['initial_key'], 'initial_val');
      expect(rewound.state['overwritten_key'], 'v1');
      expect(rewound.state['turn1_key'], 't1');
      expect(rewound.state['turn2_key'], isNull);
    });
  });

  group('Compaction abort signal cancellation (87d9dcdf5)', () {
    test('sliding window compaction aborts in-flight summarizer and skips append', () async {
      final InMemorySessionService sessionService = InMemorySessionService();
      final Session session = await sessionService.createSession(
        appName: 'app',
        userId: 'u1',
        sessionId: 's_compact',
      );
      await sessionService.appendEvent(
        session: session,
        event: Event(
          invocationId: 'inv_1',
          author: 'user',
          timestamp: 1.0,
          content: Content.userText('Very long user prompt ' * 20),
        ),
      );
      await sessionService.appendEvent(
        session: session,
        event: Event(
          invocationId: 'inv_1',
          author: 'agent',
          timestamp: 2.0,
          content: Content.modelText('Very long model response ' * 20),
        ),
      );

      final Completer<void> summarizerStarted = Completer<void>();
      final Completer<Event?> summarizerBlocker = Completer<Event?>();
      final AdkAbortSignal abortSignal = AdkAbortSignal();

      final EventsCompactionConfig config = EventsCompactionConfig(
        compactionInterval: 1,
        overlapSize: 0,
        summarizer: _BlockingSummarizer(summarizerStarted, summarizerBlocker),
      );

      final Future<bool> compactFuture =
          app_compaction.runCompactionForSlidingWindowConfig(
            config: config,
            session: session,
            sessionService: sessionService,
            agentName: 'agent',
            abortSignal: abortSignal,
          );

      await summarizerStarted.future;
      abortSignal.abort('cancelled');

      final bool compacted = await compactFuture;
      expect(compacted, isFalse);
      expect(
        session.events.where((Event e) => e.actions.compaction != null),
        isEmpty,
      );
    });
  });

  group('Output schema with sub_agents transfer (73b6790b2)', () {
    test('hasFunctionTools is true when agent has subAgents transfer targets', () {
      final _SequentialFakeLlm llm = _SequentialFakeLlm(
        const <LlmResponse>[],
        model: 'gemini-1.5-pro',
      );
      final LlmAgent subAgent = LlmAgent(
        name: 'sub_agent',
        description: 'Handles sub tasks',
        model: llm,
      );
      final LlmAgent rootAgent = LlmAgent(
        name: 'root_agent',
        model: llm,
        outputSchema: <String, Object?>{
          'type': 'object',
          'properties': <String, Object?>{
            'answer': <String, Object?>{'type': 'string'},
          },
        },
        subAgents: <BaseAgent>[subAgent],
      );

      expect(hasFunctionTools(rootAgent), isTrue);
      expect(canSetNativeOutputSchema(rootAgent), isFalse);
    });

    test('Basic and OutputSchema processors use SetModelResponseTool when subAgents exist on non-Vertex model', () async {
      final _SequentialFakeLlm llm = _SequentialFakeLlm(
        const <LlmResponse>[],
        model: 'gemini-1.5-pro',
      );
      final LlmAgent subAgent = LlmAgent(
        name: 'sub_agent',
        description: 'Sub agent',
        model: llm,
      );
      final LlmAgent rootAgent = LlmAgent(
        name: 'root_agent',
        model: llm,
        outputSchema: <String, Object?>{
          'type': 'object',
          'properties': <String, Object?>{
            'answer': <String, Object?>{'type': 'string'},
          },
        },
        subAgents: <BaseAgent>[subAgent],
      );

      final InMemorySessionService sessionService = InMemorySessionService();
      final Session session = await sessionService.createSession(
        appName: 'app',
        userId: 'u1',
      );
      final InvocationContext context = InvocationContext(
        sessionService: sessionService,
        invocationId: 'inv_1',
        agent: rootAgent,
        session: session,
      );
      final LlmRequest request = LlmRequest();

      await BasicLlmRequestProcessor().runAsync(context, request).drain<void>();
      await OutputSchemaRequestProcessor()
          .runAsync(context, request)
          .drain<void>();

      expect(request.config.responseSchema, isNull);
      expect(request.toolsDict.containsKey('set_model_response'), isTrue);
    });
  });

  group('Tool display names metadata & Features (29956a8e6)', () {
    test('populates adk:tool_display_names in model response event customMetadata', () async {
      final _TitleTool titledTool = _TitleTool(
        name: 'mcp_weather',
        description: 'Fetches weather',
        title: 'Weather Forecast',
      );
      final _TitleTool metadataTitledTool = _TitleTool(
        name: 'mcp_calendar',
        description: 'Fetches calendar',
        customMetadata: <String, dynamic>{'title': 'Calendar Lookup'},
      );
      final _SequentialFakeLlm llm = _SequentialFakeLlm(<LlmResponse>[
        LlmResponse(
          content: Content(
            role: 'model',
            parts: <Part>[
              Part.fromFunctionCall(
                name: 'mcp_weather',
                args: const <String, dynamic>{},
                id: 'c1',
              ),
              Part.fromFunctionCall(
                name: 'mcp_calendar',
                args: const <String, dynamic>{},
                id: 'c2',
              ),
            ],
          ),
        ),
        LlmResponse(content: Content.modelText('All done')),
      ]);

      final LlmAgent agent = LlmAgent(
        name: 'agent',
        model: llm,
        tools: <Object>[titledTool, metadataTitledTool],
      );
      final InMemoryRunner runner = InMemoryRunner(
        agent: agent,
        appName: 'app',
      );
      final Session session = await runner.sessionService.createSession(
        appName: 'app',
        userId: 'u1',
      );

      final List<Event> events = await runner
          .runAsync(
            userId: 'u1',
            sessionId: session.id,
            newMessage: Content.userText('check'),
          )
          .toList();

      final Event toolCallEvent = events.firstWhere(
        (Event e) => e.getFunctionCalls().isNotEmpty,
      );
      expect(
        toolCallEvent.customMetadata?[toolDisplayNamesMetadataKey],
        equals(<String, String>{
          'mcp_weather': 'Weather Forecast',
          'mcp_calendar': 'Calendar Lookup',
        }),
      );
    });

    test('FeatureName registers fsspecArtifactService and teams', () {
      expect(
        getFeatureConfig(FeatureName.fsspecArtifactService)?.defaultOn,
        isFalse,
      );
      expect(getFeatureConfig(FeatureName.teams)?.defaultOn, isTrue);
    });
  });

  group('Workflow JoinNode loop, waitForOutput rerun, and bytes output (b6600be7b, cddc57f63, 81c3fe649)', () {
    test('JoinNode in a loop keeps firing after the first iteration', () async {
      int iterations = 0;
      final FunctionNode startNode = node(
        (WorkflowContext ctx, Object? input) => 'seed',
        name: 'start_node',
      );
      final FunctionNode branchA = node(
        (WorkflowContext ctx, Object? input) => 'a_$iterations',
        name: 'branch_a',
      );
      final FunctionNode branchB = node(
        (WorkflowContext ctx, Object? input) => 'b_$iterations',
        name: 'branch_b',
      );
      final JoinNode joinNode = JoinNode(name: 'join_node');
      final FunctionNode loopRouter = node((
        WorkflowContext ctx,
        Object? input,
      ) {
        iterations += 1;
        ctx.route = iterations < 3 ? 'again' : 'done';
        return input;
      }, name: 'loop_router');
      final FunctionNode doneNode = node(
        (WorkflowContext ctx, Object? input) => 'finished_$iterations',
        name: 'done_node',
      );

      final Workflow workflow = Workflow(
        name: 'join_loop_wf',
        nodes: <BaseNode>[
          startNode,
          branchA,
          branchB,
          joinNode,
          loopRouter,
          doneNode,
        ],
        edges: <Edge>[
          Edge(fromNode: START, toNode: startNode),
          Edge(fromNode: startNode, toNode: branchA),
          Edge(fromNode: startNode, toNode: branchB),
          Edge(fromNode: branchA, toNode: joinNode),
          Edge(fromNode: branchB, toNode: joinNode),
          Edge(fromNode: joinNode, toNode: loopRouter),
          Edge(fromNode: loopRouter, toNode: branchA, route: 'again'),
          Edge(fromNode: loopRouter, toNode: branchB, route: 'again'),
          Edge(fromNode: loopRouter, toNode: doneNode, route: 'done'),
        ],
      );

      final WorkflowResult result = await workflow.runWorkflow(input: 'go');
      expect(iterations, 3);
      expect(result.outputs['done_node'], 'finished_3');
      expect(
        result.outputs['join_node'],
        equals(<String, Object?>{'branch_a': 'a_2', 'branch_b': 'b_2'}),
      );
    });

    test('waitForOutput terminal node rerunning with null output transitions back to waiting', () async {
      int turn = 0;
      final FunctionNode gateNode = FunctionNode(
        name: 'gate_node',
        waitForOutput: true,
        rerunOnResume: true,
        function: (WorkflowContext ctx, Object? input) {
          turn += 1;
          if (turn == 1) {
            ctx.route = 'retry';
            return 'first_attempt';
          }
          if (turn == 2) {
            return null;
          }
          return 'final_output';
        },
      );
      final FunctionNode doneNode = node(
        (WorkflowContext ctx, Object? input) => 'done:$input',
        name: 'done_node',
      );

      final Workflow innerWorkflow = Workflow(
        name: 'inner_wf',
        nodes: <BaseNode>[gateNode, doneNode],
        edges: <Edge>[
          Edge(fromNode: START, toNode: gateNode),
          Edge(fromNode: gateNode, toNode: gateNode, route: 'retry'),
          Edge(fromNode: gateNode, toNode: doneNode, route: DEFAULT_ROUTE),
        ],
      );

      final WorkflowResult res = await innerWorkflow.runWorkflow(input: 'in');
      expect(turn, 2);
      expect(res.nodeStates['gate_node']?.status, NodeStatus.waiting);
      expect(
        res.nodeStates['gate_node']?.outputFor.contains(r'$workflow'),
        isFalse,
      );
    });

    test('FunctionNode supports Uint8List bytes output and rehydration', () async {
      final Uint8List rawBytes = Uint8List.fromList(<int>[10, 20, 30, 40]);
      final FunctionNode bytesNode = node(
        (WorkflowContext ctx, Object? input) => rawBytes,
        name: 'bytes_node',
        outputSchema: Uint8List,
      );
      final Workflow wf = Workflow(
        name: 'bytes_wf',
        nodes: <BaseNode>[bytesNode],
        edges: <Edge>[Edge(fromNode: START, toNode: bytesNode)],
      );

      final InMemorySessionService sessionService = InMemorySessionService();
      final Session session = await sessionService.createSession(
        appName: 'app',
        userId: 'u1',
      );
      final InvocationContext context = InvocationContext(
        sessionService: sessionService,
        invocationId: 'inv_bytes',
        agent: wf,
        session: session,
      );

      final List<Event> events = await wf.runAsync(context).toList();
      final Event outputEvent = events.firstWhere((Event e) => e.hasOutput);
      expect(outputEvent.output, isA<Uint8List>());
      expect(outputEvent.output, equals(rawBytes));

      final StorageEventV0 stored = StorageEventV0.fromEvent(
        session: session,
        event: outputEvent,
      );
      final Map<String, Object?> serialized = stored.toJson();
      expect(serialized['output'], isA<String>());

      final Event roundTripped = StorageEventV0.fromJson(serialized).toEvent();
      final WorkflowResult rehydrated = wf.rehydrateResultFromEvents(
        <Event>[roundTripped],
        invocationId: 'inv_bytes',
      );
      expect(rehydrated.outputs['bytes_node'], isA<Uint8List>());
      expect(rehydrated.outputs['bytes_node'], equals(rawBytes));
    });
  });

  group('CascadeLiveConnection media filtering & sendHistory reasoning (50ab3b5e9, e4a824f24)', () {
    test('filterMediaHistory drops inlineData and fileData parts and empty contents', () {
      final List<Content> history = <Content>[
        Content(
          role: 'user',
          parts: <Part>[
            Part.fromInlineData(mimeType: 'audio/pcm', data: <int>[1, 2]),
          ],
        ),
        Content(
          role: 'user',
          parts: <Part>[
            Part.fromFileData(
              fileUri: 'artifact://app/u1/s1/_adk_live/audio.wav',
            ),
            Part.text('kept text'),
          ],
        ),
      ];

      final List<Content> filtered = filterMediaHistory(history);
      expect(filtered, hasLength(1));
      expect(filtered.single.parts, hasLength(1));
      expect(filtered.single.parts.single.text, 'kept text');
    });

    test('CascadeLiveConnection filters media and triggers reasoning on user-ending sendHistory', () async {
      final _SequentialFakeLlm llm = _SequentialFakeLlm(<LlmResponse>[
        LlmResponse(content: Content.modelText('Hello from cascade')),
      ]);
      final CascadeLiveConnection connection = CascadeLiveConnection(
        LlmRequest(
          model: 'gemini-2.5-flash',
          contents: <Content>[
            Content(
              role: 'user',
              parts: <Part>[
                Part.fromInlineData(mimeType: 'audio/pcm', data: <int>[1, 2]),
              ],
            ),
          ],
        ),
        llm,
        _NoopStt(),
        _PassthroughTts(),
      );

      expect(connection.contents, isEmpty);

      await connection.sendHistory(<Content>[
        Content(
          role: 'user',
          parts: <Part>[
            Part.fromInlineData(mimeType: 'audio/pcm', data: <int>[9, 9]),
            Part.text('Describe this'),
          ],
        ),
      ]);

      final List<LlmResponse> emitted = <LlmResponse>[];
      await for (final LlmResponse resp in connection.receive()) {
        emitted.add(resp);
        if (resp.turnComplete == true) {
          break;
        }
      }
      await connection.close();

      expect(llm.requests, hasLength(1));
      expect(llm.requests.single.contents, hasLength(1));
      expect(
        llm.requests.single.contents.single.parts.single.text,
        'Describe this',
      );
      expect(emitted.any((LlmResponse r) => r.turnComplete == true), isTrue);
    });
  });

  group('Sessions, Artifacts, Memory, Skills, and Streaming Utils (3a6b7a51d, f6325bc22, 968cd869f, da4af771b, 2cabbddf1, 4fae7b75c, da98d4d64, 0af1cdce3)', () {
    test('VertexAiSessionService filters temp state, validates config, skips partial events, and serializes stateDelta', () async {
      final _FakeVertexSessionApiClient apiClient =
          _FakeVertexSessionApiClient();
      final VertexAiSessionService service = VertexAiSessionService(
        project: 'p',
        location: 'us-central1',
        agentEngineId: '123',
        clientFactory: ({String? project, String? location, String? apiKey}) =>
            apiClient,
      );

      await expectLater(
        service.createSession(
          appName: '123',
          userId: 'u1',
          config: <String, Object?>{'unsupported_key': 1},
        ),
        throwsArgumentError,
      );

      await expectLater(
        service.createSession(
          appName: '123',
          userId: 'u1',
          ttl: '3600s',
          expireTime: '2026-01-02T00:00:00Z',
        ),
        throwsArgumentError,
      );

      final Session session = await service.createSession(
        appName: '123',
        userId: 'u1',
        displayName: 'my-session',
        ttl: '3600s',
        labels: <String, String>{'env': 'test'},
        state: <String, Object?>{
          'persisted': _SerializableModel('m1', 2),
          'temp:ephemeral': 'skip_me',
        },
      );

      expect(apiClient.lastCreateConfig?['display_name'], 'my-session');
      expect(apiClient.lastCreateConfig?['ttl'], '3600s');
      expect(
        apiClient.lastCreateConfig?['session_state'],
        equals(<String, Object?>{
          'persisted': <String, Object?>{'id': 'm1', 'count': 2},
        }),
      );
      expect(session.state.containsKey('temp:server_leak'), isFalse);

      final Event partialEvent = Event(
        invocationId: 'inv_1',
        author: 'agent',
        partial: true,
        content: Content.modelText('partial chunk'),
      );
      await service.appendEvent(session: session, event: partialEvent);
      expect(apiClient.appendCallCount, 0);

      final Event finalEvent = Event(
        invocationId: 'inv_1',
        author: 'agent',
        content: Content.modelText('final chunk'),
        actions: EventActions(
          stateDelta: <String, Object?>{
            'model_obj': _SerializableModel('m2', 5),
            'temp:scratch': 'not_persisted',
          },
        ),
      );
      await service.appendEvent(session: session, event: finalEvent);
      expect(apiClient.appendCallCount, 1);
      final Map<String, Object?> actions =
          apiClient.lastAppendConfig!['actions'] as Map<String, Object?>;
      expect(
        actions['state_delta'],
        equals(<String, Object?>{
          'model_obj': <String, Object?>{'id': 'm2', 'count': 5},
        }),
      );
    });

    test('FileArtifactService skips unversioned directories in listArtifactKeys', () async {
      final Directory tempDir = await Directory.systemTemp.createTemp(
        'adk_file_artifacts_test_',
      );
      addTearDown(() async {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });

      final FileArtifactService service = FileArtifactService(tempDir.path);
      await service.saveArtifact(
        appName: 'app',
        userId: 'u1',
        sessionId: 's1',
        filename: 'valid.txt',
        artifact: Part.text('hello'),
      );

      // Create an unversioned artifact directory with an empty versions/ folder.
      final Directory emptyVersionsDir = Directory(
        '${tempDir.path}/users/u1/sessions/s1/artifacts/stale.txt/versions/.0.pending',
      );
      emptyVersionsDir.createSync(recursive: true);

      final List<String> keys = await service.listArtifactKeys(
        appName: 'app',
        userId: 'u1',
        sessionId: 's1',
      );
      expect(keys, equals(<String>['valid.txt']));
    });

    test('VertexAiMemoryBankService filters thought parts before generating memories', () async {
      final _FakeVertexMemoryBankApiClient apiClient =
          _FakeVertexMemoryBankApiClient();
      final VertexAiMemoryBankService memoryService = VertexAiMemoryBankService(
        project: 'p',
        location: 'us-central1',
        agentEngineId: '123',
        clientFactory: ({String? project, String? location, String? apiKey}) =>
            apiClient,
      );

      await memoryService.addEventsToMemory(
        appName: 'app',
        userId: 'u1',
        events: <Event>[
          Event(
            invocationId: 'inv_1',
            author: 'agent',
            content: Content(
              role: 'model',
              parts: <Part>[Part.text('internal reasoning', thought: true)],
            ),
          ),
          Event(
            invocationId: 'inv_1',
            author: 'agent',
            content: Content(
              role: 'model',
              parts: <Part>[
                Part.text('step-by-step thought', thought: true),
                Part.text('User likes dark roast coffee.'),
              ],
            ),
          ),
        ],
      );

      expect(apiClient.generatedEvents, hasLength(1));
      final Map<String, Object?> content =
          apiClient.generatedEvents.single['content'] as Map<String, Object?>;
      final List<Object?> parts = content['parts'] as List<Object?>;
      expect(parts, hasLength(1));
      expect(
        (parts.single as Map<String, Object?>)['text'],
        'User likes dark roast coffee.',
      );
    });

    test('listSkillsInDir invokes onError callback for invalid skill directories', () async {
      final Directory tempDir = await Directory.systemTemp.createTemp(
        'adk_skills_test_',
      );
      addTearDown(() async {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });

      final Directory validDir = Directory('${tempDir.path}/valid-skill')
        ..createSync(recursive: true);
      File('${validDir.path}/SKILL.md').writeAsStringSync(
        '---\nname: valid-skill\ndescription: A valid skill\n---\nInstructions',
      );

      Directory('${tempDir.path}/broken-skill').createSync(recursive: true);

      final Map<String, Object> errors = <String, Object>{};
      final Map<String, Frontmatter> skills = listSkillsInDir(
        tempDir.path,
        onError: (String skillId, Object error) {
          errors[skillId] = error;
        },
      );

      expect(skills.keys, equals(<String>['valid-skill']));
      expect(errors.keys, equals(<String>['broken-skill']));
    });

    test('JsonPathTracker preserves split Unicode surrogate pairs across chunks', () {
      final JsonPathTracker tracker = JsonPathTracker();
      // 😀 is U+1F600 -> \uD83D\uDE00
      final List<PartialArg> prefixChunk = tracker.handleChunk(
        r'{"msg": "Hi ',
      );
      expect(prefixChunk, hasLength(1));
      expect(prefixChunk.single.jsonPath, r'$.msg');
      expect(prefixChunk.single.stringValue, 'Hi ');
      expect(prefixChunk.single.willContinue, isTrue);

      final List<PartialArg> highSurrogateChunk = tracker.handleChunk(
        r'\uD83D',
      );
      expect(highSurrogateChunk, isEmpty);

      final List<PartialArg> secondChunk = tracker.handleChunk(r'\uDE00!"}');
      expect(
        secondChunk.map((PartialArg p) => p.stringValue).join(),
        '😀!',
      );
      expect(secondChunk.last.willContinue, isFalse);
    });
  });
}
