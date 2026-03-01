import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../_google_auth_token.dart';
import '../pubsub/client.dart' as pubsub;
import '../tool_context.dart';
import 'client.dart';
import 'settings.dart';

const int defaultMaxExecutedQueryResultRows = 50;

final Object _spannerAnonymousCredentials = Object();

Future<Map<String, Object?>> executeSql({
  required String projectId,
  required String instanceId,
  required String databaseId,
  required String query,
  required Object credentials,
  required SpannerToolSettings settings,
  required ToolContext? toolContext,
  Map<String, Object?>? params,
  Map<String, Object?>? paramsTypes,
}) async {
  try {
    final SpannerClient spannerClient = getSpannerClient(
      project: projectId,
      credentials: credentials,
    );
    final SpannerInstance instance = spannerClient.instance(instanceId);
    final SpannerDatabase database = instance.database(databaseId);

    if (database.databaseDialect == SpannerDatabaseDialect.postgresql) {
      return <String, Object?>{
        'status': 'ERROR',
        'error_details': 'PostgreSQL dialect is not supported.',
      };
    }

    final SpannerSnapshot snapshot = database.snapshot();
    final SpannerResultSet resultSet = snapshot.executeSql(
      sql: query,
      params: params,
      paramTypes: paramsTypes,
    );

    final int maxRows = settings.maxExecutedQueryResultRows > 0
        ? settings.maxExecutedQueryResultRows
        : defaultMaxExecutedQueryResultRows;
    int counter = maxRows;

    final Iterable<Object?> rowsIterable =
        settings.queryResultMode == QueryResultMode.dictList
        ? resultSet.toDictList()
        : resultSet.rows;

    final List<Object?> rows = <Object?>[];
    for (final Object? row in rowsIterable) {
      rows.add(_ensureJsonEncodable(row));
      counter -= 1;
      if (counter <= 0) {
        break;
      }
    }

    final Map<String, Object?> result = <String, Object?>{
      'status': 'SUCCESS',
      'rows': rows,
    };
    if (counter <= 0) {
      result['result_is_likely_truncated'] = true;
    }
    return result;
  } catch (error) {
    return <String, Object?>{'status': 'ERROR', 'error_details': '$error'};
  }
}

typedef SpannerEmbedder =
    List<List<double>> Function({
      required String vertexAiEmbeddingModelName,
      required List<String> contents,
      int? outputDimensionality,
      Object? genAiClient,
    });

typedef SpannerEmbedderAsync =
    Future<List<List<double>>> Function({
      required String vertexAiEmbeddingModelName,
      required List<String> contents,
      int? outputDimensionality,
      Object? genAiClient,
    });

class SpannerEmbedderNotConfiguredException implements Exception {
  SpannerEmbedderNotConfiguredException([
    this.message =
        'No embedding runtime is configured for adk_dart Spanner tools. '
        'Inject an embedder with setSpannerEmbedders().',
  ]);

  static const String defaultCode = 'SPANNER_EMBEDDER_NOT_CONFIGURED';
  final String message;

  String get code => defaultCode;

  @override
  String toString() => '$code: $message';
}

SpannerEmbedder _spannerEmbedder = _defaultSpannerEmbedder;
SpannerEmbedderAsync _spannerEmbedderAsync = _defaultSpannerEmbedderAsync;

void setSpannerEmbedders({
  SpannerEmbedder? embedder,
  SpannerEmbedderAsync? embedderAsync,
}) {
  if (embedder != null) {
    _spannerEmbedder = embedder;
  }
  if (embedderAsync != null) {
    _spannerEmbedderAsync = embedderAsync;
  }
}

void resetSpannerEmbedders() {
  _spannerEmbedder = _defaultSpannerEmbedder;
  _spannerEmbedderAsync = _defaultSpannerEmbedderAsync;
}

