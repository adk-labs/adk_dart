import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

void main() {
  group('GetSessionConfig', () {
    test('rejects negative numRecentEvents', () {
      expect(
        () => GetSessionConfig(numRecentEvents: -1),
        throwsArgumentError,
      );
      final GetSessionConfig config = GetSessionConfig();
      expect(
        () => config.numRecentEvents = -5,
        throwsArgumentError,
      );
    });
  });

  group('InMemorySessionService', () {
    test('create and get session', () async {
      final InMemorySessionService service = InMemorySessionService();

      final Session created = await service.createSession(
        appName: 'my_app',
        userId: 'user_1',
        state: <String, Object?>{'foo': 'bar'},
      );

      final Session? loaded = await service.getSession(
        appName: 'my_app',
        userId: 'user_1',
        sessionId: created.id,
      );

      expect(loaded, isNotNull);
      expect(loaded!.state['foo'], 'bar');
    });

    test('merges app/user scoped state prefixes', () async {
      final InMemorySessionService service = InMemorySessionService();

      final Session created = await service.createSession(
        appName: 'my_app',
        userId: 'user_1',
        state: <String, Object?>{
          'app:region': 'us',
          'user:tier': 'pro',
          'session_key': 'value',
        },
      );

      final Session? loaded = await service.getSession(
        appName: 'my_app',
        userId: 'user_1',
        sessionId: created.id,
      );

      expect(loaded, isNotNull);
      expect(loaded!.state['session_key'], 'value');
      expect(loaded.state['app:region'], 'us');
      expect(loaded.state['user:tier'], 'pro');
    });

    test('getUserState returns raw user state copy', () async {
      final InMemorySessionService service = InMemorySessionService();

      final Session session = await service.createSession(
        appName: 'my_app',
        userId: 'user_1',
        state: <String, Object?>{
          '${State.appPrefix}region': 'us',
          '${State.userPrefix}tier': 'pro',
          'session_key': 'value',
        },
      );

      final Map<String, Object?> initial = await service.getUserState(
        appName: 'my_app',
        userId: 'user_1',
      );
      expect(initial, <String, Object?>{'tier': 'pro'});

      initial['tier'] = 'mutated';
      initial['local'] = 'only';

      await service.appendEvent(
        session: session,
        event: Event(
          invocationId: 'inv_user_state',
          author: 'agent',
          actions: EventActions(
            stateDelta: <String, Object?>{
              '${State.userPrefix}plan': 'paid',
              '${State.appPrefix}theme': 'dark',
              'turn': 2,
            },
          ),
        ),
      );

      final Map<String, Object?> updated = await service.getUserState(
        appName: 'my_app',
        userId: 'user_1',
      );
      expect(updated, <String, Object?>{'tier': 'pro', 'plan': 'paid'});
      expect(updated.containsKey('local'), isFalse);
      expect(updated.containsKey('${State.appPrefix}theme'), isFalse);
      expect(updated.containsKey('turn'), isFalse);
    });

    test(
      'appendEvent keeps temp keys visible during invocation without persisting them',
      () async {
        final InMemorySessionService service = InMemorySessionService();
        final Session session = await service.createSession(
          appName: 'my_app',
          userId: 'user_1',
        );

        final Event event = Event(
          invocationId: 'inv_1',
          author: 'agent',
          actions: EventActions(
            stateDelta: <String, Object?>{'x': 1, 'temp:transient': 'ignore'},
          ),
        );

        await service.appendEvent(session: session, event: event);

        expect(session.state['x'], 1);
        expect(session.state['temp:transient'], 'ignore');
        expect(session.events, hasLength(1));
        expect(
          session.events.single.actions.stateDelta.containsKey(
            'temp:transient',
          ),
          isFalse,
        );

        final Session? reloaded = await service.getSession(
          appName: 'my_app',
          userId: 'user_1',
          sessionId: session.id,
        );
        expect(reloaded, isNotNull);
        expect(reloaded!.state['x'], 1);
        expect(reloaded.state.containsKey('temp:transient'), isFalse);
      },
    );

    test('getSession returns no events when numRecentEvents is zero', () async {
      final InMemorySessionService service = InMemorySessionService();
      final Session session = await service.createSession(
        appName: 'my_app',
        userId: 'user_1',
      );

      await service.appendEvent(
        session: session,
        event: Event(invocationId: 'inv_1', author: 'agent'),
      );
      await service.appendEvent(
        session: session,
        event: Event(invocationId: 'inv_2', author: 'agent'),
      );

      final Session? loaded = await service.getSession(
        appName: 'my_app',
        userId: 'user_1',
        sessionId: session.id,
        config: GetSessionConfig(numRecentEvents: 0),
      );

      expect(loaded, isNotNull);
      expect(loaded!.events, isEmpty);
    });

    test('flush is a no-op for non-buffering services', () async {
      final InMemorySessionService service = InMemorySessionService();

      await service.flush();
    });
  });
}
