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
  }) {
    throw UnimplementedError(
      'This memory service does not support incremental event ingestion.',
    );
  }

  Future<void> addMemory({
    required String appName,
    required String userId,
    required List<MemoryEntry> memories,
    Map<String, Object?>? customMetadata,
  }) {
    throw UnimplementedError(
      'This memory service does not support direct memory writes.',
    );
  }

  Future<SearchMemoryResponse> searchMemory({
    required String appName,
    required String userId,
    required String query,
  });
}
