import 'dart:convert';
import 'dart:io';

import 'package:adk_dart/adk_dart.dart';
import 'package:adk_dart/src/sessions/migration/sqlite_db.dart';
import 'package:test/test.dart';

const String _legacyAppStatesSchema = '''
CREATE TABLE IF NOT EXISTS app_states (
  app_name TEXT PRIMARY KEY,
  state TEXT NOT NULL,
  update_time REAL NOT NULL
);
''';

const String _legacyUserStatesSchema = '''
CREATE TABLE IF NOT EXISTS user_states (
  app_name TEXT NOT NULL,
  user_id TEXT NOT NULL,
  state TEXT NOT NULL,
  update_time REAL NOT NULL,
  PRIMARY KEY (app_name, user_id)
);
''';

const String _legacySessionsSchema = '''
CREATE TABLE IF NOT EXISTS sessions (
  app_name TEXT NOT NULL,
  user_id TEXT NOT NULL,
  id TEXT NOT NULL,
  state TEXT NOT NULL,
  create_time REAL NOT NULL,
  update_time REAL NOT NULL,
  PRIMARY KEY (app_name, user_id, id)
);
''';

const String _legacyEventsSchema = '''
CREATE TABLE IF NOT EXISTS events (
  id TEXT NOT NULL,
  app_name TEXT NOT NULL,
  user_id TEXT NOT NULL,
  session_id TEXT NOT NULL,
  invocation_id TEXT,
  author TEXT,
  actions BLOB,
  long_running_tool_ids_json TEXT,
  branch TEXT,
  timestamp REAL,
  content TEXT,
  grounding_metadata TEXT,
  custom_metadata TEXT,
  usage_metadata TEXT,
  citation_metadata TEXT,
  partial INTEGER,
  turn_complete INTEGER,
  error_code TEXT,
  error_message TEXT,
  interrupted INTEGER,
  input_transcription TEXT,
  output_transcription TEXT,
  PRIMARY KEY (app_name, user_id, session_id, id)
);
''';

Future<void> _createLegacySourceDb(String path) async {
  final SqliteMigrationDatabase db = SqliteMigrationDatabase.open(
    connectPath: path,
    displayPath: path,
    uri: false,
    readOnly: false,
  );
  try {
    db.execute(_legacyAppStatesSchema);
    db.execute(_legacyUserStatesSchema);
    db.execute(_legacySessionsSchema);
    db.execute(_legacyEventsSchema);

    db.execute(
      'INSERT INTO app_states (app_name, state, update_time) VALUES (?, ?, ?)',
      <Object?>['app', '{"global":"g"}', 1700000000.0],
    );
    db.execute(
      'INSERT INTO user_states (app_name, user_id, state, update_time) VALUES (?, ?, ?, ?)',
      <Object?>['app', 'user', '{"profile":"u"}', 1700000001.0],
    );
    db.execute(
      'INSERT INTO sessions (app_name, user_id, id, state, create_time, update_time) VALUES (?, ?, ?, ?, ?, ?)',
      <Object?>[
        'app',
        'user',
        'session_1',
        '{"session":"s"}',
        1700000002.0,
        1700000003.0,
      ],
    );
    db.execute(
      'INSERT INTO events (id, app_name, user_id, session_id, invocation_id, author, actions, long_running_tool_ids_json, branch, timestamp, content, grounding_metadata, custom_metadata, usage_metadata, citation_metadata, partial, turn_complete, error_code, error_message, interrupted, input_transcription, output_transcription) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      <Object?>[
        'evt_1',
        'app',
        'user',
        'session_1',
        'inv_1',
        'agent',
        '{"stateDelta":{"k":"v"}}',
        '["tool_1"]',
        'main',
        1700000004.0,
        '{"parts":[{"text":"hello"}]}',
        '{"ground":"yes"}',
        '{"meta":"ok"}',
        '{"tokens":1}',
        '{"citations":[]}',
        0,
        1,
        null,
        null,
        0,
        '{"text":"in"}',
        '{"text":"out"}',
      ],
    );
  } finally {
    db.dispose();
  }
}

