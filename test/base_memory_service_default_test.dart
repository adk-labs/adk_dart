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
  test('default addEventsToMemory throws unsupported', () async {
    final _RecordingMemoryService service = _RecordingMemoryService();
    await expectLater(
      service.addEventsToMemory(
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
      ),
      throwsA(isA<UnsupportedError>()),
    );
    expect(service.ingestedSessions, isEmpty);
  });

  test('default addMemory throws unsupported', () async {
    final _RecordingMemoryService service = _RecordingMemoryService();
    await expectLater(
      service.addMemory(
        appName: 'app',
        userId: 'u1',
        memories: <MemoryEntry>[
          MemoryEntry(
            content: Content(role: 'user', parts: <Part>[Part.text('memo')]),
            author: 'memory',
          ),
        ],
      ),
      throwsA(isA<UnsupportedError>()),
    );
    expect(service.ingestedSessions, isEmpty);
  });
}
