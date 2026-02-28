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

    test('accepts sqlite URL relative and absolute path forms', () async {
      final Directory dir = await Directory.systemTemp.createTemp(
        'adk_sqlite_url_paths_',
      );
      final Directory originalCwd = Directory.current;
      Directory.current = dir;
      addTearDown(() async {
        Directory.current = originalCwd;
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      });

      final SqliteSessionService relativeAio = SqliteSessionService(
        'sqlite+aiosqlite:///./sessions.db',
      );
      await relativeAio.createSession(appName: 'app', userId: 'u1');
      expect(File('${dir.path}/sessions.db').existsSync(), isTrue);

      final SqliteSessionService relativeSqlite = SqliteSessionService(
        'sqlite:///./sessions2.db',
      );
      await relativeSqlite.createSession(appName: 'app', userId: 'u1');
      expect(File('${dir.path}/sessions2.db').existsSync(), isTrue);

      final String absolutePath = '${dir.path}/absolute.db';
      final String normalizedAbsolutePath = absolutePath.replaceAll('\\', '/');
      final String absoluteUrl = normalizedAbsolutePath.startsWith('/')
          ? 'sqlite:////${normalizedAbsolutePath.substring(1)}'
          : 'sqlite:///$normalizedAbsolutePath';
      final SqliteSessionService absolute = SqliteSessionService(absoluteUrl);
      await absolute.createSession(appName: 'app', userId: 'u1');
      expect(File(absolutePath).existsSync(), isTrue);
    });

    test('supports mode=ro query and rejects writes in read-only mode', () async {
      final Directory dir = await Directory.systemTemp.createTemp(
        'adk_sqlite_readonly_',
      );
      addTearDown(() async {
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      });

      final String dbPath = '${dir.path}/readonly.db';
      await File(dbPath).create(recursive: true);
      final String normalized = dbPath.replaceAll('\\', '/');
      final String sqliteUrl = normalized.startsWith('/')
          ? 'sqlite+aiosqlite:////${normalized.substring(1)}?mode=ro&cache=shared'
          : 'sqlite+aiosqlite:///$normalized?mode=ro&cache=shared';

      final SqliteSessionService service = SqliteSessionService(sqliteUrl);
      expect(
        () => service.createSession(appName: 'app', userId: 'u1'),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('accepts sqlite URLs with additional query parameters', () async {
      final Directory dir = await Directory.systemTemp.createTemp(
        'adk_sqlite_query_options_',
      );
      final Directory originalCwd = Directory.current;
      Directory.current = dir;
      addTearDown(() async {
        Directory.current = originalCwd;
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      });

      final SqliteSessionService cacheShared = SqliteSessionService(
        'sqlite:///./sessions.db?cache=shared',
      );
      await cacheShared.createSession(appName: 'app', userId: 'u1');
      expect(File('${dir.path}/sessions.db').existsSync(), isTrue);

      final SqliteSessionService unknownMode = SqliteSessionService(
        'sqlite:///./sessions2.db?mode=invalid',
      );
      await unknownMode.createSession(appName: 'app', userId: 'u1');
      expect(File('${dir.path}/sessions2.db').existsSync(), isTrue);
    });

    test(
      'supports sqlite memory URLs without creating placeholder files',
      () async {
        final Directory dir = await Directory.systemTemp.createTemp(
          'adk_sqlite_memory_url_',
        );
        final Directory originalCwd = Directory.current;
        Directory.current = dir;
        addTearDown(() async {
          Directory.current = originalCwd;
          if (await dir.exists()) {
            await dir.delete(recursive: true);
          }
        });

        final SqliteSessionService service = SqliteSessionService(
          'sqlite+aiosqlite:///:memory:',
        );
        final Session created = await service.createSession(
          appName: 'app',
          userId: 'u1',
        );
        final Session? loaded = await service.getSession(
          appName: 'app',
          userId: 'u1',
          sessionId: created.id,
        );
        expect(loaded, isNotNull);

        final SqliteSessionService reopened = SqliteSessionService(
          'sqlite+aiosqlite:///:memory:',
        );
        final Session? reopenedLoaded = await reopened.getSession(
          appName: 'app',
          userId: 'u1',
          sessionId: created.id,
        );
        expect(reopenedLoaded, isNull);

        final SqliteSessionService shorthandMemory = SqliteSessionService(
          'sqlite://:memory:',
        );
        final Session shorthandCreated = await shorthandMemory.createSession(
          appName: 'app',
          userId: 'u2',
        );
        final Session? shorthandLoaded = await shorthandMemory.getSession(
          appName: 'app',
          userId: 'u2',
          sessionId: shorthandCreated.id,
        );
        expect(shorthandLoaded, isNotNull);
        expect(File('${dir.path}/:memory:').existsSync(), isFalse);
      },
    );

    test(
      'accepts sqlite URL paths with placeholder-style percent text',
      () async {
        final Directory dir = await Directory.systemTemp.createTemp(
          'adk_sqlite_placeholder_path_',
        );
        final Directory originalCwd = Directory.current;
        Directory.current = dir;
        addTearDown(() async {
          Directory.current = originalCwd;
          if (await dir.exists()) {
            await dir.delete(recursive: true);
          }
        });

        final SqliteSessionService service = SqliteSessionService(
          'sqlite:///%(here)s/sessions.db',
        );
        await service.createSession(appName: 'app', userId: 'u1');
        expect(File('${dir.path}/%(here)s/sessions.db').existsSync(), isTrue);
      },
    );

    test('rejects sqlite URLs without a file path', () {
      expect(() => SqliteSessionService('sqlite://'), throwsArgumentError);
      expect(() => SqliteSessionService('sqlite:///'), throwsArgumentError);
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

    test('fails fast for unsupported database URLs', () {
      expect(
        () => DatabaseSessionService('postgresql://localhost/mydb'),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('trims surrounding whitespace before url dispatch', () async {
      final Directory dir = await Directory.systemTemp.createTemp(
        'adk_db_service_trim_',
      );
      addTearDown(() async {
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      });

      final String dbUrl = '  sqlite:///${dir.path}/trimmed.json  ';
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
    });

    test('uses in-memory backing for sqlite memory URLs', () async {
      final Directory dir = await Directory.systemTemp.createTemp(
        'adk_db_service_memory_',
      );
      final Directory originalCwd = Directory.current;
      Directory.current = dir;
      addTearDown(() async {
        Directory.current = originalCwd;
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      });

      final DatabaseSessionService service = DatabaseSessionService(
        'sqlite+aiosqlite:///:memory:',
      );
      final Session created = await service.createSession(
        appName: 'app',
        userId: 'u1',
      );
      final Session? loaded = await service.getSession(
        appName: 'app',
        userId: 'u1',
        sessionId: created.id,
      );
      expect(loaded, isNotNull);

      final DatabaseSessionService reopened = DatabaseSessionService(
        'sqlite+aiosqlite:///:memory:',
      );
      final Session? reopenedLoaded = await reopened.getSession(
        appName: 'app',
        userId: 'u1',
        sessionId: created.id,
      );
      expect(reopenedLoaded, isNull);
      expect(File('${dir.path}/:memory:').existsSync(), isFalse);
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