void configureSpannerPubSubRuntime({
  SpannerClientFactory? spannerClientFactory,
  SpannerEmbedder? spannerEmbedder,
  SpannerEmbedderAsync? spannerEmbedderAsync,
  pubsub.PubSubPublisherFactory? pubSubPublisherFactory,
  pubsub.PubSubSubscriberFactory? pubSubSubscriberFactory,
}) {
  if (spannerClientFactory != null) {
    setSpannerClientFactory(spannerClientFactory);
  }
  if (spannerEmbedder != null || spannerEmbedderAsync != null) {
    setSpannerEmbedders(
      embedder: spannerEmbedder,
      embedderAsync: spannerEmbedderAsync,
    );
  }
  if (pubSubPublisherFactory != null || pubSubSubscriberFactory != null) {
    pubsub.setPubSubClientFactories(
      publisherFactory: pubSubPublisherFactory,
      subscriberFactory: pubSubSubscriberFactory,
    );
  }
}

Future<void> resetSpannerPubSubRuntime({
  bool cleanupPubSubClients = true,
}) async {
  if (cleanupPubSubClients) {
    await pubsub.cleanupClients();
  }
  pubsub.resetPubSubClientFactories();
  resetSpannerClientFactory();
  resetSpannerEmbedders();
}

List<List<double>> embedContents({
  required String vertexAiEmbeddingModelName,
  required List<String> contents,
  int? outputDimensionality,
  Object? genAiClient,
}) {
  if (identical(_spannerEmbedder, _defaultSpannerEmbedder)) {
    throw SpannerEmbedderNotConfiguredException();
  }
  try {
    return _spannerEmbedder(
      vertexAiEmbeddingModelName: vertexAiEmbeddingModelName,
      contents: contents,
      outputDimensionality: outputDimensionality,
      genAiClient: genAiClient,
    );
  } on SpannerEmbedderNotConfiguredException {
    rethrow;
  } catch (error) {
    throw StateError('Failed to embed content: $error');
  }
}

Future<List<List<double>>> embedContentsAsync({
  required String vertexAiEmbeddingModelName,
  required List<String> contents,
  int? outputDimensionality,
  Object? genAiClient,
}) async {
  if (identical(_spannerEmbedderAsync, _defaultSpannerEmbedderAsync)) {
    throw SpannerEmbedderNotConfiguredException();
  }
  try {
    return await _spannerEmbedderAsync(
      vertexAiEmbeddingModelName: vertexAiEmbeddingModelName,
      contents: contents,
      outputDimensionality: outputDimensionality,
      genAiClient: genAiClient,
    );
  } on SpannerEmbedderNotConfiguredException {
    rethrow;
  } catch (error) {
    throw StateError('Failed to embed content: $error');
  }
}

List<List<double>> _defaultSpannerEmbedder({
  required String vertexAiEmbeddingModelName,
  required List<String> contents,
  int? outputDimensionality,
  Object? genAiClient,
}) {
  return _embedViaDefaultVertexAiRuntime(
    vertexAiEmbeddingModelName: vertexAiEmbeddingModelName,
    contents: contents,
    outputDimensionality: outputDimensionality,
    genAiClient: genAiClient,
  );
}

Future<List<List<double>>> _defaultSpannerEmbedderAsync({
  required String vertexAiEmbeddingModelName,
  required List<String> contents,
  int? outputDimensionality,
  Object? genAiClient,
}) async {
  return _embedViaDefaultVertexAiRuntime(
    vertexAiEmbeddingModelName: vertexAiEmbeddingModelName,
    contents: contents,
    outputDimensionality: outputDimensionality,
    genAiClient: genAiClient,
  );
}

class SpannerVectorStore {
  SpannerVectorStore({
    required SpannerToolSettings settings,
    Object? credentials,
    SpannerClient? spannerClient,
    Object? genAiClient,
  }) : _settings = settings,
       _genAiClient = genAiClient,
       _spannerClient =
           spannerClient ??
           getSpannerClient(
             project: _requireVectorStoreSettings(settings).projectId,
             credentials: credentials ?? _spannerAnonymousCredentials,
           ) {
    final SpannerVectorStoreSettings vectorSettings = _vectorStoreSettings;

    if (spannerClient != null &&
        !_spannerClient.userAgent.contains(spannerUserAgent)) {
      _spannerClient.userAgent = _appendUserAgent(
        _spannerClient.userAgent,
        spannerUserAgent,
      );
    }

    _spannerClient.userAgent = _appendUserAgent(
      _spannerClient.userAgent,
      spannerVectorStoreUserAgent,
    );

    final SpannerInstance instance = _spannerClient.instance(
      vectorSettings.instanceId,
    );
    if (!instance.exists()) {
      throw ArgumentError(
        "Instance id ${vectorSettings.instanceId} doesn't exist.",
      );
    }

    _database = instance.database(vectorSettings.databaseId);
    if (!_database.exists()) {
      throw ArgumentError(
        "Database id ${vectorSettings.databaseId} doesn't exist.",
      );
    }
  }

