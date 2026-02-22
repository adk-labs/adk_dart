import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

void main() {
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

    test('appendEvent updates state and drops temp keys', () async {
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
      expect(session.state.containsKey('temp:transient'), isFalse);
      expect(session.events, hasLength(1));
    });
  });
}
