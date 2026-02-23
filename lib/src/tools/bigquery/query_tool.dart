import 'dart:convert';
import 'dart:math';

import '../tool_context.dart';
import 'client.dart';
import 'config.dart';

const String bigQuerySessionInfoKey = 'bigquery_session_info';

Future<Map<String, Object?>> _executeSql({
  required String projectId,
  required String query,
  required Object credentials,
  required BigQueryToolConfig settings,
  required ToolContext toolContext,
  bool dryRun = false,
  String? callerId,
}) async {
  try {
    if (settings.computeProjectId != null &&
        projectId != settings.computeProjectId) {
      return <String, Object?>{
        'status': 'ERROR',
        'error_details':
            'Cannot execute query in the project $projectId, as the tool '
            'is restricted to execute queries only in the project '
            '${settings.computeProjectId}.',
      };
    }

    final BigQueryClient bqClient = getBigQueryClient(
      project: projectId,
      credentials: credentials,
      location: settings.location,
      userAgent: <String?>[
        settings.applicationName,
        callerId,
      ].whereType<String>(),
    );

    final List<BigQueryConnectionProperty> connectionProperties =
        <BigQueryConnectionProperty>[];

    final Map<String, String> jobLabels = settings.jobLabels == null
        ? <String, String>{}
        : Map<String, String>.from(settings.jobLabels!);
    if (callerId != null && callerId.isNotEmpty) {
      jobLabels['adk-bigquery-tool'] = callerId;
    }
    if (settings.applicationName != null &&
        settings.applicationName!.isNotEmpty) {
      jobLabels['adk-bigquery-application-name'] = settings.applicationName!;
    }

    if (settings.writeMode == WriteMode.blocked) {
      final BigQueryQueryJob dryRunQueryJob = bqClient.query(
        query: query,
        project: projectId,
        jobConfig: BigQueryQueryJobConfig(dryRun: true, labels: jobLabels),
      );
      if ((dryRunQueryJob.statementType ?? '').toUpperCase() != 'SELECT') {
        return <String, Object?>{
          'status': 'ERROR',
          'error_details': 'Read-only mode only supports SELECT statements.',
        };
      }
    } else if (settings.writeMode == WriteMode.protected) {
      final List<String>? existingSession = _readSessionInfo(
        toolContext.state[bigQuerySessionInfoKey],
      );

      String bqSessionId;
      String bqSessionDatasetId;
      if (existingSession != null) {
        bqSessionId = existingSession[0];
        bqSessionDatasetId = existingSession[1];
      } else {
        final BigQueryQueryJob sessionCreatorJob = bqClient.query(
          query: 'SELECT 1',
          project: projectId,
          jobConfig: BigQueryQueryJobConfig(
            dryRun: true,
            createSession: true,
            labels: jobLabels,
          ),
        );
        bqSessionId = sessionCreatorJob.sessionInfo?.sessionId ?? '';
        bqSessionDatasetId = sessionCreatorJob.destination?.datasetId ?? '';
        if (bqSessionId.isEmpty || bqSessionDatasetId.isEmpty) {
          return <String, Object?>{
            'status': 'ERROR',
            'error_details':
                'Failed to initialize protected BigQuery session information.',
          };
        }

        toolContext.state[bigQuerySessionInfoKey] = <String>[
          bqSessionId,
          bqSessionDatasetId,
        ];
      }

      connectionProperties.add(
        BigQueryConnectionProperty('session_id', bqSessionId),
      );

      final BigQueryQueryJob dryRunQueryJob = bqClient.query(
        query: query,
        project: projectId,
        jobConfig: BigQueryQueryJobConfig(
          dryRun: true,
          connectionProperties: connectionProperties,
          labels: jobLabels,
        ),
      );
      final String statementType = (dryRunQueryJob.statementType ?? '')
          .toUpperCase();
      if (statementType != 'SELECT') {
        final String? destinationDatasetId =
            dryRunQueryJob.destination?.datasetId;
        if (destinationDatasetId != null &&
            destinationDatasetId != bqSessionDatasetId) {
          return <String, Object?>{
            'status': 'ERROR',
            'error_details':
                'Protected write mode only supports SELECT statements, '
                'or write operations in the anonymous dataset of a '
                'BigQuery session.',
          };
        }
      }
    }

    if (dryRun) {
      final BigQueryQueryJob dryRunJob = bqClient.query(
        query: query,
        project: projectId,
        jobConfig: BigQueryQueryJobConfig(
          dryRun: true,
          connectionProperties: connectionProperties,
          labels: jobLabels,
        ),
      );
      return <String, Object?>{
        'status': 'SUCCESS',
        'dry_run_info': dryRunJob.toApiRepr(),
      };
    }

    final BigQueryQueryJobConfig jobConfig = BigQueryQueryJobConfig(
      connectionProperties: connectionProperties,
      labels: jobLabels,
      maximumBytesBilled: settings.maximumBytesBilled,
    );

    final Iterable<Map<String, Object?>> rowIterator = bqClient.queryAndWait(
      query: query,
      project: projectId,
      jobConfig: jobConfig,
      maxResults: settings.maxQueryResultRows,
    );

    final List<Map<String, Object?>> rows = <Map<String, Object?>>[];
    for (final Map<String, Object?> row in rowIterator) {
      final Map<String, Object?> normalized = <String, Object?>{};
      for (final MapEntry<String, Object?> entry in row.entries) {
        normalized[entry.key] = _ensureJsonEncodable(entry.value);
      }
      rows.add(normalized);
    }

    final Map<String, Object?> result = <String, Object?>{
      'status': 'SUCCESS',
      'rows': rows,
    };
    if (rows.length == settings.maxQueryResultRows) {
      result['result_is_likely_truncated'] = true;
    }
    return result;
  } catch (error) {
    return <String, Object?>{'status': 'ERROR', 'error_details': '$error'};
  }
}

