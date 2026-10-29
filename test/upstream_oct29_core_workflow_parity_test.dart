import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:adk_dart/adk_core.dart' as adk_core;
import 'package:adk_dart/adk_core.dart';
import 'package:adk_dart/src/apps/compaction.dart';
import 'package:adk_dart/src/features/_feature_registry.dart';
import 'package:adk_dart/src/flows/llm_flows/_fencing.dart';
import 'package:adk_dart/src/flows/llm_flows/audio_cache_manager.dart';
import 'package:adk_dart/src/flows/llm_flows/contents.dart';
import 'package:adk_dart/src/flows/llm_flows/single_flow.dart';
import 'package:adk_dart/src/memory/sqlite_memory_service.dart';
import 'package:adk_dart/src/workflow/workflow.dart';
import 'package:test/test.dart';

class _StreamingFakeLlm extends BaseLlm {
  _StreamingFakeLlm(this.responses) : super(model: 'fake-streaming');

  final List<LlmResponse> responses;

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    for (final LlmResponse response in responses) {
      await Future<void>.delayed(const Duration(milliseconds: 2));
      yield response;
    }
  }
}

class _ErrorFakeLlm extends BaseLlm {
  _ErrorFakeLlm() : super(model: 'fake-error');

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    throw Exception('simulated llm failure');
  }
}

class _RecordingPlugin extends BasePlugin {
  _RecordingPlugin() : super(name: 'recording_plugin');

  final List<CallbackInfo?> observed = <CallbackInfo?>[];

  @override
  Future<Content?> onUserMessageCallback({
    required InvocationContext invocationContext,
    required Content userMessage,
  }) async {
    observed.add(currentCallbackInfo);
    return null;
  }

  @override
  Future<Content?> beforeRunCallback({
    required InvocationContext invocationContext,
  }) async {
    observed.add(currentCallbackInfo);
    return null;
  }

  @override
  Future<Content?> beforeAgentCallback({
    required BaseAgent agent,
    required CallbackContext callbackContext,
  }) async {
    observed.add(callbackContext.callbackInfo);
    return null;
  }

  @override
  Future<LlmResponse?> beforeModelCallback({
    required CallbackContext callbackContext,
    required LlmRequest llmRequest,
  }) async {
    observed.add(callbackContext.callbackInfo);
    return null;
  }

  @override
  Future<LlmResponse?> afterModelCallback({
    required CallbackContext callbackContext,
    required LlmResponse llmResponse,
  }) async {
    observed.add(callbackContext.callbackInfo);
    return null;
  }

  @override
  Future<Map<String, dynamic>?> beforeToolCallback({
    required BaseTool tool,
    required Map<String, dynamic> toolArgs,
    required ToolContext toolContext,
  }) async {
    observed.add(toolContext.callbackInfo);
    return null;
  }

  @override
  Future<Map<String, dynamic>?> afterToolCallback({
    required BaseTool tool,
    required Map<String, dynamic> toolArgs,
    required ToolContext toolContext,
    required Map<String, dynamic> result,
  }) async {
    observed.add(toolContext.callbackInfo);
    return null;
  }

  @override
  Future<Content?> afterAgentCallback({
    required BaseAgent agent,
    required CallbackContext callbackContext,
  }) async {
    observed.add(callbackContext.callbackInfo);
    return null;
  }

  @override
  Future<Event?> onEventCallback({
    required InvocationContext invocationContext,
    required Event event,
  }) async {
    observed.add(currentCallbackInfo);
    return null;
  }

  @override
  Future<void> afterRunCallback({
    required InvocationContext invocationContext,
  }) async {
    observed.add(currentCallbackInfo);
  }
}

