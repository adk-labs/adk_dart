import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

class _NoopModel extends BaseLlm {
  _NoopModel() : super(model: 'noop');

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    yield LlmResponse(content: Content.modelText('ok'));
  }
}

Future<List<Event>> _collect(Stream<Event> stream) => stream.toList();

void main() {
  test(
    'compaction request processor appends token-threshold compaction event',
    () async {
      final Agent agent = Agent(
        name: 'root_agent',
        model: _NoopModel(),
        disallowTransferToParent: true,
        disallowTransferToPeers: true,
      );
      final InMemorySessionService sessionService = InMemorySessionService();
      final Session session = await sessionService.createSession(
        appName: 'app',
        userId: 'u1',
        sessionId: 's_compaction',
      );

      session.events.addAll(<Event>[
        Event(
          invocationId: 'inv_1',
          author: 'user',
          content: Content.userText('First message'),
        ),
        Event(
          invocationId: 'inv_1',
          author: 'root_agent',
          content: Content.modelText('First response'),
          usageMetadata: <String, Object?>{'prompt_token_count': 100},
        ),
        Event(
          invocationId: 'inv_2',
          author: 'user',
          content: Content.userText('Second message'),
        ),
      ]);

      final InvocationContext context = InvocationContext(
        sessionService: sessionService,
        invocationId: 'inv_3',
        agent: agent,
        session: session,
        eventsCompactionConfig: EventsCompactionConfig(
          tokenThreshold: 10,
          eventRetentionSize: 1,
          summarizer: (List<Event> events) {
            return Content.modelText('summary ${events.length}');
          },
        ),
      );

      await CompactionRequestProcessor()
          .runAsync(context, LlmRequest())
          .toList();

      final Event compactionEvent = session.events.last;
      expect(compactionEvent.actions.compaction, isNotNull);
      expect(
        compactionEvent.actions.compaction!.compactedContent.parts.first.text,
        contains('summary'),
      );
      expect(context.tokenCompactionChecked, isTrue);
    },
  );

  test('runner performs sliding-window compaction after invocation', () async {
    final Agent agent = Agent(name: 'root_agent', model: _NoopModel());
    final App app = App(
      name: 'compaction_app',
      rootAgent: agent,
      eventsCompactionConfig: EventsCompactionConfig(
        compactionInterval: 2,
        overlapSize: 0,
        summarizer: (List<Event> events) =>
            Content.modelText('sliding summary ${events.length}'),
      ),
    );
    final InMemoryRunner runner = InMemoryRunner(app: app);
    final Session session = await runner.sessionService.createSession(
      appName: runner.appName,
      userId: 'user_1',
      sessionId: 's_runner_compaction',
    );

    await _collect(
      runner.runAsync(
        userId: 'user_1',
        sessionId: session.id,
        newMessage: Content.userText('hello 1'),
      ),
    );
    await _collect(
      runner.runAsync(
        userId: 'user_1',
        sessionId: session.id,
        newMessage: Content.userText('hello 2'),
      ),
    );

    final Session? updated = await runner.sessionService.getSession(
      appName: runner.appName,
      userId: 'user_1',
      sessionId: session.id,
    );
    expect(updated, isNotNull);
    expect(
      updated!.events.any((Event event) => event.actions.compaction != null),
      isTrue,
    );
  });

  test(
    'runCompactionForSlidingWindow skips sliding when token compaction runs',
    () async {
      final Agent agent = Agent(name: 'root_agent', model: _NoopModel());
      final App app = App(
        name: 'token_first_compaction_app',
        rootAgent: agent,
        eventsCompactionConfig: EventsCompactionConfig(
          tokenThreshold: 10,
          eventRetentionSize: 2,
          compactionInterval: 2,
          overlapSize: 0,
          summarizer: (List<Event> events) =>
              Content.modelText('summary ${events.length}'),
        ),
      );
      final InMemorySessionService sessionService = InMemorySessionService();
      final Session session = await sessionService.createSession(
        appName: app.name,
        userId: 'u_token_first',
        sessionId: 's_token_first',
      );

      session.events.addAll(<Event>[
        Event(
          invocationId: 'inv_1',
          author: 'user',
          timestamp: 1.0,
          content: Content.userText('message 1'),
        ),
        Event(
          invocationId: 'inv_1',
          author: 'root_agent',
          timestamp: 2.0,
          content: Content.modelText('response 1'),
        ),
        Event(
          invocationId: 'inv_2',
          author: 'user',
          timestamp: 3.0,
          content: Content.userText('message 2'),
        ),
        Event(
          invocationId: 'inv_2',
          author: 'root_agent',
          timestamp: 4.0,
          content: Content.modelText('response 2'),
        ),
        Event(
          invocationId: 'inv_3',
          author: 'user',
          timestamp: 5.0,
          content: Content.userText('message 3'),
        ),
        Event(
          invocationId: 'inv_4',
          author: 'user',
          timestamp: 6.0,
          content: Content.userText('message 4'),
          usageMetadata: <String, Object?>{'prompt_token_count': 100},
        ),
      ]);

      final bool compacted = await runCompactionForSlidingWindow(
        app: app,
        session: session,
        sessionService: sessionService,
        skipTokenCompaction: false,
      );

      final List<Event> compactionEvents = session.events
          .where((Event event) => event.actions.compaction != null)
          .toList(growable: false);
      expect(compacted, isTrue);
      expect(compactionEvents, hasLength(1));
      expect(compactionEvents.single.actions.compaction!.startTimestamp, 1.0);
      expect(compactionEvents.single.actions.compaction!.endTimestamp, 4.0);
      expect(
        compactionEvents
            .single
            .actions
            .compaction!
            .compactedContent
            .parts
            .first
            .text,
        'summary 4',
      );
    },
  );
}
