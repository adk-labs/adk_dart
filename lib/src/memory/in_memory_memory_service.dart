/// In-memory implementation of memory storage and search.
library;

import '../events/event.dart';
import '../sessions/session.dart';
import '_utils.dart';
import 'base_memory_service.dart';
import 'memory_entry.dart';

/// Memory service backed by process-local event collections.
///
/// ```dart
/// final memoryService = InMemoryMemoryService();
/// await memoryService.addSessionToMemory(session);
/// final results = await memoryService.searchMemory(
///   appName: 'my_app',
///   userId: 'user_1',
///   query: 'project deadline',
/// );
/// ```
class InMemoryMemoryService extends BaseMemoryService {
  /// Creates an in-memory memory service.
  InMemoryMemoryService();

  static const int _maxSearchResults = 10;

  final Map<(String, String), Map<String, List<Event>>>
  _sessionEventsByUserKey = <(String, String), Map<String, List<Event>>>{};
  final Map<(String, String), Set<String>> _deletedMemoryIdsByUserKey =
      <(String, String), Set<String>>{};

  @override
  Future<void> addSessionToMemory(
    Session session, {
    Map<String, Object?>? customMetadata,
  }) async {
    final (String, String) key = _userKey(session.appName, session.userId);
    final Set<String> deletedIds =
        _deletedMemoryIdsByUserKey[key] ?? const <String>{};
    final Map<String, List<Event>> sessions = _sessionEventsByUserKey[key] ??=
        <String, List<Event>>{};
    sessions[session.id] = session.events
        .where(
          (Event event) =>
              event.content != null &&
              event.content!.parts.isNotEmpty &&
              !deletedIds.contains(event.id),
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
    final Set<String> deletedIds =
        _deletedMemoryIdsByUserKey[key] ?? const <String>{};
    final Map<String, List<Event>> sessions = _sessionEventsByUserKey[key] ??=
        <String, List<Event>>{};
    final String targetSessionId = sessionId ?? 'unknown_session';
    final List<Event> target = sessions[targetSessionId] ??= <Event>[];

    final Set<String> existingIds = target
        .map((Event event) => event.id)
        .toSet();
    for (final Event event in events) {
      if (event.content == null || event.content!.parts.isEmpty) {
        continue;
      }
      if (existingIds.contains(event.id) || deletedIds.contains(event.id)) {
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
    final bool matchAll = query.trim().isEmpty;
    final List<(int, MemoryEntry)> scoredMemories = <(int, MemoryEntry)>[];

    for (final List<Event> events in sessions.values) {
      for (final Event event in events) {
        final content = event.content;
        if (content == null || content.parts.isEmpty) {
          continue;
        }
        final visibleParts = content.parts
            .where((part) => !part.thought)
            .toList(growable: false);
        final String text = visibleParts
            .where((part) => part.text != null && part.text!.trim().isNotEmpty)
            .map((part) => part.text!.trim())
            .join(' ');
        if (text.isEmpty) {
          continue;
        }
        final String textLower = text.toLowerCase();
        final Set<String> eventWords = _extractWordsLower(text);
        if (eventWords.isEmpty && _isAscii(text)) {
          continue;
        }
        int matchedWords = 0;
        if (matchAll) {
          matchedWords = 1;
        } else {
          for (final String queryWord in queryWords) {
            if (eventWords.contains(queryWord) ||
                (!_isAscii(queryWord) && textLower.contains(queryWord))) {
              matchedWords += 1;
            }
          }
        }
        if (matchedWords > 0) {
          scoredMemories.add((
            matchedWords,
            MemoryEntry(
              id: event.id,
              content: content.copyWith(
                parts: visibleParts.map((part) => part.copyWith()).toList(),
              ),
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

  @override
  Future<void> deleteMemory({
    required String appName,
    required String userId,
    String? memoryId,
  }) async {
    if (memoryId == null || memoryId.isEmpty) {
      return;
    }
    final (String, String) key = _userKey(appName, userId);
    final Map<String, List<Event>>? sessions = _sessionEventsByUserKey[key];
    if (sessions != null) {
      for (final MapEntry<String, List<Event>> entry in sessions.entries) {
        final List<Event> kept = entry.value
            .where((Event event) => event.id != memoryId)
            .toList();
        if (kept.length != entry.value.length) {
          sessions[entry.key] = kept;
          (_deletedMemoryIdsByUserKey[key] ??= <String>{}).add(memoryId);
        }
      }
    }
  }
}

(String, String) _userKey(String appName, String userId) => (appName, userId);

bool _isAscii(String str) {
  for (int i = 0; i < str.length; i += 1) {
    if (str.codeUnitAt(i) > 127) {
      return false;
    }
  }
  return true;
}

Set<String> _extractWordsLower(String text) {
  final RegExp exp = RegExp(r'[\p{L}\p{N}_][\p{L}\p{N}\p{M}_]*', unicode: true);
  return exp
      .allMatches(text)
      .map((Match match) => match.group(0)!.toLowerCase())
      .toSet();
}
