import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

class _RecordingMemoryService extends BaseMemoryService {
  final List<Session> ingestedSessions = <Session>[];

  @override
  Future<void> addSessionToMemory(Session session) async {
    ingestedSessions.add(session);
  }

  @override
  Future<SearchMemoryResponse> searchMemory({
    required String appName,
    required String userId,
    required String query,
  }) async {
    return SearchMemoryResponse(memories: const <MemoryEntry>[]);
  }
}

void main() {
  test('default addEventsToMemory ingests synthetic session', () async {
    final _RecordingMemoryService service = _RecordingMemoryService();
    await service.addEventsToMemory(
      appName: 'app',
      userId: 'u1',
      sessionId: 's_memory_events',
      events: <Event>[
        Event(
          invocationId: 'inv',
          author: 'agent',
          content: Content.modelText('hello'),
        ),
      ],
    );

    expect(service.ingestedSessions, hasLength(1));
    expect(service.ingestedSessions.first.id, 's_memory_events');
    expect(
      service.ingestedSessions.first.events.first.content?.parts.first.text,
      'hello',
    );
  });

  test('default addMemory converts entries to events', () async {
    final _RecordingMemoryService service = _RecordingMemoryService();
    await service.addMemory(
      appName: 'app',
      userId: 'u1',
      memories: <MemoryEntry>[
        MemoryEntry(
          content: Content(role: 'user', parts: <Part>[Part.text('memo')]),
          author: 'memory',
        ),
      ],
    );

    expect(service.ingestedSessions, hasLength(1));
    expect(
      service.ingestedSessions.first.events.first.content?.parts.first.text,
      'memo',
    );
  });
}