Future<Map<String, Object?>> executeSql({
  required String projectId,
  required String query,
  required Object credentials,
  required Object settings,
  required ToolContext toolContext,
  bool dryRun = false,
}) {
  return _executeSql(
    projectId: projectId,
    query: query,
    credentials: credentials,
    settings: BigQueryToolConfig.fromObject(settings),
    toolContext: toolContext,
    dryRun: dryRun,
    callerId: 'execute_sql',
  );
}

typedef ExecuteSqlTool =
    Future<Map<String, Object?>> Function({
      required String projectId,
      required String query,
      required Object credentials,
      required Object settings,
      required ToolContext toolContext,
      bool dryRun,
    });

ExecuteSqlTool getExecuteSql(BigQueryToolConfig settings) {
  settings;
  return executeSql;
}

Future<Map<String, Object?>> forecast({
  required String projectId,
  required String historyData,
  required String timestampCol,
  required String dataCol,
  int horizon = 10,
  List<Object?>? idCols,
  required Object credentials,
  required Object settings,
  required ToolContext toolContext,
}) {
  const String model = 'TimesFM 2.0';
  const double confidenceLevel = 0.95;

  final String historyDataSource = _asTableOrSubquery(
    historyData,
    asTable: true,
  );

  String query;
  if (idCols != null && idCols.isNotEmpty) {
    if (!idCols.every((Object? item) => item is String)) {
      return Future<Map<String, Object?>>.value(<String, Object?>{
        'status': 'ERROR',
        'error_details': 'All elements in id_cols must be strings.',
      });
    }

    final String idColsStr =
        '[${idCols.cast<String>().map((String col) => "'$col'").join(', ')}]';
    query =
        '''
  SELECT * FROM AI.FORECAST(
    $historyDataSource,
    data_col => '$dataCol',
    timestamp_col => '$timestampCol',
    model => '$model',
    id_cols => $idColsStr,
    horizon => $horizon,
    confidence_level => $confidenceLevel
  )
  ''';
  } else {
    query =
        '''
  SELECT * FROM AI.FORECAST(
    $historyDataSource,
    data_col => '$dataCol',
    timestamp_col => '$timestampCol',
    model => '$model',
    horizon => $horizon,
    confidence_level => $confidenceLevel
  )
  ''';
  }

  return _executeSql(
    projectId: projectId,
    query: query,
    credentials: credentials,
    settings: BigQueryToolConfig.fromObject(settings),
    toolContext: toolContext,
    callerId: 'forecast',
  );
}