  static const String defaultVectorStoreIdColumnName = 'id';
  static const String spannerVectorStoreUserAgent = 'adk-spanner-vector-store';

  final SpannerToolSettings _settings;
  final SpannerClient _spannerClient;
  final Object? _genAiClient;
  late final SpannerDatabase _database;

  SpannerVectorStoreSettings get _vectorStoreSettings {
    return _requireVectorStoreSettings(_settings);
  }

  String createVectorStoreTableDdl(SpannerDatabaseDialect dialect) {
    final List<String> primaryKeyColumns =
        _vectorStoreSettings.primaryKeyColumns ??
        <String>[defaultVectorStoreIdColumnName];

    final List<String> columnDefinitions = <String>[];
    if (_vectorStoreSettings.primaryKeyColumns == null) {
      if (dialect == SpannerDatabaseDialect.postgresql) {
        columnDefinitions.add(
          '$defaultVectorStoreIdColumnName varchar(36) DEFAULT spanner.generate_uuid()',
        );
      } else {
        columnDefinitions.add(
          '$defaultVectorStoreIdColumnName STRING(36) DEFAULT (GENERATE_UUID())',
        );
      }
    }

    if (_vectorStoreSettings.additionalColumnsToSetup != null) {
      for (final TableColumn column
          in _vectorStoreSettings.additionalColumnsToSetup!) {
        final String nullStmt = column.isNullable ? '' : ' NOT NULL';
        columnDefinitions.add('${column.name} ${column.type}$nullStmt');
      }
    }

    if (dialect == SpannerDatabaseDialect.postgresql) {
      columnDefinitions.add('${_vectorStoreSettings.contentColumn} text');
      columnDefinitions.add(
        '${_vectorStoreSettings.embeddingColumn} float4[] '
        'VECTOR LENGTH ${_vectorStoreSettings.vectorLength}',
      );
    } else {
      columnDefinitions.add(
        '${_vectorStoreSettings.contentColumn} STRING(MAX)',
      );
      columnDefinitions.add(
        '${_vectorStoreSettings.embeddingColumn} '
        'ARRAY<FLOAT32>(vector_length=>${_vectorStoreSettings.vectorLength})',
      );
    }

    final String innerDdl = columnDefinitions.join(',\n  ');
    final String pkStmt = primaryKeyColumns.join(', ');

    if (dialect == SpannerDatabaseDialect.postgresql) {
      return 'CREATE TABLE IF NOT EXISTS ${_vectorStoreSettings.tableName}'
          ' (\n  $innerDdl,\n  PRIMARY KEY($pkStmt)\n)';
    }

    return 'CREATE TABLE IF NOT EXISTS ${_vectorStoreSettings.tableName}'
        ' (\n  $innerDdl\n) PRIMARY KEY($pkStmt)';
  }

