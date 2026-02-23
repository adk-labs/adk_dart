import 'dart:convert';
import 'dart:io';

import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

Future<File> _writeJsonFile(String path, Map<String, Object?> json) async {
  final File file = File(path);
  await file.parent.create(recursive: true);
  await file.writeAsString(const JsonEncoder.withIndent('  ').convert(json));
  return file;
}

Future<Map<String, Object?>> _readJsonFile(String path) async {
  final String raw = await File(path).readAsString();
  final Object? decoded = jsonDecode(raw);
  if (decoded is Map<String, Object?>) {
    return decoded;
  }
  if (decoded is Map) {
    return decoded.map((Object? key, Object? value) => MapEntry('$key', value));
  }
  throw StateError('Expected JSON map in $path.');
}

void main() {
  group('sessions migration/schema parity', () {
    test('schema check utils normalize URL and detect versions', () {
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
      expect(
        getDbSchemaVersionFromDecoded(<String, Object?>{
          'sessions': <String, Object?>{
            'app': <String, Object?>{
              'user': <String, Object?>{
                'session': <String, Object?>{
                  'events': <Map<String, Object?>>[
                    <String, Object?>{
                      'id': 'evt',
                      'invocationId': 'inv',
                      'author': 'agent',
                      'actions': <String, Object?>{},
                    },
                  ],
                },
              },
            },
          },
        }),
        schemaVersion0Pickle,
      );
    });

    test('schema v0/v1 storage events convert to Event and back', () {
      final Session session = Session(id: 's1', appName: 'app', userId: 'user');
      final Event original = Event(
        id: 'evt_1',
        invocationId: 'inv_1',
        author: 'agent',
        timestamp: 1700000000.123,
        actions: EventActions(stateDelta: <String, Object?>{'k': 'v'}),
        content: Content(parts: <Part>[Part.text('hello')]),
        turnComplete: true,
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

        final String source = '${dir.path}/source.json';
        final String dest = '${dir.path}/dest.json';
        await _writeJsonFile(source, <String, Object?>{
          'sessions': <String, Object?>{
            'app': <String, Object?>{
              'user': <String, Object?>{
                'session_1': <String, Object?>{
                  'state': <String, Object?>{},
                  'events': <Map<String, Object?>>[
                    <String, Object?>{
                      'id': 'evt_1',
                      'invocationId': 'inv_1',
                      'author': 'agent',
                      'actions': <String, Object?>{
                        'stateDelta': <String, Object?>{},
                      },
                      'timestamp': 1700000000.0,
                      'content': <String, Object?>{
                        'parts': <Map<String, Object?>>[
                          <String, Object?>{'text': 'hello', 'thought': false},
                        ],
                      },
                    },
                  ],
                  'lastUpdateTime': 1700000000.0,
                },
              },
            },
          },
          'appState': <String, Object?>{},
          'userState': <String, Object?>{},
        });

        await migrateFromSqlalchemyPickle(
          'sqlite:///$source',
          'sqlite:///$dest',
        );

        final Map<String, Object?> migrated = await _readJsonFile(dest);
        expect(
          (migrated['metadata'] as Map)['schema_version'],
          schemaVersion1Json,
        );
        expect(migrated['schemaVersion'], schemaVersion1Json);

        final Map sessions = migrated['sessions'] as Map;
        final Map byUser = sessions['app'] as Map;
        final Map bySession = byUser['user'] as Map;
        final Map stored = bySession['session_1'] as Map;
        final Map event = (stored['events'] as List).first as Map;
        expect(event['event_data'], isA<Map>());
        final Map eventData = event['event_data'] as Map;
        expect(eventData['id'], 'evt_1');
        expect(eventData['invocation_id'], 'inv_1');
        expect(eventData['actions'], isA<Map>());

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

      final String source = '${dir.path}/source.json';
      final String dest = '${dir.path}/dest.json';
      await _writeJsonFile(source, <String, Object?>{
        'sessions': <String, Object?>{
          'app': <String, Object?>{
            'user': <String, Object?>{
              'session_1': <String, Object?>{
                'state': <String, Object?>{},
                'events': <Map<String, Object?>>[
                  <String, Object?>{
                    'id': 'evt_1',
                    'invocationId': 'inv_1',
                    'author': 'agent',
                    'actions': <String, Object?>{},
                    'timestamp': 1700000000.0,
                  },
                ],
                'lastUpdateTime': 1700000000.0,
              },
            },
          },
        },
      });

      await upgrade('sqlite:///$source', 'sqlite:///$dest');
      expect(await getDbSchemaVersion('sqlite:///$dest'), schemaVersion1Json);

      await expectLater(
        () => upgrade('sqlite:///$source', 'sqlite:///$source'),
        throwsA(isA<StateError>()),
      );
    });
  });
}
