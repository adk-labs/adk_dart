import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

class _FinalTextModel extends BaseLlm {
  _FinalTextModel() : super(model: 'test-model');

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) {
    return Stream<LlmResponse>.value(
      LlmResponse(content: Content.modelText('done')),
    );
  }
}

class _RecordingRunner extends InMemoryRunner {
  _RecordingRunner({
    required super.agent,
    required super.appName,
    required Stream<Event> Function({
      required String userId,
      required String sessionId,
      String? invocationId,
      Content? newMessage,
      Map<String, Object?>? stateDelta,
      RunConfig? runConfig,
    })
    eventFactory,
  }) : _eventFactory = eventFactory;

  final Stream<Event> Function({
    required String userId,
    required String sessionId,
    String? invocationId,
    Content? newMessage,
    Map<String, Object?>? stateDelta,
    RunConfig? runConfig,
  })
  _eventFactory;

  int runAsyncCalls = 0;
  String? lastUserId;
  String? lastSessionId;
  String? lastInvocationId;
  Content? lastNewMessage;

  @override
  Stream<Event> runAsync({
    required String userId,
    required String sessionId,
    String? invocationId,
    Content? newMessage,
    Map<String, Object?>? stateDelta,
    RunConfig? runConfig,
  }) {
    runAsyncCalls += 1;
    lastUserId = userId;
    lastSessionId = sessionId;
    lastInvocationId = invocationId;
    lastNewMessage = newMessage;
    return _eventFactory(
      userId: userId,
      sessionId: sessionId,
      invocationId: invocationId,
      newMessage: newMessage,
      stateDelta: stateDelta,
      runConfig: runConfig,
    );
  }
}

Event _modelEvent({
  String invocationId = 'invocation_1',
  String author = 'root_agent',
  String text = 'done',
}) {
  return Event(
    invocationId: invocationId,
    author: author,
    content: Content.modelText(text),
  );
}

Event _longRunningFunctionCallEvent({
  String invocationId = 'invocation_1',
  String author = 'root_agent',
  String toolName = 'wait_for_input',
  String toolId = 'call_1',
  Map<String, Object?> args = const <String, Object?>{'step': 'resume'},
  bool partial = false,
}) {
  return Event(
    invocationId: invocationId,
    author: author,
    partial: partial,
    longRunningToolIds: <String>{toolId},
    content: Content(
      role: 'model',
      parts: <Part>[
        Part.fromFunctionCall(
          name: toolName,
          id: toolId,
          args: Map<String, dynamic>.from(args),
        ),
      ],
    ),
  );
}

Event _longRunningFunctionResponseEvent({
  String invocationId = 'invocation_1',
  String author = 'root_agent',
  String toolName = 'wait_for_input',
  String toolId = 'call_1',
  Map<String, Object?> response = const <String, Object?>{'pending': true},
  bool partial = false,
}) {
  return Event(
    invocationId: invocationId,
    author: author,
    partial: partial,
    content: Content(
      role: 'model',
      parts: <Part>[
        Part.fromFunctionResponse(
          name: toolName,
          id: toolId,
          response: Map<String, dynamic>.from(response),
        ),
      ],
    ),
  );
}

A2aTask _requiredTask({
  required String taskId,
  required String contextId,
  required A2aTaskState state,
}) {
  return A2aTask(
    id: taskId,
    contextId: contextId,
    status: A2aTaskStatus(
      state: state,
      message: A2aMessage(
        messageId: 'task_$taskId',
        role: A2aRole.agent,
        parts: <A2aPart>[A2aPart.text('Need a function response.')],
      ),
    ),
  );
}

A2aPart _functionResponsePart({
  String name = 'my_tool',
  String id = 'call_1',
  Map<String, Object?> response = const <String, Object?>{'ok': true},
}) {
  return A2aPart.data(
    <String, Object?>{'name': name, 'response': response, 'id': id},
    metadata: <String, Object?>{
      getAdkMetadataKey(a2aDataPartMetadataTypeKey):
          a2aDataPartMetadataTypeFunctionResponse,
    },
  );
}

