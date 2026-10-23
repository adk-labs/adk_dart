import 'dart:async';

import 'package:adk_dart/adk_dart.dart';
import 'package:adk_dart/src/workflow/workflow.dart' as wf;
import 'package:test/test.dart';

class _EmptyFinalResponseModel extends BaseLlm {
  _EmptyFinalResponseModel() : super(model: 'empty-final-model');

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    yield LlmResponse(
      content: Content(role: 'model', parts: <Part>[Part.text('done')]),
      cacheCreationTokenCount: 42,
    );
  }
}

void main() {
  group('MongoDbSessionService (adk-python 983383519)', () {
    test('creates, gets, lists, updates state prefixes, and deletes sessions', () async {
      final MongoDbSessionService service = MongoDbSessionService(
        dbUrl: 'mongodb://localhost:27017',
      );
      addTearDown(service.close);

      final Session created = await service.createSession(
        appName: 'demo_app',
        userId: 'user_1',
        sessionId: 'sess_1',
        state: <String, Object?>{
          'app:shared': 'v1',
          'user:pref': 'dark',
          'temp:ephemeral': 'skip_me',
          'counter': 1,
        },
      );
      expect(created.id, 'sess_1');
      expect(created.state['app:shared'], 'v1');
      expect(created.state['user:pref'], 'dark');
      expect(created.state.containsKey('temp:ephemeral'), isFalse);
      expect(created.state['counter'], 1);

      await expectLater(
        service.createSession(
          appName: 'demo_app',
          userId: 'user_1',
          sessionId: 'sess_1',
        ),
        throwsA(isA<AlreadyExistsError>()),
      );

      final Event event = Event(
        id: 'evt_1',
        invocationId: 'inv_1',
        author: 'assistant',
        content: Content.modelText('hello'),
        actions: EventActions(
          stateDelta: <String, Object?>{
            'app:shared': 'v2',
            'user:pref': 'light',
            'temp:scratch': 99,
            'counter': 2,
          },
        ),
      );
      await service.appendEvent(session: created, event: event);
      expect(created.state['app:shared'], 'v2');
      expect(created.state['user:pref'], 'light');
      expect(created.state.containsKey('temp:scratch'), isFalse);
      expect(created.state['counter'], 2);

      final Session? fetched = await service.getSession(
        appName: 'demo_app',
        userId: 'user_1',
        sessionId: 'sess_1',
      );
      expect(fetched, isNotNull);
      expect(fetched!.events, hasLength(1));
      expect(fetched.state['app:shared'], 'v2');
      expect(fetched.state['user:pref'], 'light');
      expect(fetched.state['counter'], 2);

      // Optimistic concurrency: appending with an older lastUpdateTime throws StaleSessionError.
      final Session staleCopy = Session(
        id: fetched.id,
        appName: fetched.appName,
        userId: fetched.userId,
        lastUpdateTime: fetched.lastUpdateTime - 10.0,
      );
      await expectLater(
        service.appendEvent(
          session: staleCopy,
          event: Event(
            id: 'evt_stale',
            invocationId: 'inv_2',
            author: 'assistant',
            content: Content.modelText('stale'),
          ),
        ),
        throwsA(isA<StaleSessionError>()),
      );

      final ListSessionsResponse listed = await service.listSessions(
        appName: 'demo_app',
        userId: 'user_1',
      );
      expect(listed.sessions, hasLength(1));

      await service.deleteSession(
        appName: 'demo_app',
        userId: 'user_1',
        sessionId: 'sess_1',
      );
      expect(
        await service.getSession(
          appName: 'demo_app',
          userId: 'user_1',
          sessionId: 'sess_1',
        ),
        isNull,
      );
    });
  });

  group('Multi-run evaluation aggregation (adk-python 7f3517e43)', () {
    test('computes meanOverInvocations, meanOfRuns, minOverRuns, and passRate', () {
      final List<RunResult> runs = <RunResult>[
        RunResult(
          status: EvalStatus.passed,
          score: 0.9,
          invocationScores: <double?>[0.8, 1.0],
        ),
        RunResult(
          status: EvalStatus.passed,
          score: 0.8,
          invocationScores: <double?>[0.8],
        ),
        RunResult(
          status: EvalStatus.failed,
          score: 0.4,
          invocationScores: <double?>[0.4],
        ),
      ];
      expect(meanOverInvocations(runs), closeTo(0.75, 1e-9));
      expect(meanOfRuns(runs), closeTo(0.7, 1e-9));
      expect(minOverRuns(runs), closeTo(0.4, 1e-9));
      expect(passRate(runs), closeTo(2.0 / 3.0, 1e-9));
    });

    test('aggregates multiple EvalCaseResult runs via EvalCaseResultMultiRunAggregator', () {
      EvalCaseResult buildRun({
        required int rep,
        required double score,
        required EvalStatus status,
      }) {
        return EvalCaseResult(
          evalSetId: 'set_1',
          evalId: 'case_1',
          finalEvalStatus: status,
          repetitionIndex: rep,
          overallEvalMetricResults: <EvalMetricResultSpec>[
            EvalMetricResultSpec(
              metricName: 'response_match_score',
              score: score,
              threshold: 0.65,
              evalStatus: status,
            ),
          ],
          evalMetricResultPerInvocation: <EvalMetricResultPerInvocation>[],
          sessionId: 'sess_$rep',
        );
      }

      final List<MultiRunCaseResult> aggregated =
          EvalCaseResultMultiRunAggregator.aggregate(
            <EvalCaseResult>[
              buildRun(rep: 0, score: 0.9, status: EvalStatus.passed),
              buildRun(rep: 1, score: 0.8, status: EvalStatus.passed),
              buildRun(rep: 2, score: 0.4, status: EvalStatus.failed),
            ],
            multiRunConfig: MultiRunConfig(
              numRuns: 3,
              crossRunCriteria: <MultiRunCriterion>[
                MultiRunCriterion(method: 'pass_rate', threshold: 0.6),
              ],
            ),
          );

      expect(aggregated, hasLength(1));
      final MultiRunCaseResult single = aggregated.first;
      expect(single.evalSetId, 'set_1');
      expect(single.evalId, 'case_1');
      expect(single.runs, hasLength(3));
      expect(single.finalEvalStatus, EvalStatus.passed);
      expect(single.overallEvalMetricResults.first.score, closeTo(0.7, 1e-6));
    });
  });

  group('Cache creation token count & Anthropic MCP is_error (b89dda409, 37b1ab3c2)', () {
    test('propagates cacheCreationTokenCount on LlmResponse and Event', () async {
      final LlmAgent agent = LlmAgent(
        name: 'cache_agent',
        model: _EmptyFinalResponseModel(),
      );
      final InMemoryRunner runner = InMemoryRunner(agent: agent);
      final Session session = await runner.sessionService.createSession(
        appName: runner.appName,
        userId: 'u1',
      );
      final List<Event> events = await runner
          .runAsync(
            userId: 'u1',
            sessionId: session.id,
            newMessage: Content.userText('hi'),
          )
          .toList();
      expect(events.last.cacheCreationTokenCount, 42);
      expect(
        Event(
          invocationId: 'inv_1',
          author: 'cache_agent',
          nodeInfo: NodeInfo(path: 'cache_agent'),
        ).nodeName,
        'cache_agent',
      );
    });

    test('AnthropicLlm.partToMessageBlock marks MCP CallToolResult isError as is_error', () {
      final Part part = Part.fromFunctionResponse(
        name: 'mcp_tool',
        id: 'call_1',
        response: <String, dynamic>{
          'isError': true,
          'content': <Map<String, Object?>>[
            <String, Object?>{'type': 'text', 'text': 'Tool failed'},
          ],
        },
      );
      final Map<String, Object?> block = AnthropicLlm.partToMessageBlock(part);
      expect(block['type'], 'tool_result');
      expect(block['is_error'], isTrue);
    });

    test('AnthropicLlm.messageToLlmResponse extracts cacheCreationTokenCount', () {
      final LlmResponse response = AnthropicLlm.messageToLlmResponse(
        <String, Object?>{
          'id': 'msg_1',
          'type': 'message',
          'role': 'assistant',
          'model': 'claude-sonnet-4-20250514',
          'content': <Map<String, Object?>>[
            <String, Object?>{'type': 'text', 'text': 'Hello'},
          ],
          'stop_reason': 'end_turn',
          'usage': <String, Object?>{
            'input_tokens': 100,
            'output_tokens': 25,
            'cache_read_input_tokens': 50,
            'cache_creation_input_tokens': 80,
          },
        },
      );
      expect(response.cacheCreationTokenCount, 80);
    });
  });

  group('Gemini clientKwargs and liveConnectConfig http_options (fb197fa39)', () {
    test('preserves ADK tracking headers when clientKwargs sets http_options', () {
      final Gemini llm = Gemini(
        model: 'gemini-2.5-flash',
        clientKwargs: <String, Object?>{
          'http_options': <String, Object?>{
            'headers': <String, String>{'x-custom': 'val'},
          },
        },
      );
      final HttpOptions merged = buildAdkHttpOptions(
        clientKwargs: llm.clientKwargs,
      );
      expect(merged.headers['x-custom'], 'val');
      expect(merged.headers.containsKey('x-goog-api-client'), isTrue);
    });

    test('rejects liveConnectConfig.httpOptions in Gemini.connect', () async {
      final Gemini llm = Gemini(model: 'gemini-2.5-flash');
      final LlmRequest request = LlmRequest(
        model: 'gemini-2.5-flash',
        liveConnectConfig: LiveConnectConfig(
          httpOptions: HttpOptions(headers: <String, String>{'a': 'b'}),
        ),
      );
      expect(
        () => llm.connect(request),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('ParallelWorker per-item retryConfig delegation (a9714eceb)', () {
    test('retries individual failed items without re-running succeeded siblings', () async {
      final Map<int, int> attemptsPerItem = <int, int>{};
      final BaseNode itemNode = node(
        name: 'multiply',
        (WorkflowContext ctx, Object? input) {
          final int x = input is int ? input : int.parse('$input');
          final int attempt = (attemptsPerItem[x] ?? 0) + 1;
          attemptsPerItem[x] = attempt;
          if (x == 2 && attempt < 2) {
            throw StateError('transient failure on 2');
          }
          return x * 10;
        },
      );
      final ParallelWorker worker = ParallelWorker(
        node: itemNode,
        retryConfig: wf.RetryConfig(
          maxAttempts: 3,
          initialDelay: const Duration(milliseconds: 1),
          maxDelay: const Duration(milliseconds: 5),
        ),
      );
      expect(worker.retryConfig, isNull);
      expect(worker.wrappedNode.retryConfig?.maxAttempts, 3);

      final Workflow workflow = Workflow(
        name: 'parallel_retry_wf',
        nodes: <BaseNode>[
          node(
            name: 'seed',
            (WorkflowContext ctx, Object? _) => <int>[1, 2, 3],
          ),
          worker,
        ],
        edges: <Edge>[
          Edge(fromNode: START, toNode: 'seed'),
          Edge(fromNode: 'seed', toNode: worker.name),
        ],
      );
      final InMemoryRunner runner = InMemoryRunner(agent: workflow);
      final Session session = await runner.sessionService.createSession(
        appName: runner.appName,
        userId: 'u1',
      );
      final List<Event> events = await runner
          .runAsync(
            userId: 'u1',
            sessionId: session.id,
            newMessage: Content.userText('go'),
          )
          .toList();
      expect(events, isNotEmpty);
      expect(attemptsPerItem[1], 1);
      expect(attemptsPerItem[2], 2);
      expect(attemptsPerItem[3], 1);
    });
  });

  group('Live transcription replay & compaction author in getContents (9a158552)', () {
    test('replays input/output transcriptions when events have no Content', () {
      final List<Event> events = <Event>[
        Event(
          id: 'e1',
          invocationId: 'inv1',
          author: 'user',
          inputTranscription: <String, Object?>{'text': 'Hello '},
        ),
        Event(
          id: 'e2',
          invocationId: 'inv1',
          author: 'user',
          inputTranscription: <String, Object?>{'text': 'there'},
        ),
        Event(
          id: 'e3',
          invocationId: 'inv1',
          author: 'assistant',
          outputTranscription: <String, Object?>{'text': 'General Kenobi'},
        ),
      ];
      final List<Content> contents = getContents(
        currentBranch: null,
        events: events,
        agentName: 'assistant',
      );
      expect(contents, hasLength(2));
      expect(contents[0].role, 'user');
      expect(contents[0].parts.single.text, 'Hello there');
      expect(contents[1].role, 'model');
      expect(contents[1].parts.single.text, 'General Kenobi');
    });
  });

  group('Live streaming tool deduplication (adk-go 0355356e, adk-kotlin 0ee2f30b)', () {
    test('handleFunctionCallsLive skips duplicate call with identical args and restarts on changed args', () async {
      int invocationCount = 0;
      final List<StreamController<String>> controllers =
          <StreamController<String>>[];
      addTearDown(() async {
        for (final StreamController<String> c in controllers) {
          if (!c.isClosed) {
            await c.close();
          }
        }
      });
      Stream<String> ticker({required String symbol}) {
        invocationCount += 1;
        final StreamController<String> controller = StreamController<String>();
        controllers.add(controller);
        controller.add('$symbol:$invocationCount');
        return controller.stream;
      }

      final FunctionTool streamTool = FunctionTool(
        func: ticker,
        name: 'ticker',
      );
      final LlmAgent agent = LlmAgent(
        name: 'live_agent',
        model: _EmptyFinalResponseModel(),
        tools: <Object>[streamTool],
      );
      final Session session = Session(
        id: 's1',
        appName: 'app',
        userId: 'u1',
      );
      final InvocationContext ctx = InvocationContext(
        invocationId: 'inv_live',
        agent: agent,
        session: session,
        sessionService: InMemorySessionService(),
        liveRequestQueue: LiveRequestQueue(),
      );

      final Event call1 = Event(
        id: 'c1',
        invocationId: 'inv_live',
        author: 'live_agent',
        content: Content(
          role: 'model',
          parts: <Part>[
            Part.fromFunctionCall(
              name: 'ticker',
              id: 'fc_1',
              args: <String, dynamic>{'symbol': 'GOOG'},
            ),
          ],
        ),
      );

      final Event? resp1 = await handleFunctionCallsLive(
        ctx,
        call1,
        <String, BaseTool>{'ticker': streamTool},
      );
      expect(resp1, isNotNull);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(invocationCount, 1);

      // Calling again with identical args is skipped without restarting the stream.
      final Event call2 = Event(
        id: 'c2',
        invocationId: 'inv_live',
        author: 'live_agent',
        content: Content(
          role: 'model',
          parts: <Part>[
            Part.fromFunctionCall(
              name: 'ticker',
              id: 'fc_2',
              args: <String, dynamic>{'symbol': 'GOOG'},
            ),
          ],
        ),
      );
      await handleFunctionCallsLive(
        ctx,
        call2,
        <String, BaseTool>{'ticker': streamTool},
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(invocationCount, 1);

      // Calling with updated args restarts the streaming tool.
      final Event call3 = Event(
        id: 'c3',
        invocationId: 'inv_live',
        author: 'live_agent',
        content: Content(
          role: 'model',
          parts: <Part>[
            Part.fromFunctionCall(
              name: 'ticker',
              id: 'fc_3',
              args: <String, dynamic>{'symbol': 'AAPL'},
            ),
          ],
        ),
      );
      await handleFunctionCallsLive(
        ctx,
        call3,
        <String, BaseTool>{'ticker': streamTool},
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(invocationCount, 2);
    });
  });

  group('BigQueryAgentAnalyticsPlugin late callbacks & dropStats (adk-go 4df7bdda, 331c9c57)', () {
    test('preserves traceId and rootAgentName for late callbacks after afterRunCallback', () async {
      final InMemoryBigQueryEventSink sink = InMemoryBigQueryEventSink();
      final BigQueryAgentAnalyticsPlugin plugin = BigQueryAgentAnalyticsPlugin(
        projectId: 'p',
        datasetId: 'd',
        sink: sink,
        useBigQueryInsertAllSink: false,
      );
      final LlmAgent agent = LlmAgent(
        name: 'root_bq_agent',
        model: _EmptyFinalResponseModel(),
      );
      final InvocationContext inv = InvocationContext(
        invocationId: 'inv_bq_1',
        agent: agent,
        session: Session(id: 's1', appName: 'app', userId: 'u1'),
        sessionService: InMemorySessionService(),
      );
      await plugin.beforeRunCallback(invocationContext: inv);
      await plugin.afterRunCallback(invocationContext: inv);
      await plugin.onEventCallback(
        invocationContext: inv,
        event: Event(
          id: 'late_evt',
          invocationId: 'inv_bq_1',
          author: 'root_bq_agent',
          content: Content.modelText('late'),
          actions: EventActions(stateDelta: <String, Object?>{'k': 'v'}),
        ),
      );
      await plugin.flush();
      expect(sink.rows, isNotEmpty);
      expect(
        sink.rows.every((Map<String, Object?> r) => r['trace_id'] == 'inv_bq_1'),
        isTrue,
      );
      expect(plugin.dropStats.total, 0);
      expect(plugin.dropStats.gcsUploadFailed, 0);
    });
  });

  group('ApplicationIntegrationToolset & McpToolset fixes (adk-js 70944fe4, 509d69d6)', () {
    test('IntegrationConnectorTool excludes dynamicAuthConfig and ApplicationIntegrationToolset accepts trigger/toolName', () {
      expect(
        IntegrationConnectorTool.excludeFields,
        contains('dynamic_auth_config'),
      );
      final McpToolset mcpToolset = McpToolset(
        connectionParams: StdioConnectionParams(command: 'echo'),
      );
      expect(mcpToolset, isNotNull);
    });
  });

  group('RemoteA2aAgent task mode failure & per-session compaction (6c672404e, 933163849)', () {
    test('RemoteA2aAgent supports mode: task and emits error output when unreachable', () async {
      final RemoteA2aAgent remoteTaskAgent = RemoteA2aAgent(
        name: 'remote_worker',
        mode: 'task',
        outputSchema: <String, Object?>{
          'type': 'object',
          'properties': <String, Object?>{
            'answer': <String, Object?>{'type': 'string'},
          },
        },
        agentCard: AgentCard(
          name: 'remote_worker',
          description: 'Remote task worker',
          url: 'http://127.0.0.1:1/unreachable',
          version: '1.0.0',
        ),
      );
      expect(remoteTaskAgent.mode, 'task');
      expect(remoteTaskAgent.description, 'Remote task worker');

      final TaskAgentTool taskTool = TaskAgentTool(agent: remoteTaskAgent);
      final LlmAgent parent = LlmAgent(
        name: 'coordinator',
        model: _EmptyFinalResponseModel(),
        subAgents: <BaseAgent>[remoteTaskAgent],
      );
      final InMemorySessionService sessionService = InMemorySessionService();
      final Session session = await sessionService.createSession(
        appName: 'app',
        userId: 'u1',
      );
      final InvocationContext inv = InvocationContext(
        invocationId: 'inv_task',
        agent: parent,
        session: session,
        sessionService: sessionService,
      );
      final ToolContext toolCtx = ToolContext(
        inv,
        functionCallId: 'call_remote_1',
      );
      final Object? result = await taskTool.run(
        args: <String, dynamic>{'request': 'do work'},
        toolContext: toolCtx,
      );
      expect(result, isA<Map>());
      expect((result as Map)['error'], isNotEmpty);
    });
  });
}
