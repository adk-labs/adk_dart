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
  });
}
