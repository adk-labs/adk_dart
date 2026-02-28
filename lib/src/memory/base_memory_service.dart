import '../events/event.dart';
import '../sessions/session.dart';
import 'memory_entry.dart';

class SearchMemoryResponse {
  SearchMemoryResponse({List<MemoryEntry>? memories})
    : memories = memories ?? <MemoryEntry>[];

  final List<MemoryEntry> memories;
}

abstract class BaseMemoryService {
  Future<void> addSessionToMemory(Session session);

  Future<void> addEventsToMemory({
    required String appName,
    required String userId,
    required List<Event> events,
    String? sessionId,
    Map<String, Object?>? customMetadata,
  }) async {
    throw UnsupportedError(
      'This memory service does not support adding event deltas. '
      'Call addSessionToMemory(session) to ingest the full session.',
    );
  }

  Future<void> addMemory({
    required String appName,
    required String userId,
    required List<MemoryEntry> memories,
    Map<String, Object?>? customMetadata,
  }) async {
    throw UnsupportedError(
      'This memory service does not support direct memory writes. '
      'Call addEventsToMemory(...) or addSessionToMemory(session) instead.',
    );
  }

  Future<SearchMemoryResponse> searchMemory({
    required String appName,
    required String userId,
    required String query,
  });
}