Map<String, Object?> _asObjectMap(Object? value) {
  if (value is Map<String, Object?>) {
    return Map<String, Object?>.from(value);
  }
  if (value is Map) {
    return value.map((Object? key, Object? value) => MapEntry('$key', value));
  }
  throw StateError('Expected a JSON map.');
}

void main() {
  group('sessions migration/schema parity', () {
    test('schema check utils normalize URL and detect versions', () async {
      expect(
        toSyncUrl('postgresql+asyncpg://localhost/mydb'),
        'postgresql://localhost/mydb',
      );
      expect(
        toSyncUrl('sqlite+aiosqlite:///tmp/adk.db'),
        'sqlite:///tmp/adk.db',
      );
      expect(
        getDbSchemaVersionFromDecoded(<String, Object?>{
          'metadata': <String, Object?>{'schema_version': schemaVersion1Json},
        }),
        schemaVersion1Json,
      );

      final Directory dir = await Directory.systemTemp.createTemp(
        'adk_schema_check_',
      );
      addTearDown(() async {
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      });

      final String v0Path = '${dir.path}/v0.db';
      await _createLegacySourceDb(v0Path);
      expect(
        await getDbSchemaVersion('sqlite:///$v0Path'),
        schemaVersion0Pickle,
      );

      final String v1Path = '${dir.path}/v1.db';
      final SqliteMigrationDatabase v1Db = SqliteMigrationDatabase.open(
        connectPath: v1Path,
        displayPath: v1Path,
        uri: false,
        readOnly: false,
      );
      try {
        v1Db.execute(
          'CREATE TABLE IF NOT EXISTS adk_internal_metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
        );
        v1Db.execute(
          'INSERT OR REPLACE INTO adk_internal_metadata (key, value) VALUES (?, ?)',
          <Object?>[schemaVersionKey, schemaVersion1Json],
        );
      } finally {
        v1Db.dispose();
      }
      expect(await getDbSchemaVersion('sqlite:///$v1Path'), schemaVersion1Json);
    });

    test('schema v0/v1 storage events convert to Event and back', () {
      final Session session = Session(id: 's1', appName: 'app', userId: 'user');
      final Event original = Event(
        id: 'evt_1',
        invocationId: 'inv_1',
        author: 'agent',
        timestamp: 1700000000.123,
        actions: EventActions(stateDelta: <String, Object?>{'k': 'v'}),
        content: Content(
          parts: <Part>[
            Part.text('hello', thought: true, thoughtSignature: <int>[1, 2, 3]),
            Part.fromFunctionCall(
              name: 'lookup',
              args: <String, dynamic>{'q': 'abc'},
              partialArgs: <Map<String, Object?>>[
                <String, Object?>{'json_path': r'$.q', 'string_value': 'abc'},
              ],
              willContinue: false,
              thoughtSignature: <int>[7, 8, 9],
            ),
          ],
        ),
        turnComplete: true,
        groundingMetadata: <String, Object?>{
          'searchEntryPoint': <String, Object?>{
            'renderedContent': '<div>grounded</div>',
          },
        },
      );

      final StorageEventV0 v0 = StorageEventV0.fromEvent(
        session: session,
        event: original,
      );
      final Event v0Roundtrip = v0.toEvent();
      expect(v0Roundtrip.id, original.id);
      expect(v0Roundtrip.invocationId, original.invocationId);
      expect(v0Roundtrip.author, original.author);
      expect(v0Roundtrip.content?.parts.first.text, 'hello');
      expect(v0Roundtrip.content?.parts.first.thought, isTrue);
      expect(v0Roundtrip.content?.parts.first.thoughtSignature, <int>[1, 2, 3]);
      expect(
        v0Roundtrip.content?.parts[1].functionCall?.partialArgs,
        isA<List<Map<String, Object?>>>(),
      );
      expect(v0Roundtrip.content?.parts[1].functionCall?.willContinue, isFalse);
      expect(v0Roundtrip.content?.parts[1].thoughtSignature, <int>[7, 8, 9]);
      expect(v0Roundtrip.groundingMetadata, isA<Map<String, Object?>>());
      expect(v0Roundtrip.actions.stateDelta['k'], 'v');

      final StorageEventV1 v1 = StorageEventV1.fromEvent(
        session: session,
        event: original,
      );
      final Event v1Roundtrip = v1.toEvent();
      expect(v1Roundtrip.id, original.id);
      expect(v1Roundtrip.invocationId, original.invocationId);
      expect(v1Roundtrip.author, original.author);
      expect(v1Roundtrip.content?.parts.first.text, 'hello');
      expect(v1Roundtrip.content?.parts.first.thought, isTrue);
      expect(v1Roundtrip.content?.parts.first.thoughtSignature, <int>[1, 2, 3]);
      expect(
        v1Roundtrip.content?.parts[1].functionCall?.partialArgs,
        isA<List<Map<String, Object?>>>(),
      );
      expect(v1Roundtrip.content?.parts[1].functionCall?.willContinue, isFalse);
      expect(v1Roundtrip.content?.parts[1].thoughtSignature, <int>[7, 8, 9]);
      expect(v1Roundtrip.groundingMetadata, isA<Map<String, Object?>>());
      expect(v1Roundtrip.actions.stateDelta['k'], 'v');
      expect(v1.eventData['invocation_id'], original.invocationId);
    });

    test(
      'pickle migration writes v1 metadata and event_data payload',
      () async {
        final Directory dir = await Directory.systemTemp.createTemp(
          'adk_migration_pickle_',
        );
        addTearDown(() async {
          if (await dir.exists()) {
            await dir.delete(recursive: true);
          }
        });

        final String source = '${dir.path}/source.db';
        final String dest = '${dir.path}/dest.db';
        await _createLegacySourceDb(source);

        await migrateFromSqlalchemyPickle(
          'sqlite:///$source',
          'sqlite:///$dest',
        );

        final SqliteMigrationDatabase db = SqliteMigrationDatabase.open(
          connectPath: dest,
          displayPath: dest,
          uri: false,
          readOnly: true,
        );
        try {
          final List<Map<String, Object?>> metadata = db.query(
            'SELECT value FROM adk_internal_metadata WHERE key=?',
            <Object?>[schemaVersionKey],
          );
          expect(metadata, isNotEmpty);
          expect('${metadata.first['value']}', schemaVersion1Json);

          final List<Map<String, Object?>> events = db.query(
            'SELECT id, invocation_id, event_data FROM events WHERE id=?',
            <Object?>['evt_1'],
          );
          expect(events, isNotEmpty);
          final Map<String, Object?> eventData = _asObjectMap(
            jsonDecode('${events.first['event_data']}'),
          );
          expect(eventData['id'], 'evt_1');
          expect(eventData['invocation_id'], 'inv_1');
          expect(eventData['actions'], isA<Map>());
          expect(_asObjectMap(eventData['actions'])['stateDelta'], isA<Map>());
          expect(
            (_asObjectMap(eventData['actions'])['stateDelta'] as Map)['k'],
            'v',
          );
          expect(eventData['long_running_tool_ids'], isA<List>());
        } finally {
          db.dispose();
        }

        expect(await getDbSchemaVersion('sqlite:///$dest'), schemaVersion1Json);
      },
    );

    test('migration runner upgrades v0 store to latest', () async {
      final Directory dir = await Directory.systemTemp.createTemp(
        'adk_migration_runner_',
      );
      addTearDown(() async {
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      });

      final String source = '${dir.path}/source.db';
      final String dest = '${dir.path}/dest.db';
      await _createLegacySourceDb(source);

      await upgrade('sqlite:///$source', 'sqlite:///$dest');
      expect(await getDbSchemaVersion('sqlite:///$dest'), schemaVersion1Json);

      await expectLater(
        () => upgrade('sqlite:///$source', 'sqlite:///$source'),
        throwsA(isA<StateError>()),
      );
    });
  });
}
