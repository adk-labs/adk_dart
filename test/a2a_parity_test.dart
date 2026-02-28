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

void main() {
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
  });
}
