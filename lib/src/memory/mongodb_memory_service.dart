/// MongoDB-backed memory service implementation for ADK.
library;

import 'dart:async';

import '../events/event.dart';
import '../features/_feature_registry.dart';
import '../sessions/mongodb_session_service.dart';
import '../sessions/session.dart';
import '../types/content.dart';
import '_utils.dart';
import 'base_memory_service.dart';
import 'memory_entry.dart';

/// Default MongoDB collection name used by [MongoDbMemoryService].
const String defaultMemoriesCollection = 'memories';

/// Default English stop words filtered out during keyword extraction.
const Set<String> defaultStopWords = <String>{
  'a',
  'an',
  'and',
  'are',
  'as',
  'at',
  'be',
  'but',
  'by',
  'for',
  'from',
  'has',
  'have',
  'how',
  'i',
  'if',
  'in',
  'into',
  'is',
  'it',
  'its',
  'me',
  'my',
  'of',
  'on',
  'or',
  'our',
  'so',
  'that',
  'the',
  'their',
  'this',
  'to',
  'was',
  'we',
  'what',
  'when',
  'where',
  'which',
  'who',
  'will',
  'with',
  'you',
  'your',
};

const String _unknownSessionId = '__unknown_session_id__';

final RegExp _wordRegExp = RegExp(r'[\p{L}\p{N}_]+', unicode: true);

/// Exception representing a MongoDB server operation failure with an error [code].
class MongoDbOperationFailure implements Exception {
  /// Creates an operation failure with [message] and optional [code] / [codeName].
  const MongoDbOperationFailure(
    this.message, {
    this.code,
    this.codeName,
  });

  /// Human-readable error message.
  final String message;

  /// Numeric MongoDB server error code (e.g. `85` for `IndexOptionsConflict`, `13` for `Unauthorized`).
  final int? code;

  /// Symbolic MongoDB error code name.
  final String? codeName;

  @override
  String toString() =>
      'MongoDbOperationFailure(code: $code, codeName: $codeName, message: $message)';
}

/// A MongoDB-backed memory service using keyword matching.
///
/// Stores session events in a MongoDB collection with extracted keywords in an
/// array field, and uses a multikey index (`app_name`, `user_id`, `keywords`)
/// with intersection-size scoring to rank matching memories.
class MongoDbMemoryService extends BaseMemoryService {
  /// Creates a [MongoDbMemoryService].
  ///
  /// Exactly one of [connectionString] or [mongoClient] must be provided.
  MongoDbMemoryService({
    required String databaseName,
    String? connectionString,
    MongoDbSessionClient? mongoClient,
    String memoriesCollection = defaultMemoriesCollection,
    Set<String>? stopWords,
    this.maxResults = 50,
    this.ensureIndexes = true,
  }) : databaseName = databaseName.trim(),
       memoriesCollection = memoriesCollection.trim(),
       _stopWords = stopWords == null
           ? defaultStopWords
           : stopWords.map((String w) => w.toLowerCase()).toSet() {
    warnFeatureUse(FeatureName.mongodbMemoryService);

    if (maxResults <= 0) {
      throw ArgumentError.value(
        maxResults,
        'maxResults',
        'maxResults must be a positive integer.',
      );
    }
    if (this.databaseName.isEmpty) {
      throw ArgumentError.value(
        databaseName,
        'databaseName',
        'databaseName must be a non-empty string.',
      );
    }
    if (this.memoriesCollection.isEmpty) {
      throw ArgumentError.value(
        memoriesCollection,
        'memoriesCollection',
        'memoriesCollection must be a non-empty string.',
      );
    }
    if ((connectionString == null) == (mongoClient == null)) {
      throw ArgumentError(
        'Provide exactly one of connectionString or mongoClient.',
      );
    }
    if (connectionString != null && connectionString.trim().isEmpty) {
      throw ArgumentError.value(
        connectionString,
        'connectionString',
        'connectionString must be a non-empty string.',
      );
    }

    if (mongoClient != null) {
      _client = mongoClient;
      _ownsClient = false;
    } else {
      _client = createMongoDbClientFromUrl(connectionString!.trim());
      _ownsClient = true;
    }

    _db = _client.database(this.databaseName);
    _memories = _db.collection(this.memoriesCollection);
  }

