import 'dart:io';

import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

void main() {
  group('SqliteSessionService', () {
    test('persists sessions and events to disk', () async {
      final Directory dir = await Directory.systemTemp.createTemp(
        'adk_sqlite_service_',
      );
      addTearDown(() async {
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      });

      final String dbPath = '${dir.path}/sessions.json';
      final SqliteSessionService service = SqliteSessionService(dbPath);
      final Session created = await service.createSession(
        appName: 'app',
        userId: 'u1',
        state: <String, Object?>{
          '${State.appPrefix}locale': 'ko',
          '${State.userPrefix}plan': 'pro',
          'turn': 1,
        },
      );
      expect(created.state['${State.appPrefix}locale'], 'ko');
      expect(created.state['${State.userPrefix}plan'], 'pro');
      expect(created.state['turn'], 1);

      final Event event = Event(
        invocationId: 'inv1',
        author: 'agent',
        content: Content.modelText('hello'),
        actions: EventActions(
          stateDelta: <String, Object?>{
            'score': 99,
            '${State.userPrefix}tier': 'gold',
            '${State.tempPrefix}scratch': 'tmp',
          },
        ),
      );
      await service.appendEvent(session: created, event: event);

      final SqliteSessionService reopened = SqliteSessionService(dbPath);
      final Session? loaded = await reopened.getSession(
        appName: 'app',
        userId: 'u1',
        sessionId: created.id,
      );
      expect(loaded, isNotNull);
      expect(loaded!.events, hasLength(1));
      expect(loaded.state['score'], 99);
      expect(loaded.state['${State.userPrefix}tier'], 'gold');
      expect(loaded.state.containsKey('${State.tempPrefix}scratch'), isFalse);
      expect(loaded.events.first.content?.parts.first.text, 'hello');
    });
  });

  group('DatabaseSessionService', () {
    test('uses sqlite backend for sqlite URLs', () async {
      final Directory dir = await Directory.systemTemp.createTemp(
        'adk_db_service_',
      );
      addTearDown(() async {
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      });
      final String dbUrl = 'sqlite:///${dir.path}/db.json';
      final DatabaseSessionService service = DatabaseSessionService(dbUrl);
      final Session session = await service.createSession(
        appName: 'app',
        userId: 'u1',
      );
      final Session? loaded = await service.getSession(
        appName: 'app',
        userId: 'u1',
        sessionId: session.id,
      );
      expect(loaded, isNotNull);
      expect(loaded!.id, session.id);
    });
  });

  group('VertexAiSessionService', () {
    test('validates app name and proxies base session operations', () async {
      final VertexAiSessionService service = VertexAiSessionService(
        project: 'p',
        location: 'us-central1',
      );
      final Session session = await service.createSession(
        appName: 'projects/p/locations/us-central1/reasoningEngines/123',
        userId: 'u1',
        state: <String, Object?>{'x': 1},
      );
      final Session? loaded = await service.getSession(
        appName: 'projects/p/locations/us-central1/reasoningEngines/123',
        userId: 'u1',
        sessionId: session.id,
      );
      expect(loaded, isNotNull);
      expect(loaded!.state['x'], 1);
    });

    test('rejects unsupported app names', () {
      final VertexAiSessionService service = VertexAiSessionService();
      expect(
        () => service.listSessions(appName: 'invalid-name'),
        throwsArgumentError,
      );
    });
  });
}