void main() {
  group('a2a platform helpers', () {
    tearDown(() {
      resetTimeProvider();
    });

    test('task status timestamps use the platform time provider', () {
      setTimeProvider(() => 123.456);

      final A2aTaskStatus status = A2aTaskStatus(state: A2aTaskState.working);

      expect(
        status.timestamp,
        DateTime.fromMicrosecondsSinceEpoch(
          123456000,
          isUtc: true,
        ).toIso8601String(),
      );
    });

    test('local a2a messages use the platform time provider', () {
      setTimeProvider(() => 456.789);

      final A2AMessage message = A2AMessage(
        fromAgent: 'planner',
        toAgent: 'worker',
        content: 'run tool',
      );

      expect(
        message.timestamp,
        DateTime.fromMicrosecondsSinceEpoch(456789000, isUtc: true),
      );
    });
  });

  group('a2a converters', () {
    test('context id and metadata key helpers', () {
      expect(getAdkMetadataKey('hello'), 'adk_hello');
      final String contextId = toA2aContextId('app', 'user', 'session');
      expect(contextId, 'ADK/app/user/session');
      expect(fromA2aContextId(contextId), ('app', 'user', 'session'));
      expect(fromA2aContextId('invalid'), (null, null, null));
    });

    test('part converter handles function-call data part roundtrip', () {
      final A2aPart part = A2aPart.data(
        <String, Object?>{
          'name': 'my_tool',
          'args': <String, Object?>{'city': 'seoul'},
          'id': 'call_1',
        },
        metadata: <String, Object?>{
          getAdkMetadataKey(a2aDataPartMetadataTypeKey):
              a2aDataPartMetadataTypeFunctionCall,
        },
      );

      final Object? converted = convertA2aPartToGenaiPart(part);
      expect(converted, isA<Part>());
      final Part convertedPart = converted! as Part;
      expect(convertedPart.functionCall?.name, 'my_tool');
      expect(convertedPart.functionCall?.id, 'call_1');

      final Object? roundtrip = convertGenaiPartToA2aPart(convertedPart);
      expect(roundtrip, isA<A2aPart>());
      final A2aPart rt = roundtrip! as A2aPart;
      expect(rt.dataPart?.data['name'], 'my_tool');
      expect(
        rt.dataPart?.metadata[getAdkMetadataKey(a2aDataPartMetadataTypeKey)],
        a2aDataPartMetadataTypeFunctionCall,
      );
    });

    test('part converter propagates thought metadata from text parts', () {
      final A2aPart part = A2aPart.text(
        'thinking',
        metadata: <String, Object?>{getAdkMetadataKey('thought'): true},
      );
      final Object? converted = convertA2aPartToGenaiPart(part);
      expect(converted, isA<Part>());
      expect((converted! as Part).thought, isTrue);
    });

    test(
      'event converter marks auth_required for long-running auth call',
      () async {
        final InMemorySessionService sessionService = InMemorySessionService();
        final Session session = await sessionService.createSession(
          appName: 'app',
          userId: 'user',
          sessionId: 'session',
        );
        final Agent agent = Agent(name: 'root_agent', model: _FinalTextModel());
        final InvocationContext invocationContext = InvocationContext(
          sessionService: sessionService,
          invocationId: 'invocation_1',
          agent: agent,
          session: session,
        );

        final Event event = Event(
          invocationId: 'invocation_1',
          author: 'root_agent',
          longRunningToolIds: <String>{'call_1'},
          content: Content(
            role: 'model',
            parts: <Part>[
              Part.fromFunctionCall(
                name: requestEucFunctionCallName,
                id: 'call_1',
                args: <String, Object?>{},
              ),
            ],
          ),
        );

        final List<A2aEvent> events = convertEventToA2aEvents(
          event,
          invocationContext,
        );
        expect(events, hasLength(1));
        final A2aTaskStatusUpdateEvent update =
            events.first as A2aTaskStatusUpdateEvent;
        expect(update.status.state, A2aTaskState.authRequired);
      },
    );

    test('function-call thought signature survives A2A roundtrip', () {
      final Part part = Part.fromFunctionCall(
        name: 'my_tool',
        args: <String, dynamic>{'city': 'seoul'},
        id: 'call_42',
        thoughtSignature: <int>[1, 2, 3, 4],
      );

      final Object? converted = convertGenaiPartToA2aPart(part);
      expect(converted, isA<A2aPart>());
      final A2aPart a2aPart = converted! as A2aPart;
      expect(a2aPart.dataPart?.data['thought_signature'], isA<String>());

      final Object? roundtrip = convertA2aPartToGenaiPart(a2aPart);
      expect(roundtrip, isA<Part>());
      final Part convertedBack = roundtrip! as Part;
      expect(convertedBack.functionCall?.name, 'my_tool');
      expect(convertedBack.functionCall?.id, 'call_42');
      expect(convertedBack.thoughtSignature, <int>[1, 2, 3, 4]);
    });

    test('file display name survives A2A roundtrip', () {
      final Part filePart = Part.fromFileData(
        fileUri: 'gs://bucket/path/report.csv',
        mimeType: 'text/csv',
        displayName: 'report.csv',
      );
      final Object? convertedFile = convertGenaiPartToA2aPart(filePart);
      expect(convertedFile, isA<A2aPart>());
      final A2aPart a2aFilePart = convertedFile! as A2aPart;
      expect(
        a2aFilePart.root.metadata[getAdkMetadataKey('display_name')],
        'report.csv',
      );

      final Object? fileRoundtrip = convertA2aPartToGenaiPart(a2aFilePart);
      expect(fileRoundtrip, isA<Part>());
      expect((fileRoundtrip! as Part).fileData?.displayName, 'report.csv');

      final Part inlinePart = Part.fromInlineData(
        mimeType: 'image/png',
        data: <int>[7, 8, 9],
        displayName: 'plot.png',
      );
      final Object? convertedInline = convertGenaiPartToA2aPart(inlinePart);
      expect(convertedInline, isA<A2aPart>());
      final A2aPart a2aInlinePart = convertedInline! as A2aPart;
      expect(
        a2aInlinePart.root.metadata[getAdkMetadataKey('display_name')],
        'plot.png',
      );

      final Object? inlineRoundtrip = convertA2aPartToGenaiPart(a2aInlinePart);
      expect(inlineRoundtrip, isA<Part>());
      expect((inlineRoundtrip! as Part).inlineData?.displayName, 'plot.png');
    });

    test('convertEventToA2aMessage works without invocation context', () {
      final Event event = Event(
        invocationId: 'inv_1',
        author: 'agent',
        content: Content.modelText('hello'),
      );

      final A2aMessage? message = convertEventToA2aMessage(event);
      expect(message, isNotNull);
      expect(message!.parts, isNotEmpty);
      expect(message.parts.first.textPart?.text, 'hello');
    });
  });

  group('a2a executor', () {
    test(
      'executor emits submitted, working, artifact, and final completed',
      () async {
        final Agent agent = Agent(name: 'root_agent', model: _FinalTextModel());
        final InMemoryRunner runner = InMemoryRunner(
          agent: agent,
          appName: 'app',
        );
        final A2aAgentExecutor executor = A2aAgentExecutor(runner: runner);

        final A2aRequestContext requestContext = A2aRequestContext(
          taskId: 'task_1',
          contextId: 'ctx_1',
          message: A2aMessage(
            messageId: 'msg_1',
            role: A2aRole.user,
            parts: <A2aPart>[A2aPart.text('hello')],
          ),
        );

        final InMemoryA2aEventQueue eventQueue = InMemoryA2aEventQueue();
        await executor.execute(requestContext, eventQueue);

        expect(eventQueue.events, isNotEmpty);
        expect(
          eventQueue.events.whereType<A2aTaskStatusUpdateEvent>().any(
            (A2aTaskStatusUpdateEvent event) =>
                event.status.state == A2aTaskState.submitted,
          ),
          isTrue,
        );
        expect(
          eventQueue.events.whereType<A2aTaskArtifactUpdateEvent>().isNotEmpty,
          isTrue,
        );
        expect(
          eventQueue.events.whereType<A2aTaskStatusUpdateEvent>().any(
            (A2aTaskStatusUpdateEvent event) =>
                event.finalEvent &&
                event.status.state == A2aTaskState.completed,
          ),
          isTrue,
        );
      },
    );

    test('executor applies before/after interceptors in order', () async {
      final Agent agent = Agent(name: 'root_agent', model: _FinalTextModel());
      final InMemoryRunner runner = InMemoryRunner(
        agent: agent,
        appName: 'app',
      );
      String? capturedAppName;
      int afterEventCalls = 0;
      final A2aAgentExecutor executor = A2aAgentExecutor(
        runner: runner,
        config: A2aAgentExecutorConfig(
          executeInterceptors: <A2aExecuteInterceptor>[
            A2aExecuteInterceptor(
              beforeAgent: (A2aRequestContext context) {
                context.contextId = 'ctx_intercepted';
                return context;
              },
              afterEvent:
                  (
                    A2aExecutorContext executorContext,
                    A2aEvent a2aEvent,
                    Event _,
                  ) {
                    if (a2aEvent is A2aTaskArtifactUpdateEvent) {
                      return null;
                    }
                    afterEventCalls += 1;
                    return a2aEvent;
                  },
              afterAgent:
                  (
                    A2aExecutorContext executorContext,
                    A2aTaskStatusUpdateEvent finalEvent,
                  ) {
                    capturedAppName = executorContext.appName;
                    finalEvent.status.message = A2aMessage(
                      messageId: 'm-final',
                      role: A2aRole.agent,
                      parts: <A2aPart>[A2aPart.text('intercepted final')],
                    );
                    return finalEvent;
                  },
            ),
          ],
        ),
      );

      final InMemoryA2aEventQueue eventQueue = InMemoryA2aEventQueue();
      await executor.execute(
        A2aRequestContext(
          taskId: 'task_2',
          contextId: 'ctx_2',
          message: A2aMessage(
            messageId: 'msg_2',
            role: A2aRole.user,
            parts: <A2aPart>[A2aPart.text('hello')],
          ),
        ),
        eventQueue,
      );

      expect(capturedAppName, 'app');
      final A2aTaskStatusUpdateEvent submitted = eventQueue.events
          .whereType<A2aTaskStatusUpdateEvent>()
          .firstWhere(
            (A2aTaskStatusUpdateEvent event) =>
                event.status.state == A2aTaskState.submitted,
          );
      expect(submitted.contextId, 'ctx_intercepted');
      expect(afterEventCalls, greaterThan(0));
      final A2aTaskStatusUpdateEvent finalEvent = eventQueue.events
          .whereType<A2aTaskStatusUpdateEvent>()
          .firstWhere((A2aTaskStatusUpdateEvent event) => event.finalEvent);
      expect(
        finalEvent.status.message?.parts.single.textPart?.text,
        'intercepted final',
      );
    });

    test(
      'resume without function response stays input_required and skips runner',
      () async {
        final Agent agent = Agent(name: 'root_agent', model: _FinalTextModel());
        final _RecordingRunner runner = _RecordingRunner(
          agent: agent,
          appName: 'app',
          eventFactory:
              ({
                required String userId,
                required String sessionId,
                String? invocationId,
                Content? newMessage,
                Map<String, Object?>? stateDelta,
                RunConfig? runConfig,
              }) => Stream<Event>.value(_modelEvent()),
        );
        final A2aAgentExecutor executor = A2aAgentExecutor(runner: runner);
        final InMemoryA2aEventQueue eventQueue = InMemoryA2aEventQueue();

        await executor.execute(
          A2aRequestContext(
            taskId: 'task_resume_input',
            contextId: 'ctx_resume_input',
            currentTask: _requiredTask(
              taskId: 'task_resume_input',
              contextId: 'ctx_resume_input',
              state: A2aTaskState.inputRequired,
            ),
            message: A2aMessage(
              messageId: 'msg_resume_input',
              role: A2aRole.user,
              parts: <A2aPart>[A2aPart.text('plain user text')],
            ),
          ),
          eventQueue,
        );

        expect(runner.runAsyncCalls, 0);
        final List<A2aTaskStatusUpdateEvent> updates = eventQueue.events
            .whereType<A2aTaskStatusUpdateEvent>()
            .toList();
        expect(updates, hasLength(1));
        final A2aTaskStatusUpdateEvent finalEvent = updates.single;
        expect(finalEvent.finalEvent, isTrue);
        expect(finalEvent.status.state, A2aTaskState.inputRequired);
        expect(
          finalEvent.status.message?.parts.single.textPart?.text,
          'It was not provided a function response for the function call.',
        );
        expect(finalEvent.metadata[getAdkMetadataKey('app_name')], 'app');
        expect(
          finalEvent.metadata[getAdkMetadataKey('user_id')],
          'A2A_USER_ctx_resume_input',
        );
        expect(
          finalEvent.metadata[getAdkMetadataKey('session_id')],
          'ctx_resume_input',
        );
        expect(
          finalEvent.metadata[getAdkMetadataKey('agent_executor_v2')],
          isTrue,
        );
      },
    );

    test(
      'resume without function response stays auth_required and skips runner',
      () async {
        final Agent agent = Agent(name: 'root_agent', model: _FinalTextModel());
        final _RecordingRunner runner = _RecordingRunner(
          agent: agent,
          appName: 'app',
          eventFactory:
              ({
                required String userId,
                required String sessionId,
                String? invocationId,
                Content? newMessage,
                Map<String, Object?>? stateDelta,
                RunConfig? runConfig,
              }) => Stream<Event>.value(_modelEvent()),
        );
        final A2aAgentExecutor executor = A2aAgentExecutor(runner: runner);
        final InMemoryA2aEventQueue eventQueue = InMemoryA2aEventQueue();

        await executor.execute(
          A2aRequestContext(
            taskId: 'task_resume_auth',
            contextId: 'ctx_resume_auth',
            currentTask: _requiredTask(
              taskId: 'task_resume_auth',
              contextId: 'ctx_resume_auth',
              state: A2aTaskState.authRequired,
            ),
            message: A2aMessage(
              messageId: 'msg_resume_auth',
              role: A2aRole.user,
              parts: <A2aPart>[A2aPart.text('plain user text')],
            ),
          ),
          eventQueue,
        );

        expect(runner.runAsyncCalls, 0);
        final A2aTaskStatusUpdateEvent finalEvent = eventQueue.events
            .whereType<A2aTaskStatusUpdateEvent>()
            .single;
        expect(finalEvent.finalEvent, isTrue);
        expect(finalEvent.status.state, A2aTaskState.authRequired);
        expect(
          finalEvent.status.message?.parts.single.textPart?.text,
          'It was not provided a function response for the function call.',
        );
      },
    );

    test('resume with function response proceeds to runner', () async {
      final Agent agent = Agent(name: 'root_agent', model: _FinalTextModel());
      final _RecordingRunner runner = _RecordingRunner(
        agent: agent,
        appName: 'app',
        eventFactory:
            ({
              required String userId,
              required String sessionId,
              String? invocationId,
              Content? newMessage,
              Map<String, Object?>? stateDelta,
              RunConfig? runConfig,
            }) => Stream<Event>.value(
              _modelEvent(invocationId: invocationId ?? 'resume_invocation'),
            ),
      );
      final A2aAgentExecutor executor = A2aAgentExecutor(runner: runner);
      final InMemoryA2aEventQueue eventQueue = InMemoryA2aEventQueue();

      await executor.execute(
        A2aRequestContext(
          taskId: 'task_resume_ok',
          contextId: 'ctx_resume_ok',
          currentTask: _requiredTask(
            taskId: 'task_resume_ok',
            contextId: 'ctx_resume_ok',
            state: A2aTaskState.inputRequired,
          ),
          message: A2aMessage(
            messageId: 'msg_resume_ok',
            role: A2aRole.user,
            parts: <A2aPart>[_functionResponsePart()],
          ),
        ),
        eventQueue,
      );

      expect(runner.runAsyncCalls, 1);
      expect(runner.lastUserId, 'A2A_USER_ctx_resume_ok');
      expect(runner.lastSessionId, 'ctx_resume_ok');
      final List<A2aTaskStatusUpdateEvent> updates = eventQueue.events
          .whereType<A2aTaskStatusUpdateEvent>()
          .toList();
      expect(
        updates.any(
          (A2aTaskStatusUpdateEvent event) =>
              !event.finalEvent && event.status.state == A2aTaskState.working,
        ),
        isTrue,
      );
      expect(
        updates.any(
          (A2aTaskStatusUpdateEvent event) =>
              event.finalEvent && event.status.state == A2aTaskState.completed,
        ),
        isTrue,
      );
    });

    test(
      'executor includes invocation metadata on working and final events',
      () async {
        final Agent agent = Agent(name: 'root_agent', model: _FinalTextModel());
        final _RecordingRunner runner = _RecordingRunner(
          agent: agent,
          appName: 'app',
          eventFactory:
              ({
                required String userId,
                required String sessionId,
                String? invocationId,
                Content? newMessage,
                Map<String, Object?>? stateDelta,
                RunConfig? runConfig,
              }) => Stream<Event>.value(
                _modelEvent(invocationId: invocationId ?? 'invocation_meta'),
              ),
        );
        final A2aAgentExecutor executor = A2aAgentExecutor(runner: runner);
        final InMemoryA2aEventQueue eventQueue = InMemoryA2aEventQueue();

        await executor.execute(
          A2aRequestContext(
            taskId: 'task_meta',
            contextId: 'ctx_meta',
            message: A2aMessage(
              messageId: 'msg_meta',
              role: A2aRole.user,
              parts: <A2aPart>[A2aPart.text('hello')],
            ),
          ),
          eventQueue,
        );

        final A2aTaskStatusUpdateEvent workingEvent = eventQueue.events
            .whereType<A2aTaskStatusUpdateEvent>()
            .firstWhere(
              (A2aTaskStatusUpdateEvent event) =>
                  !event.finalEvent &&
                  event.status.state == A2aTaskState.working,
            );
        final A2aTaskStatusUpdateEvent finalEvent = eventQueue.events
            .whereType<A2aTaskStatusUpdateEvent>()
            .firstWhere((A2aTaskStatusUpdateEvent event) => event.finalEvent);

        for (final A2aTaskStatusUpdateEvent event in <A2aTaskStatusUpdateEvent>[
          workingEvent,
          finalEvent,
        ]) {
          expect(event.metadata[getAdkMetadataKey('app_name')], 'app');
          expect(
            event.metadata[getAdkMetadataKey('user_id')],
            'A2A_USER_ctx_meta',
          );
          expect(event.metadata[getAdkMetadataKey('session_id')], 'ctx_meta');
          expect(
            event.metadata[getAdkMetadataKey('agent_executor_v2')],
            isTrue,
          );
        }
      },
    );

    test(
      'long-running function calls become a final input_required event',
      () async {
        final Agent agent = Agent(name: 'root_agent', model: _FinalTextModel());
        final _RecordingRunner runner = _RecordingRunner(
          agent: agent,
          appName: 'app',
          eventFactory:
              ({
                required String userId,
                required String sessionId,
                String? invocationId,
                Content? newMessage,
                Map<String, Object?>? stateDelta,
                RunConfig? runConfig,
              }) => Stream<Event>.value(
                _longRunningFunctionCallEvent(
                  invocationId: invocationId ?? 'invocation_long_running',
                ),
              ),
        );
        final A2aAgentExecutor executor = A2aAgentExecutor(runner: runner);
        final InMemoryA2aEventQueue eventQueue = InMemoryA2aEventQueue();

        await executor.execute(
          A2aRequestContext(
            taskId: 'task_long_running',
            contextId: 'ctx_long_running',
            message: A2aMessage(
              messageId: 'msg_long_running',
              role: A2aRole.user,
              parts: <A2aPart>[A2aPart.text('start')],
            ),
          ),
          eventQueue,
        );

        expect(
          eventQueue.events.whereType<A2aTaskArtifactUpdateEvent>(),
          isEmpty,
        );
        final List<A2aTaskStatusUpdateEvent> updates = eventQueue.events
            .whereType<A2aTaskStatusUpdateEvent>()
            .toList();
        expect(updates, hasLength(3));
        final A2aTaskStatusUpdateEvent finalEvent = updates.last;
        expect(finalEvent.finalEvent, isTrue);
        expect(finalEvent.status.state, A2aTaskState.inputRequired);
        expect(finalEvent.status.message?.parts, hasLength(1));
        final A2aDataPart? dataPart =
            finalEvent.status.message?.parts.single.dataPart;
        expect(dataPart, isNotNull);
        expect(dataPart?.data['name'], 'wait_for_input');
        expect(
          dataPart?.metadata[getAdkMetadataKey(a2aDataPartMetadataTypeKey)],
          a2aDataPartMetadataTypeFunctionCall,
        );
        expect(
          dataPart?.metadata[getAdkMetadataKey(
            a2aDataPartMetadataIsLongRunningKey,
          )],
          isTrue,
        );
      },
    );

    test(
      'credential long-running calls become auth_required final events',
      () async {
        final Agent agent = Agent(name: 'root_agent', model: _FinalTextModel());
        final _RecordingRunner runner = _RecordingRunner(
          agent: agent,
          appName: 'app',
          eventFactory:
              ({
                required String userId,
                required String sessionId,
                String? invocationId,
                Content? newMessage,
                Map<String, Object?>? stateDelta,
                RunConfig? runConfig,
              }) => Stream<Event>.value(
                _longRunningFunctionCallEvent(
                  invocationId: invocationId ?? 'invocation_auth_long_running',
                  toolName: requestEucFunctionCallName,
                ),
              ),
        );
        final A2aAgentExecutor executor = A2aAgentExecutor(runner: runner);
        final InMemoryA2aEventQueue eventQueue = InMemoryA2aEventQueue();

        await executor.execute(
          A2aRequestContext(
            taskId: 'task_auth_long_running',
            contextId: 'ctx_auth_long_running',
            message: A2aMessage(
              messageId: 'msg_auth_long_running',
              role: A2aRole.user,
              parts: <A2aPart>[A2aPart.text('start')],
            ),
          ),
          eventQueue,
        );

        final A2aTaskStatusUpdateEvent finalEvent = eventQueue.events
            .whereType<A2aTaskStatusUpdateEvent>()
            .last;
        expect(finalEvent.finalEvent, isTrue);
        expect(finalEvent.status.state, A2aTaskState.authRequired);
        expect(
          finalEvent.status.message?.parts.single.dataPart?.data['name'],
          requestEucFunctionCallName,
        );
      },
    );

    test(
      'long-running function responses are removed from intermediate events and preserved in the final event',
      () async {
        final Agent agent = Agent(name: 'root_agent', model: _FinalTextModel());
        final _RecordingRunner runner = _RecordingRunner(
          agent: agent,
          appName: 'app',
          eventFactory:
              ({
                required String userId,
                required String sessionId,
                String? invocationId,
                Content? newMessage,
                Map<String, Object?>? stateDelta,
                RunConfig? runConfig,
              }) => Stream<Event>.fromIterable(<Event>[
                _longRunningFunctionCallEvent(
                  invocationId: invocationId ?? 'invocation_lrf_response',
                ),
                _longRunningFunctionResponseEvent(
                  invocationId: invocationId ?? 'invocation_lrf_response',
                ),
              ]),
        );
        final A2aAgentExecutor executor = A2aAgentExecutor(runner: runner);
        final InMemoryA2aEventQueue eventQueue = InMemoryA2aEventQueue();

        await executor.execute(
          A2aRequestContext(
            taskId: 'task_lrf_response',
            contextId: 'ctx_lrf_response',
            message: A2aMessage(
              messageId: 'msg_lrf_response',
              role: A2aRole.user,
              parts: <A2aPart>[A2aPart.text('start')],
            ),
          ),
          eventQueue,
        );

        final List<A2aTaskStatusUpdateEvent> updates = eventQueue.events
            .whereType<A2aTaskStatusUpdateEvent>()
            .toList();
        expect(updates, hasLength(3));
        final A2aTaskStatusUpdateEvent workingEvent = updates.firstWhere(
          (A2aTaskStatusUpdateEvent event) =>
              !event.finalEvent && event.status.state == A2aTaskState.working,
        );
        expect(workingEvent.status.message, isNull);

        final A2aTaskStatusUpdateEvent finalEvent = updates.last;
        expect(finalEvent.finalEvent, isTrue);
        expect(finalEvent.status.state, A2aTaskState.inputRequired);
        expect(finalEvent.status.message?.parts, hasLength(2));
        expect(
          finalEvent
              .status
              .message
              ?.parts
              .first
              .dataPart
              ?.metadata[getAdkMetadataKey(a2aDataPartMetadataTypeKey)],
          a2aDataPartMetadataTypeFunctionCall,
        );
        expect(
          finalEvent
              .status
              .message
              ?.parts
              .last
              .dataPart
              ?.metadata[getAdkMetadataKey(a2aDataPartMetadataTypeKey)],
          a2aDataPartMetadataTypeFunctionResponse,
        );
      },
    );
  });
}
