import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

void main() {
  group('PersistBarrier parity', () {
    test(
      'awaitPersisted is no-op when runner did not enable barrier',
      () async {
        final InvocationContext context = await _context();
        final Event event = Event(
          id: Event.newId(),
          invocationId: 'inv',
          author: 'agent',
        );

        await PersistBarrier.awaitPersisted(context, <Event>[
          event,
        ]).timeout(const Duration(milliseconds: 50));

        expect(PersistBarrier.pendingCount(context), 0);
      },
    );

    test('awaitPersisted resolves when markPersisted happens later', () async {
      final InvocationContext context = await _context();
      PersistBarrier.enable(context);
      final Event event = Event(
        id: Event.newId(),
        invocationId: 'inv',
        author: 'agent',
      );

      bool completed = false;
      final Future<void> waiter =
          PersistBarrier.awaitPersisted(context, <Event>[event]).then((_) {
            completed = true;
          });

      await Future<void>.delayed(Duration.zero);
      expect(completed, isFalse);
      expect(PersistBarrier.pendingCount(context), 1);

      PersistBarrier.markPersisted(context, event.id);
      await waiter;

      expect(completed, isTrue);
      expect(PersistBarrier.pendingCount(context), 0);
    });

    test('awaitPersisted resolves when markPersisted happened first', () async {
      final InvocationContext context = await _context();
      PersistBarrier.enable(context);
      final Event event = Event(
        id: Event.newId(),
        invocationId: 'inv',
        author: 'agent',
      );

      PersistBarrier.markPersisted(context, event.id);

      await PersistBarrier.awaitPersisted(context, <Event>[
        event,
      ]).timeout(const Duration(milliseconds: 50));
      expect(PersistBarrier.pendingCount(context), 0);
    });

    test('awaitPersisted forwards persistence failures', () async {
      final InvocationContext context = await _context();
      PersistBarrier.enable(context);
      final Event event = Event(
        id: Event.newId(),
        invocationId: 'inv',
        author: 'agent',
      );

      final Future<void> waiter = PersistBarrier.awaitPersisted(
        context,
        <Event>[event],
      );
      final StateError error = StateError('append failed');

      PersistBarrier.markFailed(context, event.id, error);

      await expectLater(waiter, throwsA(same(error)));
      expect(PersistBarrier.pendingCount(context), 0);
    });

    test('context copies share invocation barrier state', () async {
      final InvocationContext context = await _context();
      final InvocationContext copy = context.copyWith();
      PersistBarrier.enable(context);
      final Event event = Event(
        id: Event.newId(),
        invocationId: 'inv',
        author: 'agent',
      );

      final Future<void> waiter = PersistBarrier.awaitPersisted(copy, <Event>[
        event,
      ]);
      PersistBarrier.markPersisted(context, event.id);

      await waiter.timeout(const Duration(milliseconds: 50));
      expect(PersistBarrier.pendingCount(copy), 0);
    });
  });
}

Future<InvocationContext> _context() async {
  final InMemorySessionService sessionService = InMemorySessionService();
  final Session session = await sessionService.createSession(
    appName: 'app',
    userId: 'user',
    sessionId: 'session',
  );
  return InvocationContext(
    sessionService: sessionService,
    invocationId: 'inv',
    agent: LlmAgent(name: 'agent'),
    session: session,
  );
}