  /// Name of the MongoDB database used to store memories.
  final String databaseName;

  /// Name of the collection used to store memory documents.
  final String memoriesCollection;

  /// Maximum number of memories returned by [searchMemory].
  final int maxResults;

  /// Whether to create the `(app_name, user_id, keywords)` multikey index on first search.
  final bool ensureIndexes;

  final Set<String> _stopWords;
  late final MongoDbSessionClient _client;
  late final bool _ownsClient;
  late final MongoDbSessionDatabase _db;
  late final MongoDbSessionCollection _memories;

  bool _indexesEnsured = false;
  Future<void>? _ensureIndexesFuture;

  /// Underlying MongoDB client.
  MongoDbSessionClient get client => _client;

  /// Whether this service owns [client] and closes it in [close].
  bool get ownsClient => _ownsClient;

  /// Extracts lowercase keywords from [text] and filters stop words.
  ///
  /// For mixed-script tokens (for example Latin characters combined with CJK
  /// characters without whitespace), both the full token and contiguous Latin
  /// and non-Latin character runs are extracted.
  Set<String> extractKeywords(String text) {
    final Set<String> keywords = <String>{};
    for (final RegExpMatch match in _wordRegExp.allMatches(text)) {
      final String word = match.group(0)!;
      keywords.add(word.toLowerCase());
      if (!_isAscii(word)) {
        for (final String part in _splitByLatinScript(word)) {
          if (part.isNotEmpty) {
            keywords.add(part.toLowerCase());
          }
        }
      }
    }
    keywords.removeAll(_stopWords);
    return keywords;
  }

  Future<void> _ensureIndexesOnce() async {
    if (_indexesEnsured || !ensureIndexes) {
      return;
    }
    if (_ensureIndexesFuture != null) {
      await _ensureIndexesFuture;
      return;
    }
    final Completer<void> completer = Completer<void>();
    _ensureIndexesFuture = completer.future;
    try {
      await _memories.createIndex(
        const <(String, int)>[
          ('app_name', 1),
          ('user_id', 1),
          ('keywords', 1),
        ],
        name: 'app_user_keywords',
      );
      _indexesEnsured = true;
      completer.complete();
    } catch (error) {
      if (_isIgnorableIndexError(error)) {
        _indexesEnsured = true;
        completer.complete();
        return;
      }
      _ensureIndexesFuture = null;
      unawaited(completer.future.catchError((Object _) {}));
      completer.completeError(error);
      rethrow;
    }
  }

