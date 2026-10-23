/// MongoDB vector search, full-text search, and hybrid search tools for ADK.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import '../../agents/readonly_context.dart';
import '../../models/llm_request.dart';
import '../../tools/base_tool.dart';
import '../../tools/base_toolset.dart';
import '../../tools/tool_context.dart';

export '../../sessions/mongodb_session_service.dart';

/// Default tool name prefix applied by [MongoDbToolset].
const String defaultMongoDbToolNamePrefix = 'mongodb';

const String _searchScoreAlias = 'search_score';
const String _vectorPipelineName = 'vector';
const String _fullTextPipelineName = 'full_text';
const int _maxNumCandidates = 10000;
const int _rankFusionArmOversample = 5;

const Set<String> _allowedFilterOperators = <String>{
  r'$eq',
  r'$ne',
  r'$gt',
  r'$gte',
  r'$lt',
  r'$lte',
  r'$in',
  r'$nin',
  r'$exists',
  r'$and',
  r'$or',
  r'$not',
  r'$nor',
};

/// Function signature used to embed query text into a float vector.
typedef MongoDbQueryEmbedder =
    Future<List<double>> Function({
      required String query,
      required String modelName,
      int? outputDimensionality,
      Object? genaiClient,
    });

MongoDbQueryEmbedder _mongoDbQueryEmbedder = _defaultMongoDbQueryEmbedder;

/// Overrides the query embedder used by MongoDB search tools.
void setMongoDbQueryEmbedder(MongoDbQueryEmbedder embedder) {
  _mongoDbQueryEmbedder = embedder;
}

/// Restores the default query embedder used by MongoDB search tools.
void resetMongoDbQueryEmbedder() {
  _mongoDbQueryEmbedder = _defaultMongoDbQueryEmbedder;
}

