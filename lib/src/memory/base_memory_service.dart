/// Memory service contracts for session ingestion and retrieval.
library;

import '../events/event.dart';
import '../sessions/session.dart';
import 'memory_entry.dart';

/// Response model returned by memory search operations.
class SearchMemoryResponse {
  /// Creates a memory search response.
  SearchMemoryResponse({List<MemoryEntry>? memories})
    : memories = memories ?? <MemoryEntry>[];

  /// Memories matched for a given query.
  final List<MemoryEntry> memories;
}

/// Base contract for memory ingestion and search implementations.
abstract class BaseMemoryService {
  /// Creates a memory service.
  BaseMemoryService();

  /// Adds all events from [session] to memory storage.
  Future<void> addSessionToMemory(Session session);

  /// Adds scoped [events] to memory storage.
  ///
  /// Default implementation throws [UnsupportedError].
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

  /// Adds pre-built [memories] directly into storage.
  ///
  /// Default implementation throws [UnsupportedError].
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

  /// Searches memory using [query] for one app/user scope.
  Future<SearchMemoryResponse> searchMemory({
    required String appName,
    required String userId,
    required String query,
  });
}