  String createAnnVectorSearchIndexDdl(SpannerDatabaseDialect dialect) {
    final VectorSearchIndexSettings? indexSettings =
        _vectorStoreSettings.vectorSearchIndexSettings;
    if (indexSettings == null) {
      throw ArgumentError('Vector search index settings are not set.');
    }

    if (dialect != SpannerDatabaseDialect.googleStandardSql) {
      throw ArgumentError(
        'ANN is only supported for the Google Standard SQL dialect.',
      );
    }

    final List<String> indexColumns = <String>[
      _vectorStoreSettings.embeddingColumn,
      ...?indexSettings.additionalKeyColumns,
    ];

    String statement =
        'CREATE VECTOR INDEX IF NOT EXISTS ${indexSettings.indexName}\n\tON '
        '${_vectorStoreSettings.tableName}(${indexColumns.join(', ')})';

    if (indexSettings.additionalStoringColumns != null &&
        indexSettings.additionalStoringColumns!.isNotEmpty) {
      statement +=
          '\n\tSTORING (${indexSettings.additionalStoringColumns!.join(', ')})';
    }

    statement +=
        '\n\tWHERE ${_vectorStoreSettings.embeddingColumn} IS NOT NULL';

    final List<String> optionsSegments = <String>[
      "distance_type='${_vectorStoreSettings.distanceType}'",
    ];

    if (indexSettings.treeDepth > 0) {
      if (indexSettings.treeDepth != 2 && indexSettings.treeDepth != 3) {
        throw ArgumentError(
          'Vector search index settings: tree_depth: ${indexSettings.treeDepth} '
          'must be either 2 or 3',
        );
      }
      optionsSegments.add('tree_depth=${indexSettings.treeDepth}');
    }

    if (indexSettings.numBranches != null && indexSettings.numBranches! > 0) {
      optionsSegments.add('num_branches=${indexSettings.numBranches}');
    }

    if (indexSettings.numLeaves > 0) {
      optionsSegments.add('num_leaves=${indexSettings.numLeaves}');
    }

    statement += '\n\tOPTIONS(${optionsSegments.join(', ')})';
    return statement.trim();
  }

  Future<void> createVectorStore() async {
    final String ddl = createVectorStoreTableDdl(_database.databaseDialect);
    final SpannerUpdateDdlOperation operation = _database.updateDdl(<String>[
      ddl,
    ]);
    await Future<void>.sync(() => operation.result());
  }

  Future<void> createVectorSearchIndex() async {
    if (_vectorStoreSettings.vectorSearchIndexSettings == null) {
      return;
    }
    final String ddl = createAnnVectorSearchIndexDdl(_database.databaseDialect);
    final SpannerUpdateDdlOperation operation = _database.updateDdl(<String>[
      ddl,
    ]);
    await Future<void>.sync(() => operation.result());
  }

  Future<void> createVectorStoreAsync() async {
    await createVectorStore();
  }

  Future<void> createVectorSearchIndexAsync() async {
    await createVectorSearchIndex();
  }

  Iterable<SpannerContentBatch> prepareAndValidateBatches({
    required Iterable<String> contents,
    required Iterable<Map<String, Object?>>? additionalColumnsValues,
    required int batchSize,
  }) sync* {
    final Iterator<String> contentIterator = contents.iterator;
    final Iterator<Map<String, Object?>>? valuesIterator =
        additionalColumnsValues?.iterator;

    int index = 0;
    while (true) {
      final List<String> contentBatch = <String>[];
      for (int i = 0; i < batchSize; i += 1) {
        if (!contentIterator.moveNext()) {
          break;
        }
        contentBatch.add(contentIterator.current);
      }
      if (contentBatch.isEmpty) {
        break;
      }

      final List<Map<String, Object?>> valueBatch = <Map<String, Object?>>[];
      if (valuesIterator == null) {
        for (int i = 0; i < contentBatch.length; i += 1) {
          valueBatch.add(<String, Object?>{});
        }
      } else {
        for (int i = 0; i < contentBatch.length; i += 1) {
          if (!valuesIterator.moveNext()) {
            throw ArgumentError(
              'Data mismatch: ended at index $index. Expected '
              '${contentBatch.length} values for this batch, but got $i.',
            );
          }
          valueBatch.add(valuesIterator.current);
        }
      }

      yield SpannerContentBatch(
        contentBatch: contentBatch,
        valueBatch: valueBatch,
        batchIndex: index,
      );
      index += batchSize;
    }

    if (valuesIterator != null && valuesIterator.moveNext()) {
      throw ArgumentError(
        'additional_columns_values contains more items than contents.',
      );
    }
  }

