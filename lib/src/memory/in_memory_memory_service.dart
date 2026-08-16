/// In-memory implementation of memory storage and search.
library;

import '../events/event.dart';
import '../sessions/session.dart';
import '_utils.dart';
import 'base_memory_service.dart';
import 'memory_entry.dart';

/// Memory service backed by process-local event collections.
class InMemoryMemoryService extends BaseMemoryService {
  /// Creates an in-memory memory service.
  InMemoryMemoryService();

  static const int _maxSearchResults = 10;

  final Map<(String, String), Map<String, List<Event>>> _sessionEventsByUserKey =
      <(String, String), Map<String, List<Event>>>{};

  @override
  Future<void> addSessionToMemory(Session session) async {
    final (String, String) key = _userKey(session.appName, session.userId);
    final Map<String, List<Event>> sessions =
        _sessionEventsByUserKey[key] ??= <String, List<Event>>{};
    sessions[session.id] = session.events
        .where(
          (Event event) =>
              event.content != null && event.content!.parts.isNotEmpty,
        )
        .map((Event event) => event.copyWith())
        .toList();
  }

  @override
  Future<void> addEventsToMemory({
    required String appName,
    required String userId,
    required List<Event> events,
    String? sessionId,
    Map<String, Object?>? customMetadata,
  }) async {
    final (String, String) key = _userKey(appName, userId);
    final Map<String, List<Event>> sessions =
        _sessionEventsByUserKey[key] ??= <String, List<Event>>{};
    final String targetSessionId = sessionId ?? 'unknown_session';
    final List<Event> target = sessions[targetSessionId] ??= <Event>[];

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
  Future<SearchMemoryResponse> searchMemory({
    required String appName,
    required String userId,
    required String query,
  }) async {
    final (String, String) key = _userKey(appName, userId);
    final Map<String, List<Event>> sessions =
        _sessionEventsByUserKey[key] ?? <String, List<Event>>{};

    final Set<String> queryWords = _extractWordsLower(query);
    final List<(int, MemoryEntry)> scoredMemories = <(int, MemoryEntry)>[];

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
        final int matchedWords = queryWords.intersection(eventWords).length;
        if (matchedWords > 0) {
          scoredMemories.add((
            matchedWords,
            MemoryEntry(
              content: event.content!.copyWith(),
              author: event.author,
              timestamp: formatTimestamp(event.timestamp),
            ),
          ));
        }
      }
    }

    scoredMemories.sort(
      ((int, MemoryEntry) a, (int, MemoryEntry) b) => b.$1.compareTo(a.$1),
    );

    final List<MemoryEntry> topMemories = scoredMemories
        .take(_maxSearchResults)
        .map(((int, MemoryEntry) item) => item.$2)
        .toList();

    return SearchMemoryResponse(memories: topMemories);
  }
}

(String, String) _userKey(String appName, String userId) => (appName, userId);

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

