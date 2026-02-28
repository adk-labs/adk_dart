import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

void main() {
  group('InMemoryMemoryService', () {
    test('adds session events and searches by keyword', () async {
      final InMemoryMemoryService service = InMemoryMemoryService();
      final Session session = Session(
        id: 's1',
        appName: 'app',
        userId: 'u1',
        events: <Event>[
          Event(
            invocationId: 'inv1',
            author: 'agent',
            content: Content.modelText('The weather in Seoul is clear'),
          ),
          Event(
            invocationId: 'inv2',
            author: 'agent',
            content: Content.modelText('Another response'),
          ),
        ],
      );

      await service.addSessionToMemory(session);
      final SearchMemoryResponse response = await service.searchMemory(
        appName: 'app',
        userId: 'u1',
        query: 'seoul weather',
      );

      expect(response.memories, hasLength(1));
      expect(response.memories.first.author, 'agent');
      expect(
        response.memories.first.content.parts.first.text,
        contains('Seoul'),
      );
    });

    test('addEventsToMemory ignores customMetadata payload', () async {
      final InMemoryMemoryService service = InMemoryMemoryService();

      await service.addEventsToMemory(
        appName: 'app',
        userId: 'u1',
        sessionId: 's1',
        customMetadata: <String, Object?>{
          'source': 'ingest',
          'priority': 'high',
        },
        events: <Event>[
          Event(
            invocationId: 'inv3',
            author: 'agent',
            content: Content.modelText('metadata searchable text'),
            customMetadata: <String, dynamic>{
              'priority': 'low',
              'event_only': 'yes',
            },
          ),
        ],
      );

      final SearchMemoryResponse response = await service.searchMemory(
        appName: 'app',
        userId: 'u1',
        query: 'metadata searchable',
      );

      expect(response.memories, hasLength(1));
      expect(response.memories.first.customMetadata, isEmpty);
    });

    test('addMemory is unsupported', () async {
      final InMemoryMemoryService service = InMemoryMemoryService();

      await expectLater(
        service.addMemory(
          appName: 'app',
          userId: 'u1',
          memories: <MemoryEntry>[MemoryEntry(content: Content.userText('m1'))],
        ),
        throwsA(isA<UnsupportedError>()),
      );
    });
  });
}