  Future<void> addContents({
    required Iterable<String> contents,
    Iterable<Map<String, Object?>>? additionalColumnsValues,
    int batchSize = 200,
  }) async {
    _database.reload();

    final List<String> columns =
        (_vectorStoreSettings.additionalColumnsToSetup ?? <TableColumn>[])
            .map((TableColumn column) => column.name)
            .toList(growable: false);

    for (final SpannerContentBatch batch in prepareAndValidateBatches(
      contents: contents,
      additionalColumnsValues: additionalColumnsValues,
      batchSize: batchSize,
    )) {
      final List<List<double>> embeddings = embedContents(
        vertexAiEmbeddingModelName:
            _vectorStoreSettings.vertexAiEmbeddingModelName,
        contents: batch.contentBatch,
        outputDimensionality: _vectorStoreSettings.vectorLength,
        genAiClient: _genAiClient,
      );

      final List<List<Object?>> mutationRows = <List<Object?>>[];
      for (int i = 0; i < batch.contentBatch.length; i += 1) {
        final String content = batch.contentBatch[i];
        final List<double> embedding = embeddings[i];
        final Map<String, Object?> extraValues = batch.valueBatch[i];
        final List<Object?> row = <Object?>[content, embedding];
        for (final String columnName in columns) {
          row.add(extraValues[columnName]);
        }
        mutationRows.add(row);
      }

      final SpannerBatch spannerBatch = _database.batch();
      spannerBatch.insertOrUpdate(
        table: _vectorStoreSettings.tableName,
        columns: <String>[
          _vectorStoreSettings.contentColumn,
          _vectorStoreSettings.embeddingColumn,
          ...columns,
        ],
        values: mutationRows,
      );
    }
  }

  Future<void> addContentsAsync({
    required Iterable<String> contents,
    Iterable<Map<String, Object?>>? additionalColumnsValues,
    int batchSize = 200,
  }) async {
    _database.reload();

    final List<String> columns =
        (_vectorStoreSettings.additionalColumnsToSetup ?? <TableColumn>[])
            .map((TableColumn column) => column.name)
            .toList(growable: false);

    for (final SpannerContentBatch batch in prepareAndValidateBatches(
      contents: contents,
      additionalColumnsValues: additionalColumnsValues,
      batchSize: batchSize,
    )) {
      final List<List<double>> embeddings = await embedContentsAsync(
        vertexAiEmbeddingModelName:
            _vectorStoreSettings.vertexAiEmbeddingModelName,
        contents: batch.contentBatch,
        outputDimensionality: _vectorStoreSettings.vectorLength,
        genAiClient: _genAiClient,
      );

      final List<List<Object?>> mutationRows = <List<Object?>>[];
      for (int i = 0; i < batch.contentBatch.length; i += 1) {
        final String content = batch.contentBatch[i];
        final List<double> embedding = embeddings[i];
        final Map<String, Object?> extraValues = batch.valueBatch[i];
        final List<Object?> row = <Object?>[content, embedding];
        for (final String columnName in columns) {
          row.add(extraValues[columnName]);
        }
        mutationRows.add(row);
      }

      final SpannerBatch spannerBatch = _database.batch();
      spannerBatch.insertOrUpdate(
        table: _vectorStoreSettings.tableName,
        columns: <String>[
          _vectorStoreSettings.contentColumn,
          _vectorStoreSettings.embeddingColumn,
          ...columns,
        ],
        values: mutationRows,
      );
    }
  }
}

class SpannerContentBatch {
  SpannerContentBatch({
    required this.contentBatch,
    required this.valueBatch,
    required this.batchIndex,
  });

  final List<String> contentBatch;
  final List<Map<String, Object?>> valueBatch;
  final int batchIndex;
}

SpannerVectorStoreSettings _requireVectorStoreSettings(
  SpannerToolSettings settings,
) {
  final SpannerVectorStoreSettings? vectorStoreSettings =
      settings.vectorStoreSettings;
  if (vectorStoreSettings == null) {
    throw ArgumentError('Spanner vector store settings are not set.');
  }
  return vectorStoreSettings;
}

Object? _ensureJsonEncodable(Object? value) {
  try {
    jsonEncode(value);
    return value;
  } catch (_) {
    return '$value';
  }
}