  @override
  Future<void> addSessionToMemory(
    Session session, {
    Map<String, Object?>? customMetadata,
  }) async {
    await addEventsToMemory(
      appName: session.appName,
      userId: session.userId,
      events: session.events,
      sessionId: session.id,
      customMetadata: customMetadata,
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
    final String scopedSessionId = sessionId ?? _unknownSessionId;
    for (final Event event in events) {
      final Content? content = event.content;
      if (content == null || content.parts.isEmpty) {
        continue;
      }
      final List<Part> visibleParts = content.parts
          .where((Part part) => !part.thought)
          .toList(growable: false);
      if (visibleParts.isEmpty) {
        continue;
      }
      final String text = visibleParts
          .where((Part part) => part.text != null && part.text!.isNotEmpty)
          .map((Part part) => part.text!)
          .join(' ');
      if (text.isEmpty) {
        continue;
      }
      final List<String> keywords = extractKeywords(text).toList()..sort();
      if (keywords.isEmpty) {
        continue;
      }

      final Content filteredContent = Content(
        role: content.role,
        parts: visibleParts.map((Part part) => part.copyWith()).toList(),
      );
      final Map<String, Object?> docId = <String, Object?>{
        'app_name': appName,
        'user_id': userId,
        'session_id': scopedSessionId,
        'event_id': event.id,
      };
      final Map<String, Object?> doc = <String, Object?>{
        '_id': docId,
        'app_name': appName,
        'user_id': userId,
        'session_id': scopedSessionId,
        'author': event.author,
        'keywords': keywords,
        'content': _serializeContent(filteredContent),
        'timestamp': event.timestamp,
      };
      await _memories.updateOne(
        <String, Object?>{'_id': docId},
        <String, Object?>{r'$set': doc},
        upsert: true,
      );
    }
  }

  @override
  Future<SearchMemoryResponse> searchMemory({
    required String appName,
    required String userId,
    required String query,
  }) async {
    final List<String> queryKeywords = extractKeywords(query).toList()..sort();
    if (queryKeywords.isEmpty) {
      return SearchMemoryResponse();
    }

    await _ensureIndexesOnce();

    final List<Map<String, Object?>> matchedDocs = await _memories.find(
      <String, Object?>{
        'app_name': appName,
        'user_id': userId,
        'keywords': <String, Object?>{r'$in': queryKeywords},
      },
      projection: const <String, Object?>{
        '_id': 0,
        'content': 1,
        'author': 1,
        'timestamp': 1,
        'keywords': 1,
      },
    );

    final Set<String> queryKeywordSet = queryKeywords.toSet();
    final List<_ScoredMemoryDoc> scoredDocs = <_ScoredMemoryDoc>[];
    for (final Map<String, Object?> doc in matchedDocs) {
      final Object? rawKeywords = doc['keywords'];
      int score = 0;
      if (rawKeywords is Iterable) {
        final Set<String> docKeywordSet = rawKeywords
            .map((Object? item) => '$item')
            .toSet();
        score = docKeywordSet.intersection(queryKeywordSet).length;
      }
      final double timestamp = doc['timestamp'] is num
          ? (doc['timestamp'] as num).toDouble()
          : 0.0;
      scoredDocs.add(_ScoredMemoryDoc(doc: doc, score: score, timestamp: timestamp));
    }

    scoredDocs.sort((_ScoredMemoryDoc a, _ScoredMemoryDoc b) {
      final int scoreCompare = b.score.compareTo(a.score);
      if (scoreCompare != 0) {
        return scoreCompare;
      }
      return b.timestamp.compareTo(a.timestamp);
    });

    final List<_ScoredMemoryDoc> limitedDocs = scoredDocs.length > maxResults
        ? scoredDocs.sublist(0, maxResults)
        : scoredDocs;

    final List<MemoryEntry> memories = <MemoryEntry>[];
    final Set<(String?, String, String?)> seen = <(String?, String, String?)>{};

    for (final _ScoredMemoryDoc item in limitedDocs) {
      final Map<String, Object?> doc = item.doc;
      final Object? rawContent = doc['content'];
      if (rawContent is! Map) {
        continue;
      }
      final Content content = _deserializeContent(rawContent);
      final double? timestampNum = doc['timestamp'] is num
          ? (doc['timestamp'] as num).toDouble()
          : null;
      final MemoryEntry entry = MemoryEntry(
        content: content,
        author: doc['author']?.toString(),
        timestamp: timestampNum != null ? formatTimestamp(timestampNum) : null,
      );
      final String contentText = (entry.content.parts)
          .where((Part part) => part.text != null && part.text!.isNotEmpty)
          .map((Part part) => part.text!)
          .join(' ');
      final (String?, String, String?) dedupKey = (
        entry.author,
        contentText,
        entry.timestamp,
      );
      if (seen.contains(dedupKey)) {
        continue;
      }
      seen.add(dedupKey);
      memories.add(entry);
    }

    return SearchMemoryResponse(memories: memories);
  }

  /// Closes the underlying MongoDB client if owned by this service.
  Future<void> close() async {
    if (_ownsClient) {
      await _client.close();
    }
  }
}

class _ScoredMemoryDoc {
  const _ScoredMemoryDoc({
    required this.doc,
    required this.score,
    required this.timestamp,
  });