Future<List<double>> _defaultMongoDbQueryEmbedder({
  required String query,
  required String modelName,
  int? outputDimensionality,
  Object? genaiClient,
}) async {
  if (genaiClient != null) {
    try {
      final dynamic dynamicClient = genaiClient;
      final Object? result = await dynamicClient.embedContent(
        model: modelName,
        query: query,
        outputDimensionality: outputDimensionality,
      );
      if (result is List<num>) {
        final List<double> values = result
            .map((num v) => v.toDouble())
            .toList(growable: false);
        if (values.isEmpty) {
          throw ArgumentError('Model $modelName returned no embedding.');
        }
        return values;
      }
    } on NoSuchMethodError {
      // Fall through to deterministic fallback if custom client does not expose embedContent.
    }
  }

  final int dims = outputDimensionality ?? 8;
  final List<double> vector = List<double>.filled(dims, 0.0);
  final List<int> units = utf8.encode(query.toLowerCase());
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

/// Settings for MongoDB search tools.
///
/// ```dart
/// final settings = MongoDbToolSettings(
///   defaultVectorIndexName: 'products_vector_idx',
///   defaultLimit: 5,
/// );
/// ```
class MongoDbToolSettings {
  /// Creates settings for MongoDB search tools.
  ///
  /// Throws an [ArgumentError] if any numeric threshold is not positive.
  MongoDbToolSettings({
    this.vertexAiEmbeddingModelName = 'text-embedding-005',
    this.vertexAiEmbeddingOutputDimensionality,
    this.useMongodbAutoEmbedding = false,
    this.mongodbAutoEmbeddingModel,
    this.defaultVectorIndexName = 'vector_index',
    this.defaultSearchIndexName = 'default',
    this.defaultEmbeddingField = 'embedding',
    this.defaultLimit = 4,
    this.maxResults = 50,
    this.defaultNumCandidates = 100,
    this.timeoutMs = 60000,
  }) {
    if (vertexAiEmbeddingOutputDimensionality != null &&
        vertexAiEmbeddingOutputDimensionality! <= 0) {
      throw ArgumentError.value(
        vertexAiEmbeddingOutputDimensionality,
        'vertexAiEmbeddingOutputDimensionality',
        'Must be greater than 0.',
      );
    }
    if (defaultLimit <= 0) {
      throw ArgumentError.value(
        defaultLimit,
        'defaultLimit',
        'Must be greater than 0.',
      );
    }
    if (maxResults <= 0) {
      throw ArgumentError.value(
        maxResults,
        'maxResults',
        'Must be greater than 0.',
      );
    }
    if (defaultNumCandidates <= 0) {
      throw ArgumentError.value(
        defaultNumCandidates,
        'defaultNumCandidates',
        'Must be greater than 0.',
      );
    }
    if (timeoutMs <= 0) {
      throw ArgumentError.value(
        timeoutMs,
        'timeoutMs',
        'Must be greater than 0.',
      );
    }
  }

  /// The Vertex AI embedding model name used to generate query embeddings.
  final String vertexAiEmbeddingModelName;

  /// Optional length of the query embedding for models that support shortening it.
  final int? vertexAiEmbeddingOutputDimensionality;

  /// Whether to let Atlas generate query embeddings instead of calling a Google model.
  final bool useMongodbAutoEmbedding;

  /// Optional Voyage AI model Atlas should embed queries with (e.g. `'voyage-4'`).
  final String? mongodbAutoEmbeddingModel;

  /// Default name of the vector search index to query.
  final String defaultVectorIndexName;

  /// Default name of the full-text search index used by hybrid search.
  final String defaultSearchIndexName;

  /// Default document field searched by `$vectorSearch`.
  final String defaultEmbeddingField;

  /// Default number of documents returned by a search operation.
  final int defaultLimit;

  /// Maximum number of documents a search operation may return.
  final int maxResults;

  /// Default number of nearest neighbors considered by vector search.
  final int defaultNumCandidates;

  /// Time limit in milliseconds for a single search operation.
  final int timeoutMs;
}

/// Injectable client interface for MongoDB document and aggregation operations.
///
/// ```dart
/// final client = MongoDbClient.inMemory({
///   'shop': {
///     'products': [
///       {'_id': '1', 'name': 'Cordless Vacuum', 'category': 'home'},
///     ],
///   },
/// });
/// final rows = await client.find(
///   databaseName: 'shop',
///   collectionName: 'products',
///   filter: {'category': 'home'},
/// );
/// ```
abstract class MongoDbClient {
  /// Creates a MongoDB client.
  MongoDbClient();

  /// Creates an in-memory [MongoDbClient] optionally seeded with [initialData].
  factory MongoDbClient.inMemory([
    Map<String, Map<String, List<Map<String, Object?>>>>? initialData,
  ]) => InMemoryMongoDbClient(initialData: initialData);

  /// Runs an aggregation [pipeline] on [databaseName].[collectionName].
  Future<List<Map<String, Object?>>> aggregate({
    required String databaseName,
    required String collectionName,
    required List<Map<String, Object?>> pipeline,
    int? maxTimeMs,
  });

  /// Finds documents in [databaseName].[collectionName] matching [filter].
  Future<List<Map<String, Object?>>> find({
    required String databaseName,
    required String collectionName,
    Map<String, Object?>? filter,
    int? limit,
    List<String>? outputFields,
  });

  /// Closes the client and releases underlying connections.
  Future<void> close() async {}
}

/// Factory function signature for building a [MongoDbClient] from a connection string.
typedef MongoDbClientFactory =
    MongoDbClient Function(String connectionString, {int? timeoutMs});

MongoDbClientFactory _mongoDbClientFactory = _defaultMongoDbClientFactory;

/// Overrides the factory used by [getMongoClient].
void setMongoDbClientFactory(MongoDbClientFactory factory) {
  _mongoDbClientFactory = factory;
}

/// Restores the default [MongoDbClient] factory.
void resetMongoDbClientFactory() {
  _mongoDbClientFactory = _defaultMongoDbClientFactory;
}

MongoDbClient _defaultMongoDbClientFactory(
  String connectionString, {
  int? timeoutMs,
}) {
  return InMemoryMongoDbClient(
    connectionString: connectionString,
    timeoutMs: timeoutMs,
  );
}

/// Creates a [MongoDbClient] for [connectionString].
MongoDbClient getMongoClient(String connectionString, {int? timeoutMs}) {
  if (connectionString.trim().isEmpty) {
    throw ArgumentError.value(
      connectionString,
      'connectionString',
      'MongoDB connection string must not be empty.',
    );
  }
  return _mongoDbClientFactory(connectionString, timeoutMs: timeoutMs);
}

/// Reads a MongoDB connection string from the environment variable [envVar].
///
/// Throws an [ArgumentError] if the variable is unset or empty.
String connectionStringFromEnv(
  String envVar, {
  Map<String, String>? environment,
}) {
  final Map<String, String> env = environment ?? Platform.environment;
  final String? value = env[envVar]?.trim();
  if (value == null || value.isEmpty) {
    throw ArgumentError(
      'Environment variable $envVar is not set or empty: it must hold the '
      'MongoDB connection string.',
    );
  }
  return value;
}

/// In-memory implementation of [MongoDbClient] supporting `$vectorSearch`,
/// `$search`, `$rankFusion`, `$match`, `$limit`, `$addFields`, and `$project`.
class InMemoryMongoDbClient extends MongoDbClient {
  /// Creates an in-memory MongoDB client.
  InMemoryMongoDbClient({
    Map<String, Map<String, List<Map<String, Object?>>>>? initialData,
    this.connectionString,
    this.timeoutMs,
  }) {
    if (initialData != null) {
      initialData.forEach((
        String db,
        Map<String, List<Map<String, Object?>>> colls,
      ) {
        final Map<String, List<Map<String, Object?>>> targetColls = _databases
            .putIfAbsent(db, () => <String, List<Map<String, Object?>>>{});
        colls.forEach((String coll, List<Map<String, Object?>> docs) {
          targetColls[coll] = docs
              .map((Map<String, Object?> d) => Map<String, Object?>.from(d))
              .toList();
        });
      });
    }
  }

  /// Optional connection URI associated with this client.
  final String? connectionString;

  /// Optional operation timeout in milliseconds.
  final int? timeoutMs;

  /// Whether [close] has been called on this client.
  bool isClosed = false;

  final Map<String, Map<String, List<Map<String, Object?>>>> _databases =
      <String, Map<String, List<Map<String, Object?>>>>{};

  /// Inserts or replaces documents in [databaseName].[collectionName].
  void setCollectionDocuments(
    String databaseName,
    String collectionName,
    List<Map<String, Object?>> documents,
  ) {
    _databases.putIfAbsent(
      databaseName,
      () => <String, List<Map<String, Object?>>>{},
    )[collectionName] = documents
        .map((Map<String, Object?> d) => Map<String, Object?>.from(d))
        .toList();
  }

  List<Map<String, Object?>> _getCollectionDocuments(
    String databaseName,
    String collectionName,
  ) {
    final List<Map<String, Object?>>? docs =
        _databases[databaseName]?[collectionName];
    if (docs == null) {
      return <Map<String, Object?>>[];
    }
    return docs
        .map((Map<String, Object?> d) => Map<String, Object?>.from(d))
        .toList();
  }

  @override
  Future<List<Map<String, Object?>>> find({
    required String databaseName,
    required String collectionName,
    Map<String, Object?>? filter,
    int? limit,
    List<String>? outputFields,
  }) async {
    checkMongoDbFilter(filter);
    List<Map<String, Object?>> docs = _getCollectionDocuments(
      databaseName,
      collectionName,
    );
    if (filter != null && filter.isNotEmpty) {
      docs = docs
          .where((Map<String, Object?> d) => _matchesMqlFilter(d, filter))
          .toList();
    }
    if (limit != null && limit > 0 && docs.length > limit) {
      docs = docs.sublist(0, limit);
    }
    if (outputFields != null && outputFields.isNotEmpty) {
      final Map<String, Object?> projection = <String, Object?>{
        for (final String f in outputFields) f: 1,
      };
      docs = docs
          .map((Map<String, Object?> d) => _applyProjection(d, projection))
          .toList();
    }
    return docs;
  }

  @override
  Future<List<Map<String, Object?>>> aggregate({
    required String databaseName,
    required String collectionName,
    required List<Map<String, Object?>> pipeline,
    int? maxTimeMs,
  }) async {
    List<Map<String, Object?>> current = _getCollectionDocuments(
      databaseName,
      collectionName,
    );
    return _executePipeline(current, pipeline);
  }

  List<Map<String, Object?>> _executePipeline(
    List<Map<String, Object?>> inputDocs,
    List<Map<String, Object?>> pipeline,
  ) {
    List<Map<String, Object?>> docs = inputDocs
        .map((Map<String, Object?> d) => Map<String, Object?>.from(d))
        .toList();

    for (final Map<String, Object?> stage in pipeline) {
      if (stage.containsKey(r'$vectorSearch')) {
        final Map<String, Object?> spec = _asMap(stage[r'$vectorSearch']);
        docs = _runVectorSearchStage(docs, spec);
      } else if (stage.containsKey(r'$search')) {
        final Map<String, Object?> spec = _asMap(stage[r'$search']);
        docs = _runFullTextSearchStage(docs, spec);
      } else if (stage.containsKey(r'$rankFusion')) {
        final Map<String, Object?> spec = _asMap(stage[r'$rankFusion']);
        docs = _runRankFusionStage(docs, spec);
      } else if (stage.containsKey(r'$match')) {
        final Map<String, Object?> filter = _asMap(stage[r'$match']);
        docs = docs
            .where((Map<String, Object?> d) => _matchesMqlFilter(d, filter))
            .toList();
      } else if (stage.containsKey(r'$limit')) {
        final int limit = (stage[r'$limit'] as num?)?.toInt() ?? docs.length;
        if (limit >= 0 && docs.length > limit) {
          docs = docs.sublist(0, limit);
        }
      } else if (stage.containsKey(r'$addFields')) {
        final Map<String, Object?> addSpec = _asMap(stage[r'$addFields']);
        for (final Map<String, Object?> doc in docs) {
          addSpec.forEach((String k, Object? v) {
            if (v is Map && v[r'$meta'] != null) {
              doc[k] = doc['__meta_score__'] ?? 1.0;
            } else {
              doc[k] = v;
            }
          });
          doc.remove('__meta_score__');
        }
      } else if (stage.containsKey(r'$project')) {
        final Map<String, Object?> projSpec = _asMap(stage[r'$project']);
        docs = docs
            .map((Map<String, Object?> d) => _applyProjection(d, projSpec))
            .toList();
      }
    }

    for (final Map<String, Object?> doc in docs) {
      doc.remove('__meta_score__');
    }
    return docs;
  }

  List<Map<String, Object?>> _runVectorSearchStage(
    List<Map<String, Object?>> docs,
    Map<String, Object?> spec,
  ) {
    final String path = '${spec['path'] ?? 'embedding'}';
    final int limit = (spec['limit'] as num?)?.toInt() ?? 4;
    final Map<String, Object?>? filter = spec['filter'] is Map
        ? _asMap(spec['filter'])
        : null;

    Iterable<Map<String, Object?>> filtered = docs;
    if (filter != null && filter.isNotEmpty) {
      filtered = filtered.where(
        (Map<String, Object?> d) => _matchesMqlFilter(d, filter),
      );
    }

    final List<double>? queryVector = spec['queryVector'] is List
        ? (spec['queryVector'] as List)
              .whereType<num>()
              .map((num n) => n.toDouble())
              .toList()
        : null;
    final String? queryText = spec['query'] is Map
        ? '${(spec['query'] as Map)['text'] ?? ''}'
        : null;

    final List<(double, Map<String, Object?>)> scored =
        <(double, Map<String, Object?>)>[];
    for (final Map<String, Object?> doc in filtered) {
      final Map<String, Object?> copy = Map<String, Object?>.from(doc);
      double score = 0.5;
      final Object? docField = copy[path];
      if (queryVector != null && docField is List) {
        final List<double> docVec = docField
            .whereType<num>()
            .map((num n) => n.toDouble())
            .toList();
        score = _cosineSimilarity(queryVector, docVec);
      } else if (queryText != null && docField is String) {
        score = _textOverlapScore(queryText, docField);
      }
      copy['__meta_score__'] = score;
      scored.add((score, copy));
    }

    scored.sort(
      ((double, Map<String, Object?>) a, (double, Map<String, Object?>) b) =>
          b.$1.compareTo(a.$1),
    );
    return scored
        .take(limit)
        .map(((double, Map<String, Object?>) e) => e.$2)
        .toList();
  }

  List<Map<String, Object?>> _runFullTextSearchStage(
    List<Map<String, Object?>> docs,
    Map<String, Object?> spec,
  ) {
    final Map<String, Object?> textSpec = _asMap(spec['text']);
    final String query = '${textSpec['query'] ?? ''}'.toLowerCase();
    final String path = '${textSpec['path'] ?? ''}';

    final List<(double, Map<String, Object?>)> scored =
        <(double, Map<String, Object?>)>[];
    for (final Map<String, Object?> doc in docs) {
      final String target = '${doc[path] ?? ''}'.toLowerCase();
      final double score = _textOverlapScore(query, target);
      if (score > 0 || query.isEmpty) {
        final Map<String, Object?> copy = Map<String, Object?>.from(doc);
        copy['__meta_score__'] = score;
        scored.add((score, copy));
      }
    }

    scored.sort(
      ((double, Map<String, Object?>) a, (double, Map<String, Object?>) b) =>
          b.$1.compareTo(a.$1),
    );
    return scored.map(((double, Map<String, Object?>) e) => e.$2).toList();
  }

  List<Map<String, Object?>> _runRankFusionStage(
    List<Map<String, Object?>> docs,
    Map<String, Object?> spec,
  ) {
    final Map<String, Object?> input = _asMap(spec['input']);
    final Map<String, Object?> pipelines = _asMap(input['pipelines']);
    final Map<String, Object?> combination = _asMap(spec['combination']);
    final Map<String, Object?> weights = _asMap(combination['weights']);

    final Map<String, double> fusedScores = <String, double>{};
    final Map<String, Map<String, Object?>> docsById =
        <String, Map<String, Object?>>{};

    pipelines.forEach((String armName, Object? armStagesRaw) {
      if (armStagesRaw is! List) {
        return;
      }
      final List<Map<String, Object?>> armStages = armStagesRaw
          .whereType<Map>()
          .map(_asMap)
          .toList();
      final List<Map<String, Object?>> armResults = _executePipeline(
        docs,
        armStages,
      );
      final double weight = (weights[armName] as num?)?.toDouble() ?? 1.0;

      for (int rank = 0; rank < armResults.length; rank += 1) {
        final Map<String, Object?> doc = armResults[rank];
        final String docKey = '${doc['_id'] ?? jsonEncode(doc)}';
        docsById[docKey] = doc;
        final double rrf = weight * (1.0 / (60.0 + rank + 1.0));
        fusedScores[docKey] = (fusedScores[docKey] ?? 0.0) + rrf;
      }
    });

    final List<MapEntry<String, double>> sortedEntries =
        fusedScores.entries.toList()..sort(
          (MapEntry<String, double> a, MapEntry<String, double> b) =>
              b.value.compareTo(a.value),
        );

    return sortedEntries.map((MapEntry<String, double> entry) {
      final Map<String, Object?> doc = Map<String, Object?>.from(
        docsById[entry.key]!,
      );
      doc['__meta_score__'] = double.parse(entry.value.toStringAsFixed(6));
      return doc;
    }).toList();
  }

  @override
  Future<void> close() async {
    isClosed = true;
  }
}

/// Validates that [filter] only uses operators in the `$vectorSearch` allowlist.
///
/// Throws an [ArgumentError] if any disallowed `$`-prefixed operator is present.
void checkMongoDbFilter(Object? filter) {
  if (filter is List) {
    for (final Object? item in filter) {
      checkMongoDbFilter(item);
    }
    return;
  }
  if (filter is! Map) {
    return;
  }
  filter.forEach((Object? rawKey, Object? value) {
    final String key = '$rawKey';
    if (key.startsWith(r'$') && !_allowedFilterOperators.contains(key)) {
      throw ArgumentError('Operator $key is not allowed in a search filter.');
    }
    checkMongoDbFilter(value);
  });
}

(int, int) _resolveLimits(
  int? limit,
  int? numCandidates,
  MongoDbToolSettings settings,
) {
  final int baseLimit = (limit != null && limit > 0)
      ? limit
      : settings.defaultLimit;
  final int resolvedLimit = math.min(
    math.min(baseLimit, settings.maxResults),
    _maxNumCandidates,
  );
  final int rawCandidates =
      numCandidates ??
      math.max(resolvedLimit * 10, settings.defaultNumCandidates);
  final int resolvedNumCandidates = math.min(
    math.max(rawCandidates, resolvedLimit),
    _maxNumCandidates,
  );
  return (resolvedLimit, resolvedNumCandidates);
}

double _resolveWeight(num? weight) {
  if (weight == null) {
    return 1.0;
  }
  return math.max(weight.toDouble(), 0.0);
}

Future<Map<String, Object?>> _buildVectorSearchStage({
  required String query,
  required MongoDbToolSettings settings,
  required Object? genaiClient,
  required String indexName,
  required String embeddingField,
  required int limit,
  required int numCandidates,
}) async {
  final Map<String, Object?> stage = <String, Object?>{
    'index': indexName,
    'path': embeddingField,
    'numCandidates': numCandidates,
    'limit': limit,
  };
  if (settings.useMongodbAutoEmbedding) {
    stage['query'] = <String, Object?>{'text': query};
    if (settings.mongodbAutoEmbeddingModel != null &&
        settings.mongodbAutoEmbeddingModel!.isNotEmpty) {
      stage['model'] = settings.mongodbAutoEmbeddingModel;
    }
  } else {
    stage['queryVector'] = await _mongoDbQueryEmbedder(
      query: query,
      modelName: settings.vertexAiEmbeddingModelName,
      outputDimensionality: settings.vertexAiEmbeddingOutputDimensionality,
      genaiClient: genaiClient,
    );
  }
  return stage;
}

List<Map<String, Object?>> _buildResultStages({
  required String? embeddingField,
  required List<String>? outputFields,
  required String scoreMeta,
}) {
  final List<Map<String, Object?>> stages = <Map<String, Object?>>[
    <String, Object?>{
      r'$addFields': <String, Object?>{
        _searchScoreAlias: <String, Object?>{r'$meta': scoreMeta},
      },
    },
  ];
  if (outputFields != null && outputFields.isNotEmpty) {
    final Map<String, Object?> projection = <String, Object?>{
      for (final String field in outputFields) field: 1,
      _searchScoreAlias: 1,
    };
    stages.add(<String, Object?>{r'$project': projection});
  } else if (embeddingField != null && embeddingField.isNotEmpty) {
    stages.add(<String, Object?>{
      r'$project': <String, Object?>{embeddingField: 0},
    });
  }
  return stages;
}

Object? _jsonSafe(Object? value) {
  try {
    jsonEncode(value);
    return value;
  } catch (_) {
    return '$value';
  }
}

/// Runs an Atlas Vector Search query against a MongoDB collection.
Future<Map<String, Object?>> vectorSearch({
  required String collectionName,
  required String query,
  required MongoDbClient client,
  required String databaseName,
  required MongoDbToolSettings settings,
  Object? genaiClient,
  Map<String, Object?>? filter,
  int? limit,
  int? numCandidates,
  String? indexName,
  String? embeddingField,
  List<String>? outputFields,
}) async {
  try {
    checkMongoDbFilter(filter);
    final String resolvedIndexName =
        (indexName != null && indexName.isNotEmpty)
        ? indexName
        : settings.defaultVectorIndexName;
    final String resolvedEmbeddingField =
        (embeddingField != null && embeddingField.isNotEmpty)
        ? embeddingField
        : settings.defaultEmbeddingField;
    final (int resolvedLimit, int resolvedNumCandidates) = _resolveLimits(
      limit,
      numCandidates,
      settings,
    );

    final Map<String, Object?> vectorSearchStage =
        await _buildVectorSearchStage(
          query: query,
          settings: settings,
          genaiClient: genaiClient,
          indexName: resolvedIndexName,
          embeddingField: resolvedEmbeddingField,
          limit: resolvedLimit,
          numCandidates: resolvedNumCandidates,
        );
    if (filter != null && filter.isNotEmpty) {
      vectorSearchStage['filter'] = filter;
    }

    final List<Map<String, Object?>> pipeline = <Map<String, Object?>>[
      <String, Object?>{r'$vectorSearch': vectorSearchStage},
      ..._buildResultStages(
        embeddingField: settings.useMongodbAutoEmbedding
            ? null
            : resolvedEmbeddingField,
        outputFields: outputFields,
        scoreMeta: 'vectorSearchScore',
      ),
    ];

    final List<Map<String, Object?>> rawRows = await client.aggregate(
      databaseName: databaseName,
      collectionName: collectionName,
      pipeline: pipeline,
      maxTimeMs: settings.timeoutMs,
    );
    final List<Map<String, Object?>> rows = rawRows
        .map(
          (Map<String, Object?> doc) => <String, Object?>{
            for (final MapEntry<String, Object?> e in doc.entries)
              e.key: _jsonSafe(e.value),
          },
        )
        .toList(growable: false);
    return <String, Object?>{'status': 'SUCCESS', 'rows': rows};
  } catch (ex) {
    return <String, Object?>{'status': 'ERROR', 'error_details': '$ex'};
  }
}

/// Runs a hybrid (full-text + vector) search against a MongoDB collection.
Future<Map<String, Object?>> hybridSearch({
  required String collectionName,
  required String query,
  required String textSearchField,
  required MongoDbClient client,
  required String databaseName,
  required MongoDbToolSettings settings,
  Object? genaiClient,
  Map<String, Object?>? filter,
  int? limit,
  int? numCandidates,
  String? vectorIndexName,
  String? searchIndexName,
  String? embeddingField,
  double? vectorWeight,
  double? textWeight,
  List<String>? outputFields,
}) async {
  try {
    checkMongoDbFilter(filter);
    final String resolvedVectorIndexName =
        (vectorIndexName != null && vectorIndexName.isNotEmpty)
        ? vectorIndexName
        : settings.defaultVectorIndexName;
    final String resolvedSearchIndexName =
        (searchIndexName != null && searchIndexName.isNotEmpty)
        ? searchIndexName
        : settings.defaultSearchIndexName;
    final String resolvedEmbeddingField =
        (embeddingField != null && embeddingField.isNotEmpty)
        ? embeddingField
        : settings.defaultEmbeddingField;
    final (int resolvedLimit, int resolvedNumCandidates) = _resolveLimits(
      limit,
      numCandidates,
      settings,
    );
    final int armLimit = math.min(
      resolvedLimit * _rankFusionArmOversample,
      resolvedNumCandidates,
    );

    final Map<String, Object?> vectorSearchStage =
        await _buildVectorSearchStage(
          query: query,
          settings: settings,
          genaiClient: genaiClient,
          indexName: resolvedVectorIndexName,
          embeddingField: resolvedEmbeddingField,
          limit: armLimit,
          numCandidates: resolvedNumCandidates,
        );
    if (filter != null && filter.isNotEmpty) {
      vectorSearchStage['filter'] = filter;
    }

    final List<Map<String, Object?>> fullTextPipeline = <Map<String, Object?>>[
      <String, Object?>{
        r'$search': <String, Object?>{
          'index': resolvedSearchIndexName,
          'text': <String, Object?>{'query': query, 'path': textSearchField},
        },
      },
      if (filter != null && filter.isNotEmpty)
        <String, Object?>{r'$match': filter},
      <String, Object?>{r'$limit': armLimit},
    ];

    final List<Map<String, Object?>> pipeline = <Map<String, Object?>>[
      <String, Object?>{
        r'$rankFusion': <String, Object?>{
          'input': <String, Object?>{
            'pipelines': <String, Object?>{
              _vectorPipelineName: <Map<String, Object?>>[
                <String, Object?>{r'$vectorSearch': vectorSearchStage},
              ],
              _fullTextPipelineName: fullTextPipeline,
            },
          },
          'combination': <String, Object?>{
            'weights': <String, Object?>{
              _vectorPipelineName: _resolveWeight(vectorWeight),
              _fullTextPipelineName: _resolveWeight(textWeight),
            },
          },
          'scoreDetails': false,
        },
      },
      <String, Object?>{r'$limit': resolvedLimit},
      ..._buildResultStages(
        embeddingField: settings.useMongodbAutoEmbedding
            ? null
            : resolvedEmbeddingField,
        outputFields: outputFields,
        scoreMeta: 'score',
      ),
    ];

    final List<Map<String, Object?>> rawRows = await client.aggregate(
      databaseName: databaseName,
      collectionName: collectionName,
      pipeline: pipeline,
      maxTimeMs: settings.timeoutMs,
    );
    final List<Map<String, Object?>> rows = rawRows
        .map(
          (Map<String, Object?> doc) => <String, Object?>{
            for (final MapEntry<String, Object?> e in doc.entries)
              e.key: _jsonSafe(e.value),
          },
        )
        .toList(growable: false);
    return <String, Object?>{'status': 'SUCCESS', 'rows': rows};
  } catch (ex) {
    return <String, Object?>{'status': 'ERROR', 'error_details': '$ex'};
  }
}

/// Supported search modes for [MongoDbSearchTool].
enum MongoDbSearchMode {
  /// Atlas Vector Search (`$vectorSearch`).
  vectorSearch('vector_search'),

  /// Hybrid search (`$rankFusion` combining `$vectorSearch` and `$search`).
  hybridSearch('hybrid_search'),

  /// Full-text search (`$search`).
  fullTextSearch('full_text_search'),

  /// Standard MQL find query.
  find('find'),

  /// Custom aggregation pipeline execution.
  aggregate('aggregate');

  /// Creates a search mode with its [wireValue].
  const MongoDbSearchMode(this.wireValue);

  /// Wire identifier for the search mode.
  final String wireValue;
}

/// Tool that executes vector search, hybrid search, full-text search, find, or
/// aggregation queries against a MongoDB database.
///
/// ```dart
/// final tool = MongoDbSearchTool.vectorSearch(
///   client: MongoDbClient.inMemory(),
///   databaseName: 'products_db',
///   settings: MongoDbToolSettings(),
/// );
/// ```
class MongoDbSearchTool extends BaseTool {
  /// Creates a MongoDB search tool for [mode].
  MongoDbSearchTool({
    required super.name,
    required super.description,
    required this.client,
    required this.databaseName,
    MongoDbToolSettings? settings,
    this.genaiClient,
    this.mode = MongoDbSearchMode.vectorSearch,
  }) : settings = settings ?? MongoDbToolSettings();

  /// Creates the `vector_search` tool bound to [client] and [databaseName].
  factory MongoDbSearchTool.vectorSearch({
    required MongoDbClient client,
    required String databaseName,
    MongoDbToolSettings? settings,
    Object? genaiClient,
  }) {
    return MongoDbSearchTool(
      name: 'vector_search',
      description:
          'Runs an Atlas Vector Search query against a MongoDB collection.',
      client: client,
      databaseName: databaseName,
      settings: settings,
      genaiClient: genaiClient,
      mode: MongoDbSearchMode.vectorSearch,
    );
  }

  /// Creates the `hybrid_search` tool bound to [client] and [databaseName].
  factory MongoDbSearchTool.hybridSearch({
    required MongoDbClient client,
    required String databaseName,
    MongoDbToolSettings? settings,
    Object? genaiClient,
  }) {
    return MongoDbSearchTool(
      name: 'hybrid_search',
      description:
          'Runs a hybrid (full-text + vector) search against a MongoDB collection.',
      client: client,
      databaseName: databaseName,
      settings: settings,
      genaiClient: genaiClient,
      mode: MongoDbSearchMode.hybridSearch,
    );
  }

  /// MongoDB client used to run queries.
  final MongoDbClient client;

  /// Target MongoDB database name.
  final String databaseName;

  /// Search settings applied to tool invocations.
  final MongoDbToolSettings settings;

  /// Optional GenAI client used for query embeddings.
  final Object? genaiClient;

  /// Search operation mode executed by this tool.
  final MongoDbSearchMode mode;

  @override
  String? detectErrorInResponse(Object? response) {
    if (response is Map && response['status'] == 'ERROR') {
      return 'TOOL_ERROR';
    }
    return super.detectErrorInResponse(response);
  }

  @override
  FunctionDeclaration? getDeclaration() {
    switch (mode) {
      case MongoDbSearchMode.vectorSearch:
        return FunctionDeclaration(
          name: name,
          description: description,
          parameters: <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{
              'collection_name': <String, dynamic>{'type': 'string'},
              'query': <String, dynamic>{'type': 'string'},
              'filter': <String, dynamic>{'type': 'object'},
              'limit': <String, dynamic>{'type': 'integer'},
              'num_candidates': <String, dynamic>{'type': 'integer'},
              'index_name': <String, dynamic>{'type': 'string'},
              'embedding_field': <String, dynamic>{'type': 'string'},
              'output_fields': <String, dynamic>{
                'type': 'array',
                'items': <String, dynamic>{'type': 'string'},
              },
            },
            'required': <String>['collection_name', 'query'],
          },
        );
      case MongoDbSearchMode.hybridSearch:
        return FunctionDeclaration(
          name: name,
          description: description,
          parameters: <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{
              'collection_name': <String, dynamic>{'type': 'string'},
              'query': <String, dynamic>{'type': 'string'},
              'text_search_field': <String, dynamic>{'type': 'string'},
              'filter': <String, dynamic>{'type': 'object'},
              'limit': <String, dynamic>{'type': 'integer'},
              'num_candidates': <String, dynamic>{'type': 'integer'},
              'vector_index_name': <String, dynamic>{'type': 'string'},
              'search_index_name': <String, dynamic>{'type': 'string'},
              'embedding_field': <String, dynamic>{'type': 'string'},
              'vector_weight': <String, dynamic>{'type': 'number'},
              'text_weight': <String, dynamic>{'type': 'number'},
              'output_fields': <String, dynamic>{
                'type': 'array',
                'items': <String, dynamic>{'type': 'string'},
              },
            },
            'required': <String>[
              'collection_name',
              'query',
              'text_search_field',
            ],
          },
        );
      case MongoDbSearchMode.fullTextSearch:
      case MongoDbSearchMode.find:
      case MongoDbSearchMode.aggregate:
        return FunctionDeclaration(
          name: name,
          description: description,
          parameters: <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{
              'collection_name': <String, dynamic>{'type': 'string'},
              'query': <String, dynamic>{'type': 'string'},
              'text_search_field': <String, dynamic>{'type': 'string'},
              'filter': <String, dynamic>{'type': 'object'},
              'pipeline': <String, dynamic>{'type': 'array'},
              'limit': <String, dynamic>{'type': 'integer'},
              'output_fields': <String, dynamic>{
                'type': 'array',
                'items': <String, dynamic>{'type': 'string'},
              },
            },
            'required': <String>['collection_name'],
          },
        );
    }
  }

  @override
  Future<Object?> run({
    required Map<String, dynamic> args,
    required ToolContext toolContext,
  }) async {
    final String collectionName =
        '${args['collection_name'] ?? args['collectionName'] ?? ''}';
    final Map<String, Object?>? filter = args['filter'] is Map
        ? _asMap(args['filter'])
        : null;
    final int? limit = (args['limit'] as num?)?.toInt();
    final int? numCandidates =
        (args['num_candidates'] as num?)?.toInt() ??
        (args['numCandidates'] as num?)?.toInt();
    final List<String>? outputFields =
        (args['output_fields'] ?? args['outputFields']) is List
        ? ((args['output_fields'] ?? args['outputFields']) as List)
              .map((Object? e) => '$e')
              .toList()
        : null;

    switch (mode) {
      case MongoDbSearchMode.vectorSearch:
        final String query = '${args['query'] ?? ''}';
        return vectorSearch(
          collectionName: collectionName,
          query: query,
          client: client,
          databaseName: databaseName,
          settings: settings,
          genaiClient: genaiClient,
          filter: filter,
          limit: limit,
          numCandidates: numCandidates,
          indexName:
              (args['index_name'] ?? args['indexName']) as String?,
          embeddingField:
              (args['embedding_field'] ?? args['embeddingField']) as String?,
          outputFields: outputFields,
        );
      case MongoDbSearchMode.hybridSearch:
        final String query = '${args['query'] ?? ''}';
        final String textSearchField =
            '${args['text_search_field'] ?? args['textSearchField'] ?? ''}';
        return hybridSearch(
          collectionName: collectionName,
          query: query,
          textSearchField: textSearchField,
          client: client,
          databaseName: databaseName,
          settings: settings,
          genaiClient: genaiClient,
          filter: filter,
          limit: limit,
          numCandidates: numCandidates,
          vectorIndexName:
              (args['vector_index_name'] ?? args['vectorIndexName']) as String?,
          searchIndexName:
              (args['search_index_name'] ?? args['searchIndexName']) as String?,
          embeddingField:
              (args['embedding_field'] ?? args['embeddingField']) as String?,
          vectorWeight:
              (args['vector_weight'] ?? args['vectorWeight'] as num?)
                  ?.toDouble(),
          textWeight:
              (args['text_weight'] ?? args['textWeight'] as num?)?.toDouble(),
          outputFields: outputFields,
        );
      case MongoDbSearchMode.fullTextSearch:
        try {
          checkMongoDbFilter(filter);
          final String query = '${args['query'] ?? ''}';
          final String textSearchField =
              '${args['text_search_field'] ?? args['textSearchField'] ?? ''}';
          final String resolvedSearchIndexName =
              (args['search_index_name'] ?? args['searchIndexName'])
                  as String? ??
              settings.defaultSearchIndexName;
          final (int resolvedLimit, _) = _resolveLimits(
            limit,
            numCandidates,
            settings,
          );
          final List<Map<String, Object?>> pipeline = <Map<String, Object?>>[
            <String, Object?>{
              r'$search': <String, Object?>{
                'index': resolvedSearchIndexName,
                'text': <String, Object?>{
                  'query': query,
                  'path': textSearchField,
                },
              },
            },
            if (filter != null && filter.isNotEmpty)
              <String, Object?>{r'$match': filter},
            <String, Object?>{r'$limit': resolvedLimit},
            ..._buildResultStages(
              embeddingField: settings.useMongodbAutoEmbedding
                  ? null
                  : settings.defaultEmbeddingField,
              outputFields: outputFields,
              scoreMeta: 'searchScore',
            ),
          ];
          final List<Map<String, Object?>> rows = await client.aggregate(
            databaseName: databaseName,
            collectionName: collectionName,
            pipeline: pipeline,
            maxTimeMs: settings.timeoutMs,
          );
          return <String, Object?>{'status': 'SUCCESS', 'rows': rows};
        } catch (ex) {
          return <String, Object?>{'status': 'ERROR', 'error_details': '$ex'};
        }
      case MongoDbSearchMode.find:
        try {
          final List<Map<String, Object?>> rows = await client.find(
            databaseName: databaseName,
            collectionName: collectionName,
            filter: filter,
            limit: limit ?? settings.defaultLimit,
            outputFields: outputFields,
          );
          return <String, Object?>{'status': 'SUCCESS', 'rows': rows};
        } catch (ex) {
          return <String, Object?>{'status': 'ERROR', 'error_details': '$ex'};
        }
      case MongoDbSearchMode.aggregate:
        try {
          final List<Map<String, Object?>> pipeline = (args['pipeline'] is List)
              ? (args['pipeline'] as List)
                    .whereType<Map>()
                    .map(_asMap)
                    .toList()
              : <Map<String, Object?>>[];
          final List<Map<String, Object?>> rows = await client.aggregate(
            databaseName: databaseName,
            collectionName: collectionName,
            pipeline: pipeline,
            maxTimeMs: settings.timeoutMs,
          );
          return <String, Object?>{'status': 'SUCCESS', 'rows': rows};
        } catch (ex) {
          return <String, Object?>{'status': 'ERROR', 'error_details': '$ex'};
        }
    }
  }
}

