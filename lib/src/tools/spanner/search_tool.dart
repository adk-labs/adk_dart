import 'dart:convert';

import 'client.dart';
import 'settings.dart';
import 'utils.dart' as utils;

const String _spannerGsqlEmbeddingModelNameKey =
    'spanner_googlesql_embedding_model_name';
const String _spannerPgVertexAiEmbeddingModelEndpointKey =
    'spanner_postgresql_vertex_ai_embedding_model_endpoint';
const String _vertexAiEmbeddingModelNameKey = 'vertex_ai_embedding_model_name';
const String _outputDimensionalityKey = 'output_dimensionality';

const String _topKKey = 'top_k';
const String _distanceTypeKey = 'distance_type';
const String _nearestNeighborsAlgorithmKey = 'nearest_neighbors_algorithm';
const String _numLeavesToSearchKey = 'num_leaves_to_search';

const String _distanceAlias = 'distance';
const String _googlesqlParameterTextQuery = 'query';
const String _postgresqlParameterTextQuery = '1';
const String _googlesqlParameterQueryEmbedding = 'embedding';
const String _postgresqlParameterQueryEmbedding = '1';

String _generateGooglesqlForEmbeddingQuery(
  String spannerGsqlEmbeddingModelName,
) {
  return '''
    SELECT embeddings.values
    FROM ML.PREDICT(
      MODEL $spannerGsqlEmbeddingModelName,
      (SELECT CAST(@$_googlesqlParameterTextQuery AS STRING) as content)
    )
  ''';
}

String _generatePostgresqlForEmbeddingQuery(
  String vertexAiEmbeddingModelEndpoint,
  int? outputDimensionality,
) {
  const String instancesJson =
      '''
      'instances',
      JSONB_BUILD_ARRAY(
          JSONB_BUILD_OBJECT(
              'content',
              \$$_postgresqlParameterTextQuery::TEXT
          )
      )
  ''';

  final List<String> paramsList = <String>[];
  if (outputDimensionality != null) {
    paramsList.add('''
        'parameters',
        JSONB_BUILD_OBJECT(
            'outputDimensionality',
            $outputDimensionality
        )
    ''');
  }

  final String jsonbBuildArgs = <String>[
    instancesJson,
    ...paramsList,
  ].join(',\n');

  return '''
      SELECT spanner.FLOAT32_ARRAY(
          spanner.ML_PREDICT_ROW(
              '$vertexAiEmbeddingModelEndpoint',
              JSONB_BUILD_OBJECT(
                  $jsonbBuildArgs
              )
          ) -> 'predictions' -> 0 -> 'embeddings' -> 'values'
      )
  ''';
}

List<double> _getEmbeddingForQuery({
  required SpannerDatabase database,
  required SpannerDatabaseDialect dialect,
  required String? spannerGsqlEmbeddingModelName,
  required String? spannerPgVertexAiEmbeddingModelEndpoint,
  required String query,
  int? outputDimensionality,
}) {
  late final String embeddingQuery;
  late final Map<String, Object?> params;

  if (dialect == SpannerDatabaseDialect.postgresql) {
    embeddingQuery = _generatePostgresqlForEmbeddingQuery(
      '$spannerPgVertexAiEmbeddingModelEndpoint',
      outputDimensionality,
    );
    params = <String, Object?>{'p$_postgresqlParameterTextQuery': query};
  } else {
    embeddingQuery = _generateGooglesqlForEmbeddingQuery(
      '$spannerGsqlEmbeddingModelName',
    );
    params = <String, Object?>{_googlesqlParameterTextQuery: query};
  }

  final SpannerSnapshot snapshot = database.snapshot();
  final SpannerResultSet resultSet = snapshot.executeSql(
    sql: embeddingQuery,
    params: params,
  );
  final Object? one = resultSet.one();
  final List<Object?> values = _asRow(one);
  if (values.isEmpty) {
    return <double>[];
  }
  return _asDoubleList(values[0]);
}

String _getPostgresqlDistanceFunction(String distanceType) {
  return <String, String>{
        'COSINE': 'spanner.cosine_distance',
        'EUCLIDEAN': 'spanner.euclidean_distance',
        'DOT_PRODUCT': 'spanner.dot_product',
      }[distanceType] ??
      (throw ArgumentError('Unsupported distance type: $distanceType'));
}

