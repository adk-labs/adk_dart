import 'dart:io';

import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

void main() {
  group('InMemorySessionService', () {
    test('appendEvent returns event when session does not exist', () async {
      final InMemorySessionService service = InMemorySessionService();
      final Session session = await service.createSession(
        appName: 'app',
        userId: 'u1',
      );
      await service.deleteSession(
        appName: 'app',
        userId: 'u1',
        sessionId: session.id,
      );

      final Event event = Event(
        invocationId: 'inv_missing',
        author: 'agent',
        content: Content.modelText('hello'),
      );

      final Event appended = await service.appendEvent(
        session: session,
        event: event,
      );
      expect(appended, same(event));
    });
  });

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

      final String dbPath = '${dir.path}/sessions.db';
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

      final RandomAccessFile sqliteFile = await File(dbPath).open();
      final List<int> header = await sqliteFile.read(16);
      await sqliteFile.close();
      expect(String.fromCharCodes(header.take(15)), 'SQLite format 3');

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

    test('enforces stale-session protection when appending events', () async {
      final Directory dir = await Directory.systemTemp.createTemp(
        'adk_sqlite_stale_check_',
      );
      addTearDown(() async {
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      });

      final String dbPath = '${dir.path}/stale_check.db';
      final SqliteSessionService service = SqliteSessionService(dbPath);
      final Session original = await service.createSession(
        appName: 'app',
        userId: 'u1',
      );
      final Session fresh = (await service.getSession(
        appName: 'app',
        userId: 'u1',
        sessionId: original.id,
      ))!;

      final Event first = Event(
        invocationId: 'inv_stale_1',
        author: 'agent',
        timestamp: original.lastUpdateTime + 10,
        actions: EventActions(stateDelta: <String, Object?>{'a': 1}),
      );
      await service.appendEvent(session: fresh, event: first);

      final Event staleAppend = Event(
        invocationId: 'inv_stale_2',
        author: 'agent',
        timestamp: first.timestamp + 1,
        actions: EventActions(stateDelta: <String, Object?>{'b': 2}),
      );
      expect(
        () => service.appendEvent(session: original, event: staleAppend),
        throwsA(isA<StateError>()),
      );

      final Session? loaded = await service.getSession(
        appName: 'app',
        userId: 'u1',
        sessionId: original.id,
      );
      expect(loaded, isNotNull);
      expect(loaded!.events, hasLength(1));
      expect(loaded.state['a'], 1);
      expect(loaded.state.containsKey('b'), isFalse);
    });

    test('applies GetSessionConfig filters for persisted events', () async {
      final Directory dir = await Directory.systemTemp.createTemp(
        'adk_sqlite_event_filters_',
      );
      addTearDown(() async {
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      });

      final SqliteSessionService service = SqliteSessionService(
        '${dir.path}/filters.db',
      );
      final Session session = await service.createSession(
        appName: 'app',
        userId: 'u1',
      );

      final double base = session.lastUpdateTime + 100;
      for (int i = 1; i <= 5; i += 1) {
        await service.appendEvent(
          session: session,
          event: Event(
            invocationId: 'inv_filter_$i',
            author: 'agent',
            timestamp: base + i,
            actions: EventActions(stateDelta: <String, Object?>{'k$i': 'v$i'}),
          ),
        );
      }

      final Session? recent = await service.getSession(
        appName: 'app',
        userId: 'u1',
        sessionId: session.id,
        config: GetSessionConfig(numRecentEvents: 3),
      );
      expect(recent, isNotNull);
      expect(recent!.events, hasLength(3));
      expect(
        recent.events.map((Event event) => event.timestamp).toList(),
        <double>[base + 3, base + 4, base + 5],
      );

      final Session? after = await service.getSession(
        appName: 'app',
        userId: 'u1',
        sessionId: session.id,
        config: GetSessionConfig(afterTimestamp: base + 4),
      );
      expect(after, isNotNull);
      expect(after!.events, hasLength(2));
      expect(
        after.events.map((Event event) => event.timestamp).toList(),
        <double>[base + 4, base + 5],
      );

      final Session? combined = await service.getSession(
        appName: 'app',
        userId: 'u1',
        sessionId: session.id,
        config: GetSessionConfig(afterTimestamp: base + 4, numRecentEvents: 3),
      );
      expect(combined, isNotNull);
      expect(combined!.events, hasLength(2));
      expect(
        combined.events.map((Event event) => event.timestamp).toList(),
        <double>[base + 4, base + 5],
      );
    });

    test('lists merged state and deletes persisted sessions', () async {
      final Directory dir = await Directory.systemTemp.createTemp(
        'adk_sqlite_list_delete_',
      );
      addTearDown(() async {
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      });

      final SqliteSessionService service = SqliteSessionService(
        '${dir.path}/list_delete.db',
      );
      final Session user1 = await service.createSession(
        appName: 'app',
        userId: 'u1',
        sessionId: 's1',
        state: <String, Object?>{
          '${State.appPrefix}locale': 'ko',
          '${State.userPrefix}plan': 'pro',
          'turn': 1,
        },
      );
      await service.createSession(
        appName: 'app',
        userId: 'u2',
        sessionId: 's2',
      );

      await service.appendEvent(
        session: user1,
        event: Event(
          invocationId: 'inv_list',
          author: 'agent',
          actions: EventActions(
            stateDelta: <String, Object?>{
              '${State.appPrefix}theme': 'dark',
              '${State.userPrefix}tier': 'gold',
              'score': 42,
            },
          ),
        ),
      );

      final ListSessionsResponse all = await service.listSessions(
        appName: 'app',
      );
      expect(all.sessions, hasLength(2));
      final Map<String, Session> byId = <String, Session>{
        for (final Session value in all.sessions) value.id: value,
      };
      expect(byId['s1'], isNotNull);
      expect(byId['s2'], isNotNull);
      expect(byId['s1']!.state['${State.appPrefix}locale'], 'ko');
      expect(byId['s1']!.state['${State.appPrefix}theme'], 'dark');
      expect(byId['s1']!.state['${State.userPrefix}plan'], 'pro');
      expect(byId['s1']!.state['${State.userPrefix}tier'], 'gold');
      expect(byId['s1']!.state['score'], 42);
      expect(byId['s2']!.state['${State.appPrefix}locale'], 'ko');
      expect(byId['s2']!.state['${State.appPrefix}theme'], 'dark');
      expect(byId['s2']!.state.containsKey('${State.userPrefix}plan'), isFalse);
      expect(byId['s2']!.state.containsKey('${State.userPrefix}tier'), isFalse);

      await service.deleteSession(
        appName: 'app',
        userId: 'u1',
        sessionId: 's1',
      );

      final Session? deleted = await service.getSession(
        appName: 'app',
        userId: 'u1',
        sessionId: 's1',
      );
      expect(deleted, isNull);

      final Session? remaining = await service.getSession(
        appName: 'app',
        userId: 'u2',
        sessionId: 's2',
      );
      expect(remaining, isNotNull);
      expect(remaining!.id, 's2');
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

    test(
      'treats sqlite:/// and sqlite+aiosqlite:/// paths as relative by SQLAlchemy convention',
      () async {
        final Directory cwd = await Directory.systemTemp.createTemp(
          'adk_sqlite_triple_slash_relative_',
        );
        final Directory originalCwd = Directory.current;
        Directory.current = cwd;
        addTearDown(() async {
          Directory.current = originalCwd;
          if (await cwd.exists()) {
            await cwd.delete(recursive: true);
          }
        });

        final String absoluteLikeA = '${cwd.path}/absolute_like_a.db'
            .replaceAll('\\', '/');
        final String absoluteLikeB = '${cwd.path}/absolute_like_b.db'
            .replaceAll('\\', '/');

        final String urlA = absoluteLikeA.startsWith('/')
            ? 'sqlite:///${absoluteLikeA.substring(1)}'
            : 'sqlite:///$absoluteLikeA';
        final String urlB = absoluteLikeB.startsWith('/')
            ? 'sqlite+aiosqlite:///${absoluteLikeB.substring(1)}'
            : 'sqlite+aiosqlite:///$absoluteLikeB';

        await SqliteSessionService(
          urlA,
        ).createSession(appName: 'app', userId: 'u1');
        await SqliteSessionService(
          urlB,
        ).createSession(appName: 'app', userId: 'u1');

        expect(File(absoluteLikeA).existsSync(), isFalse);
        expect(File(absoluteLikeB).existsSync(), isFalse);

        expect(
          File('${cwd.path}/${absoluteLikeA.substring(1)}').existsSync(),
          isTrue,
        );
        expect(
          File('${cwd.path}/${absoluteLikeB.substring(1)}').existsSync(),
          isTrue,
        );
      },
    );

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

    test(
      'preserves sqlite URLs with additional query parameters without sanitizing mode',
      () async {
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

      final SqliteSessionService invalidMode = SqliteSessionService(
        'sqlite:///./sessions2.db?mode=invalid',
      );
      await expectLater(
        () => invalidMode.createSession(appName: 'app', userId: 'u1'),
        throwsA(isA<FileSystemException>()),
      );
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

    test('fails fast when opening legacy schema without event_data column', () async {
      final Directory dir = await Directory.systemTemp.createTemp(
        'adk_sqlite_legacy_schema_',
      );
      addTearDown(() async {
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      });

      final String dbPath = '${dir.path}/legacy.db';
      final ProcessResult init = await Process.run('sqlite3', <String>[
        dbPath,
        '''
CREATE TABLE events (
  id TEXT NOT NULL,
  app_name TEXT NOT NULL,
  user_id TEXT NOT NULL,
  session_id TEXT NOT NULL,
  invocation_id TEXT NOT NULL,
  timestamp REAL NOT NULL,
  actions TEXT NOT NULL
);
''',
      ]);
      if (init.exitCode != 0) {
        final String stderr = '${init.stderr}'.toLowerCase();
        if (stderr.contains('not found')) {
          markTestSkipped('sqlite3 CLI is not available in test environment.');
          return;
        }
        fail('Failed to initialize legacy sqlite schema: ${init.stderr}');
      }

      expect(
        () => SqliteSessionService(dbPath),
        throwsA(
          isA<StateError>().having(
            (StateError error) => error.message.toString(),
            'message',
            contains('old schema'),
          ),
        ),
      );
    });
  });

  group('DatabaseSessionService', () {
    tearDown(() {
      DatabaseSessionService.resetCustomResolversAndFactories();
    });

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

    test('uses registered custom factory for non-sqlite schemes', () async {
      int factoryCalls = 0;
      String? capturedDbUrl;
      final InMemorySessionService delegate = InMemorySessionService();
      DatabaseSessionService.registerCustomFactory(
        scheme: 'postgresql',
        factory: (String dbUrl) {
          factoryCalls += 1;
          capturedDbUrl = dbUrl;
          return delegate;
        },
      );

      final DatabaseSessionService service = DatabaseSessionService(
        '  postgresql://localhost/mydb  ',
      );
      expect(factoryCalls, 1);
      expect(capturedDbUrl, 'postgresql://localhost/mydb');

      final Session created = await service.createSession(
        appName: 'app',
        userId: 'u1',
      );
      final Session? loaded = await delegate.getSession(
        appName: 'app',
        userId: 'u1',
        sessionId: created.id,
      );
      expect(loaded, isNotNull);
      expect(loaded!.id, created.id);
    });

    test('uses registered custom resolver for unmatched urls', () async {
      int resolverCalls = 0;
      final InMemorySessionService delegate = InMemorySessionService();
      DatabaseSessionService.registerCustomResolver((String dbUrl) {
        resolverCalls += 1;
        if (dbUrl.startsWith('customdb://')) {
          return delegate;
        }
        return null;
      });

      final DatabaseSessionService service = DatabaseSessionService(
        ' customdb://region-a/tenant-1 ',
      );
      expect(resolverCalls, 1);

      final Session created = await service.createSession(
        appName: 'app',
        userId: 'u2',
      );
      final Session? loaded = await delegate.getSession(
        appName: 'app',
        userId: 'u2',
        sessionId: created.id,
      );
      expect(loaded, isNotNull);
      expect(loaded!.id, created.id);
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

    test(
      'keeps sqlite dispatch precedence over custom registrations',
      () async {
        int customFactoryCalls = 0;
        int customResolverCalls = 0;
        DatabaseSessionService.registerCustomFactory(
          scheme: 'sqlite',
          factory: (String dbUrl) {
            customFactoryCalls += 1;
            return InMemorySessionService();
          },
        );
        DatabaseSessionService.registerCustomResolver((String dbUrl) {
          customResolverCalls += 1;
          return InMemorySessionService();
        });

        final Directory dir = await Directory.systemTemp.createTemp(
          'adk_db_service_sqlite_precedence_',
        );
        addTearDown(() async {
          if (await dir.exists()) {
            await dir.delete(recursive: true);
          }
        });

        final String dbUrl = 'sqlite:///${dir.path}/sqlite_precedence.json';
        final DatabaseSessionService service = DatabaseSessionService(dbUrl);
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
        expect(File('${dir.path}/sqlite_precedence.json').existsSync(), isTrue);
        expect(customFactoryCalls, 0);
        expect(customResolverCalls, 0);
      },
    );

    test('reloads stale session and appends event successfully', () async {
      final Directory dir = await Directory.systemTemp.createTemp(
        'adk_db_service_stale_reload_',
      );
      addTearDown(() async {
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      });

      final DatabaseSessionService service = DatabaseSessionService(
        'sqlite:///${dir.path}/stale_reload.db',
      );
      final Session original = await service.createSession(
        appName: 'app',
        userId: 'u1',
      );
      final Session fresh = (await service.getSession(
        appName: 'app',
        userId: 'u1',
        sessionId: original.id,
      ))!;

      await service.appendEvent(
        session: fresh,
        event: Event(
          invocationId: 'inv_db_stale_1',
          author: 'agent',
          timestamp: original.lastUpdateTime + 10,
          actions: EventActions(stateDelta: <String, Object?>{'k1': 'v1'}),
        ),
      );

      await service.appendEvent(
        session: original,
        event: Event(
          invocationId: 'inv_db_stale_2',
          author: 'agent',
          timestamp: original.lastUpdateTime + 20,
          actions: EventActions(stateDelta: <String, Object?>{'k2': 'v2'}),
        ),
      );

      final Session? reloaded = await service.getSession(
        appName: 'app',
        userId: 'u1',
        sessionId: original.id,
      );
      expect(reloaded, isNotNull);
      expect(reloaded!.events, hasLength(2));
      expect(reloaded.state['k1'], 'v1');
      expect(reloaded.state['k2'], 'v2');
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