/// MongoDB toolset providing `mongodb_vector_search` and `mongodb_hybrid_search` tools.
///
/// ```dart
/// final toolset = MongoDbToolset(
///   connectionString: 'mongodb+srv://user:pass@cluster.mongodb.net/',
///   databaseName: 'products_db',
/// );
/// final tools = await toolset.getToolsWithPrefix();
/// ```
class MongoDbToolset extends BaseToolset {
  /// Creates a [MongoDbToolset] bound to [databaseName].
  ///
  /// Exactly one of [connectionString], [connectionStringEnvVar], or
  /// [mongoClient] must be provided.
  MongoDbToolset({
    required this.databaseName,
    String? connectionString,
    String? connectionStringEnvVar,
    MongoDbClient? mongoClient,
    super.toolFilter,
    MongoDbToolSettings? settings,
    this.genaiClient,
    Map<String, String>? environment,
  }) : settings = settings ?? MongoDbToolSettings(),
       _connectionStringEnvVar = connectionStringEnvVar,
       super(toolNamePrefix: defaultMongoDbToolNamePrefix) {
    final int sources = <Object?>[
      connectionString,
      connectionStringEnvVar,
      mongoClient,
    ].where((Object? s) => s != null).length;
    if (sources != 1) {
      throw ArgumentError(
        'Exactly one of `connectionString`, `connectionStringEnvVar` or '
        '`mongoClient` must be provided.',
      );
    }

    if (mongoClient != null) {
      _client = mongoClient;
      _ownsClient = false;
      _connectionString = null;
    } else {
      final String resolved =
          connectionString ??
          connectionStringFromEnv(
            connectionStringEnvVar!,
            environment: environment,
          );
      _client = getMongoClient(resolved, timeoutMs: this.settings.timeoutMs);
      _ownsClient = true;
      _connectionString = connectionString;
    }
  }

