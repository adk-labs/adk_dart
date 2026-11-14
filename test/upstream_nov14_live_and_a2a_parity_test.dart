import 'dart:async';

import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

class _RecordingA2aClient implements A2aClient {
  _RecordingA2aClient(this._streamBuilder);

  final Stream<Object> Function() _streamBuilder;

  @override
  Stream<Object> sendMessage({
    required A2aMessage request,
    Map<String, Object?>? requestMetadata,
    A2aClientCallContext? context,
  }) {
    return _streamBuilder();
  }
}

class _RecordingA2aClientFactory implements A2aClientFactory {
  _RecordingA2aClientFactory(this.client);

  final A2aClient client;

  @override
  A2aClient create(AgentCard agentCard) => client;
}

class _FakeLiveConnection extends BaseLlmConnection {
  final List<Content> historySent = <Content>[];
  final List<Content> contentsSent = <Content>[];
  final List<RealtimeBlob> realtimeSent = <RealtimeBlob>[];
  final StreamController<LlmResponse> _responses =
      StreamController<LlmResponse>();

  Future<void> Function(Content content)? onSendContent;
  void Function()? onReceiveSubscribed;
  int closeCount = 0;

  @override
  Future<void> sendHistory(List<Content> history) async {
    historySent.addAll(
      history.map((Content content) => content.copyWith()).toList(),
    );
  }

  @override
  Future<void> sendContent(Content content) async {
    contentsSent.add(content.copyWith());
    if (onSendContent != null) {
      await onSendContent!(content);
    }
  }

  @override
  Future<void> sendRealtime(RealtimeBlob blob) async {
    realtimeSent.add(
      RealtimeBlob(mimeType: blob.mimeType, data: List<int>.from(blob.data)),
    );
  }

  @override
  Stream<LlmResponse> receive() {
    onReceiveSubscribed?.call();
    return _responses.stream;
  }

  void emit(LlmResponse response) {
    if (!_responses.isClosed) {
      _responses.add(response);
    }
  }

  void emitError(Object error, [StackTrace? stackTrace]) {
    if (!_responses.isClosed) {
      _responses.addError(error, stackTrace);
    }
  }

  Future<void> finish() async {
    if (!_responses.isClosed) {
      await _responses.close();
    }
  }

  @override
  Future<void> close() async {
    closeCount += 1;
    if (!_responses.isClosed) {
      await _responses.close();
    }
  }
}

class _LiveConnectModel extends BaseLlm {
  _LiveConnectModel({
    _FakeLiveConnection? connection,
    List<_FakeLiveConnection>? connections,
  }) : _connections =
           connections ??
           <_FakeLiveConnection>[
             if (connection != null)
               connection
             else
               throw ArgumentError.notNull('connection'),
           ],
       super(model: 'gemini-live-test');

  final List<_FakeLiveConnection> _connections;
  final List<LlmRequest> connectedRequests = <LlmRequest>[];
  int _connectIndex = 0;

  LlmRequest? get connectedRequest =>
      connectedRequests.isEmpty ? null : connectedRequests.last;

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    yield LlmResponse(content: Content.modelText('unused-sync'));
  }

  BaseLlmConnection connect(LlmRequest request) {
    connectedRequests.add(request);
    final int index = _connectIndex < _connections.length
        ? _connectIndex
        : _connections.length - 1;
    _connectIndex += 1;
    return _connections[index];
  }
}

RemoteA2aAgent _makeRemoteA2aAgent({
  String name = 'currency',
  A2aClient? client,
  String? mode,
}) {
  final AgentCard card = AgentCard(
    name: name,
    description: 'Remote A2A agent',
    url: 'https://remote.example/rpc',
    version: '1.0.0',
  );
  return RemoteA2aAgent(
    name: name,
    agentCard: card,
    mode: mode,
    a2aClientFactory: client == null
        ? null
        : _RecordingA2aClientFactory(client),
  );
}

InvocationContext _makeA2aContext({
  required BaseAgent agent,
  String? nodePath,
  List<Event>? events,
}) {
  final InMemorySessionService sessionService = InMemorySessionService();
  final Session session = Session(
    id: 'session-a2a',
    appName: 'app-a2a',
    userId: 'user-a2a',
    events:
        events ??
        <Event>[
          Event(
            invocationId: 'inv-user',
            author: 'user',
            content: Content.userText('convert 10 USD to EUR'),
          ),
        ],
  );
  return InvocationContext(
    sessionService: sessionService,
    invocationId: 'inv-a2a',
    agent: agent,
    session: session,
    nodePath: nodePath,
  );
}

Future<InvocationContext> _makeLiveInvocationContext({
  required LlmAgent agent,
  LiveRequestQueue? liveRequestQueue,
  RunConfig? runConfig,
  PluginManager? pluginManager,
}) async {
  final InMemorySessionService sessionService = InMemorySessionService();
  final Session session = await sessionService.createSession(
    appName: 'app-live',
    userId: 'user-live',
    sessionId: 'session-live',
  );
  return InvocationContext(
    sessionService: sessionService,
    invocationId: 'inv-live',
    agent: agent,
    session: session,
    liveRequestQueue: liveRequestQueue ?? LiveRequestQueue(),
    runConfig: runConfig ?? RunConfig(),
    pluginManager: pluginManager,
  );
}

Event _functionCallEvent(
  List<FunctionCall> calls, {
  String author = 'assistant',
  String? liveSessionId,
  bool? partial,
}) {
  return Event(
    invocationId: 'inv-live',
    author: author,
    liveSessionId: liveSessionId,
    partial: partial,
    content: Content(
      role: 'model',
      parts: calls.map((FunctionCall call) => Part(functionCall: call)).toList(),
    ),
  );
}

