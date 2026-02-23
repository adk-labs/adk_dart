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
    if (events.isEmpty) {
      return;
    }

    final String resolvedSessionId =
        sessionId ?? 'memory_ingest_${DateTime.now().microsecondsSinceEpoch}';
    final Map<String, Object?> metadata = <String, Object?>{...?customMetadata};

    final List<Event> copiedEvents = events
        .map((Event event) {
          return event.copyWith(
            customMetadata: <String, dynamic>{
              ...?event.customMetadata,
              ...metadata.map(
                (String key, Object? value) =>
                    MapEntry<String, dynamic>(key, value),
              ),
            },
          );
        })
        .toList(growable: false);

    await addSessionToMemory(
      Session(
        id: resolvedSessionId,
        appName: appName,
        userId: userId,
        events: copiedEvents,
      ),
    );
  }

  Future<void> addMemory({
    required String appName,
    required String userId,
    required List<MemoryEntry> memories,
    Map<String, Object?>? customMetadata,
  }) async {
    if (memories.isEmpty) {
      return;
    }

    final String invocationId =
        'memory_write_${DateTime.now().microsecondsSinceEpoch}';
    final List<Event> syntheticEvents = memories
        .map((MemoryEntry memory) {
          final Map<String, dynamic> metadata = <String, dynamic>{
            ...?customMetadata,
            ...memory.customMetadata.map(
              (String key, Object? value) =>
                  MapEntry<String, dynamic>(key, value),
            ),
          };
          return Event(
            invocationId: invocationId,
            author: memory.author ?? 'memory',
            content: memory.content.copyWith(),
            customMetadata: metadata.isEmpty ? null : metadata,
          );
        })
        .toList(growable: false);

    await addEventsToMemory(
      appName: appName,
      userId: userId,
      events: syntheticEvents,
      customMetadata: customMetadata,
    );
  }

  Future<SearchMemoryResponse> searchMemory({
    required String appName,
    required String userId,
    required String query,
  });
}