  /// Target MongoDB database name.
  final String databaseName;

  /// Settings for the MongoDB search tools.
  final MongoDbToolSettings settings;

  /// Optional GenAI client used to embed queries.
  final Object? genaiClient;

  late final MongoDbClient _client;
  late final bool _ownsClient;
  late final String? _connectionString;
  final String? _connectionStringEnvVar;

  /// Underlying [MongoDbClient] instance.
  MongoDbClient get client => _client;

  /// Whether this toolset created and owns [client].
  bool get ownsClient => _ownsClient;

  /// Connection string stored on this toolset (`null` when using env var or injected client).
  String? get connectionString => _connectionString;

  /// Environment variable name holding the connection string, if configured.
  String? get connectionStringEnvVar => _connectionStringEnvVar;

  @override
  Future<List<BaseTool>> getTools({ReadonlyContext? readonlyContext}) async {
    final List<BaseTool> allTools = <BaseTool>[
      MongoDbSearchTool.vectorSearch(
        client: _client,
        databaseName: databaseName,
        settings: settings,
        genaiClient: genaiClient,
      ),
      MongoDbSearchTool.hybridSearch(
        client: _client,
        databaseName: databaseName,
        settings: settings,
        genaiClient: genaiClient,
      ),
    ];
    return allTools
        .where((BaseTool tool) => isToolSelected(tool, readonlyContext))
        .toList(growable: false);
  }