void main() {
  group('f67cc356c: RemoteA2aAgent workflow output promotion', () {
    const String nodePath = 'wf@1/currency@1';

    test(
      'skips non-final task states and omitted status.state across A2A 0.3, 1.x, and internal wire formats',
      () {
        final RemoteA2aAgent agent = _makeRemoteA2aAgent();
        const List<String> nonFinalStates = <String>[
          'submitted',
          'working',
          'input-required',
          'auth-required',
          'unknown',
          'inputRequired',
          'authRequired',
          'TASK_STATE_SUBMITTED',
          'TASK_STATE_WORKING',
          'TASK_STATE_INPUT_REQUIRED',
          'TASK_STATE_AUTH_REQUIRED',
          'TASK_STATE_UNSPECIFIED',
        ];

        for (final String state in nonFinalStates) {
          final Event event = Event(
            invocationId: 'inv-1',
            author: 'currency',
            content: Content.modelText('Still working on $state...'),
            nodeInfo: NodeInfo(path: nodePath),
            customMetadata: <String, dynamic>{
              '${a2aMetadataPrefix}response': <String, Object?>{
                'id': 'task-1',
                'status': <String, Object?>{'state': state},
              },
            },
          );

          expect(
            agent.promoteResponseToOutput(event, nodePath),
            isFalse,
            reason: 'Expected non-final state "$state" not to be promoted',
          );
          expect(event.hasOutput, isFalse);
          expect(event.output, isNull);
          expect(event.nodeInfo.messageAsOutput, isNull);
        }

        // A2A 1.x MessageToDict omits default TASK_STATE_UNSPECIFIED on status.
        final Event omittedStateEvent = Event(
          invocationId: 'inv-1',
          author: 'currency',
          content: Content.modelText('Unspecified status'),
          nodeInfo: NodeInfo(path: nodePath),
          customMetadata: <String, dynamic>{
            '${a2aMetadataPrefix}response': <String, Object?>{
              'id': 'task-1',
              'status': <String, Object?>{},
            },
          },
        );
        expect(
          agent.promoteResponseToOutput(omittedStateEvent, nodePath),
          isFalse,
        );
        expect(omittedStateEvent.output, isNull);
      },
    );

    test(
      'promotes terminal task states and direct A2aMessage responses, filtering thoughts and tool parts',
      () {
        final RemoteA2aAgent agent = _makeRemoteA2aAgent();
        const List<String> terminalStates = <String>[
          'completed',
          'canceled',
          'rejected',
          'TASK_STATE_COMPLETED',
        ];

        for (final String state in terminalStates) {
          final Event event = Event(
            invocationId: 'inv-1',
            author: 'currency',
            content: Content(
              role: 'model',
              parts: <Part>[
                Part.text('thinking...', thought: true),
                Part.fromFunctionCall(
                  name: 'helper',
                  id: 'c1',
                  args: const <String, dynamic>{},
                ),
                Part.text('9.25 '),
                Part.text('EUR'),
              ],
            ),
            nodeInfo: NodeInfo(path: nodePath),
            customMetadata: <String, dynamic>{
              '${a2aMetadataPrefix}response': <String, Object?>{
                'id': 'task-1',
                'status': <String, Object?>{'state': state},
              },
            },
          );

          expect(
            agent.promoteResponseToOutput(event, nodePath),
            isTrue,
            reason: 'Expected terminal state "$state" to promote output',
          );
          expect(event.output, '9.25 EUR');
          expect(event.nodeInfo.messageAsOutput, isTrue);
        }

        // Direct A2aMessage response (no status block in response metadata).
        final Event messageEvent = Event(
          invocationId: 'inv-1',
          author: 'currency',
          content: Content.modelText('Direct message answer'),
          nodeInfo: NodeInfo(path: nodePath),
          customMetadata: <String, dynamic>{
            '${a2aMetadataPrefix}response': <String, Object?>{
              'messageId': 'msg-1',
              'role': 'agent',
            },
          },
        );
        expect(agent.promoteResponseToOutput(messageEvent, nodePath), isTrue);
        expect(messageEvent.output, 'Direct message answer');
        expect(messageEvent.nodeInfo.messageAsOutput, isTrue);
      },
    );

    test(
      'promotes completed task with MAX_TOKENS errorCode but skips failed tasks with errorCode',
      () {
        final RemoteA2aAgent agent = _makeRemoteA2aAgent();

        for (final String completedState in <String>[
          'completed',
          'TASK_STATE_COMPLETED',
        ]) {
          final Event completedMaxTokens = Event(
            invocationId: 'inv-1',
            author: 'currency',
            errorCode: 'MAX_TOKENS',
            content: Content.modelText('Truncated but valid answer'),
            nodeInfo: NodeInfo(path: nodePath),
            customMetadata: <String, dynamic>{
              '${a2aMetadataPrefix}response': <String, Object?>{
                'id': 'task-1',
                'status': <String, Object?>{'state': completedState},
              },
            },
          );

          expect(
            agent.promoteResponseToOutput(completedMaxTokens, nodePath),
            isTrue,
          );
          expect(completedMaxTokens.output, 'Truncated but valid answer');
          expect(completedMaxTokens.nodeInfo.messageAsOutput, isTrue);
        }

        for (final String failedState in <String>[
          'failed',
          'TASK_STATE_FAILED',
        ]) {
          for (final String code in <String>[
            a2aTaskFailedErrorCode,
            'MAX_TOKENS',
          ]) {
            final Event failedEvent = Event(
              invocationId: 'inv-1',
              author: 'currency',
              errorCode: code,
              errorMessage: 'Upstream service crashed',
              content: Content.modelText('Upstream service crashed'),
              nodeInfo: NodeInfo(path: nodePath),
              customMetadata: <String, dynamic>{
                '${a2aMetadataPrefix}response': <String, Object?>{
                  'id': 'task-1',
                  'status': <String, Object?>{'state': failedState},
                },
              },
            );

            expect(
              agent.promoteResponseToOutput(failedEvent, nodePath),
              isFalse,
              reason:
                  'Failed task ($failedState, errorCode=$code) must not promote',
            );
            expect(failedEvent.hasOutput, isFalse);
            expect(failedEvent.output, isNull);
            expect(failedEvent.nodeInfo.messageAsOutput, isNull);
          }
        }
      },
    );

    test(
      'runAsync does not promote failed remote A2A task across unary/streaming and v1/v2 metadata, keeping rehydrated workflow output empty',
      () async {
        for (final bool useV2 in <bool>[false, true]) {
          for (final bool streaming in <bool>[false, true]) {
            final A2aMessage failureMessage = A2aMessage(
              messageId: 'fail-msg',
              role: A2aRole.agent,
              parts: <A2aPart>[A2aPart.text('Rate limit exceeded')],
            );
            final Map<String, Object?> metadata = useV2
                ? <String, Object?>{'adk_a2a_extension': true}
                : <String, Object?>{};

            final _RecordingA2aClient client = _RecordingA2aClient(() {
              if (!streaming) {
                final A2aTask failedTask = A2aTask(
                  id: 'task-fail',
                  contextId: 'ctx-1',
                  metadata: metadata,
                  status: A2aTaskStatus(
                    state: A2aTaskState.failed,
                    message: failureMessage,
                  ),
                );
                return Stream<Object>.value((failedTask, null));
              }

              final A2aTask workingSnapshot = A2aTask(
                id: 'task-fail',
                contextId: 'ctx-1',
                metadata: metadata,
                status: A2aTaskStatus(state: A2aTaskState.working),
              );
              final A2aTask failedSnapshot = A2aTask(
                id: 'task-fail',
                contextId: 'ctx-1',
                metadata: metadata,
                status: A2aTaskStatus(
                  state: A2aTaskState.failed,
                  message: failureMessage,
                ),
              );
              return Stream<Object>.fromIterable(<Object>[
                (
                  workingSnapshot,
                  A2aTaskStatusUpdateEvent(
                    taskId: 'task-fail',
                    contextId: 'ctx-1',
                    status: A2aTaskStatus(
                      state: A2aTaskState.working,
                      message: A2aMessage(
                        messageId: 'work-msg',
                        role: A2aRole.agent,
                        parts: <A2aPart>[A2aPart.text('Fetching rates...')],
                      ),
                    ),
                  ),
                ),
                (
                  failedSnapshot,
                  A2aTaskStatusUpdateEvent(
                    taskId: 'task-fail',
                    contextId: 'ctx-1',
                    finalEvent: true,
                    status: A2aTaskStatus(
                      state: A2aTaskState.failed,
                      message: failureMessage,
                    ),
                  ),
                ),
              ]);
            });

            final RemoteA2aAgent agent = _makeRemoteA2aAgent(client: client);
            final Workflow wf = Workflow(
              name: 'wf',
              nodes: <BaseNode>[AgentNode(agent: agent, name: 'currency')],
              edges: <Edge>[Edge(fromNode: START, toNode: 'currency')],
            );

            final InvocationContext ctx = _makeA2aContext(
              agent: agent,
              nodePath: nodePath,
            );
            final List<Event> emitted = await agent.runAsync(ctx).toList();
            expect(emitted, isNotEmpty);

            final Event terminalEvent = emitted.last;
            expect(terminalEvent.errorCode, a2aTaskFailedErrorCode);
            expect(terminalEvent.hasOutput, isFalse);
            expect(terminalEvent.output, isNull);
            expect(terminalEvent.nodeInfo.path, nodePath);
            expect(terminalEvent.nodeInfo.messageAsOutput, isNull);

            final WorkflowResult rehydrated = wf.rehydrateResultFromEvents(
              emitted,
              invocationId: ctx.invocationId,
            );
            expect(
              rehydrated.outputs.containsKey('currency'),
              isFalse,
              reason:
                  'Failed remote A2A task (useV2=$useV2, streaming=$streaming) must not populate workflow outputs',
            );
            expect(
              rehydrated.nodeStates['currency']?.status,
              NodeStatus.failed,
            );
          }
        }
      },
    );

    test(
      'runAsync promotes only the first terminal response on nodePath and skips promotion in task mode',
      () async {
        final _RecordingA2aClient multiTerminalClient = _RecordingA2aClient(() {
          final A2aTask completedTask = A2aTask(
            id: 'task-ok',
            contextId: 'ctx-ok',
            status: A2aTaskStatus(state: A2aTaskState.completed),
          );
          return Stream<Object>.fromIterable(<Object>[
            (
              completedTask,
              A2aTaskStatusUpdateEvent(
                taskId: 'task-ok',
                contextId: 'ctx-ok',
                status: A2aTaskStatus(
                  state: A2aTaskState.working,
                  message: A2aMessage(
                    messageId: 'm-work',
                    role: A2aRole.agent,
                    parts: <A2aPart>[A2aPart.text('Calculating...')],
                  ),
                ),
              ),
            ),
            (
              completedTask,
              A2aTaskStatusUpdateEvent(
                taskId: 'task-ok',
                contextId: 'ctx-ok',
                finalEvent: true,
                status: A2aTaskStatus(
                  state: A2aTaskState.completed,
                  message: A2aMessage(
                    messageId: 'm-done-1',
                    role: A2aRole.agent,
                    parts: <A2aPart>[A2aPart.text('First answer')],
                  ),
                ),
              ),
            ),
            (
              completedTask,
              A2aTaskStatusUpdateEvent(
                taskId: 'task-ok',
                contextId: 'ctx-ok',
                finalEvent: true,
                status: A2aTaskStatus(
                  state: A2aTaskState.completed,
                  message: A2aMessage(
                    messageId: 'm-done-2',
                    role: A2aRole.agent,
                    parts: <A2aPart>[A2aPart.text('Second trailing message')],
                  ),
                ),
              ),
            ),
          ]);
        });

        final RemoteA2aAgent standardAgent = _makeRemoteA2aAgent(
          client: multiTerminalClient,
        );
        final List<Event> standardEvents = await standardAgent
            .runAsync(_makeA2aContext(agent: standardAgent, nodePath: nodePath))
            .toList();

        expect(standardEvents, hasLength(3));
        expect(standardEvents[0].output, isNull);
        expect(standardEvents[1].output, 'First answer');
        expect(standardEvents[1].nodeInfo.messageAsOutput, isTrue);
        expect(standardEvents[2].output, isNull);
        expect(standardEvents[2].nodeInfo.messageAsOutput, isNull);

        final Workflow wf = Workflow(
          name: 'wf',
          nodes: <BaseNode>[AgentNode(agent: standardAgent, name: 'currency')],
          edges: <Edge>[Edge(fromNode: START, toNode: 'currency')],
        );
        final WorkflowResult rehydrated = wf.rehydrateResultFromEvents(
          standardEvents.sublist(0, 2),
          invocationId: 'inv-a2a',
        );
        expect(rehydrated.outputs['currency'], 'First answer');

        // Task mode relies on finish_task unwrapping instead of text promotion.
        final RemoteA2aAgent taskModeAgent = _makeRemoteA2aAgent(
          client: multiTerminalClient,
          mode: 'task',
        );
        final List<Event> taskModeEvents = await taskModeAgent
            .runAsync(_makeA2aContext(agent: taskModeAgent, nodePath: nodePath))
            .toList();
        expect(taskModeEvents.every((Event e) => e.output == null), isTrue);
      },
    );
  });

  group('e5dd820da: Live background function calls & mergeFunctionResponses', () {
    test(
      'launchFunctionCallsLive runs parallel calls concurrently, tracks activeBackgroundTools, preserves liveSessionId, and queues responses in completion order',
      () async {
        final Completer<void> slowGate = Completer<void>();
        final Completer<void> bothStarted = Completer<void>();
        int startedCount = 0;

        final FunctionTool slowTool = FunctionTool(
          name: 'slow_tool',
          func: () async {
            startedCount += 1;
            if (startedCount == 2 && !bothStarted.isCompleted) {
              bothStarted.complete();
            }
            await slowGate.future;
            return <String, Object?>{'value': 'slow'};
          },
        );
        final FunctionTool fastTool = FunctionTool(
          name: 'fast_tool',
          func: () async {
            startedCount += 1;
            if (startedCount == 2 && !bothStarted.isCompleted) {
              bothStarted.complete();
            }
            return <String, Object?>{'value': 'fast'};
          },
        );

        final LlmAgent agent = LlmAgent(
          name: 'assistant',
          model: 'gemini-2.5-flash',
          tools: <Object>[slowTool, fastTool],
        );
        final InvocationContext context = await _makeLiveInvocationContext(
          agent: agent,
        );
        final LiveFunctionResponseQueue queue = LiveFunctionResponseQueue();

        final Event callEvent = _functionCallEvent(<FunctionCall>[
          FunctionCall(name: 'slow_tool', id: 'call-slow', args: const {}),
          FunctionCall(name: 'fast_tool', id: 'call-fast', args: const {}),
        ], liveSessionId: 'live-sess-42');

        launchFunctionCallsLive(context, callEvent, <String, BaseTool>{
          'slow_tool': slowTool,
          'fast_tool': fastTool,
        }, queue);

        expect(
          context.activeBackgroundTools.keys,
          containsAll(<String>['call-slow', 'call-fast']),
        );

        await bothStarted.future;
        final Event firstFinished = await queue.get();
        expect(firstFinished.getFunctionResponses().single.id, 'call-fast');
        expect(firstFinished.getFunctionResponses().single.response, {
          'value': 'fast',
        });
        expect(firstFinished.liveSessionId, 'live-sess-42');
        expect(context.activeBackgroundTools.containsKey('call-fast'), isFalse);
        expect(context.activeBackgroundTools.containsKey('call-slow'), isTrue);

        slowGate.complete();
        final Event secondFinished = await queue.get();
        expect(secondFinished.getFunctionResponses().single.id, 'call-slow');
        expect(secondFinished.getFunctionResponses().single.response, {
          'value': 'slow',
        });
        expect(secondFinished.liveSessionId, 'live-sess-42');
        expect(context.activeBackgroundTools, isEmpty);
      },
    );

    test(
      'launchFunctionCallsLive isolates tool exceptions with internal error response and supports onToolErrorCallback',
      () async {
        final FunctionTool crashingTool = FunctionTool(
          name: 'boom_tool',
          func: () async {
            throw StateError('database offline');
          },
        );
        final FunctionTool healthyTool = FunctionTool(
          name: 'ok_tool',
          func: () async => <String, Object?>{'ok': true},
        );

        final LlmAgent unhandledAgent = LlmAgent(
          name: 'assistant',
          model: 'gemini-2.5-flash',
          tools: <Object>[crashingTool, healthyTool],
        );
        final InvocationContext unhandledContext = await _makeLiveInvocationContext(
          agent: unhandledAgent,
        );
        final LiveFunctionResponseQueue unhandledQueue =
            LiveFunctionResponseQueue();

        launchFunctionCallsLive(
          unhandledContext,
          _functionCallEvent(<FunctionCall>[
            FunctionCall(name: 'boom_tool', id: 'c-boom', args: const {}),
            FunctionCall(name: 'ok_tool', id: 'c-ok', args: const {}),
          ], liveSessionId: 'sess-err'),
          <String, BaseTool>{
            'boom_tool': crashingTool,
            'ok_tool': healthyTool,
          },
          unhandledQueue,
        );

        final List<Event> responses = <Event>[
          await unhandledQueue.get(),
          await unhandledQueue.get(),
        ];
        final Map<String?, Map<String, dynamic>> byId =
            <String?, Map<String, dynamic>>{
              for (final Event e in responses)
                e.getFunctionResponses().single.id:
                    e.getFunctionResponses().single.response,
            };
        expect(byId['c-boom'], <String, dynamic>{
          'error': 'Invoking `boom_tool()` failed with an internal error.',
        });
        expect(byId['c-ok'], <String, dynamic>{'ok': true});
        expect(
          responses.every((Event e) => e.liveSessionId == 'sess-err'),
          isTrue,
        );

        // Now verify onToolErrorCallback overrides the failure response.
        final LlmAgent handledAgent = LlmAgent(
          name: 'assistant',
          model: 'gemini-2.5-flash',
          tools: <Object>[crashingTool],
          onToolErrorCallback:
              (
                BaseTool tool,
                Map<String, dynamic> args,
                ToolContext toolContext,
                Exception error,
              ) {
                return <String, dynamic>{'recovered': tool.name};
              },
        );
        final InvocationContext handledContext = await _makeLiveInvocationContext(
          agent: handledAgent,
        );
        final LiveFunctionResponseQueue handledQueue =
            LiveFunctionResponseQueue();

        launchFunctionCallsLive(
          handledContext,
          _functionCallEvent(<FunctionCall>[
            FunctionCall(name: 'boom_tool', id: 'c-handled', args: const {}),
          ]),
          <String, BaseTool>{'boom_tool': crashingTool},
          handledQueue,
        );

        final Event recovered = await handledQueue.get();
        expect(recovered.getFunctionResponses().single.response, {
          'recovered': 'boom_tool',
        });
      },
    );

    test(
      'streaming live tool queues pending status, receives inputStream fanout, emits caller-only Event items, and stops cleanly via stop_streaming',
      () async {
        final List<String> receivedInputs = <String>[];
        final Completer<void> gotUserLiveInput = Completer<void>();

        Stream<Object?> monitorStream({required LiveRequestQueue inputStream}) {
          final StreamController<Object?> controller =
              StreamController<Object?>();
          unawaited(() async {
            controller.add(<String, Object?>{'tick': 1});
            controller.add(
              Event(
                invocationId: 'inv-live',
                author: 'monitor',
                content: Content.modelText('ui-progress-badge'),
              ),
            );
            while (true) {
              final LiveRequest liveReq = await inputStream.get();
              if (liveReq.close) {
                return;
              }
              final String? text = liveReq.content?.parts.firstOrNull?.text;
              if (text != null) {
                receivedInputs.add(text);
                if (!gotUserLiveInput.isCompleted) {
                  gotUserLiveInput.complete();
                }
                break;
              }
            }
            // Wait until cancelled via stop_streaming.
            await Completer<void>().future;
          }());
          return controller.stream;
        }

        final FunctionTool streamTool = FunctionTool(
          name: 'monitor',
          func: monitorStream,
        );
        final FunctionTool customStopTool = FunctionTool(
          name: 'stop_streaming',
          // ignore: non_constant_identifier_names
          func: ({required String function_name}) async => <String, Object?>{
            'custom': function_name,
          },
        );

        final _FakeLiveConnection connection = _FakeLiveConnection();
        final _LiveConnectModel model = _LiveConnectModel(
          connection: connection,
        );
        final LlmAgent agent = LlmAgent(
          name: 'assistant',
          model: model,
          tools: <Object>[streamTool, customStopTool],
        );

        final LiveRequestQueue liveQueue = LiveRequestQueue();
        final InvocationContext context = await _makeLiveInvocationContext(
          agent: agent,
          liveRequestQueue: liveQueue,
        );

        connection.onReceiveSubscribed = () {
          connection.emit(
            LlmResponse(
              content: Content(
                role: 'model',
                parts: <Part>[
                  Part.fromFunctionCall(
                    name: 'monitor',
                    id: 'stream-1',
                    args: const <String, dynamic>{},
                  ),
                ],
              ),
            ),
          );
        };

        bool sentStopCall = false;
        connection.onSendContent = (Content content) async {
          final List<FunctionResponse> responses = content.parts
              .where((Part p) => p.functionResponse != null)
              .map((Part p) => p.functionResponse!)
              .toList();
          if (responses.any((FunctionResponse r) => r.id == 'stream-1') &&
              !sentStopCall) {
            sentStopCall = true;
            unawaited(() async {
              // Send live user content to verify fanout into tool's inputStream.
              liveQueue.sendContent(Content.userText('fanout-hello'));
              await gotUserLiveInput.future;
              connection.emit(
                LlmResponse(
                  content: Content(
                    role: 'model',
                    parts: <Part>[
                      Part.fromFunctionCall(
                        name: 'stop_streaming',
                        id: 'stop-1',
                        args: const <String, dynamic>{
                          'function_name': 'monitor',
                        },
                      ),
                    ],
                  ),
                ),
              );
            }());
          } else if (responses.any((FunctionResponse r) => r.id == 'stop-1')) {
            connection.emit(
              LlmResponse(
                content: Content.modelText('All done'),
                turnComplete: true,
              ),
            );
            await connection.finish();
          }
        };

        final List<Event> events = await agent.runLive(context).toList();

        expect(receivedInputs, <String>['fanout-hello']);

        // Verify caller-only Event yielded on monitor@stream-1 branch and was
        // NOT forwarded to connection.contentsSent as a FunctionResponse.
        final List<Event> callerBadgeEvents = events
            .where((Event e) => e.branch == 'monitor@stream-1')
            .toList();
        expect(callerBadgeEvents, hasLength(1));
        expect(callerBadgeEvents.single.content?.role, 'user');
        expect(
          callerBadgeEvents.single.content?.parts.single.text,
          'ui-progress-badge',
        );

        final List<FunctionResponse> stopResponses = events
            .expand((Event e) => e.getFunctionResponses())
            .where((FunctionResponse r) => r.id == 'stop-1')
            .toList();
        expect(stopResponses, hasLength(1));
        expect(stopResponses.single.response, <String, dynamic>{
          'status': 'Successfully stopped streaming function monitor',
        });
        expect(context.activeBackgroundTools, isEmpty);
      },
    );

    test(
      'streaming tool skips startup when beforeToolCallback answers or afterToolCallback throws',
      () async {
        int streamInvocations = 0;
        final FunctionTool streamTool = FunctionTool(
          name: 'feed',
          func: () async* {
            streamInvocations += 1;
            yield 'chunk';
          },
        );

        // Case 1: beforeToolCallback short-circuits.
        final LlmAgent shortCircuitAgent = LlmAgent(
          name: 'assistant',
          model: 'gemini-2.5-flash',
          tools: <Object>[streamTool],
          beforeToolCallback:
              (
                BaseTool tool,
                Map<String, dynamic> args,
                ToolContext toolContext,
              ) => <String, dynamic>{'cached': true},
        );
        final InvocationContext ctx1 = await _makeLiveInvocationContext(
          agent: shortCircuitAgent,
        );
        final LiveFunctionResponseQueue q1 = LiveFunctionResponseQueue();
        launchFunctionCallsLive(
          ctx1,
          _functionCallEvent(<FunctionCall>[
            FunctionCall(name: 'feed', id: 'c1', args: const {}),
          ]),
          <String, BaseTool>{'feed': streamTool},
          q1,
        );
        final Event shortCircuited = await q1.get();
        expect(shortCircuited.getFunctionResponses().single.response, {
          'cached': true,
        });
        expect(streamInvocations, 0);

        // Case 2: afterToolCallback throws -> queues internal error response.
        final LlmAgent afterThrowsAgent = LlmAgent(
          name: 'assistant',
          model: 'gemini-2.5-flash',
          tools: <Object>[streamTool],
          afterToolCallback:
              (
                BaseTool tool,
                Map<String, dynamic> args,
                ToolContext toolContext,
                Map<String, dynamic> response,
              ) {
                throw StateError('afterTool boom');
              },
        );
        final InvocationContext ctx2 = await _makeLiveInvocationContext(
          agent: afterThrowsAgent,
        );
        final LiveFunctionResponseQueue q2 = LiveFunctionResponseQueue();
        launchFunctionCallsLive(
          ctx2,
          _functionCallEvent(<FunctionCall>[
            FunctionCall(name: 'feed', id: 'c2', args: const {}),
          ]),
          <String, BaseTool>{'feed': streamTool},
          q2,
        );
        final Event errored = await q2.get();
        expect(errored.getFunctionResponses().single.response, <String, dynamic>{
          'error': 'Invoking `feed()` failed with an internal error.',
        });
      },
    );

    test(
      'markLiveFunctionDeclarationBehavior leaves default tools unset and marks scheduled/streaming/blocking tools accurately',
      () async {
        final FunctionTool defaultTool = FunctionTool(
          name: 'default_tool',
          func: () => 'ok',
        );
        final FunctionTool scheduledTool = FunctionTool(
          name: 'scheduled_tool',
          func: () => 'ok',
          responseScheduling: FunctionResponseScheduling.whenIdle,
        );
        final FunctionTool streamingTool = FunctionTool(
          name: 'stream_tool',
          func: () async* {
            yield 'item';
          },
        );
        final FunctionTool blockingTool = FunctionTool(
          name: 'blocking_tool',
          func: () => 'ok',
          behavior: ToolBehavior.blocking,
          responseScheduling: FunctionResponseScheduling.interrupt,
        );

        final _FakeLiveConnection connection = _FakeLiveConnection();
        connection.onReceiveSubscribed = () {
          unawaited(connection.finish());
        };
        final _LiveConnectModel model = _LiveConnectModel(
          connection: connection,
        );
        final LlmAgent agent = LlmAgent(
          name: 'assistant',
          model: model,
          tools: <Object>[
            defaultTool,
            scheduledTool,
            streamingTool,
            blockingTool,
          ],
        );

        final InvocationContext context = await _makeLiveInvocationContext(
          agent: agent,
        );
        await agent.runLive(context).toList();

        final LlmRequest connected = model.connectedRequest!;
        final Map<String, FunctionDeclaration> declarations =
            <String, FunctionDeclaration>{
              for (final ToolDeclaration toolDecl
                  in connected.config.tools ?? const <ToolDeclaration>[])
                for (final FunctionDeclaration fnDecl
                    in toolDecl.functionDeclarations)
                  fnDecl.name: fnDecl,
            };

        expect(declarations['default_tool']?.behavior, isNull);
        expect(
          declarations['scheduled_tool']?.behavior,
          ToolBehavior.nonBlocking,
        );
        expect(declarations['stream_tool']?.behavior, ToolBehavior.nonBlocking);
        expect(declarations['blocking_tool']?.behavior, ToolBehavior.blocking);
      },
    );

    test(
      'mergeFunctionResponses satisfies backpressure, clean-EOF flush, error retention, and early-close re-queue invariants',
      () async {
        final BaseLlmFlow flow = BaseLlmFlow();

        // 1. Clean EOF flushes waiting function responses in finish order.
        final StreamController<Event> modelCtrl1 = StreamController<Event>();
        final LiveFunctionResponseQueue fnQueue1 = LiveFunctionResponseQueue();
        final List<String> order1 = <String>[];
        final Future<void> done1 = () async {
          await for (final Event e in flow.mergeFunctionResponses(
            modelCtrl1.stream,
            fnQueue1,
          )) {
            order1.add(e.id);
          }
        }();
        modelCtrl1.add(Event(id: 'm1', invocationId: 'inv', author: 'model'));
        await Future<void>.delayed(Duration.zero);
        fnQueue1.putNowait(Event(id: 'f1', invocationId: 'inv', author: 'fn'));
        fnQueue1.putNowait(Event(id: 'f2', invocationId: 'inv', author: 'fn'));
        await modelCtrl1.close();
        await done1;
        expect(order1, <String>['m1', 'f1', 'f2']);
        expect(fnQueue1.isEmpty, isTrue);

        // 2. Receive stream error keeps unconsumed function responses queued in finish order.
        final StreamController<Event> modelCtrl2 = StreamController<Event>();
        final LiveFunctionResponseQueue fnQueue2 = LiveFunctionResponseQueue();
        final Completer<void> holdConsumer = Completer<void>();
        final List<String> seenBeforeError = <String>[];

        Object? caughtError;
        final Future<void> done2 = () async {
          try {
            await for (final Event e in flow.mergeFunctionResponses(
              modelCtrl2.stream,
              fnQueue2,
            )) {
              seenBeforeError.add(e.id);
              await holdConsumer.future;
            }
          } catch (error) {
            caughtError = error;
          }
        }();

        modelCtrl2.add(Event(id: 'm-first', invocationId: 'inv', author: 'a'));
        await Future<void>.delayed(Duration.zero);
        fnQueue2.putNowait(Event(id: 'fn-a', invocationId: 'inv', author: 'a'));
        fnQueue2.putNowait(Event(id: 'fn-b', invocationId: 'inv', author: 'a'));
        modelCtrl2.addError(StateError('socket dropped'));
        await Future<void>.delayed(const Duration(milliseconds: 10));
        holdConsumer.complete();
        await done2;

        expect(seenBeforeError, contains('m-first'));
        expect(caughtError, isA<StateError>());
        final List<String> remainingIds = <String>[];
        for (final String id in seenBeforeError.where(
          (String id) => id.startsWith('fn-'),
        )) {
          remainingIds.add(id);
        }
        while (fnQueue2.isNotEmpty) {
          remainingIds.add(fnQueue2.getNowait().id);
        }
        expect(remainingIds, <String>['fn-a', 'fn-b']);

        // 3. Early break from merged stream re-queues in-flight function response at front.
        final StreamController<Event> modelCtrl3 = StreamController<Event>();
        final LiveFunctionResponseQueue fnQueue3 = LiveFunctionResponseQueue();
        modelCtrl3.add(Event(id: 'm-break', invocationId: 'inv', author: 'a'));
        fnQueue3.putNowait(Event(id: 'fn-1', invocationId: 'inv', author: 'a'));
        fnQueue3.putNowait(Event(id: 'fn-2', invocationId: 'inv', author: 'a'));

        final List<String> consumed3 = <String>[];
        await for (final Event e in flow.mergeFunctionResponses(
          modelCtrl3.stream,
          fnQueue3,
        )) {
          consumed3.add(e.id);
          break;
        }
        await modelCtrl3.close();

        final List<String> allFn3 = <String>[
          ...consumed3.where((String id) => id.startsWith('fn-')),
        ];
        while (fnQueue3.isNotEmpty) {
          allFn3.add(fnQueue3.getNowait().id);
        }
        expect(allFn3, <String>['fn-1', 'fn-2']);
      },
    );

    test(
      'runLive keeps streaming model events and interruptions while a BLOCKING tool call is running, sending each parallel response individually',
      () async {
        final Completer<void> releaseBlockingTool = Completer<void>();
        final Completer<void> toolStarted = Completer<void>();

        final FunctionTool blockingSlowTool = FunctionTool(
          name: 'slow_blocking',
          behavior: ToolBehavior.blocking,
          func: () async {
            if (!toolStarted.isCompleted) {
              toolStarted.complete();
            }
            await releaseBlockingTool.future;
            return <String, Object?>{'done': 'blocking'};
          },
        );
        final FunctionTool fastSiblingTool = FunctionTool(
          name: 'fast_sibling',
          func: () async => <String, Object?>{'done': 'fast'},
        );

        final _FakeLiveConnection connection = _FakeLiveConnection();
        final _LiveConnectModel model = _LiveConnectModel(
          connection: connection,
        );
        final LlmAgent agent = LlmAgent(
          name: 'assistant',
          model: model,
          tools: <Object>[blockingSlowTool, fastSiblingTool],
        );

        connection.onReceiveSubscribed = () {
          unawaited(() async {
            connection.emit(
              LlmResponse(
                content: Content(
                  role: 'model',
                  parts: <Part>[
                    Part.fromFunctionCall(
                      name: 'slow_blocking',
                      id: 'call-block',
                      args: const <String, dynamic>{},
                    ),
                    Part.fromFunctionCall(
                      name: 'fast_sibling',
                      id: 'call-fast',
                      args: const <String, dynamic>{},
                    ),
                  ],
                ),
              ),
            );
            await toolStarted.future;
            // Model emits audio/text and interruption BEFORE slow_blocking finishes!
            connection.emit(
              LlmResponse(content: Content.modelText('Speaking while busy...')),
            );
            connection.emit(LlmResponse(interrupted: true));
          }());
        };

        connection.onSendContent = (Content content) async {
          final List<FunctionResponse> responses = content.parts
              .where((Part p) => p.functionResponse != null)
              .map((Part p) => p.functionResponse!)
              .toList();
          if (responses.any((FunctionResponse r) => r.id == 'call-block')) {
            connection.emit(
              LlmResponse(
                content: Content.modelText('Final answer'),
                turnComplete: true,
              ),
            );
            await connection.finish();
          }
        };

        final InvocationContext context = await _makeLiveInvocationContext(
          agent: agent,
        );
        final List<String> timeline = <String>[];
        final Completer<void> sawInterruptionWhileBlocked = Completer<void>();

        final Future<void> runFuture = () async {
          await for (final Event event in agent.runLive(context)) {
            if (event.getFunctionCalls().isNotEmpty) {
              timeline.add('calls');
            } else if (event.getFunctionResponses().isNotEmpty) {
              for (final FunctionResponse r in event.getFunctionResponses()) {
                timeline.add('resp:${r.id}');
              }
            } else if (event.interrupted == true) {
              timeline.add('interrupted');
              if (!sawInterruptionWhileBlocked.isCompleted) {
                sawInterruptionWhileBlocked.complete();
              }
            } else if (event.content?.parts.firstOrNull?.text != null) {
              timeline.add('text:${event.content!.parts.first.text}');
            }
          }
        }();

        await sawInterruptionWhileBlocked.future;
        // Verify model text + interruption arrived BEFORE slow_blocking was released!
        expect(timeline, contains('text:Speaking while busy...'));
        expect(timeline, contains('interrupted'));
        expect(timeline.contains('resp:call-block'), isFalse);

        releaseBlockingTool.complete();
        await runFuture;

        expect(timeline, contains('resp:call-fast'));
        expect(timeline, contains('resp:call-block'));
        expect(timeline.last, 'text:Final answer');

        // Each parallel call's FunctionResponse must be sent individually to the model.
        final List<List<String?>> sentResponseBatches = connection.contentsSent
            .map(
              (Content c) => c.parts
                  .where((Part p) => p.functionResponse != null)
                  .map((Part p) => p.functionResponse!.id)
                  .toList(),
            )
            .where((List<String?> ids) => ids.isNotEmpty)
            .toList();
        expect(sentResponseBatches, <List<String?>>[
          <String?>['call-fast'],
          <String?>['call-block'],
        ]);
      },
    );

    test(
      'normal live run completion drains non-streaming tools within liveToolFinishTimeout and cancels slower/streaming ones',
      () async {
        // Case A: Non-streaming tool finishes before timeout -> yielded & saved.
        final FunctionTool quickDrainTool = FunctionTool(
          name: 'quick_drain',
          func: () async {
            await Future<void>.delayed(const Duration(milliseconds: 40));
            return <String, Object?>{'drained': true};
          },
        );
        final _FakeLiveConnection connA = _FakeLiveConnection();
        connA.onReceiveSubscribed = () {
          connA.emit(
            LlmResponse(
              content: Content(
                role: 'model',
                parts: <Part>[
                  Part.fromFunctionCall(
                    name: 'quick_drain',
                    id: 'c-drain',
                    args: const <String, dynamic>{},
                  ),
                ],
              ),
            ),
          );
          unawaited(
            Future<void>.delayed(
              const Duration(milliseconds: 5),
              connA.finish,
            ),
          );
        };
        final InMemoryRunner runnerA = InMemoryRunner(
          agent: LlmAgent(
            name: 'assistant',
            model: _LiveConnectModel(connection: connA),
            tools: <Object>[quickDrainTool],
          ),
        );
        final Session sessionA = await runnerA.sessionService.createSession(
          appName: runnerA.appName,
          userId: 'u1',
        );
        final List<Event> eventsA = await runnerA
            .runLive(
              userId: 'u1',
              sessionId: sessionA.id,
              liveRequestQueue: LiveRequestQueue(),
            )
            .toList();
        expect(
          eventsA
              .expand((Event e) => e.getFunctionResponses())
              .single
              .response,
          <String, dynamic>{'drained': true},
        );

        // Case B: Non-streaming tool exceeds liveToolFinishTimeout -> cancelled without yielding.
        bool cancelledHungTool = false;
        final FunctionTool hungTool = FunctionTool(
          name: 'hung_tool',
          func: () async {
            await Future<void>.delayed(const Duration(seconds: 5));
            return <String, Object?>{'never': true};
          },
        );
        final _FakeLiveConnection connB = _FakeLiveConnection();
        connB.onReceiveSubscribed = () {
          connB.emit(
            LlmResponse(
              content: Content(
                role: 'model',
                parts: <Part>[
                  Part.fromFunctionCall(
                    name: 'hung_tool',
                    id: 'c-hung',
                    args: const <String, dynamic>{},
                  ),
                ],
              ),
            ),
          );
          unawaited(
            Future<void>.delayed(
              const Duration(milliseconds: 5),
              connB.finish,
            ),
          );
        };
        final LlmAgent agentB = LlmAgent(
          name: 'assistant',
          model: _LiveConnectModel(connection: connB),
          tools: <Object>[hungTool],
        );
        final BaseLlmFlow flowB = agentB.llmFlow
          ..liveToolFinishTimeout = const Duration(milliseconds: 40);
        final PluginManager pmB = PluginManager(
          plugins: <BasePlugin>[
            _CancelTrackingPlugin(
              onCancelled: () {
                cancelledHungTool = true;
              },
            ),
          ],
        );
        final InvocationContext ctxB = await _makeLiveInvocationContext(
          agent: agentB,
          pluginManager: pmB,
        );
        final List<Event> eventsB = await flowB.runLive(ctxB).toList();
        expect(
          eventsB.expand((Event e) => e.getFunctionResponses()),
          isEmpty,
        );
        expect(cancelledHungTool, isTrue);
        expect(ctxB.activeBackgroundTools, isEmpty);
      },
    );

    test(
      'session restart on blocked outputTranscription cancels running background tools and restarts cleanly',
      () async {
        final Completer<void> toolStarted = Completer<void>();
        bool toolWasCancelled = false;

        final FunctionTool backgroundTool = FunctionTool(
          name: 'long_op',
          func: () async {
            if (!toolStarted.isCompleted) {
              toolStarted.complete();
            }
            await Future<void>.delayed(const Duration(seconds: 5));
            return <String, Object?>{'late': true};
          },
        );

        final _FakeLiveConnection conn1 = _FakeLiveConnection();
        final _FakeLiveConnection conn2 = _FakeLiveConnection();
        final _LiveConnectModel model = _LiveConnectModel(
          connections: <_FakeLiveConnection>[conn1, conn2],
        );

        conn1.onReceiveSubscribed = () {
          unawaited(() async {
            conn1.emit(
              LlmResponse(
                content: Content(
                  role: 'model',
                  parts: <Part>[
                    Part.fromFunctionCall(
                      name: 'long_op',
                      id: 'c-restart',
                      args: const <String, dynamic>{},
                    ),
                  ],
                ),
              ),
            );
            await toolStarted.future;
            conn1.emit(
              LlmResponse(
                outputTranscription: <String, Object?>{
                  'text': 'forbidden output',
                  'finished': false,
                },
              ),
            );
          }());
        };

        conn2.onReceiveSubscribed = () {
          conn2.emit(
            LlmResponse(
              content: Content.modelText('Safe restarted response'),
              turnComplete: true,
            ),
          );
          unawaited(conn2.finish());
        };

        final LlmAgent agent = LlmAgent(
          name: 'assistant',
          model: model,
          tools: <Object>[backgroundTool],
          afterModelCallback:
              (CallbackContext callbackContext, LlmResponse llmResponse) {
                final Object? rawTx = llmResponse.outputTranscription;
                final String txText = rawTx is LiveTranscription
                    ? rawTx.text
                    : rawTx is Map
                    ? '${rawTx['text'] ?? ''}'
                    : '';
                if (txText.contains('forbidden output')) {
                  return LlmResponse(
                    content: Content.modelText('[REDACTED]'),
                  );
                }
                return null;
              },
        );

        final PluginManager pm = PluginManager(
          plugins: <BasePlugin>[
            _CancelTrackingPlugin(
              onCancelled: () {
                toolWasCancelled = true;
              },
            ),
          ],
        );
        final InvocationContext context = await _makeLiveInvocationContext(
          agent: agent,
          pluginManager: pm,
        );

        final List<Event> events = await agent.runLive(context).toList();

        expect(model.connectedRequests, hasLength(2));
        expect(toolWasCancelled, isTrue);
        expect(
          events.any(
            (Event e) => e.content?.parts.firstOrNull?.text == '[REDACTED]',
          ),
          isTrue,
        );
        expect(
          events.any(
            (Event e) =>
                e.content?.parts.firstOrNull?.text == 'Safe restarted response',
          ),
          isTrue,
        );
        expect(
          events.expand((Event e) => e.getFunctionResponses()),
          isEmpty,
        );
      },
    );

    test(
      'runAsync with RunConfig(supportCfc: true) delegates to live background execution once per tool call',
      () async {
        int toolRuns = 0;
        final FunctionTool cfcTool = FunctionTool(
          name: 'cfc_lookup',
          func: () async {
            toolRuns += 1;
            return <String, Object?>{'count': toolRuns};
          },
        );

        final _FakeLiveConnection connection = _FakeLiveConnection();
        connection.onReceiveSubscribed = () {
          connection.emit(
            LlmResponse(
              content: Content(
                role: 'model',
                parts: <Part>[
                  Part.fromFunctionCall(
                    name: 'cfc_lookup',
                    id: 'cfc-1',
                    args: const <String, dynamic>{},
                  ),
                ],
              ),
            ),
          );
        };
        connection.onSendContent = (Content content) async {
          if (content.parts.any((Part p) => p.functionResponse != null)) {
            connection.emit(
              LlmResponse(
                content: Content.modelText('CFC complete'),
                turnComplete: true,
              ),
            );
            await connection.finish();
          }
        };

        final LlmAgent agent = LlmAgent(
          name: 'assistant',
          model: _LiveConnectModel(connection: connection),
          tools: <Object>[cfcTool],
        );
        final InMemoryRunner runner = InMemoryRunner(agent: agent);
        final Session session = await runner.sessionService.createSession(
          appName: runner.appName,
          userId: 'u-cfc',
        );

        final List<Event> events = await runner
            .runAsync(
              userId: 'u-cfc',
              sessionId: session.id,
              newMessage: Content.userText('run cfc'),
              runConfig: RunConfig(supportCfc: true),
            )
            .toList();

        expect(toolRuns, 1);
        expect(
          events
              .expand((Event e) => e.getFunctionResponses())
              .map((FunctionResponse r) => r.response),
          <Map<String, dynamic>>[
            <String, dynamic>{'count': 1},
          ],
        );
        expect(events.last.content?.parts.single.text, 'CFC complete');
      },
    );

    test(
      'deprecated handleFunctionCallsLive remains backward-compatible for direct callers',
      () async {
        final FunctionTool echoTool = FunctionTool(
          name: 'echo',
          func: ({required String msg}) => <String, Object?>{'echo': msg},
        );
        final LlmAgent agent = LlmAgent(
          name: 'assistant',
          model: 'gemini-2.5-flash',
          tools: <Object>[echoTool],
        );
        final InvocationContext context = await _makeLiveInvocationContext(
          agent: agent,
        );
        // ignore: deprecated_member_use_from_same_package
        final Event? response = await handleFunctionCallsLive(
          context,
          _functionCallEvent(<FunctionCall>[
            FunctionCall(
              name: 'echo',
              id: 'legacy-1',
              args: const <String, dynamic>{'msg': 'hi'},
            ),
          ]),
          <String, BaseTool>{'echo': echoTool},
        );

        expect(response, isNotNull);
        expect(response!.getFunctionResponses().single.response, {
          'echo': 'hi',
        });
      },
    );
  });

  group('e237ec06c: Long-running live calls returning nothing', () {
    test(
      'LongRunningFunctionTool returning null emits no FunctionResponse in launchFunctionCallLive or runLive',
      () async {
        final Completer<void> started = Completer<void>();
        final LongRunningFunctionTool silentLongTool = LongRunningFunctionTool(
          func: () async {
            if (!started.isCompleted) {
              started.complete();
            }
            return null;
          },
        );

        // 1. Direct launchFunctionCallsLive check.
        final LlmAgent directAgent = LlmAgent(
          name: 'assistant',
          model: 'gemini-2.5-flash',
          tools: <Object>[silentLongTool],
        );
        final InvocationContext directCtx = await _makeLiveInvocationContext(
          agent: directAgent,
        );
        final LiveFunctionResponseQueue queue = LiveFunctionResponseQueue();

        launchFunctionCallsLive(
          directCtx,
          _functionCallEvent(<FunctionCall>[
            FunctionCall(name: silentLongTool.name, id: 'lr-1', args: const {}),
          ]),
          <String, BaseTool>{silentLongTool.name: silentLongTool},
          queue,
        );
        await waitForLiveToolCalls(directCtx);
        expect(queue.isEmpty, isTrue);

        // 2. End-to-end runLive check.
        final _FakeLiveConnection connection = _FakeLiveConnection();
        connection.onReceiveSubscribed = () {
          unawaited(() async {
            connection.emit(
              LlmResponse(
                content: Content(
                  role: 'model',
                  parts: <Part>[
                    Part.fromFunctionCall(
                      name: silentLongTool.name,
                      id: 'lr-live',
                      args: const <String, dynamic>{},
                    ),
                  ],
                ),
              ),
            );
            await started.future;
            await Future<void>.delayed(const Duration(milliseconds: 20));
            connection.emit(
              LlmResponse(
                content: Content.modelText('Awaiting external ticket update'),
                turnComplete: true,
              ),
            );
            await connection.finish();
          }());
        };

        final LlmAgent liveAgent = LlmAgent(
          name: 'assistant',
          model: _LiveConnectModel(connection: connection),
          tools: <Object>[silentLongTool],
        );
        final List<Event> liveEvents = await liveAgent
            .runLive(await _makeLiveInvocationContext(agent: liveAgent))
            .toList();

        expect(
          liveEvents.expand((Event e) => e.getFunctionResponses()),
          isEmpty,
        );
        expect(
          connection.contentsSent.where(
            (Content c) => c.parts.any((Part p) => p.functionResponse != null),
          ),
          isEmpty,
        );
      },
    );
  });

  group('1a0ddabf1: Yield finished tool responses when live connection fails', () {
    test(
      'BaseLlmFlow.runLive and Runner.runLive yield and persist finished tool responses before rethrowing connection failure',
      () async {
        final Completer<void> toolCompleted = Completer<void>();

        final FunctionTool sideEffectTool = FunctionTool(
          name: 'charge_card',
          func: () async {
            final Map<String, Object?> receipt = <String, Object?>{
              'charged': true,
              'tx_id': 'tx-999',
            };
            Future<void>.microtask(() {
              if (!toolCompleted.isCompleted) {
                toolCompleted.complete();
              }
            });
            return receipt;
          },
        );

        final _FakeLiveConnection connection = _FakeLiveConnection();
        connection.onReceiveSubscribed = () {
          unawaited(() async {
            connection.emit(
              LlmResponse(
                content: Content(
                  role: 'model',
                  parts: <Part>[
                    Part.fromFunctionCall(
                      name: 'charge_card',
                      id: 'call-tx',
                      args: const <String, dynamic>{},
                    ),
                  ],
                ),
              ),
            );
            await toolCompleted.future;
            await Future<void>.delayed(const Duration(milliseconds: 20));
            connection.emitError(StateError('WebSocket 1011 internal error'));
          }());
        };

        final LlmAgent agent = LlmAgent(
          name: 'assistant',
          model: _LiveConnectModel(connection: connection),
          tools: <Object>[sideEffectTool],
        );
        final InMemoryRunner runner = InMemoryRunner(agent: agent);
        final Session session = await runner.sessionService.createSession(
          appName: runner.appName,
          userId: 'u-crash',
        );

        final List<Event> yieldedBeforeCrash = <Event>[];
        Object? thrownError;
        try {
          await for (final Event event in runner.runLive(
            userId: 'u-crash',
            sessionId: session.id,
            liveRequestQueue: LiveRequestQueue(),
          )) {
            yieldedBeforeCrash.add(event);
            if (event.getFunctionCalls().isNotEmpty) {
              // Simulate slow caller processing while tool finishes & socket drops.
              await Future<void>.delayed(const Duration(milliseconds: 50));
            }
          }
        } catch (error) {
          thrownError = error;
        }

        expect(thrownError, isA<StateError>());
        expect(thrownError.toString(), contains('WebSocket 1011'));

        final List<FunctionResponse> yieldedResponses = yieldedBeforeCrash
            .expand((Event e) => e.getFunctionResponses())
            .toList();
        expect(yieldedResponses, hasLength(1));
        expect(yieldedResponses.single.id, 'call-tx');
        expect(yieldedResponses.single.response, <String, dynamic>{
          'charged': true,
          'tx_id': 'tx-999',
        });

        final Session? persisted = await runner.sessionService.getSession(
          appName: runner.appName,
          userId: 'u-crash',
          sessionId: session.id,
        );
        final List<FunctionResponse> persistedResponses = persisted!.events
            .expand((Event e) => e.getFunctionResponses())
            .toList();
        expect(persistedResponses, hasLength(1));
        expect(persistedResponses.single.id, 'call-tx');
      },
    );
  });
}

class _CancelTrackingPlugin extends BasePlugin {
  _CancelTrackingPlugin({required this.onCancelled})
    : super(name: 'cancel_tracker');

  final void Function() onCancelled;

  @override
  Future<Map<String, dynamic>?> onToolErrorCallback({
    required BaseTool tool,
    required Map<String, dynamic> toolArgs,
    required ToolContext toolContext,
    required Exception error,
  }) async {
    onCancelled();
    return null;
  }
}
