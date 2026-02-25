import 'dart:async';
import 'dart:convert';

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
  throw SpannerEmbedderNotConfiguredException();
}

Future<List<List<double>>> _defaultSpannerEmbedderAsync({
  required String vertexAiEmbeddingModelName,
  required List<String> contents,
  int? outputDimensionality,
  Object? genAiClient,
}) async {
  return _defaultSpannerEmbedder(
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
