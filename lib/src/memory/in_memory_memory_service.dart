/// In-memory implementation of memory storage and search.
library;

import '../events/event.dart';
import '../events/rewind_events.dart';
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

  final Map<(String, String), Map<String?, List<Event>>>
  _sessionEventsByUserKey = <(String, String), Map<String?, List<Event>>>{};
  final Map<(String, String), Set<String>> _deletedMemoryIdsByUserKey =
      <(String, String), Set<String>>{};

  @override
  Future<void> addSessionToMemory(
    Session session, {
    Map<String, Object?>? customMetadata,
  }) async {
    _addEventsToMemory(
      appName: session.appName,
      userId: session.userId,
      sessionId: session.id,
      events: applyRewinds(session.events),
      replaceSessionEvents: true,
    );
  }

  @override
  Future<void> addEventsToMemory({
    required String appName,
    required String userId,
    required List<Event> events,
    String? sessionId,
    Map<String, Object?>? customMetadata,
  }) async {
    final String? normalizedSessionId =
        (sessionId == null || sessionId.isEmpty) ? null : sessionId;
    _addEventsToMemory(
      appName: appName,
      userId: userId,
      sessionId: normalizedSessionId,
      events: events,
      replaceSessionEvents: false,
    );
  }

  void _addEventsToMemory({
    required String appName,
    required String userId,
    required String? sessionId,
    required List<Event> events,
    required bool replaceSessionEvents,
  }) {
    final (String, String) key = _userKey(appName, userId);
    final Set<String> deletedIds =
        _deletedMemoryIdsByUserKey[key] ?? const <String>{};
    final Map<String?, List<Event>> sessions = _sessionEventsByUserKey[key] ??=
        <String?, List<Event>>{};

    if (replaceSessionEvents) {
      final Set<String> seenIds = <String>{};
      final List<Event> replaced = <Event>[];
      for (final Event event in events) {
        if (event.content == null || event.content!.parts.isEmpty) {
          continue;
        }
        if (deletedIds.contains(event.id) || !seenIds.add(event.id)) {
          continue;
        }
        replaced.add(event.copyWith());
      }
      sessions[sessionId] = replaced;
      return;
    }

    final List<Event> target = sessions[sessionId] ??= <Event>[];
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
    final Map<String?, List<Event>> sessions =
        _sessionEventsByUserKey[key] ?? <String?, List<Event>>{};

    final Set<String> wholeWordsInQuery = _extractWordsLower(query);
    final Set<String> wordsInQuery = _extractSearchableWords(query);
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
        final String normalizedEventText = _normalizeCommonNfc(text);
        final String textLower = normalizedEventText.toLowerCase();
        final Set<String> wordsInEvent = _extractSearchableWords(
          normalizedEventText,
        );
        if (wordsInEvent.isEmpty && _isAscii(normalizedEventText)) {
          continue;
        }
        int matchedWords = 0;
        if (matchAll) {
          matchedWords = 1;
        } else {
          for (final String queryWord in wordsInQuery) {
            if (wordsInEvent.contains(queryWord) ||
                // A script run split out of a query word, such as `と` from
                // `Pythonと`, would match nearly any Japanese text as a
                // substring; restrict substring matching to whole query words.
                (wholeWordsInQuery.contains(queryWord) &&
                    !_isAscii(queryWord) &&
                    textLower.contains(queryWord))) {
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
    final Map<String?, List<Event>>? sessions = _sessionEventsByUserKey[key];
    if (sessions != null) {
      for (final MapEntry<String?, List<Event>> entry in sessions.entries) {
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

bool _isLatin(int rune) {
  if (rune < 0x80) {
    return (rune >= 0x30 && rune <= 0x39) ||
        (rune >= 0x41 && rune <= 0x5A) ||
        (rune >= 0x61 && rune <= 0x7A) ||
        rune == 0x5F;
  }
  if ((rune >= 0x00C0 && rune <= 0x00D6) ||
      (rune >= 0x00D8 && rune <= 0x00F6) ||
      (rune >= 0x00F8 && rune <= 0x024F)) {
    return true;
  }
  if ((rune >= 0x1D00 && rune <= 0x1D25) ||
      (rune >= 0x1D6B && rune <= 0x1D77) ||
      (rune >= 0x1D79 && rune <= 0x1D9A) ||
      (rune >= 0x1E00 && rune <= 0x1EFF) ||
      rune == 0x2071 ||
      rune == 0x207F ||
      (rune >= 0x2090 && rune <= 0x209C) ||
      (rune >= 0x2C60 && rune <= 0x2C7F) ||
      (rune >= 0xA720 && rune <= 0xA7FF) ||
      (rune >= 0xAB30 && rune <= 0xAB65) ||
      (rune >= 0xFB00 && rune <= 0xFB06)) {
    return true;
  }
  return false;
}

const Map<(int, int), int> _commonNfcCompositions = <(int, int), int>{
  // Grave
  (0x0041, 0x0300): 0x00C0,
  (0x0045, 0x0300): 0x00C8,
  (0x0049, 0x0300): 0x00CC,
  (0x004F, 0x0300): 0x00D2,
  (0x0055, 0x0300): 0x00D9,
  (0x0061, 0x0300): 0x00E0,
  (0x0065, 0x0300): 0x00E8,
  (0x0069, 0x0300): 0x00EC,
  (0x006F, 0x0300): 0x00F2,
  (0x0075, 0x0300): 0x00F9,
  // Acute
  (0x0041, 0x0301): 0x00C1,
  (0x0045, 0x0301): 0x00C9,
  (0x0049, 0x0301): 0x00CD,
  (0x004F, 0x0301): 0x00D3,
  (0x0055, 0x0301): 0x00DA,
  (0x0059, 0x0301): 0x00DD,
  (0x0061, 0x0301): 0x00E1,
  (0x0065, 0x0301): 0x00E9,
  (0x0069, 0x0301): 0x00ED,
  (0x006F, 0x0301): 0x00F3,
  (0x0075, 0x0301): 0x00FA,
  (0x0079, 0x0301): 0x00FD,
  // Circumflex
  (0x0041, 0x0302): 0x00C2,
  (0x0045, 0x0302): 0x00CA,
  (0x0049, 0x0302): 0x00CE,
  (0x004F, 0x0302): 0x00D4,
  (0x0055, 0x0302): 0x00DB,
  (0x0061, 0x0302): 0x00E2,
  (0x0065, 0x0302): 0x00EA,
  (0x0069, 0x0302): 0x00EE,
  (0x006F, 0x0302): 0x00F4,
  (0x0075, 0x0302): 0x00FB,
  // Tilde
  (0x0041, 0x0303): 0x00C3,
  (0x004E, 0x0303): 0x00D1,
  (0x004F, 0x0303): 0x00D5,
  (0x0061, 0x0303): 0x00E3,
  (0x006E, 0x0303): 0x00F1,
  (0x006F, 0x0303): 0x00F5,
  // Breve / Dot above
  (0x0047, 0x0306): 0x011E,
  (0x0067, 0x0306): 0x011F,
  (0x0049, 0x0307): 0x0130,
  // Diaeresis
  (0x0041, 0x0308): 0x00C4,
  (0x0045, 0x0308): 0x00CB,
  (0x0049, 0x0308): 0x00CF,
  (0x004F, 0x0308): 0x00D6,
  (0x0055, 0x0308): 0x00DC,
  (0x0059, 0x0308): 0x0178,
  (0x0061, 0x0308): 0x00E4,
  (0x0065, 0x0308): 0x00EB,
  (0x0069, 0x0308): 0x00EF,
  (0x006F, 0x0308): 0x00F6,
  (0x0075, 0x0308): 0x00FC,
  (0x0079, 0x0308): 0x00FF,
  // Ring above / Cedilla
  (0x0041, 0x030A): 0x00C5,
  (0x0061, 0x030A): 0x00E5,
  (0x0043, 0x0327): 0x00C7,
  (0x0063, 0x0327): 0x00E7,
  (0x0053, 0x0327): 0x015E,
  (0x0073, 0x0327): 0x015F,
};

String _normalizeCommonNfc(String text) {
  if (_isAscii(text)) {
    return text;
  }
  final List<int> runes = text.runes.toList(growable: false);
  bool changed = false;
  final List<int> out = <int>[];
  int i = 0;
  while (i < runes.length) {
    int current = runes[i];
    while (i + 1 < runes.length) {
      final int? composed = _commonNfcCompositions[(current, runes[i + 1])];
      if (composed == null) {
        break;
      }
      current = composed;
      changed = true;
      i += 1;
    }
    out.add(current);
    i += 1;
  }
  return changed ? String.fromCharCodes(out) : text;
}

final RegExp _unicodeWordPattern = RegExp(
  r'[\p{L}\p{N}_][\p{L}\p{N}\p{M}_]*',
  unicode: true,
);

Set<String> _extractWordsLower(String text) {
  final String normalized = _normalizeCommonNfc(text);
  return _unicodeWordPattern
      .allMatches(normalized)
      .map((Match match) => match.group(0)!.toLowerCase())
      .toSet();
}

Set<String> _extractSearchableWords(String text) {
  final String normalized = _normalizeCommonNfc(text);
  final Set<String> words = <String>{};
  for (final Match match in _unicodeWordPattern.allMatches(normalized)) {
    final String word = match.group(0)!;
    words.add(word.toLowerCase());
    if (!_isAscii(word)) {
      // Split before lowercasing: `'İ'.toLowerCase()` expands to `'i\u0307'`,
      // where `\u0307` is not Latin, which would otherwise yield a stray `'i'`.
      final StringBuffer run = StringBuffer();
      bool? currentIsLatin;
      for (final int rune in word.runes) {
        final bool runeIsLatin = _isLatin(rune);
        if (currentIsLatin != null && runeIsLatin != currentIsLatin) {
          words.add(run.toString().toLowerCase());
          run.clear();
        }
        currentIsLatin = runeIsLatin;
        run.writeCharCode(rune);
      }
      if (run.isNotEmpty) {
        words.add(run.toString().toLowerCase());
      }
    }
  }
  return words;
}
