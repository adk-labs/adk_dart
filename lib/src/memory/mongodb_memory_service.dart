/// MongoDB-backed memory service implementation for ADK.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

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

/// Supported retrieval modes for [MongoDbMemoryService].
const Set<String> mongoDbMemoryRetrievalModes = <String>{
  'keyword',
  'vector',
  'auto',
};

/// Default Google embedding model name used by [MongoDbMemoryService] in `'vector'` mode.
const String defaultMongoDbEmbeddingModelName = 'text-embedding-005';

/// Default embedding vector dimensions for [defaultMongoDbEmbeddingModelName].
const int defaultMongoDbEmbeddingDimensions = 768;

/// Default Voyage AI model name used by [MongoDbMemoryService] in `'auto'` mode.
const String defaultMongoDbAutoEmbeddingModel = 'voyage-4';

/// Default Atlas Vector Search index name used by [MongoDbMemoryService].
const String defaultMongoDbMemoryVectorIndexName = 'memory_vector_index';

const int _defaultNumCandidates = 100;
const int _maxNumCandidates = 10000;
const int _embedBatchSize = 100;
const int _indexAlreadyExistsCode = 68;
const String _memoriesRecallIndexName = 'app_user_keywords';
const String _memoriesTtlIndexName = 'memory_ttl';

final Expando<List<Map<String, Object?>>> _collectionSearchIndexes =
    Expando<List<Map<String, Object?>>>('mongoDbCollectionSearchIndexes');
final Expando<Map<String, Map<String, Object?>>> _collectionIndexOptions =
    Expando<Map<String, Map<String, Object?>>>('mongoDbCollectionIndexOptions');

/// Returns the search indexes registered on [collection] in memory.
List<Map<String, Object?>> getInMemoryMongoDbSearchIndexes(
  MongoDbSessionCollection collection,
) {
  return List<Map<String, Object?>>.unmodifiable(
    _collectionSearchIndexes[collection] ?? const <Map<String, Object?>>[],
  );
}

/// Seeds the search indexes registered on [collection] in memory.
void setInMemoryMongoDbSearchIndexes(
  MongoDbSessionCollection collection,
  List<Map<String, Object?>> indexes,
) {
  _collectionSearchIndexes[collection] = List<Map<String, Object?>>.from(
    indexes,
  );
}

/// Returns index options (such as `expireAfterSeconds`) recorded on [collection] in memory.
Map<String, Map<String, Object?>> getInMemoryMongoDbIndexOptions(
  MongoDbSessionCollection collection,
) {
  return Map<String, Map<String, Object?>>.unmodifiable(
    _collectionIndexOptions[collection] ??
        const <String, Map<String, Object?>>{},
  );
}

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

