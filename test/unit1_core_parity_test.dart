import 'package:adk_dart/adk_core.dart';
import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

void main() {
  group('Unit 1: Core Runtime Parity', () {
    test('JSON pointer dereference resolves paths, arrays, and escapes', () {
      final Map<String, dynamic> schema = <String, dynamic>{
        'type': 'object',
        'definitions': <String, dynamic>{
          'User': <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{
              'name': <String, dynamic>{'type': 'string'},
            },
          },
        },
        'properties': <String, dynamic>{
          'creator': <String, dynamic>{r'$ref': '#/definitions/User'},
          'self': <String, dynamic>{r'$ref': '#'},
          'firstTag': <String, dynamic>{r'$ref': '#/properties/tags/anyOf/0'},
          'tags': <String, dynamic>{
            'anyOf': <dynamic>[
              <String, dynamic>{'type': 'string'},
              <String, dynamic>{'type': 'integer'},
            ],
          },
          'escaped/prop': <String, dynamic>{'type': 'boolean'},
          'escapedRef': <String, dynamic>{r'$ref': '#/properties/escaped~1prop'},
        },
      };

      final Map<String, dynamic> dereferenced = dereferenceSchema(schema);
      final Map<String, dynamic> props =
          dereferenced['properties'] as Map<String, dynamic>;

      expect(
        (props['creator'] as Map<String, dynamic>)['properties']['name']['type'],
        'string',
      );
      expect(
        (props['firstTag'] as Map<String, dynamic>)['type'],
        'string',
      );
      expect(
        (props['escapedRef'] as Map<String, dynamic>)['type'],
        'boolean',
      );
      expect(props['self']['type'], 'object');
    });

    test('InMemoryMemoryService deleteMemory purges and prevents re-ingestion', () async {
      final InMemoryMemoryService memoryService = InMemoryMemoryService();
      final Event e1 = Event(
        id: 'mem-1',
        invocationId: 'inv-1',
        author: 'user',
        timestamp: 1000,
        content: Content.userText('ADK memory deletion test'),
      );
      final Event e2 = Event(
        id: 'mem-2',
        invocationId: 'inv-1',
        author: 'user',
        timestamp: 1001,
        content: Content.userText('ADK persistent memory test'),
      );

      final Session session = Session(
        appName: 'test_app',
        userId: 'u1',
        id: 's1',
        events: <Event>[e1, e2],
      );

      await memoryService.addSessionToMemory(session);
      SearchMemoryResponse searchRes = await memoryService.searchMemory(
        appName: 'test_app',
        userId: 'u1',
        query: 'deletion',
      );
      expect(searchRes.memories.length, 1);
      expect(searchRes.memories.first.id, 'mem-1');

      // Delete mem-1
      await memoryService.deleteMemory(
        appName: 'test_app',
        userId: 'u1',
        memoryId: 'mem-1',
      );

      searchRes = await memoryService.searchMemory(
        appName: 'test_app',
        userId: 'u1',
        query: 'deletion',
      );
      expect(searchRes.memories, isEmpty);

      // Re-ingest should not restore mem-1
      await memoryService.addSessionToMemory(session);
      searchRes = await memoryService.searchMemory(
        appName: 'test_app',
        userId: 'u1',
        query: 'deletion',
      );
      expect(searchRes.memories, isEmpty);

      // But mem-2 is still searchable
      searchRes = await memoryService.searchMemory(
        appName: 'test_app',
        userId: 'u1',
        query: 'persistent',
      );
      expect(searchRes.memories.length, 1);
      expect(searchRes.memories.first.id, 'mem-2');
    });
  });
}