String _getGooglesqlDistanceFunction(String distanceType, bool ann) {
  if (ann) {
    return <String, String>{
          'COSINE': 'APPROX_COSINE_DISTANCE',
          'EUCLIDEAN': 'APPROX_EUCLIDEAN_DISTANCE',
          'DOT_PRODUCT': 'APPROX_DOT_PRODUCT',
        }[distanceType] ??
        (throw ArgumentError('Unsupported distance type: $distanceType'));
  }
  return <String, String>{
        'COSINE': 'COSINE_DISTANCE',
        'EUCLIDEAN': 'EUCLIDEAN_DISTANCE',
        'DOT_PRODUCT': 'DOT_PRODUCT',
      }[distanceType] ??
      (throw ArgumentError('Unsupported distance type: $distanceType'));
}

String _generateSqlForKnn({
  required SpannerDatabaseDialect dialect,
  required String tableName,
  required String embeddingColumnToSearch,
  required List<String> columns,
  required String? additionalFilter,
  required String distanceType,
  required int topK,
}) {
  final String distanceFunction;
  final String embeddingParameter;
  if (dialect == SpannerDatabaseDialect.postgresql) {
    distanceFunction = _getPostgresqlDistanceFunction(distanceType);
    embeddingParameter = '\$$_postgresqlParameterQueryEmbedding';
  } else {
    distanceFunction = _getGooglesqlDistanceFunction(distanceType, false);
    embeddingParameter = '@$_googlesqlParameterQueryEmbedding';
  }

  final List<String> selectColumns = <String>[
    ...columns,
    '''$distanceFunction(
      $embeddingColumnToSearch,
      $embeddingParameter) AS $_distanceAlias
  ''',
  ];

  final String filter = additionalFilter ?? '1=1';
  final String optionalLimitClause = topK > 0 ? 'LIMIT $topK' : '';

  return '''
    SELECT ${selectColumns.join(', ')}
    FROM $tableName
    WHERE $filter
    ORDER BY $_distanceAlias
    $optionalLimitClause
  ''';
}

String _generateSqlForAnn({
  required SpannerDatabaseDialect dialect,
  required String tableName,
  required String embeddingColumnToSearch,
  required List<String> columns,
  required String? additionalFilter,
  required String distanceType,
  required int topK,
  required int numLeavesToSearch,
}) {
  if (dialect == SpannerDatabaseDialect.postgresql) {
    throw UnsupportedError(
      '$approximateNearestNeighbors is not supported for PostgreSQL dialect.',
    );
  }

  final String distanceFunction = _getGooglesqlDistanceFunction(
    distanceType,
    true,
  );
  final List<String> selectColumns = <String>[
    ...columns,
    '''$distanceFunction(
      $embeddingColumnToSearch,
      @$_googlesqlParameterQueryEmbedding,
      options => JSON '{"num_leaves_to_search": $numLeavesToSearch}'
  ) AS $_distanceAlias
  ''',
  ];

  String queryFilter = '$embeddingColumnToSearch IS NOT NULL';
  if (additionalFilter != null) {
    queryFilter = '$queryFilter AND $additionalFilter';
  }

  return '''
    SELECT ${selectColumns.join(', ')}
    FROM $tableName
    WHERE $queryFilter
    ORDER BY $_distanceAlias
    LIMIT $topK
  ''';
}