List<List<double>> _embedViaDefaultVertexAiRuntime({
  required String vertexAiEmbeddingModelName,
  required List<String> contents,
  required int? outputDimensionality,
  required Object? genAiClient,
}) {
  if (contents.isEmpty) {
    return <List<double>>[];
  }

  final _ResolvedVertexEmbeddingModel resolvedModel = _resolveVertexModel(
    vertexAiEmbeddingModelName,
  );
  final String accessToken = _resolveVertexAccessToken(
    genAiClient: genAiClient,
  );

  final Uri uri = Uri.parse(
    'https://${resolvedModel.location}-aiplatform.googleapis.com/v1/'
    'projects/${resolvedModel.project}/locations/${resolvedModel.location}/'
    'publishers/google/models/${resolvedModel.model}:predict',
  );

  final Map<String, Object?> payload = <String, Object?>{
    'instances': contents
        .map((String content) => <String, Object?>{'content': content})
        .toList(growable: false),
    if (outputDimensionality != null)
      'parameters': <String, Object?>{
        'outputDimensionality': outputDimensionality,
      },
  };

  final List<String> args = <String>[
    '-sS',
    '-X',
    'POST',
    uri.toString(),
    '-H',
    'Authorization: Bearer $accessToken',
    '-H',
    'Content-Type: application/json',
    '-H',
    'Accept: application/json',
    '--data-binary',
    jsonEncode(payload),
    '-w',
    '\n%{http_code}',
  ];
  final ProcessResult result = Process.runSync('curl', args);
  if (result.exitCode != 0) {
    throw SpannerEmbedderNotConfiguredException(
      'Default Spanner embedder runtime failed to invoke Vertex AI: '
      '${result.stderr}. Inject an embedder with setSpannerEmbedders().',
    );
  }

  final String responseText = '${result.stdout}';
  final int separator = responseText.lastIndexOf('\n');
  final String bodyText = separator < 0
      ? ''
      : responseText.substring(0, separator);
  final String statusText = separator < 0
      ? responseText.trim()
      : responseText.substring(separator + 1).trim();
  final int statusCode = int.tryParse(statusText) ?? 0;
  if (statusCode < 200 || statusCode >= 300) {
    throw SpannerEmbedderNotConfiguredException(
      'Default Spanner embedder runtime received Vertex AI error '
      '($statusCode): $bodyText. Inject an embedder with setSpannerEmbedders().',
    );
  }

  final Object? decoded = bodyText.trim().isEmpty ? null : jsonDecode(bodyText);
  if (decoded is! Map) {
    throw SpannerEmbedderNotConfiguredException(
      'Default Spanner embedder runtime got malformed Vertex AI response. '
      'Inject an embedder with setSpannerEmbedders().',
    );
  }

  final List<Object?> predictions = _asObjectList(decoded['predictions']);
  final List<List<double>> embeddings = <List<double>>[];
  for (final Object? prediction in predictions) {
    final Map<String, Object?> map = _asObjectMap(prediction);
    final Map<String, Object?> embeddingPayload = _asObjectMap(
      map['embeddings'] ?? map['embedding'],
    );
    final List<Object?> values = _asObjectList(
      embeddingPayload['values'] ?? map['values'],
    );
    if (values.isEmpty) {
      continue;
    }
    embeddings.add(
      values
          .map((Object? value) => value is num ? value.toDouble() : null)
          .whereType<double>()
          .toList(growable: false),
    );
  }

  if (embeddings.length != contents.length) {
    throw SpannerEmbedderNotConfiguredException(
      'Default Spanner embedder runtime response length mismatch '
      '(expected ${contents.length}, got ${embeddings.length}). '
      'Inject an embedder with setSpannerEmbedders().',
    );
  }

  return embeddings;
}