void main() {
  group('Item 1: Runner & Rewind optimizations and compaction flags', () {
    test('applyRewinds fast-path and getActiveEvents alias work', () {
      final List<Event> plainEvents = <Event>[
        Event(
          id: 'e1',
          invocationId: 'inv_1',
          author: 'user',
          content: Content.userText('hello'),
        ),
        Event(
          id: 'e2',
          invocationId: 'inv_1',
          author: 'agent',
          content: Content.modelText('world'),
        ),
      ];
      final List<Event> active = getActiveEvents(plainEvents);
      expect(active.map((Event e) => e.id), <String>['e1', 'e2']);

      final List<Event> withRewind = <Event>[
        ...plainEvents,
        Event(
          id: 'e3',
          invocationId: 'inv_2',
          author: 'user',
          content: Content.userText('mistake'),
        ),
        Event(
          id: 'e4',
          invocationId: 'inv_3',
          author: 'user',
          actions: EventActions(rewindBeforeInvocationId: 'inv_2'),
        ),
      ];
      expect(
        getActiveEvents(withRewind).map((Event e) => e.id),
        <String>['e1', 'e2'],
      );
    });

    test(
      'Runner honors eventsCompactionConfig and skipPostInvocationCompaction',
      () async {
        final LlmAgent agent = LlmAgent(
          name: 'compaction_agent',
          model: _StreamingFakeLlm(<LlmResponse>[
            LlmResponse(content: Content.modelText('turn 1 response')),
          ]),
        );
        final EventsCompactionConfig compactionConfig = EventsCompactionConfig(
          compactionInterval: 1,
          overlapSize: 0,
        );

        final InMemoryRunner skippedRunner = InMemoryRunner(
          agent: agent,
          eventsCompactionConfig: compactionConfig,
          skipPostInvocationCompaction: true,
        );
        final Session s1 = await skippedRunner.sessionService.createSession(
          appName: skippedRunner.appName,
          userId: 'u1',
        );
        await skippedRunner
            .runAsync(
              userId: 'u1',
              sessionId: s1.id,
              newMessage: Content.userText('hi'),
            )
            .toList();
        final Session? updatedS1 = await skippedRunner.sessionService.getSession(
          appName: skippedRunner.appName,
          userId: 'u1',
          sessionId: s1.id,
        );
        expect(
          updatedS1!.events.any((Event e) => e.actions.compaction != null),
          isFalse,
        );

        final InMemoryRunner activeRunner = InMemoryRunner(
          agent: LlmAgent(
            name: 'compaction_agent_2',
            model: _StreamingFakeLlm(<LlmResponse>[
              LlmResponse(content: Content.modelText('turn 1 response')),
            ]),
          ),
          eventsCompactionConfig: EventsCompactionConfig(
            compactionInterval: 1,
            overlapSize: 0,
          ),
          skipPostInvocationCompaction: false,
        );
        final Session s2 = await activeRunner.sessionService.createSession(
          appName: activeRunner.appName,
          userId: 'u1',
        );
        await activeRunner
            .runAsync(
              userId: 'u1',
              sessionId: s2.id,
              newMessage: Content.userText('hi'),
            )
            .toList();
        final Session? updatedS2 = await activeRunner.sessionService.getSession(
          appName: activeRunner.appName,
          userId: 'u1',
          sessionId: s2.id,
        );
        expect(
          updatedS2!.events.any((Event e) => e.actions.compaction != null),
          isTrue,
        );
      },
    );
  });

  group('Item 2: NodePathBuilder & BranchPath fast string helpers', () {
    test('parentNodePath, joinNodePath, isSameOrBelow, hasToolSegmentBelow', () {
      expect(parentNodePath(''), '');
      expect(parentNodePath('root@1'), '');
      expect(parentNodePath('root@1/child@2'), 'root@1');
      expect(parentNodePath('root@1.child@2'), 'root@1');
      expect(joinNodePath('', 'child@1'), 'child@1');
      expect(joinNodePath('root@1', 'child@2'), 'root@1/child@2');

      expect(BranchPath.isSameOrBelow('a.b', 'a.b'), isTrue);
      expect(BranchPath.isSameOrBelow('a.b.c', 'a.b'), isTrue);
      expect(BranchPath.isSameOrBelow('a.bc', 'a.b'), isFalse);

      expect(
        BranchPath.hasToolSegmentBelow(
          'agent.sub@fc_1',
          null,
          'agent',
          <String>{'fc_1'},
        ),
        isTrue,
      );
      expect(
        BranchPath.hasToolSegmentBelow(
          'agent.sub@fc_1',
          'agent',
          'agent',
          <String>{'fc_1'},
        ),
        isTrue,
      );
      expect(
        BranchPath.hasToolSegmentBelow(
          'agent.child@1',
          'agent',
          'agent',
          <String>{'fc_1'},
        ),
        isFalse,
      );
    });

    test('getContents and getCurrentTurnContents exclude tool sub-branches', () {
      final List<Event> events = <Event>[
        Event(
          id: 'u1',
          invocationId: 'inv1',
          author: 'user',
          branch: 'wf@1',
          content: Content.userText('run tool'),
        ),
        Event(
          id: 'fc1',
          invocationId: 'inv1',
          author: 'main_agent',
          branch: 'wf@1',
          content: Content(
            role: 'model',
            parts: <Part>[
              Part.fromFunctionCall(
                name: 'my_tool',
                id: 'fc_1',
                args: <String, dynamic>{},
              ),
            ],
          ),
        ),
        Event(
          id: 't1',
          invocationId: 'inv1',
          author: 'sub_agent',
          branch: 'wf@1.sub_agent@fc_1',
          content: Content.modelText('internal tool branch output'),
        ),
        Event(
          id: 'fr1',
          invocationId: 'inv1',
          author: 'main_agent',
          branch: 'wf@1',
          content: Content(
            role: 'user',
            parts: <Part>[
              Part.fromFunctionResponse(
                name: 'my_tool',
                id: 'fc_1',
                response: <String, dynamic>{'result': 'ok'},
              ),
            ],
          ),
        ),
        Event(
          id: 'm1',
          invocationId: 'inv1',
          author: 'main_agent',
          branch: 'wf@1',
          content: Content.modelText('final answer'),
        ),
      ];

      expect(
        isToolSubBranchEvent(
          'wf@1',
          events[2],
          'main_agent',
          <String>{'fc_1'},
        ),
        isTrue,
      );
      expect(
        isToolSubBranchEvent(
          'wf@1',
          events[4],
          'main_agent',
          <String>{'fc_1'},
        ),
        isFalse,
      );

      final List<Content> contents = getContents(
        currentBranch: 'wf@1',
        events: events,
        agentName: 'main_agent',
      );
      final String combined = contents
          .expand((Content c) => c.parts)
          .map((Part p) => p.text ?? '')
          .join(' ');
      expect(combined, contains('run tool'));
      expect(combined, contains('final answer'));
      expect(combined, isNot(contains('internal tool branch output')));

      final List<Content> currentTurn = getCurrentTurnContents(
        currentBranch: 'wf@1',
        events: events,
        agentName: 'main_agent',
      );
      final String turnCombined = currentTurn
          .expand((Content c) => c.parts)
          .map((Part p) => p.text ?? '')
          .join(' ');
      expect(turnCombined, isNot(contains('internal tool branch output')));
    });
  });

  group('Item 3: BaseLlmFlow partial event ID stability and timestamp refresh', () {
    test('streaming partial chunks share event ID with finalized event', () async {
      final LlmAgent agent = LlmAgent(
        name: 'stream_agent',
        model: _StreamingFakeLlm(<LlmResponse>[
          LlmResponse(
            content: Content.modelText('Hel'),
            partial: true,
          ),
          LlmResponse(
            content: Content.modelText('lo'),
            partial: true,
          ),
          LlmResponse(
            content: Content.modelText('Hello'),
            partial: false,
            turnComplete: true,
          ),
        ]),
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
            newMessage: Content.userText('greet'),
            runConfig: RunConfig(streamingMode: StreamingMode.sse),
          )
          .toList();

      final List<Event> modelEvents = events
          .where((Event e) => e.author == 'stream_agent')
          .toList();
      expect(modelEvents, hasLength(3));
      expect(modelEvents[0].partial, isTrue);
      expect(modelEvents[1].partial, isTrue);
      expect(modelEvents[2].partial, isFalse);
      expect(modelEvents[0].id, modelEvents[1].id);
      expect(modelEvents[1].id, modelEvents[2].id);
      expect(
        modelEvents[2].timestamp,
        greaterThanOrEqualTo(modelEvents[0].timestamp),
      );
    });
  });

  group('Item 4: Workflow error retry guards, partial/silent resume, and replay concurrency', () {
    test('WorkflowConfigurationError and WorkflowInvariantError are never retried', () async {
      int configAttempts = 0;
      final Workflow configWf = Workflow(
        name: 'cfg_wf',
        nodes: <BaseNode>[
          node(
            (WorkflowContext ctx, Object? input) {
              configAttempts += 1;
              throw WorkflowConfigurationError('bad config');
            },
            name: 'bad_cfg',
            retryConfig: const RetryConfig(
              maxAttempts: 4,
              initialDelay: Duration.zero,
            ),
          ),
        ],
      );
      await expectLater(
        configWf.runWorkflow(),
        throwsA(isA<WorkflowConfigurationError>()),
      );
      expect(configAttempts, 1);

      int invariantAttempts = 0;
      final Workflow invWf = Workflow(
        name: 'inv_wf',
        nodes: <BaseNode>[
          node(
            (WorkflowContext ctx, Object? input) {
              invariantAttempts += 1;
              throw WorkflowInvariantError('broken invariant');
            },
            name: 'bad_inv',
            retryConfig: const RetryConfig(
              maxAttempts: 4,
              initialDelay: Duration.zero,
            ),
          ),
        ],
      );
      await expectLater(
        invWf.runWorkflow(),
        throwsA(isA<WorkflowInvariantError>()),
      );
      expect(invariantAttempts, 1);
    });

    test('nodeRetryConfig, hasOwnRetryConfig, and withRetryConfig helpers', () {
      const RetryConfig retry = RetryConfig(maxAttempts: 3);
      final FunctionNode fn = node(
        (WorkflowContext ctx, Object? input) => input,
        name: 'fn',
      );
      expect(hasOwnRetryConfig(fn), isFalse);
      final BaseNode fnWithRetry = withRetryConfig(fn, retry);
      expect(hasOwnRetryConfig(fnWithRetry), isTrue);
      expect(nodeRetryConfig(fnWithRetry)?.maxAttempts, 3);

      final ParallelWorker pw = parallelWorker(fn, retryConfig: retry);
      expect(hasOwnRetryConfig(pw), isTrue);
      expect(nodeRetryConfig(pw)?.maxAttempts, 3);
    });

    test('partial resume of multi-interrupt rerunOnResume node does not rerun on later resume', () async {
      int waitForEitherRuns = 0;
      final FunctionNode waitForEither = FunctionNode(
        name: 'wait_for_either',
        rerunOnResume: true,
        function: (WorkflowContext ctx, Object? input) async {
          waitForEitherRuns += 1;
          if (ctx.resumeInputs.containsKey('takeover')) {
            return 'manual:${ctx.resumeInputs['takeover']}';
          }
          if (ctx.resumeInputs.containsKey('approval')) {
            return 'approved:${ctx.resumeInputs['approval']}';
          }
          await ctx.runNode(
            (WorkflowContext c, Object? i) =>
                RequestInput(interruptId: 'approval', message: 'Approve?'),
            name: 'ask_approval',
          );
          await ctx.runNode(
            (WorkflowContext c, Object? i) =>
                RequestInput(interruptId: 'takeover', message: 'Take over?'),
            name: 'ask_takeover',
          );
          return null;
        },
      );
      final FunctionNode followUp = FunctionNode(
        name: 'follow_up',
        rerunOnResume: true,
        function: (WorkflowContext ctx, Object? input) {
          if (ctx.resumeInputs.containsKey('later')) {
            return null;
          }
          return RequestInput(
            interruptId: 'later',
            message: 'Follow up?',
          );
        },
      );

      final Workflow wf = Workflow(
        name: 'multi_interrupt_wf',
        nodes: <BaseNode>[waitForEither, followUp],
      );

      final WorkflowResult r1 = await wf.runWorkflow();
      expect(waitForEitherRuns, 1);
      expect(r1.nodeStates['wait_for_either']?.status, NodeStatus.waiting);
      expect(r1.nodeStates['follow_up']?.status, NodeStatus.waiting);

      // Answer only 'takeover'; 'wait_for_either' completes while 'follow_up' stays waiting.
      final WorkflowResult r2 = await wf.runWorkflow(
        previousResult: r1,
        resumeInputs: <String, Object?>{'takeover': 'override'},
      );
      expect(waitForEitherRuns, 2);
      expect(r2.outputs['wait_for_either'], 'manual:override');
      expect(r2.nodeStates['wait_for_either']?.status, NodeStatus.completed);
      expect(r2.nodeStates['wait_for_either']?.interrupts, isEmpty);
      expect(r2.nodeStates['follow_up']?.status, NodeStatus.waiting);

      // Now answer 'later'; 'wait_for_either' must NOT run a 3rd time.
      final WorkflowResult r3 = await wf.runWorkflow(
        previousResult: r2,
        resumeInputs: <String, Object?>{'later': 'finished'},
      );
      expect(waitForEitherRuns, 2);
      expect(r3.outputs['wait_for_either'], 'manual:override');
      expect(r3.nodeStates['follow_up']?.status, NodeStatus.completed);
    });

    test('silent completion after resume marks node completed across event rehydration', () async {
      int silentNodeRuns = 0;
      final FunctionNode maybeSilent = FunctionNode(
        name: 'maybe_silent',
        rerunOnResume: true,
        waitForOutput: false,
        function: (WorkflowContext ctx, Object? input) {
          silentNodeRuns += 1;
          if (ctx.resumeInputs.containsKey('go')) {
            return null;
          }
          return RequestInput(interruptId: 'go', message: 'Go?');
        },
      );
      final FunctionNode followUp = FunctionNode(
        name: 'follow_up',
        function: (WorkflowContext ctx, Object? input) {
          return RequestInput(
            interruptId: 'later',
            message: 'Later?',
          );
        },
      );
      final Workflow wf = Workflow(
        name: 'silent_resume_wf',
        nodes: <BaseNode>[maybeSilent, followUp],
      );
      final App app = App(
        name: 'silent_app',
        rootAgent: wf,
        resumabilityConfig: ResumabilityConfig(isResumable: true),
      );
      final InMemoryRunner runner = InMemoryRunner(app: app);
      final Session session = await runner.sessionService.createSession(
        appName: runner.appName,
        userId: 'u1',
      );

      final List<Event> turn1 = await runner
          .runAsync(
            userId: 'u1',
            sessionId: session.id,
            newMessage: Content.userText('start'),
          )
          .toList();
      final String invId = turn1.first.invocationId;
      expect(silentNodeRuns, 1);

      // Respond to 'go' -> maybe_silent completes with null while follow_up stays waiting.
      await runner
          .runAsync(
            userId: 'u1',
            sessionId: session.id,
            invocationId: invId,
            newMessage: Content(
              role: 'user',
              parts: <Part>[
                Part.fromFunctionResponse(
                  name: requestInputFunctionCallName,
                  id: 'go',
                  response: <String, dynamic>{'result': 'quiet'},
                ),
              ],
            ),
          )
          .toList();
      expect(silentNodeRuns, 2);

      // Respond to 'later' -> maybe_silent must already be completed and not rerun.
      await runner
          .runAsync(
            userId: 'u1',
            sessionId: session.id,
            invocationId: invId,
            newMessage: Content(
              role: 'user',
              parts: <Part>[
                Part.fromFunctionResponse(
                  name: requestInputFunctionCallName,
                  id: 'later',
                  response: <String, dynamic>{'result': 'done'},
                ),
              ],
            ),
          )
          .toList();
      expect(silentNodeRuns, 2);
    });
  });

  group('Item 5: Compaction latestPromptTokenCount with trailing events and author filter', () {
    test('latestPromptTokenCount filters by agentName and adds trailing estimate', () {
      final List<Event> events = <Event>[
        Event(
          id: 'e1',
          invocationId: 'inv1',
          author: 'user',
          content: Content.userText('hello'),
        ),
        Event(
          id: 'e2',
          invocationId: 'inv1',
          author: 'agent_a',
          content: Content(
            role: 'model',
            parts: <Part>[
              Part.fromFunctionCall(
                name: 'lookup',
                id: 'call_1',
                args: <String, dynamic>{'q': 'abc'},
              ),
            ],
          ),
          usageMetadata: <String, Object?>{'promptTokenCount': 100},
        ),
        Event(
          id: 'e3',
          invocationId: 'inv1',
          author: 'agent_a',
          content: Content(
            role: 'user',
            parts: <Part>[
              Part.fromFunctionResponse(
                name: 'lookup',
                id: 'call_1',
                response: <String, dynamic>{
                  'result': 'a' * 80,
                },
              ),
            ],
          ),
        ),
        Event(
          id: 'e4',
          invocationId: 'inv1',
          author: 'other_agent',
          content: Content.modelText('other agent message'),
          usageMetadata: <String, Object?>{'promptTokenCount': 999},
        ),
      ];

      final int? count = latestPromptTokenCount(
        events: events,
        currentBranch: null,
        agentName: 'agent_a',
      );
      expect(count, isNotNull);
      // Must ignore other_agent's 999 and add trailing chars/4 to agent_a's 100.
      expect(count, greaterThan(100));
      expect(count, lessThan(500));
    });
  });

  group('Item 6: Memory services rewind filtering, thought filtering, and sessionless bucket', () {
    test('InMemoryMemoryService applies rewinds and isolates sessionless events', () async {
      final InMemoryMemoryService memory = InMemoryMemoryService();
      final Session session = Session(
        id: 'unknown_session',
        appName: 'app',
        userId: 'u1',
        events: <Event>[
          Event(
            id: 'ev1',
            invocationId: 'inv1',
            author: 'user',
            content: Content.userText('keep alpha'),
          ),
          Event(
            id: 'ev2',
            invocationId: 'inv2',
            author: 'user',
            content: Content.userText('rewound beta'),
          ),
          Event(
            id: 'ev3',
            invocationId: 'inv3',
            author: 'user',
            actions: EventActions(rewindBeforeInvocationId: 'inv2'),
          ),
        ],
      );

      // Add sessionless event first.
      await memory.addEventsToMemory(
        appName: 'app',
        userId: 'u1',
        events: <Event>[
          Event(
            id: 'ev_sessionless',
            invocationId: 'inv0',
            author: 'user',
            content: Content.userText('sessionless gamma'),
          ),
        ],
      );

      // Saving a session literally named 'unknown_session' must not overwrite sessionless events,
      // and must exclude rewound 'beta'.
      await memory.addSessionToMemory(session);

      final SearchMemoryResponse betaRes = await memory.searchMemory(
        appName: 'app',
        userId: 'u1',
        query: 'beta',
      );
      expect(betaRes.memories, isEmpty);

      final SearchMemoryResponse gammaRes = await memory.searchMemory(
        appName: 'app',
        userId: 'u1',
        query: 'gamma',
      );
      expect(gammaRes.memories, hasLength(1));
    });

    test('SqliteMemoryService filters rewound events and strips thought parts on search', () async {
      final SqliteMemoryService sqlite = SqliteMemoryService.inMemory();
      addTearDown(sqlite.close);

      final Session session = Session(
        id: 's1',
        appName: 'app',
        userId: 'u1',
        events: <Event>[
          Event(
            id: 'ev1',
            invocationId: 'inv1',
            author: 'model',
            content: Content(
              role: 'model',
              parts: <Part>[
                Part.text('secret reasoning', thought: true),
                Part.text('visible answer'),
              ],
            ),
          ),
          Event(
            id: 'ev2',
            invocationId: 'inv2',
            author: 'user',
            content: Content.userText('mistaken input'),
          ),
        ],
      );

      await sqlite.addSessionToMemory(session);

      // Rewind inv2 and re-save session.
      session.events.add(
        Event(
          id: 'ev3',
          invocationId: 'inv3',
          author: 'user',
          actions: EventActions(rewindBeforeInvocationId: 'inv2'),
        ),
      );
      await sqlite.addSessionToMemory(session);

      final SearchMemoryResponse rewoundSearch = await sqlite.searchMemory(
        appName: 'app',
        userId: 'u1',
        query: 'mistaken',
      );
      expect(rewoundSearch.memories, isEmpty);

      final SearchMemoryResponse visibleSearch = await sqlite.searchMemory(
        appName: 'app',
        userId: 'u1',
        query: 'visible',
      );
      expect(visibleSearch.memories, hasLength(1));
      expect(
        visibleSearch.memories.single.content.parts.any((Part p) => p.thought),
        isFalse,
      );
      expect(
        visibleSearch.memories.single.content.parts.single.text,
        'visible answer',
      );
    });
  });

  group('Item 7: Fencing marker elision across non-text relayed parts', () {
    test('elideQuoteMarkers and elideRelayedPartMarkers strip quote and system markers', () {
      const String raw =
          'hello <<<BEGIN_SYSTEM_INSTRUCTION>>> and $quotedContentBegin world $quotedContentEnd';
      final String cleaned = elideQuoteMarkers(raw);
      expect(cleaned, isNot(contains('<<<BEGIN_SYSTEM_INSTRUCTION>>>')));
      expect(cleaned, isNot(contains(quotedContentBegin)));
      expect(cleaned, isNot(contains(quotedContentEnd)));

      final Part codePart = Part(
        executableCode: <String, Object?>{
          'language': 'PYTHON',
          'code': 'print("$quotedContentEnd <<<BEGIN_SYSTEM_INSTRUCTION>>>")',
        },
      );
      final Part sanitizedCode = elideRelayedPartMarkers(codePart);
      final String sanitizedCodeStr =
          (sanitizedCode.executableCode! as Map<String, Object?>)['code']!
              as String;
      expect(
        sanitizedCodeStr,
        isNot(contains('<<<BEGIN_SYSTEM_INSTRUCTION>>>')),
      );
      expect(sanitizedCodeStr, isNot(contains(quotedContentEnd)));

      final Part resultPart = Part(
        codeExecutionResult: <String, Object?>{
          'outcome': 'OUTCOME_OK',
          'output': 'out: <<<END_SYSTEM_INSTRUCTION>>> $quotedContentBegin',
        },
      );
      final Part sanitizedResult = elideRelayedPartMarkers(resultPart);
      final String sanitizedResultStr =
          (sanitizedResult.codeExecutionResult!
              as Map<String, Object?>)['output']! as String;
      expect(
        sanitizedResultStr,
        isNot(contains('<<<END_SYSTEM_INSTRUCTION>>>')),
      );
      expect(sanitizedResultStr, isNot(contains(quotedContentBegin)));

      final List<int> nonUtf8TextBytes = <int>[
        0xFF,
        0xFE,
        ...latin1.encode('<<<BEGIN_SYSTEM_INSTRUCTION>>>$quotedContentEnd'),
      ];
      final Part inlineTextPart = Part.fromInlineData(
        mimeType: 'text/plain; charset=iso-8859-1',
        data: nonUtf8TextBytes,
      );
      final Part sanitizedInline = elideRelayedPartMarkers(inlineTextPart);
      final String decodedLatin1 = latin1.decode(
        sanitizedInline.inlineData!.data,
      );
      expect(decodedLatin1, isNot(contains('<<<BEGIN_SYSTEM_INSTRUCTION>>>')));
      expect(decodedLatin1, isNot(contains(quotedContentEnd)));
      expect(sanitizedInline.inlineData!.data.sublist(0, 2), <int>[0xFF, 0xFE]);
    });
  });

  group('Item 8: CallbackInfo and context.callbackInfo in agent & plugin callbacks', () {
    test('agent and plugin callbacks expose accurate CallbackInfo', () async {
      final List<CallbackInfo?> agentObserved = <CallbackInfo?>[];
      final _RecordingPlugin plugin = _RecordingPlugin();

      FutureOr<Content?> myBeforeAgent(CallbackContext ctx) {
        agentObserved.add(ctx.callbackInfo);
        return null;
      }

      FutureOr<Content?> myAfterAgent(CallbackContext ctx) {
        agentObserved.add(ctx.callbackInfo);
        return null;
      }

      FutureOr<LlmResponse?> myBeforeModel(
        CallbackContext ctx,
        LlmRequest req,
      ) {
        agentObserved.add(ctx.callbackInfo);
        return null;
      }

      FutureOr<LlmResponse?> myAfterModel(
        CallbackContext ctx,
        LlmResponse resp,
      ) {
        agentObserved.add(ctx.callbackInfo);
        return null;
      }

      FutureOr<Map<String, dynamic>?> myBeforeTool(
        BaseTool tool,
        Map<String, dynamic> args,
        ToolContext ctx,
      ) {
        agentObserved.add(ctx.callbackInfo);
        return null;
      }

      FutureOr<Map<String, dynamic>?> myAfterTool(
        BaseTool tool,
        Map<String, dynamic> args,
        ToolContext ctx,
        Map<String, dynamic> response,
      ) {
        agentObserved.add(ctx.callbackInfo);
        return null;
      }

      final FunctionTool echoTool = FunctionTool(
        name: 'echo_tool',
        description: 'Echoes input',
        func: ({required String msg}) => <String, Object?>{'echo': msg},
      );

      final LlmAgent agent = LlmAgent(
        name: 'cb_agent',
        model: _StreamingFakeLlm(<LlmResponse>[
          LlmResponse(
            content: Content(
              role: 'model',
              parts: <Part>[
                Part.fromFunctionCall(
                  name: 'echo_tool',
                  id: 'fc_1',
                  args: <String, dynamic>{'msg': 'hi'},
                ),
              ],
            ),
          ),
          LlmResponse(content: Content.modelText('done')),
        ]),
        tools: <Object>[echoTool],
        beforeAgentCallback: myBeforeAgent,
        afterAgentCallback: myAfterAgent,
        beforeModelCallback: myBeforeModel,
        afterModelCallback: myAfterModel,
        beforeToolCallback: myBeforeTool,
        afterToolCallback: myAfterTool,
      );

      final InMemoryRunner runner = InMemoryRunner(
        agent: agent,
        plugins: <BasePlugin>[plugin],
      );
      final Session session = await runner.sessionService.createSession(
        appName: runner.appName,
        userId: 'u1',
      );
      await runner
          .runAsync(
            userId: 'u1',
            sessionId: session.id,
            newMessage: Content.userText('run'),
          )
          .toList();

      expect(
        agentObserved.map((CallbackInfo? i) => i?.type),
        containsAll(<CallbackType>[
          CallbackType.beforeAgent,
          CallbackType.beforeModel,
          CallbackType.afterModel,
          CallbackType.beforeTool,
          CallbackType.afterTool,
          CallbackType.afterAgent,
        ]),
      );
      expect(
        agentObserved.every((CallbackInfo? i) => i != null && !i.isFromPlugin),
        isTrue,
      );
      expect(
        plugin.observed.every(
          (CallbackInfo? i) =>
              i != null && i.isFromPlugin && i.pluginName == 'recording_plugin',
        ),
        isTrue,
      );
    });

    test('onModelErrorCallback exposes CallbackType.onModelError', () async {
      CallbackInfo? errorCallbackInfo;
      final LlmAgent agent = LlmAgent(
        name: 'err_agent',
        model: _ErrorFakeLlm(),
        onModelErrorCallback: (
          CallbackContext ctx,
          LlmRequest req,
          Exception err,
        ) {
          errorCallbackInfo = ctx.callbackInfo;
          return LlmResponse(content: Content.modelText('recovered'));
        },
      );
      final InMemoryRunner runner = InMemoryRunner(agent: agent);
      final Session session = await runner.sessionService.createSession(
        appName: runner.appName,
        userId: 'u1',
      );
      await runner
          .runAsync(
            userId: 'u1',
            sessionId: session.id,
            newMessage: Content.userText('trigger error'),
          )
          .toList();
      expect(errorCallbackInfo?.type, CallbackType.onModelError);
      expect(errorCallbackInfo?.isFromPlugin, isFalse);
    });
  });

  group('Item 9: Feature registry promotions and new stable features', () {
    test('promoted and newly added features are stable and enabled by default', () {
      const List<FeatureName> expectedStableFeatures = <FeatureName>[
        FeatureName.agentConfig,
        FeatureName.authenticatedFunctionTool,
        FeatureName.bigQueryToolset,
        FeatureName.bigtableToolset,
        FeatureName.computerUse,
        FeatureName.dataAgentToolset,
        FeatureName.e2bEnvironment,
        FeatureName.environmentSimulation,
        FeatureName.gcsAdminToolset,
        FeatureName.gcsToolSettings,
        FeatureName.gcsToolset,
        FeatureName.googleCredentialsConfig,
        FeatureName.googleTool,
        FeatureName.mcpAgentServer,
        FeatureName.mcpToolset,
        FeatureName.openapiToolset,
        FeatureName.planners,
        FeatureName.pubsubToolset,
        FeatureName.skillToolset,
        FeatureName.spannerToolset,
        FeatureName.toolConfig,
        FeatureName.toolboxToolset,
      ];

      for (final FeatureName feature in expectedStableFeatures) {
        final FeatureConfig? config = getFeatureConfig(feature);
        expect(config, isNotNull, reason: '$feature should be registered');
        expect(
          config!.stage,
          FeatureStage.stable,
          reason: '$feature should be stable',
        );
        expect(
          config.defaultOn,
          isTrue,
          reason: '$feature should be defaultOn',
        );
        expect(isFeatureEnabled(feature), isTrue);
      }
    });
  });

  group('Item 10: InMemorySessionService deep-copies initial state', () {
    test('mutating caller state map after createSession does not mutate stored session', () async {
      final InMemorySessionService service = InMemorySessionService();
      final Map<String, Object?> nestedSession = <String, Object?>{'count': 1};
      final Map<String, Object?> nestedApp = <String, Object?>{'flag': true};
      final Map<String, Object?> nestedUser = <String, Object?>{'role': 'admin'};
      final Map<String, Object?> initialState = <String, Object?>{
        'nested': nestedSession,
        'app:config': nestedApp,
        'user:prefs': nestedUser,
      };

      final Session created = await service.createSession(
        appName: 'app',
        userId: 'u1',
        state: initialState,
      );

      nestedSession['count'] = 999;
      nestedApp['flag'] = false;
      nestedUser['role'] = 'guest';
      (created.state['nested'] as Map<String, Object?>)['count'] = 555;

      final Session? fetched = await service.getSession(
        appName: 'app',
        userId: 'u1',
        sessionId: created.id,
      );
      expect((fetched!.state['nested'] as Map<String, Object?>)['count'], 1);
      expect((fetched.state['app:config'] as Map<String, Object?>)['flag'], isTrue);
      expect((fetched.state['user:prefs'] as Map<String, Object?>)['role'], 'admin');
    });
  });

  group('Item 11: Realtime visual cache manager and live flow visual flush', () {
    test('RealtimeCacheManager caches visual blobs, enforces cap, and flushes zip artifact', () async {
      expect(
        () => RealtimeCacheConfig(maxVisualCacheFrames: 0),
        throwsArgumentError,
      );

      final RealtimeCacheManager manager = RealtimeCacheManager(
        config: RealtimeCacheConfig(maxVisualCacheFrames: 2),
      );
      final InMemorySessionService sessionService = InMemorySessionService();
      final InMemoryArtifactService artifactService = InMemoryArtifactService();
      final Session session = await sessionService.createSession(
        appName: 'app',
        userId: 'u1',
      );
      final InvocationContext ctx = InvocationContext(
        sessionService: sessionService,
        artifactService: artifactService,
        invocationId: 'inv_live',
        agent: LlmAgent(name: 'live_agent'),
        session: session,
      );

      manager.cacheRealtimeBlob(
        ctx,
        InlineData(mimeType: 'image/jpeg', data: <int>[1, 2]),
      );
      manager.cacheRealtimeBlob(
        ctx,
        InlineData(mimeType: 'image/png', data: <int>[3, 4, 5]),
      );
      manager.cacheRealtimeBlob(
        ctx,
        InlineData(mimeType: 'video/mp4', data: <int>[6, 7, 8, 9]),
      );

      final Map<String, int> stats = manager.getCacheStats(ctx);
      expect(stats['input_visual_frames'], 2);
      expect(stats['input_visual_bytes'], 7);

      final List<Event> flushed = await manager.flushCaches(ctx);
      expect(flushed, hasLength(1));
      final FileData fileData = flushed.single.content!.parts.single.fileData!;
      expect(fileData.mimeType, visualFramesZipMimeType);
      expect(fileData.fileUri, contains('adk_live_visual_storage_input_visual_'));

      final List<String> keys = await artifactService.listArtifactKeys(
        appName: 'app',
        userId: 'u1',
        sessionId: session.id,
      );
      expect(keys, hasLength(1));
      final Part? saved = await artifactService.loadArtifact(
        appName: 'app',
        userId: 'u1',
        sessionId: session.id,
        filename: keys.single,
      );
      final (List<VisualFrame> unpacked, _) = unpackVisualFrames(
        Uint8List.fromList(saved!.inlineData!.data),
      );
      expect(unpacked, hasLength(2));
      expect(unpacked[0].blob.mimeType, 'image/png');
      expect(unpacked[1].blob.mimeType, 'video/mp4');
    });

    test('BaseLlmFlow.handleControlEventFlush preserves visual cache on interrupted and flushes on turnComplete', () async {
      final SingleFlow flow = SingleFlow();
      final InMemorySessionService sessionService = InMemorySessionService();
      final InMemoryArtifactService artifactService = InMemoryArtifactService();
      final Session session = await sessionService.createSession(
        appName: 'app',
        userId: 'u1',
      );
      final InvocationContext ctx = InvocationContext(
        sessionService: sessionService,
        artifactService: artifactService,
        invocationId: 'inv_ctrl',
        agent: LlmAgent(name: 'live_agent'),
        session: session,
      );

      flow.audioCacheManager.cacheRealtimeBlob(
        ctx,
        InlineData(mimeType: 'image/jpeg', data: <int>[10, 20, 30]),
      );

      final List<Event> onInterrupted = await flow.handleControlEventFlush(
        ctx,
        LlmResponse(interrupted: true),
      );
      expect(onInterrupted, isEmpty);
      expect(ctx.inputVisualCache, hasLength(1));

      final List<Event> onTurnComplete = await flow.handleControlEventFlush(
        ctx,
        LlmResponse(turnComplete: true),
      );
      expect(onTurnComplete, hasLength(1));
      expect(ctx.inputVisualCache, isEmpty);
    });
  });

  group('Item 12: Web-safe plugin exports in adk_core', () {
    test('adk_core exports web-safe built-in plugins', () {
      expect(adk_core.AutoTracingPlugin(), isA<BasePlugin>());
      expect(adk_core.GlobalInstructionPlugin(), isA<BasePlugin>());
      expect(adk_core.LoggingPlugin(), isA<BasePlugin>());
      expect(adk_core.SaveFilesAsArtifactsPlugin(), isA<BasePlugin>());
      expect(
        adk_core.ToolCallIntegrityPlugin('secret-key-for-hmac-verification'),
        isA<BasePlugin>(),
      );
    });
  });
}
