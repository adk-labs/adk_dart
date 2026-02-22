import '../events/event.dart';
import '../sessions/session.dart';
import 'base_memory_service.dart';
import 'memory_entry.dart';

class InMemoryMemoryService extends BaseMemoryService {
  final Map<String, Map<String, List<Event>>> _sessionEventsByUserKey =
      <String, Map<String, List<Event>>>{};

  @override
  Future<void> addSessionToMemory(Session session) async {
    final String key = _userKey(session.appName, session.userId);
    final List<Event> events = session.events
        .where(
          (Event event) =>
              event.content != null && event.content!.parts.isNotEmpty,
        )
        .map((Event event) => event.copyWith())
        .toList();

    _sessionEventsByUserKey.putIfAbsent(
      key,
      () => <String, List<Event>>{},
    )[session.id] = events;
  }

  @override
  Future<void> addEventsToMemory({
    required String appName,
    required String userId,
    required List<Event> events,
    String? sessionId,
    Map<String, Object?>? customMetadata,
  }) async {
    final String key = _userKey(appName, userId);
    final String scopedSessionId = sessionId ?? '__unknown_session_id__';
    final List<Event> target = _sessionEventsByUserKey
        .putIfAbsent(key, () => <String, List<Event>>{})
        .putIfAbsent(scopedSessionId, () => <Event>[]);

    final Set<String> existingIds = target
        .map((Event event) => event.id)
        .toSet();
    for (final Event event in events) {
      if (event.content == null || event.content!.parts.isEmpty) {
        continue;
      }
      if (existingIds.contains(event.id)) {
        continue;
      }
      target.add(event.copyWith());
      existingIds.add(event.id);
    }
  }

  @override
  Future<void> addMemory({
    required String appName,
    required String userId,
    required List<MemoryEntry> memories,
    Map<String, Object?>? customMetadata,
  }) async {
    final List<Event> asEvents = memories.map((MemoryEntry memory) {
      return Event(
        invocationId: 'memory_ingest',
        author: memory.author ?? 'memory',
        content: memory.content.copyWith(),
      );
    }).toList();
    await addEventsToMemory(
      appName: appName,
      userId: userId,
      events: asEvents,
      sessionId: '__manual_memory__',
      customMetadata: customMetadata,
    );
  }

  @override
  Future<SearchMemoryResponse> searchMemory({
    required String appName,
    required String userId,
    required String query,
  }) async {
    final String key = _userKey(appName, userId);
    final Map<String, List<Event>> sessions =
        _sessionEventsByUserKey[key] ?? <String, List<Event>>{};

    final Set<String> queryWords = _extractWordsLower(query);
    final List<MemoryEntry> found = <MemoryEntry>[];

    for (final List<Event> events in sessions.values) {
      for (final Event event in events) {
        final String text = _eventText(event);
        if (text.isEmpty) {
          continue;
        }
        final Set<String> eventWords = _extractWordsLower(text);
        if (eventWords.isEmpty) {
          continue;
        }
        if (!_hasAnyWordOverlap(queryWords, eventWords)) {
          continue;
        }

        found.add(
          MemoryEntry(
            content: event.content!.copyWith(),
            author: event.author,
            id: event.id,
            timestamp: DateTime.fromMillisecondsSinceEpoch(
              (event.timestamp * 1000).toInt(),
            ).toIso8601String(),
          ),
        );
      }
    }

    return SearchMemoryResponse(memories: found);
  }
}

String _userKey(String appName, String userId) => '$appName/$userId';

String _eventText(Event event) {
  final content = event.content;
  if (content == null) {
    return '';
  }
  return content.parts
      .where((part) => part.text != null && part.text!.trim().isNotEmpty)
      .map((part) => part.text!.trim())
      .join(' ');
}

Set<String> _extractWordsLower(String text) {
  final RegExp exp = RegExp(r'[A-Za-z]+');
  return exp
      .allMatches(text)
      .map((Match match) => match.group(0)!.toLowerCase())
      .toSet();
}

bool _hasAnyWordOverlap(Set<String> left, Set<String> right) {
  if (left.isEmpty || right.isEmpty) {
    return false;
  }
  for (final String word in left) {
    if (right.contains(word)) {
      return true;
    }
  }
  return false;
}