  @override
  Future<void> close() async {
    if (_ownsClient) {
      await _client.close();
    }
  }
}

Map<String, Object?> _asMap(Object? value) {
  if (value is Map<String, Object?>) {
    return Map<String, Object?>.from(value);
  }
  if (value is Map) {
    return value.map((Object? k, Object? v) => MapEntry('$k', v));
  }
  return <String, Object?>{};
}

Map<String, Object?> _applyProjection(
  Map<String, Object?> doc,
  Map<String, Object?> projection,
) {
  final bool hasInclusions = projection.entries.any(
    (MapEntry<String, Object?> e) =>
        e.key != '_id' && (e.value == 1 || e.value == true),
  );
  if (hasInclusions) {
    final Map<String, Object?> result = <String, Object?>{};
    final bool includeId =
        projection['_id'] != 0 && projection['_id'] != false;
    if (includeId && doc.containsKey('_id')) {
      result['_id'] = doc['_id'];
    }
    projection.forEach((String k, Object? v) {
      if ((v == 1 || v == true) && doc.containsKey(k)) {
        result[k] = doc[k];
      }
    });
    return result;
  } else {
    final Map<String, Object?> result = Map<String, Object?>.from(doc);
    projection.forEach((String k, Object? v) {
      if (v == 0 || v == false) {
        result.remove(k);
      }
    });
    return result;
  }
}