Future<Map<String, Object?>> analyzeContribution({
  required String projectId,
  required String inputData,
  required String contributionMetric,
  required List<Object?> dimensionIdCols,
  required String isTestCol,
  required Object credentials,
  required Object settings,
  required ToolContext toolContext,
  int topKInsights = 30,
  String pruningMethod = 'PRUNE_REDUNDANT_INSIGHTS',
}) async {
  if (!dimensionIdCols.every((Object? item) => item is String)) {
    return <String, Object?>{
      'status': 'ERROR',
      'error_details': 'All elements in dimension_id_cols must be strings.',
    };
  }

  final String upperPruning = pruningMethod.toUpperCase();
  if (upperPruning != 'NO_PRUNING' &&
      upperPruning != 'PRUNE_REDUNDANT_INSIGHTS') {
    return <String, Object?>{
      'status': 'ERROR',
      'error_details': 'Invalid pruning_method: $pruningMethod',
    };
  }

  final String modelName = 'contribution_analysis_model_${_randomIdentifier()}';

  final List<String> dimensionCols = dimensionIdCols.cast<String>();
  final String idColsStr =
      '[${dimensionCols.map((String col) => "'$col'").join(', ')}]';

  final String optionsStr = <String>[
    "MODEL_TYPE = 'CONTRIBUTION_ANALYSIS'",
    "CONTRIBUTION_METRIC = '$contributionMetric'",
    "IS_TEST_COL = '$isTestCol'",
    'DIMENSION_ID_COLS = $idColsStr',
    'TOP_K_INSIGHTS_BY_APRIORI_SUPPORT = $topKInsights',
    "PRUNING_METHOD = '$upperPruning'",
  ].join(', ');

  final String inputDataSource = _asTableOrSubquery(inputData);

  final String createModelQuery =
      '''
  CREATE TEMP MODEL $modelName
    OPTIONS ($optionsStr)
  AS $inputDataSource
  ''';

  final String getInsightsQuery =
      '''
  SELECT * FROM ML.GET_INSIGHTS(MODEL $modelName)
  ''';

  try {
    BigQueryToolConfig executeSqlSettings = BigQueryToolConfig.fromObject(
      settings,
    );
    if (executeSqlSettings.writeMode == WriteMode.blocked) {
      throw ArgumentError(
        'analyze_contribution is not allowed in this session.',
      );
    } else if (executeSqlSettings.writeMode != WriteMode.protected) {
      executeSqlSettings = executeSqlSettings.copyWith(
        writeMode: WriteMode.protected,
      );
    }

    Map<String, Object?> result = await _executeSql(
      projectId: projectId,
      query: createModelQuery,
      credentials: credentials,
      settings: executeSqlSettings,
      toolContext: toolContext,
      callerId: 'analyze_contribution',
    );
    if (result['status'] != 'SUCCESS') {
      return result;
    }

    result = await _executeSql(
      projectId: projectId,
      query: getInsightsQuery,
      credentials: credentials,
      settings: executeSqlSettings,
      toolContext: toolContext,
      callerId: 'analyze_contribution',
    );
    return result;
  } catch (error) {
    return <String, Object?>{
      'status': 'ERROR',
      'error_details': 'Error during analyze_contribution: $error',
    };
  }
}