  final Map<String, Object?> doc;
  final int score;
  final double timestamp;
}

bool _isAscii(String value) {
  for (int i = 0; i < value.length; i += 1) {
    if (value.codeUnitAt(i) > 0x7F) {
      return false;
    }
  }
  return true;
}

bool _isLatinRune(int rune) {
  if ((rune >= 0x30 && rune <= 0x39) ||
      (rune >= 0x41 && rune <= 0x5A) ||
      (rune >= 0x61 && rune <= 0x7A) ||
      rune == 0x5F) {
    return true;
  }
  // Latin-1 Supplement letters, Latin Extended-A/B, IPA, Phonetic, Latin Extended Additional,
  // Latin Extended-C/D/E, Fullwidth Latin letters.
  return (rune >= 0x00C0 && rune <= 0x00D6) ||
      (rune >= 0x00D8 && rune <= 0x00F6) ||
      (rune >= 0x00F8 && rune <= 0x02AF) ||
      (rune >= 0x1D00 && rune <= 0x1DBF) ||
      (rune >= 0x1E00 && rune <= 0x1EFF) ||
      (rune >= 0x2C60 && rune <= 0x2C7F) ||
      (rune >= 0xA720 && rune <= 0xA7FF) ||
      (rune >= 0xAB30 && rune <= 0xAB6F) ||
      (rune >= 0xFF21 && rune <= 0xFF3A) ||
      (rune >= 0xFF41 && rune <= 0xFF5A);
}

List<String> _splitByLatinScript(String word) {
  final List<String> parts = <String>[];
  StringBuffer? current;
  bool? currentIsLatin;
  for (final int rune in word.runes) {
    final bool isLatin = _isLatinRune(rune);
    if (currentIsLatin == null || currentIsLatin != isLatin) {
      if (current != null && current.isNotEmpty) {
        parts.add(current.toString());
      }
      current = StringBuffer();
      currentIsLatin = isLatin;
    }
    current!.writeCharCode(rune);
  }
  if (current != null && current.isNotEmpty) {
    parts.add(current.toString());
  }
  return parts;
}

bool _isIgnorableIndexError(Object error) {
  if (error is MongoDbOperationFailure) {
    if (error.code == 85 ||
        error.code == 86 ||
        error.code == 13 ||
        error.codeName == 'IndexOptionsConflict' ||
        error.codeName == 'IndexKeySpecsConflict' ||
        error.codeName == 'Unauthorized') {
      return true;
    }
  }
  final String message = '$error'.toLowerCase();
  return message.contains('indexoptionsconflict') ||
      message.contains('indexkeyspecsconflict') ||
      message.contains('already exists with different options') ||
      message.contains('not authorized') ||
      message.contains('unauthorized');
}

Map<String, Object?> _serializeContent(Content content) {
  return <String, Object?>{
    if (content.role != null) 'role': content.role,
    'parts': content.parts
        .map(
          (Part part) => <String, Object?>{
            if (part.text != null) 'text': part.text,
            if (part.thought) 'thought': part.thought,
          },
        )
        .toList(growable: false),
  };
}

Content _deserializeContent(Map<Object?, Object?> map) {
  final String? role = map['role']?.toString();
  final List<Part> parts = <Part>[];
  final Object? rawParts = map['parts'];
  if (rawParts is Iterable) {
    for (final Object? item in rawParts) {
      if (item is Map) {
        parts.add(
          Part(
            text: item['text']?.toString(),
            thought: item['thought'] == true,
          ),
        );
      }
    }
  }
  return Content(role: role, parts: parts);
}