/// A MongoDB-backed memory service supporting keyword, vector, and auto-embedding retrieval.
///
/// Stores session events in a MongoDB collection and recalls them using:
/// - `'keyword'` (default): multikey index (`app_name`, `user_id`, `keywords`)
///   with intersection-size scoring.
/// - `'vector'`: embeds memories at ingest with [embeddingModelName] and recalls
///   with `$vectorSearch`.
/// - `'auto'`: Atlas Automated Embedding over the plain `text` field.
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
    this.retrievalMode = 'keyword',
    this.genaiClient,
    this.embeddingModelName = defaultMongoDbEmbeddingModelName,
    this.embeddingOutputDimensionality,
    this.autoEmbeddingModelName = defaultMongoDbAutoEmbeddingModel,
    this.vectorIndexName = defaultMongoDbMemoryVectorIndexName,
    this.memoryTtlDays,
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
    if (memoryTtlDays != null && memoryTtlDays! < 1) {
      throw ArgumentError.value(
        memoryTtlDays,
        'memoryTtlDays',
        'memoryTtlDays must be a positive integer or null (no expiry).',
      );
    }
    if (!mongoDbMemoryRetrievalModes.contains(retrievalMode)) {
      final List<String> sortedModes = mongoDbMemoryRetrievalModes.toList()
        ..sort();
      throw ArgumentError.value(
        retrievalMode,
        'retrievalMode',
        'retrievalMode must be one of $sortedModes, got "$retrievalMode".',
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

  /// Whether to create recommended recall and TTL indexes on first use.
  final bool ensureIndexes;

  /// Retrieval mode (`'keyword'`, `'vector'`, or `'auto'`).
  final String retrievalMode;

  /// Optional GenAI client used to embed memory texts and queries in `'vector'` mode.
  final Object? genaiClient;

  /// Google embedding model name for `'vector'` mode.
  final String embeddingModelName;

  /// Optional shortened embedding dimensionality for `'vector'` mode.
  final int? embeddingOutputDimensionality;

  /// Voyage AI model name for `'auto'` mode's `autoEmbed` index.
  final String autoEmbeddingModelName;

  /// Name of the vector search index used in `'vector'` and `'auto'` modes.
  final String vectorIndexName;

  /// Optional retention period in days before MongoDB's TTL monitor expires memories.
  final int? memoryTtlDays;

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
      if (retrievalMode == 'keyword') {
        await _createIndex(
          () => _memories.createIndex(
            const <(String, int)>[
              ('app_name', 1),
              ('user_id', 1),
              ('keywords', 1),
            ],
            name: _memoriesRecallIndexName,
          ),
        );
      } else {
        await _createIndex(_createVectorIndex);
      }
      await _createIndex(_createTtlIndex);
      _indexesEnsured = true;
      completer.complete();
    } catch (error) {
      _ensureIndexesFuture = null;
      unawaited(completer.future.catchError((Object _) {}));
      completer.completeError(error);
      rethrow;
    }
  }

  Future<void> _createIndex(Future<void> Function() create) async {
    try {
      await create();
    } catch (error) {
      if (_isIgnorableIndexError(error)) {
        return;
      }
      rethrow;
    }
  }

  Future<void> _createTtlIndex() async {
    if (memoryTtlDays == null) {
      return;
    }
    final dynamic dynMemories = _memories;
    try {
      await dynMemories.createIndex(
        const <(String, int)>[('expire_at', 1)],
        name: _memoriesTtlIndexName,
        expireAfterSeconds: 0,
      );
    } on NoSuchMethodError {
      await _memories.createIndex(
        const <(String, int)>[('expire_at', 1)],
        name: _memoriesTtlIndexName,
      );
    }
    final Map<String, Map<String, Object?>> optionsMap =
        _collectionIndexOptions[_memories] ??= <String, Map<String, Object?>>{};
    optionsMap[_memoriesTtlIndexName] = <String, Object?>{
      'expireAfterSeconds': 0,
    };
  }

  Future<void> _createVectorIndex() async {
    final dynamic dynDb = _db;
    try {
      final Object? rawNames = await dynDb.listCollectionNames(
        filter: <String, Object?>{'name': memoriesCollection},
      );
      final bool exists =
          rawNames is Iterable && rawNames.contains(memoriesCollection);
      if (!exists) {
        try {
          await dynDb.createCollection(memoriesCollection, checkExists: false);
        } catch (exc) {
          if (!_isErrorCode(exc, 48)) {
            rethrow;
          }
        }
      }
    } on NoSuchMethodError {
      // Standard MongoDbSessionDatabase creates collections on demand.
    }

    final Map<String, Object?> searchField = retrievalMode == 'vector'
        ? <String, Object?>{
            'type': 'vector',
            'path': 'embedding',
            'numDimensions':
                embeddingOutputDimensionality ??
                defaultMongoDbEmbeddingDimensions,
            'similarity': 'cosine',
          }
        : <String, Object?>{
            'type': 'autoEmbed',
            'modality': 'text',
            'path': 'text',
            'model': autoEmbeddingModelName,
          };

    Map<String, Object?>? existing;
    final dynamic dynMemories = _memories;
    try {
      final Object? rawExisting = await dynMemories.listSearchIndexes(
        vectorIndexName,
      );
      if (rawExisting is Iterable && rawExisting.isNotEmpty) {
        final Object? first = rawExisting.first;
        if (first is Map) {
          existing = first.map((Object? k, Object? v) => MapEntry('$k', v));
        }
      }
    } on NoSuchMethodError {
      final List<Map<String, Object?>> stored =
          _collectionSearchIndexes[_memories] ?? const <Map<String, Object?>>[];
      for (final Map<String, Object?> idx in stored) {
        if (idx['name'] == vectorIndexName) {
          existing = idx;
          break;
        }
      }
    }

    if (existing != null) {
      _checkVectorIndex(existing, searchField);
      return;
    }

    final Map<String, Object?> indexModel = <String, Object?>{
      'definition': <String, Object?>{
        'fields': <Map<String, Object?>>[
          searchField,
          <String, Object?>{'type': 'filter', 'path': 'app_name'},
          <String, Object?>{'type': 'filter', 'path': 'user_id'},
        ],
      },
      'name': vectorIndexName,
      'type': 'vectorSearch',
    };

    try {
      try {
        await dynMemories.createSearchIndex(model: indexModel);
      } on NoSuchMethodError {
        final List<Map<String, Object?>> stored =
            _collectionSearchIndexes[_memories] ??= <Map<String, Object?>>[];
        stored.add(indexModel);
      }
    } catch (exc) {
      if (!_isErrorCode(exc, _indexAlreadyExistsCode)) {
        rethrow;
      }
    }
  }

  void _checkVectorIndex(
    Map<String, Object?> existing,
    Map<String, Object?> searchField,
  ) {
    final Object? rawDef =
        existing['latestDefinition'] ?? existing['definition'];
    final Map<Object?, Object?> definition = rawDef is Map
        ? rawDef
        : const <Object?, Object?>{};
    final Object? rawFields = definition['fields'];
    Map<Object?, Object?> actual = const <Object?, Object?>{};
    if (rawFields is Iterable) {
      for (final Object? item in rawFields) {
        if (item is Map && item['path'] == searchField['path']) {
          actual = item;
          break;
        }
      }
    }
    final List<String> mismatched = <String>[];
    for (final String key in const <String>[
      'type',
      'numDimensions',
      'model',
    ]) {
      if (searchField.containsKey(key) && actual[key] != searchField[key]) {
        mismatched.add(
          '$key=${actual[key]} (expected ${searchField[key]})',
        );
      }
    }
    if (mismatched.isNotEmpty) {
      throw ArgumentError(
        "Vector index '$vectorIndexName' does not match this service's "
        "configuration: ${mismatched.join(', ')} on '${searchField['path']}'. "
        'Drop and recreate the index, or pass a different vectorIndexName.',
      );
    }
  }

  Future<List<List<double>>> _embedTexts(List<String> texts) async {
    final List<List<double>> vectors = <List<double>>[];
    for (int start = 0; start < texts.length; start += _embedBatchSize) {
      final int end = math.min(start + _embedBatchSize, texts.length);
      final List<String> batch = texts.sublist(start, end);
      List<List<double>>? batchVectors;
      if (genaiClient != null) {
        final dynamic dynClient = genaiClient;
        try {
          final Object? response = await dynClient.embedContent(
            model: embeddingModelName,
            contents: batch,
            outputDimensionality: embeddingOutputDimensionality,
          );
          batchVectors = _extractBatchEmbeddings(response);
        } on NoSuchMethodError {
          try {
            final Object? response = await dynClient.aio.models.embedContent(
              model: embeddingModelName,
              contents: batch,
              config: <String, Object?>{
                if (embeddingOutputDimensionality != null)
                  'output_dimensionality': embeddingOutputDimensionality,
              },
            );
            batchVectors = _extractBatchEmbeddings(response);
          } on NoSuchMethodError {
            // Fall through to single-query embedContent on custom clients.
            final List<List<double>> singleVectors = <List<double>>[];
            for (final String text in batch) {
              final Object? single = await dynClient.embedContent(
                model: embeddingModelName,
                query: text,
                outputDimensionality: embeddingOutputDimensionality,
              );
              if (single is Iterable) {
                singleVectors.add(
                  single
                      .whereType<num>()
                      .map((num n) => n.toDouble())
                      .toList(growable: false),
                );
              }
            }
            batchVectors = singleVectors;
          }
        } catch (ex) {
          throw StateError('Failed to embed memory texts: $ex');
        }
      } else {
        final int dims =
            embeddingOutputDimensionality ?? defaultMongoDbEmbeddingDimensions;
        batchVectors = batch
            .map((String text) => _deterministicEmbedding(text, dims))
            .toList(growable: false);
      }

      if (batchVectors == null || batchVectors.length != batch.length) {
        throw ArgumentError(
          'Model $embeddingModelName returned ${batchVectors?.length ?? 0} '
          'embeddings for ${batch.length} texts.',
        );
      }
      vectors.addAll(batchVectors);
    }
    return vectors;
  }

  Future<List<double>> _embedQueryText(String query) async {
    if (genaiClient != null) {
      final dynamic dynClient = genaiClient;
      try {
        final Object? result = await dynClient.embedContent(
          model: embeddingModelName,
          query: query,
          outputDimensionality: embeddingOutputDimensionality,
        );
        if (result is Iterable) {
          final List<double> vec = result
              .whereType<num>()
              .map((num n) => n.toDouble())
              .toList(growable: false);
          if (vec.isEmpty) {
            throw ArgumentError(
              'Model $embeddingModelName returned no embedding.',
            );
          }
          return vec;
        }
      } on NoSuchMethodError {
        // Try batch-style embedContent(contents: [query]).
      }
    }
    final List<List<double>> batch = await _embedTexts(<String>[query]);
    if (batch.isEmpty || batch.first.isEmpty) {
      throw ArgumentError('Model $embeddingModelName returned no embedding.');
    }
    return batch.first;
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
    final List<(Event, Content, String, List<Part>)> entries =
        <(Event, Content, String, List<Part>)>[];
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
      entries.add((event, content, text, visibleParts));
    }
    if (entries.isEmpty) {
      return;
    }

    List<List<double>>? embeddings;
    if (retrievalMode == 'vector') {
      embeddings = await _embedTexts(
        entries.map(((Event, Content, String, List<Part>) e) => e.$3).toList(),
      );
      final int expected =
          embeddingOutputDimensionality ?? defaultMongoDbEmbeddingDimensions;
      if (embeddings.any((List<double> v) => v.length != expected)) {
        throw ArgumentError(
          'Model $embeddingModelName returned embeddings that are not '
          '$expected-dimensional. Set embeddingOutputDimensionality to the '
          "model's output size and the vector index's numDimensions.",
        );
      }
    }

    final DateTime? expireAt = memoryTtlDays != null
        ? DateTime.now().toUtc().add(Duration(days: memoryTtlDays!))
        : null;

    final List<(Map<String, Object?>, Map<String, Object?>)> writes =
        <(Map<String, Object?>, Map<String, Object?>)>[];
    for (int i = 0; i < entries.length; i += 1) {
      final (Event event, Content content, String text, List<Part> visibleParts) =
          entries[i];
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
        'text': text,
        'content': _serializeContent(filteredContent),
        'timestamp': event.timestamp,
        'expire_at': ?expireAt,
      };
      if (retrievalMode == 'keyword') {
        final List<String> keywords = extractKeywords(text).toList()..sort();
        if (keywords.isEmpty) {
          continue;
        }
        doc['keywords'] = keywords;
      } else if (embeddings != null) {
        doc['embedding'] = embeddings[i];
      }
      writes.add((docId, doc));
    }

    await _ensureIndexesOnce();
    for (final (Map<String, Object?> docId, Map<String, Object?> doc) in writes) {
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
    if (query.trim().isEmpty) {
      return SearchMemoryResponse();
    }

    List<double>? queryVector;
    if (retrievalMode == 'vector') {
      queryVector = await _embedQueryText(query);
    }

    List<String>? queryKeywords;
    if (retrievalMode == 'keyword') {
      final Set<String> keywords = extractKeywords(query);
      if (keywords.isEmpty) {
        return SearchMemoryResponse();
      }
      queryKeywords = keywords.toList()..sort();
    }

    await _ensureIndexesOnce();

    final List<Map<String, Object?>> docs = retrievalMode == 'keyword'
        ? await _keywordSearchDocs(appName, userId, queryKeywords!)
        : await _vectorSearchDocs(appName, userId, query, queryVector);

    final List<MemoryEntry> memories = <MemoryEntry>[];
    final Set<(String?, String, String?)> seen = <(String?, String, String?)>{};

    for (final Map<String, Object?> doc in docs) {
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

  Future<List<Map<String, Object?>>> _keywordSearchDocs(
    String appName,
    String userId,
    List<String> queryKeywords,
  ) async {
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
      scoredDocs.add(
        _ScoredMemoryDoc(doc: doc, score: score.toDouble(), timestamp: timestamp),
      );
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
    return limitedDocs.map((_ScoredMemoryDoc e) => e.doc).toList();
  }

  Future<List<Map<String, Object?>>> _vectorSearchDocs(
    String appName,
    String userId,
    String query,
    List<double>? queryVector,
  ) async {
    final int numCandidates = math.min(
      math.max(maxResults * 10, _defaultNumCandidates),
      _maxNumCandidates,
    );
    final int limit = math.min(maxResults, _maxNumCandidates);
    final Map<String, Object?> stage = <String, Object?>{
      'index': vectorIndexName,
      'numCandidates': numCandidates,
      'limit': limit,
      'filter': <String, Object?>{'app_name': appName, 'user_id': userId},
      if (retrievalMode == 'auto') ...<String, Object?>{
        'path': 'text',
        'query': <String, Object?>{'text': query},
      } else ...<String, Object?>{
        'path': 'embedding',
        'queryVector': queryVector,
      },
    };
    final List<Map<String, Object?>> pipeline = <Map<String, Object?>>[
      <String, Object?>{r'$vectorSearch': stage},
      <String, Object?>{
        r'$project': <String, Object?>{'embedding': 0},
      },
    ];

    final dynamic dynMemories = _memories;
    try {
      final Object? raw = await dynMemories.aggregate(pipeline);
      if (raw is Iterable) {
        return raw
            .whereType<Map>()
            .map(
              (Map m) => m.map((Object? k, Object? v) => MapEntry('$k', v)),
            )
            .toList();
      }
    } on NoSuchMethodError {
      // Fall back to in-memory vector/auto search over _memories.find.
    }

    final List<Map<String, Object?>> candidateDocs = await _memories.find(
      <String, Object?>{'app_name': appName, 'user_id': userId},
    );
    final List<_ScoredMemoryDoc> scored = <_ScoredMemoryDoc>[];
    for (final Map<String, Object?> rawDoc in candidateDocs) {
      final Map<String, Object?> doc = Map<String, Object?>.from(rawDoc);
      double score = 0.0;
      if (retrievalMode == 'auto') {
        final String docText = '${doc['text'] ?? ''}';
        score = _textOverlapSimilarity(query, docText);
      } else if (queryVector != null && doc['embedding'] is Iterable) {
        final List<double> docVec = (doc['embedding'] as Iterable)
            .whereType<num>()
            .map((num n) => n.toDouble())
            .toList(growable: false);
        score = _cosineSimilarity(queryVector, docVec);
      }
      doc.remove('embedding');
      final double timestamp = doc['timestamp'] is num
          ? (doc['timestamp'] as num).toDouble()
          : 0.0;
      scored.add(_ScoredMemoryDoc(doc: doc, score: score, timestamp: timestamp));
    }
    scored.sort((_ScoredMemoryDoc a, _ScoredMemoryDoc b) {
      final int cmp = b.score.compareTo(a.score);
      if (cmp != 0) {
        return cmp;
      }
      return b.timestamp.compareTo(a.timestamp);
    });
    return scored
        .take(limit)
        .map((_ScoredMemoryDoc item) => item.doc)
        .toList();
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
  final double score;
  final double timestamp;
}

bool _isErrorCode(Object error, int code) {
  if (error is MongoDbOperationFailure) {
    return error.code == code;
  }
  try {
    return (error as dynamic).code == code;
  } catch (_) {
    return false;
  }
}

List<List<double>>? _extractBatchEmbeddings(Object? response) {
  if (response == null) {
    return null;
  }
  if (response is List) {
    final List<List<double>> vectors = <List<double>>[];
    for (final Object? item in response) {
      if (item is Iterable) {
        vectors.add(
          item
              .whereType<num>()
              .map((num n) => n.toDouble())
              .toList(growable: false),
        );
      } else if (item is Map && item['values'] is Iterable) {
        vectors.add(
          (item['values'] as Iterable)
              .whereType<num>()
              .map((num n) => n.toDouble())
              .toList(growable: false),
        );
      }
    }
    return vectors;
  }
  if (response is Map && response['embeddings'] is Iterable) {
    return _extractBatchEmbeddings(
      (response['embeddings'] as Iterable).toList(),
    );
  }
  try {
    final Object? embeddings = (response as dynamic).embeddings;
    if (embeddings is Iterable) {
      final List<List<double>> vectors = <List<double>>[];
      for (final Object? emb in embeddings) {
        if (emb is Iterable) {
          vectors.add(
            emb
                .whereType<num>()
                .map((num n) => n.toDouble())
                .toList(growable: false),
          );
        } else if (emb is Map && emb['values'] is Iterable) {
          vectors.add(
            (emb['values'] as Iterable)
                .whereType<num>()
                .map((num n) => n.toDouble())
                .toList(growable: false),
          );
        } else {
          final Object? values = (emb as dynamic).values;
          if (values is Iterable) {
            vectors.add(
              values
                  .whereType<num>()
                  .map((num n) => n.toDouble())
                  .toList(growable: false),
            );
          } else {
            vectors.add(const <double>[]);
          }
        }
      }
      return vectors;
    }
  } catch (_) {}
  return null;
}

List<double> _deterministicEmbedding(String text, int dims) {
  final List<double> vector = List<double>.filled(dims, 0.0);
  final List<int> units = utf8.encode(text.toLowerCase());
  for (int i = 0; i < units.length; i += 1) {
    vector[i % dims] += (units[i] / 255.0);
  }
  double norm = 0.0;
  for (final double v in vector) {
    norm += v * v;
  }
  if (norm > 0) {
    final double scale = 1.0 / math.sqrt(norm);
    for (int i = 0; i < dims; i += 1) {
      vector[i] = double.parse((vector[i] * scale).toStringAsFixed(6));
    }
  }
  return vector;
}

double _cosineSimilarity(List<double> a, List<double> b) {
  final int len = math.min(a.length, b.length);
  if (len == 0) {
    return 0.0;
  }
  double dot = 0.0;
  double normA = 0.0;
  double normB = 0.0;
  for (int i = 0; i < len; i += 1) {
    dot += a[i] * b[i];
    normA += a[i] * a[i];
    normB += b[i] * b[i];
  }
  if (normA <= 0 || normB <= 0) {
    return 0.0;
  }
  return dot / (math.sqrt(normA) * math.sqrt(normB));
}

double _textOverlapSimilarity(String query, String target) {
  final Set<String> qWords = _wordRegExp
      .allMatches(query.toLowerCase())
      .map((RegExpMatch m) => m.group(0)!)
      .toSet();
  if (qWords.isEmpty) {
    return 0.0;
  }
  final Set<String> tWords = _wordRegExp
      .allMatches(target.toLowerCase())
      .map((RegExpMatch m) => m.group(0)!)
      .toSet();
  final int matched = qWords.intersection(tWords).length;
  return matched / qWords.length;
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