Future<Map<String, Object?>> similaritySearch({
  required String projectId,
  required String instanceId,
  required String databaseId,
  required String tableName,
  required String query,
  required String embeddingColumnToSearch,
  required List<String> columns,
  required Map<String, Object?> embeddingOptions,
  required Object credentials,
  String? additionalFilter,
  Map<String, Object?>? searchOptions,
}) async {
  try {
    final SpannerClient spannerClient = getSpannerClient(
      project: projectId,
      credentials: credentials,
    );
    final SpannerInstance instance = spannerClient.instance(instanceId);
    final SpannerDatabase database = instance.database(databaseId);

    final SpannerDatabaseDialect dialect = database.databaseDialect;
    if (dialect != SpannerDatabaseDialect.googleStandardSql &&
        dialect != SpannerDatabaseDialect.postgresql) {
      throw ArgumentError('Unsupported database dialect: $dialect');
    }

    final Map<String, Object?> embeddingOpts = Map<String, Object?>.from(
      embeddingOptions,
    );
    final Map<String, Object?> searchOpts = searchOptions == null
        ? <String, Object?>{}
        : Map<String, Object?>.from(searchOptions);

    const Set<String> exclusiveEmbeddingModelKeys = <String>{
      _vertexAiEmbeddingModelNameKey,
      _spannerGsqlEmbeddingModelNameKey,
      _spannerPgVertexAiEmbeddingModelEndpointKey,
    };

    final int matchedModelKeys = exclusiveEmbeddingModelKeys
        .where((String key) => embeddingOpts.containsKey(key))
        .length;
    if (matchedModelKeys != 1) {
      throw ArgumentError(
        'Exactly one embedding model option must be specified.',
      );
    }

    final String? vertexAiEmbeddingModelName = _readNullableString(
      embeddingOpts[_vertexAiEmbeddingModelNameKey],
    );
    final String? spannerGsqlEmbeddingModelName = _readNullableString(
      embeddingOpts[_spannerGsqlEmbeddingModelNameKey],
    );
    final String? spannerPgVertexAiEmbeddingModelEndpoint = _readNullableString(
      embeddingOpts[_spannerPgVertexAiEmbeddingModelEndpointKey],
    );

    if (dialect == SpannerDatabaseDialect.googleStandardSql &&
        vertexAiEmbeddingModelName == null &&
        spannerGsqlEmbeddingModelName == null) {
      throw ArgumentError(
        "embedding_options['$_vertexAiEmbeddingModelNameKey'] or "
        "embedding_options['$_spannerGsqlEmbeddingModelNameKey'] must be "
        'specified for GoogleSQL dialect Spanner database.',
      );
    }

    if (dialect == SpannerDatabaseDialect.postgresql &&
        vertexAiEmbeddingModelName == null &&
        spannerPgVertexAiEmbeddingModelEndpoint == null) {
      throw ArgumentError(
        "embedding_options['$_vertexAiEmbeddingModelNameKey'] or "
        "embedding_options['$_spannerPgVertexAiEmbeddingModelEndpointKey'] "
        'must be specified for PostgreSQL dialect Spanner database.',
      );
    }

    final int? outputDimensionality = _asInt(
      embeddingOpts[_outputDimensionalityKey],
    );
    if (outputDimensionality != null && spannerGsqlEmbeddingModelName != null) {
      throw ArgumentError(
        'embedding_options[$_outputDimensionalityKey] is not supported when '
        "embedding_options['$_spannerGsqlEmbeddingModelNameKey'] is specified.",
      );
    }

    final String distanceType =
        _readNullableString(searchOpts[_distanceTypeKey]) ?? 'COSINE';
    final int topK = _asInt(searchOpts[_topKKey]) ?? 4;
    final String nearestNeighborsAlgorithm =
        _readNullableString(searchOpts[_nearestNeighborsAlgorithmKey]) ??
        exactNearestNeighbors;

    if (nearestNeighborsAlgorithm != exactNearestNeighbors &&
        nearestNeighborsAlgorithm != approximateNearestNeighbors) {
      throw UnsupportedError(
        "Unsupported search_options['$_nearestNeighborsAlgorithmKey']: "
        '$nearestNeighborsAlgorithm',
      );
    }

    final List<double> embedding;
    if (vertexAiEmbeddingModelName != null) {
      final List<List<double>> embeddings = utils.embedContents(
        vertexAiEmbeddingModelName: vertexAiEmbeddingModelName,
        contents: <String>[query],
        outputDimensionality: outputDimensionality,
      );
      embedding = embeddings.first;
    } else {
      embedding = _getEmbeddingForQuery(
        database: database,
        dialect: dialect,
        spannerGsqlEmbeddingModelName: spannerGsqlEmbeddingModelName,
        spannerPgVertexAiEmbeddingModelEndpoint:
            spannerPgVertexAiEmbeddingModelEndpoint,
        query: query,
        outputDimensionality: outputDimensionality,
      );
    }

    final String sql;
    if (nearestNeighborsAlgorithm == exactNearestNeighbors) {
      sql = _generateSqlForKnn(
        dialect: dialect,
        tableName: tableName,
        embeddingColumnToSearch: embeddingColumnToSearch,
        columns: columns,
        additionalFilter: additionalFilter,
        distanceType: distanceType,
        topK: topK,
      );
    } else {
      final int numLeavesToSearch =
          _asInt(searchOpts[_numLeavesToSearchKey]) ?? 1000;
      sql = _generateSqlForAnn(
        dialect: dialect,
        tableName: tableName,
        embeddingColumnToSearch: embeddingColumnToSearch,
        columns: columns,
        additionalFilter: additionalFilter,
        distanceType: distanceType,
        topK: topK,
        numLeavesToSearch: numLeavesToSearch,
      );
    }

    final Map<String, Object?> params =
        dialect == SpannerDatabaseDialect.postgresql
        ? <String, Object?>{'p$_postgresqlParameterQueryEmbedding': embedding}
        : <String, Object?>{_googlesqlParameterQueryEmbedding: embedding};

    final SpannerSnapshot snapshot = database.snapshot();
    final SpannerResultSet resultSet = snapshot.executeSql(
      sql: sql,
      params: params,
    );

    final List<Object?> rows = <Object?>[];
    for (final Object? row in resultSet.rows) {
      rows.add(_ensureJsonEncodable(row));
    }

    return <String, Object?>{'status': 'SUCCESS', 'rows': rows};
  } catch (error) {
    return <String, Object?>{'status': 'ERROR', 'error_details': '$error'};
  }
}