Future<Map<String, Object?>> detectAnomalies({
  required String projectId,
  required String historyData,
  required String timesSeriesTimestampCol,
  required String timesSeriesDataCol,
  int horizon = 1000,
  String? targetData,
  List<Object?>? timesSeriesIdCols,
  double anomalyProbThreshold = 0.95,
  required Object credentials,
  required Object settings,
  required ToolContext toolContext,
}) async {
  final String historyDataSource = _asTableOrSubquery(historyData);

  final List<String> options = <String>[
    "MODEL_TYPE = 'ARIMA_PLUS'",
    "TIME_SERIES_TIMESTAMP_COL = '$timesSeriesTimestampCol'",
    "TIME_SERIES_DATA_COL = '$timesSeriesDataCol'",
    'HORIZON = $horizon',
  ];

  List<String>? idCols;
  if (timesSeriesIdCols != null && timesSeriesIdCols.isNotEmpty) {
    if (!timesSeriesIdCols.every((Object? item) => item is String)) {
      return <String, Object?>{
        'status': 'ERROR',
        'error_details':
            'All elements in times_series_id_cols must be strings.',
      };
    }
    idCols = timesSeriesIdCols.cast<String>();
    final String idColsStr =
        '[${idCols.map((String col) => "'$col'").join(', ')}]';
    options.add('TIME_SERIES_ID_COL = $idColsStr');
  }

  final String modelName = 'detect_anomalies_model_${_randomIdentifier()}';

  final String createModelQuery =
      '''
  CREATE TEMP MODEL $modelName
    OPTIONS (${options.join(', ')})
  AS $historyDataSource
  ''';

  final String orderByIdCols = idCols == null ? '' : '${idCols.join(', ')}, ';

  String anomalyDetectionQuery =
      '''
  SELECT * FROM ML.DETECT_ANOMALIES(
    MODEL $modelName,
    STRUCT($anomalyProbThreshold AS anomaly_prob_threshold)
  ) ORDER BY $orderByIdCols$timesSeriesTimestampCol
  ''';

  if (targetData != null && targetData.trim().isNotEmpty) {
    final String targetDataSource = _asTableOrSubquery(
      targetData,
      forceSelect: true,
    );
    anomalyDetectionQuery =
        '''
    SELECT * FROM ML.DETECT_ANOMALIES(
      MODEL $modelName,
      STRUCT($anomalyProbThreshold AS anomaly_prob_threshold),
      $targetDataSource
    ) ORDER BY $orderByIdCols$timesSeriesTimestampCol
    ''';
  }

  try {
    BigQueryToolConfig executeSqlSettings = BigQueryToolConfig.fromObject(
      settings,
    );
    if (executeSqlSettings.writeMode == WriteMode.blocked) {
      throw ArgumentError('anomaly detection is not allowed in this session.');
    } else if (executeSqlSettings.writeMode != WriteMode.protected) {
      executeSqlSettings = executeSqlSettings.copyWith(
        writeMode: WriteMode.protected,
      );
    }

    Map<String, Object?> result = await _executeSql(
      projectId: projectId,
      query: createModelQuery,
      credentials: credentials,
      settings: executeSqlSettings,
      toolContext: toolContext,
      callerId: 'detect_anomalies',
    );

    if (result['status'] != 'SUCCESS') {
      return result;
    }

    result = await _executeSql(
      projectId: projectId,
      query: anomalyDetectionQuery,
      credentials: credentials,
      settings: executeSqlSettings,
      toolContext: toolContext,
      callerId: 'detect_anomalies',
    );

    return result;
  } catch (error) {
    return <String, Object?>{
      'status': 'ERROR',
      'error_details': 'Error during anomaly detection: $error',
    };
  }
}

List<String>? _readSessionInfo(Object? rawValue) {
  if (rawValue is List && rawValue.length >= 2) {
    final String sessionId = '${rawValue[0]}';
    final String datasetId = '${rawValue[1]}';
    if (sessionId.isNotEmpty && datasetId.isNotEmpty) {
      return <String>[sessionId, datasetId];
    }
  }
  return null;
}

Object? _ensureJsonEncodable(Object? value) {
  try {
    jsonEncode(value);
    return value;
  } catch (_) {
    return '$value';
  }
}

String _asTableOrSubquery(
  String text, {
  bool asTable = false,
  bool forceSelect = false,
}) {
  final String trimmed = text.trim();
  final String upper = trimmed.toUpperCase();
  final bool isQuery = upper.startsWith('SELECT') || upper.startsWith('WITH');
  if (isQuery) {
    return '($trimmed)';
  }

  if (forceSelect) {
    return '(SELECT * FROM `$trimmed`)';
  }

  if (asTable) {
    return 'TABLE `$trimmed`';
  }

  return 'SELECT * FROM `$trimmed`';
}

String _randomIdentifier() {
  final Random random = Random();
  final int micros = DateTime.now().microsecondsSinceEpoch;
  final int noise = random.nextInt(1 << 32);
  return '${micros.toRadixString(16)}_${noise.toRadixString(16)}';
}