String _resolveVertexAccessToken({required Object? genAiClient}) {
  final String? fromClient = tryExtractGoogleAccessToken(genAiClient);
  if (fromClient != null && fromClient.isNotEmpty) {
    return fromClient;
  }
  final String? fromEnv = _firstNonEmptyEnvValue(const <String>[
    'GOOGLE_OAUTH_ACCESS_TOKEN',
    'GOOGLE_ACCESS_TOKEN',
    'ACCESS_TOKEN',
  ]);
  if (fromEnv != null) {
    return fromEnv;
  }

  final ProcessResult gcloud = Process.runSync('gcloud', <String>[
    'auth',
    'application-default',
    'print-access-token',
    '--scopes',
    'https://www.googleapis.com/auth/cloud-platform',
  ]);
  if (gcloud.exitCode == 0) {
    final String token = '${gcloud.stdout}'.trim();
    if (token.isNotEmpty) {
      return token;
    }
  }

  final ProcessResult metadata = Process.runSync('curl', <String>[
    '-sS',
    '-H',
    'Metadata-Flavor: Google',
    'http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token',
  ]);
  if (metadata.exitCode == 0) {
    final String text = '${metadata.stdout}'.trim();
    if (text.isNotEmpty) {
      try {
        final Object? decoded = jsonDecode(text);
        if (decoded is Map && decoded['access_token'] != null) {
          final String token = '${decoded['access_token']}'.trim();
          if (token.isNotEmpty) {
            return token;
          }
        }
      } on FormatException {
        // Ignore malformed metadata response.
      }
    }
  }

  throw SpannerEmbedderNotConfiguredException(
    'No default Vertex AI access token available. '
    'Set GOOGLE_OAUTH_ACCESS_TOKEN or inject an embedder with '
    'setSpannerEmbedders().',
  );
}

_ResolvedVertexEmbeddingModel _resolveVertexModel(String rawModelName) {
  final String modelName = rawModelName.trim();
  if (modelName.isEmpty) {
    throw SpannerEmbedderNotConfiguredException(
      'vertexAiEmbeddingModelName is empty. Inject an embedder with '
      'setSpannerEmbedders().',
    );
  }

  final RegExp fullModelPattern = RegExp(
    r'^projects/([^/]+)/locations/([^/]+)/publishers/google/models/([^/]+)$',
  );
  final RegExpMatch? fullMatch = fullModelPattern.firstMatch(modelName);
  if (fullMatch != null) {
    return _ResolvedVertexEmbeddingModel(
      project: fullMatch.group(1)!,
      location: fullMatch.group(2)!,
      model: fullMatch.group(3)!,
    );
  }

  final String? project = _firstNonEmptyEnvValue(const <String>[
    'GOOGLE_CLOUD_PROJECT',
    'GCP_PROJECT',
    'GCLOUD_PROJECT',
  ]);
  if (project == null) {
    throw SpannerEmbedderNotConfiguredException(
      'GOOGLE_CLOUD_PROJECT is required for default Spanner embedder '
      'when model is not a full Vertex resource path. '
      'Inject an embedder with setSpannerEmbedders().',
    );
  }
  final String location =
      _firstNonEmptyEnvValue(const <String>[
        'GOOGLE_CLOUD_LOCATION',
        'GOOGLE_LOCATION',
        'LOCATION',
      ]) ??
      'us-central1';

  return _ResolvedVertexEmbeddingModel(
    project: project,
    location: location,
    model: modelName,
  );
}

String? _firstNonEmptyEnvValue(List<String> keys) {
  for (final String key in keys) {
    final String value = (Platform.environment[key] ?? '').trim();
    if (value.isNotEmpty) {
      return value;
    }
  }
  return null;
}

class _ResolvedVertexEmbeddingModel {
  const _ResolvedVertexEmbeddingModel({
    required this.project,
    required this.location,
    required this.model,
  });

  final String project;
  final String location;
  final String model;
}

Map<String, Object?> _asObjectMap(Object? value) {
  if (value is Map<String, Object?>) {
    return Map<String, Object?>.from(value);
  }
  if (value is Map) {
    return value.map((Object? key, Object? item) => MapEntry('$key', item));
  }
  return <String, Object?>{};
}

List<Object?> _asObjectList(Object? value) {
  if (value is List<Object?>) {
    return List<Object?>.from(value);
  }
  if (value is List) {
    return value.cast<Object?>();
  }
  return <Object?>[];
}

String _appendUserAgent(String base, String addition) {
  final String normalizedBase = base.trim();
  if (normalizedBase.isEmpty) {
    return addition;
  }
  if (normalizedBase.contains(addition)) {
    return normalizedBase;
  }
  return '$normalizedBase $addition';
}