Future<Map<String, Object?>> vectorStoreSimilaritySearch({
  required String query,
  required Object credentials,
  required Object settings,
}) async {
  try {
    final SpannerToolSettings toolSettings = SpannerToolSettings.fromObject(
      settings,
    );
    final SpannerVectorStoreSettings? vectorSettings =
        toolSettings.vectorStoreSettings;
    if (vectorSettings == null) {
      throw ArgumentError('Spanner vector store settings are not set.');
    }

    final Map<String, Object?> embeddingOptions = <String, Object?>{
      _vertexAiEmbeddingModelNameKey: vectorSettings.vertexAiEmbeddingModelName,
      _outputDimensionalityKey: vectorSettings.vectorLength,
    };

    final Map<String, Object?> searchOptions = <String, Object?>{
      _topKKey: vectorSettings.topK,
      _distanceTypeKey: vectorSettings.distanceType,
      _nearestNeighborsAlgorithmKey: vectorSettings.nearestNeighborsAlgorithm,
    };
    if (vectorSettings.nearestNeighborsAlgorithm ==
        approximateNearestNeighbors) {
      searchOptions[_numLeavesToSearchKey] = vectorSettings.numLeavesToSearch;
    }

    return similaritySearch(
      projectId: vectorSettings.projectId,
      instanceId: vectorSettings.instanceId,
      databaseId: vectorSettings.databaseId,
      tableName: vectorSettings.tableName,
      query: query,
      embeddingColumnToSearch: vectorSettings.embeddingColumn,
      columns: vectorSettings.selectedColumns,
      embeddingOptions: embeddingOptions,
      credentials: credentials,
      additionalFilter: vectorSettings.additionalFilter,
      searchOptions: searchOptions,
    );
  } catch (error) {
    return <String, Object?>{'status': 'ERROR', 'error_details': '$error'};
  }
}

Object? _ensureJsonEncodable(Object? value) {
  try {
    jsonEncode(value);
    return value;
  } catch (_) {
    return '$value';
  }
}

String? _readNullableString(Object? value) {
  if (value == null) {
    return null;
  }
  final String text = '$value';
  return text.isEmpty ? null : text;
}

int? _asInt(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value.trim());
  }
  return null;
}

List<double> _asDoubleList(Object? value) {
  if (value == null) {
    return <double>[];
  }
  if (value is List) {
    return value
        .map((Object? item) => item is num ? item.toDouble() : 0.0)
        .toList(growable: false);
  }
  if (value is Iterable) {
    return value
        .map((Object? item) => item is num ? item.toDouble() : 0.0)
        .toList(growable: false);
  }
  return <double>[];
}

List<Object?> _asRow(Object? row) {
  if (row is List) {
    return row.cast<Object?>();
  }
  if (row is Iterable) {
    return row.cast<Object?>().toList(growable: false);
  }
  if (row is Map) {
    return row.values.cast<Object?>().toList(growable: false);
  }
  return <Object?>[row];
}