bool _matchesMqlFilter(
  Map<String, Object?> doc,
  Map<String, Object?> filter,
) {
  for (final MapEntry<String, Object?> entry in filter.entries) {
    final String key = entry.key;
    final Object? cond = entry.value;
    if (key == r'$and' && cond is List) {
      if (!cond.every(
        (Object? c) => c is Map && _matchesMqlFilter(doc, _asMap(c)),
      )) {
        return false;
      }
      continue;
    }
    if (key == r'$or' && cond is List) {
      if (!cond.any(
        (Object? c) => c is Map && _matchesMqlFilter(doc, _asMap(c)),
      )) {
        return false;
      }
      continue;
    }
    if (key == r'$nor' && cond is List) {
      if (cond.any(
        (Object? c) => c is Map && _matchesMqlFilter(doc, _asMap(c)),
      )) {
        return false;
      }
      continue;
    }

    final Object? actual = doc[key];
    if (!_matchesFieldCondition(actual, cond)) {
      return false;
    }
  }
  return true;
}

bool _matchesFieldCondition(Object? actual, Object? condition) {
  if (condition is! Map) {
    return actual == condition;
  }
  final Map<String, Object?> ops = _asMap(condition);
  for (final MapEntry<String, Object?> op in ops.entries) {
    final Object? expected = op.value;
    switch (op.key) {
      case r'$eq':
        if (actual != expected) return false;
      case r'$ne':
        if (actual == expected) return false;
      case r'$gt':
        if (!_compareNumOrComparable(actual, expected, (int c) => c > 0)) {
          return false;
        }
      case r'$gte':
        if (!_compareNumOrComparable(actual, expected, (int c) => c >= 0)) {
          return false;
        }
      case r'$lt':
        if (!_compareNumOrComparable(actual, expected, (int c) => c < 0)) {
          return false;
        }
      case r'$lte':
        if (!_compareNumOrComparable(actual, expected, (int c) => c <= 0)) {
          return false;
        }
      case r'$in':
        if (expected is! Iterable || !expected.contains(actual)) return false;
      case r'$nin':
        if (expected is Iterable && expected.contains(actual)) return false;
      case r'$exists':
        final bool exists = actual != null;
        if (exists != (expected == true)) return false;
      case r'$not':
        if (_matchesFieldCondition(actual, expected)) return false;
    }
  }
  return true;
}

bool _compareNumOrComparable(
  Object? a,
  Object? b,
  bool Function(int) predicate,
) {
  if (a is num && b is num) {
    return predicate(a.compareTo(b));
  }
  if (a is Comparable && b is Comparable) {
    try {
      return predicate(a.compareTo(b));
    } catch (_) {
      return false;
    }
  }
  return false;
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
  return double.parse(
    (dot / (math.sqrt(normA) * math.sqrt(normB))).toStringAsFixed(6),
  );
}

double _textOverlapScore(String query, String target) {
  final Set<String> qWords = RegExp(r'[a-z0-9]+')
      .allMatches(query.toLowerCase())
      .map((RegExpMatch m) => m.group(0)!)
      .toSet();
  if (qWords.isEmpty) {
    return 0.0;
  }
  final Set<String> tWords = RegExp(r'[a-z0-9]+')
      .allMatches(target.toLowerCase())
      .map((RegExpMatch m) => m.group(0)!)
      .toSet();
  final int matched = qWords.intersection(tWords).length;
  return double.parse((matched / qWords.length).toStringAsFixed(6));
}
