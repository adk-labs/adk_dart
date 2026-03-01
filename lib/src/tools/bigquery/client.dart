import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../_google_auth_token.dart';
import '../../version.dart';

const String bigQueryUserAgent = 'adk-bigquery-tool google-adk/$adkVersion';

class BigQueryDatasetReference {
  const BigQueryDatasetReference({
    required this.projectId,
    required this.datasetId,
  });

  final String projectId;
  final String datasetId;
}

class BigQueryTableReference {
  const BigQueryTableReference({required this.dataset, required this.tableId});

  final BigQueryDatasetReference dataset;
  final String tableId;

  String get projectId => dataset.projectId;

  String get datasetId => dataset.datasetId;
}

class BigQuerySessionInfo {
  const BigQuerySessionInfo({required this.sessionId});

  final String sessionId;
}

class BigQueryConnectionProperty {
  const BigQueryConnectionProperty(this.key, this.value);

  final String key;
  final String value;
}

class BigQueryQueryJobConfig {
  const BigQueryQueryJobConfig({
    this.dryRun = false,
    this.createSession = false,
    this.connectionProperties = const <BigQueryConnectionProperty>[],
    this.labels = const <String, String>{},
    this.maximumBytesBilled,
  });

  final bool dryRun;
  final bool createSession;
  final List<BigQueryConnectionProperty> connectionProperties;
  final Map<String, String> labels;
  final int? maximumBytesBilled;
}

abstract class BigQueryDatasetListItem {
  String get datasetId;
}

abstract class BigQueryTableListItem {
  String get tableId;
}

abstract class BigQueryResourceInfo {
  Map<String, Object?> toApiRepr();
}

abstract class BigQueryJobInfo {
  Map<String, Object?> get properties;
}

abstract class BigQueryQueryJob {
  String? get statementType;

  BigQueryTableReference? get destination;

  BigQuerySessionInfo? get sessionInfo;

  Map<String, Object?> toApiRepr();
}

abstract class BigQueryClient {
  Iterable<BigQueryDatasetListItem> listDatasets(String projectId);

  BigQueryResourceInfo getDataset(BigQueryDatasetReference reference);

  Iterable<BigQueryTableListItem> listTables(
    BigQueryDatasetReference reference,
  );

  BigQueryResourceInfo getTable(BigQueryTableReference reference);

  BigQueryJobInfo getJob(String jobId);

  BigQueryQueryJob query({
    required String query,
    required String project,
    required BigQueryQueryJobConfig jobConfig,
  });

  Iterable<Map<String, Object?>> queryAndWait({
    required String query,
    required String project,
    required BigQueryQueryJobConfig jobConfig,
    required int maxResults,
  });
}

typedef BigQueryClientFactory =
    BigQueryClient Function({
      required String? project,
      required Object credentials,
      String? location,
      required List<String> userAgent,
    });

BigQueryClientFactory _bigQueryClientFactory = _defaultBigQueryClientFactory;

BigQueryClient getBigQueryClient({
  required String? project,
  required Object credentials,
  String? location,
  Object? userAgent,
}) {
  return _bigQueryClientFactory(
    project: project,
    credentials: credentials,
    location: location,
    userAgent: _resolveUserAgents(userAgent),
  );
}

void setBigQueryClientFactory(BigQueryClientFactory factory) {
  _bigQueryClientFactory = factory;
}

void resetBigQueryClientFactory() {
  _bigQueryClientFactory = _defaultBigQueryClientFactory;
}

BigQueryClient _defaultBigQueryClientFactory({
  required String? project,
  required Object credentials,
  String? location,
  required List<String> userAgent,
}) {
  return _RestBigQueryClient(
    project: project,
    credentials: credentials,
    location: location,
    userAgents: userAgent,
  );
}

List<String> _resolveUserAgents(Object? userAgent) {
  final List<String> userAgents = <String>[bigQueryUserAgent];
  if (userAgent is String) {
    final String trimmed = userAgent.trim();
    if (trimmed.isNotEmpty) {
      userAgents.add(trimmed);
    }
    return userAgents;
  }

  if (userAgent is Iterable) {
    for (final Object? value in userAgent) {
      final String text = '$value'.trim();
      if (text.isNotEmpty) {
        userAgents.add(text);
      }
    }
  }

  return userAgents;
}

const List<String> _bigQueryScopes = <String>[
  'https://www.googleapis.com/auth/bigquery',
  'https://www.googleapis.com/auth/cloud-platform',
];

class _RestBigQueryClient implements BigQueryClient {
  _RestBigQueryClient({
    required this.project,
    required this.credentials,
    required this.location,
    required this.userAgents,
  });

  final String? project;
  final Object credentials;
  final String? location;
  final List<String> userAgents;

  static const String _baseApiUrl = 'https://bigquery.googleapis.com';

  @override
  Iterable<BigQueryDatasetListItem> listDatasets(String projectId) sync* {
    final List<Map<String, Object?>> items = _collectListEntriesSync(
      listKey: 'datasets',
      path: '/bigquery/v2/projects/${Uri.encodeComponent(projectId)}/datasets',
    );
    for (final Map<String, Object?> item in items) {
      final Map<String, Object?> reference = _map(item['datasetReference']);
      final String datasetId = _string(reference['datasetId']) ?? '';
      if (datasetId.isNotEmpty) {
        yield _RestBigQueryDatasetListItem(datasetId);
      }
    }
  }

  @override
  BigQueryResourceInfo getDataset(BigQueryDatasetReference reference) {
    final Map<String, Object?> payload = _requestJsonSync(
      method: 'GET',
      path:
          '/bigquery/v2/projects/${Uri.encodeComponent(reference.projectId)}'
          '/datasets/${Uri.encodeComponent(reference.datasetId)}',
    );
    return _RestBigQueryResourceInfo(payload);
  }

  @override
  Iterable<BigQueryTableListItem> listTables(
    BigQueryDatasetReference reference,
  ) sync* {
    final List<Map<String, Object?>> items = _collectListEntriesSync(
      listKey: 'tables',
      path:
          '/bigquery/v2/projects/${Uri.encodeComponent(reference.projectId)}'
          '/datasets/${Uri.encodeComponent(reference.datasetId)}/tables',
    );
    for (final Map<String, Object?> item in items) {
      final Map<String, Object?> tableReference = _map(item['tableReference']);
      final String tableId = _string(tableReference['tableId']) ?? '';
      if (tableId.isNotEmpty) {
        yield _RestBigQueryTableListItem(tableId);
      }
    }
  }

  @override
  BigQueryResourceInfo getTable(BigQueryTableReference reference) {
    final Map<String, Object?> payload = _requestJsonSync(
      method: 'GET',
      path:
          '/bigquery/v2/projects/${Uri.encodeComponent(reference.projectId)}'
          '/datasets/${Uri.encodeComponent(reference.datasetId)}'
          '/tables/${Uri.encodeComponent(reference.tableId)}',
    );
    return _RestBigQueryResourceInfo(payload);
  }

  @override
  BigQueryJobInfo getJob(String jobId) {
    final String resolvedProject = _requiredProject();
    final _ParsedJobId parsed = _parseJobId(jobId);
    final Map<String, Object?> payload = _requestJsonSync(
      method: 'GET',
      path:
          '/bigquery/v2/projects/${Uri.encodeComponent(resolvedProject)}'
          '/jobs/${Uri.encodeComponent(parsed.jobId)}',
      queryParameters: <String, String>{
        if (parsed.location != null) 'location': parsed.location!,
      },
    );
    return _RestBigQueryJobInfo(payload);
  }

  @override
  BigQueryQueryJob query({
    required String query,
    required String project,
    required BigQueryQueryJobConfig jobConfig,
  }) {
    final Map<String, Object?> payload = _insertQueryJobSync(
      queryText: query,
      projectId: project,
      jobConfig: jobConfig,
    );
    return _RestBigQueryQueryJob.fromPayload(payload);
  }

  @override
  Iterable<Map<String, Object?>> queryAndWait({
    required String query,
    required String project,
    required BigQueryQueryJobConfig jobConfig,
    required int maxResults,
  }) sync* {
    final Map<String, Object?> jobPayload = _insertQueryJobSync(
      queryText: query,
      projectId: project,
      jobConfig: jobConfig,
    );
    final Map<String, Object?> jobReference = _map(jobPayload['jobReference']);
    final String jobId = _string(jobReference['jobId']) ?? '';
    if (jobId.isEmpty) {
      throw StateError(
        'BigQuery job submission did not return a valid job id.',
      );
    }
    final String? resolvedLocation =
        _string(jobReference['location']) ?? location;

    _waitForQueryJobDoneSync(
      projectId: project,
      jobId: jobId,
      location: resolvedLocation,
    );

    for (final Map<String, Object?> row in _readQueryResultsSync(
      projectId: project,
      jobId: jobId,
      location: resolvedLocation,
      maxResults: maxResults,
    )) {
      yield row;
    }
  }

  String _requiredProject() {
    final String resolved = (project ?? '').trim();
    if (resolved.isEmpty) {
      throw ArgumentError('A BigQuery project id is required.');
    }
    return resolved;
  }

  _ParsedJobId _parseJobId(String jobId) {
    final String trimmed = jobId.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('jobId cannot be empty.');
    }
    if (!trimmed.contains(':')) {
      return _ParsedJobId(jobId: trimmed, location: location);
    }
    final List<String> parts = trimmed.split(':');
    if (parts.length != 2 || parts[0].trim().isEmpty) {
      return _ParsedJobId(jobId: trimmed, location: location);
    }
    return _ParsedJobId(
      jobId: parts[1].trim(),
      location: parts[0].trim().isEmpty ? location : parts[0].trim(),
    );
  }

  List<Map<String, Object?>> _collectListEntriesSync({
    required String listKey,
    required String path,
  }) {
    final List<Map<String, Object?>> entries = <Map<String, Object?>>[];
    String? nextPageToken;
    do {
      final Map<String, String> query = <String, String>{
        if (nextPageToken != null && nextPageToken.isNotEmpty)
          'pageToken': nextPageToken,
      };
      final Map<String, Object?> payload = _requestJsonSync(
        method: 'GET',
        path: path,
        queryParameters: query,
      );
      final List<Map<String, Object?>> pageEntries = _listOfMaps(
        payload[listKey],
      );
      entries.addAll(pageEntries);
      nextPageToken = _string(payload['nextPageToken']);
    } while (nextPageToken != null && nextPageToken.isNotEmpty);
    return entries;
  }

  Map<String, Object?> _insertQueryJobSync({
    required String queryText,
    required String projectId,
    required BigQueryQueryJobConfig jobConfig,
  }) {
    final Map<String, Object?> queryConfiguration = <String, Object?>{
      'query': queryText,
      'useLegacySql': false,
      if (jobConfig.createSession) 'createSession': true,
      if (jobConfig.maximumBytesBilled != null)
        'maximumBytesBilled': '${jobConfig.maximumBytesBilled}',
      if (jobConfig.connectionProperties.isNotEmpty)
        'connectionProperties': jobConfig.connectionProperties
            .map(
              (BigQueryConnectionProperty item) => <String, Object?>{
                'key': item.key,
                'value': item.value,
              },
            )
            .toList(growable: false),
    };

    final Map<String, Object?> configuration = <String, Object?>{
      'query': queryConfiguration,
      if (jobConfig.dryRun) 'dryRun': true,
      if (jobConfig.labels.isNotEmpty)
        'labels': Map<String, Object?>.from(jobConfig.labels),
    };

    final Map<String, Object?> body = <String, Object?>{
      'configuration': configuration,
      if (location != null && location!.trim().isNotEmpty)
        'jobReference': <String, Object?>{'location': location},
    };

    return _requestJsonSync(
      method: 'POST',
      path: '/bigquery/v2/projects/${Uri.encodeComponent(projectId)}/jobs',
      body: body,
    );
  }

  void _waitForQueryJobDoneSync({
    required String projectId,
    required String jobId,
    required String? location,
  }) {
    const int maxAttempts = 90;
    for (int attempt = 0; attempt < maxAttempts; attempt += 1) {
      final Map<String, Object?> payload = _requestJsonSync(
        method: 'GET',
        path:
            '/bigquery/v2/projects/${Uri.encodeComponent(projectId)}'
            '/jobs/${Uri.encodeComponent(jobId)}',
        queryParameters: <String, String>{
          if (location != null && location.isNotEmpty) 'location': location,
        },
      );
      final Map<String, Object?> status = _map(payload['status']);
      final String state = (_string(status['state']) ?? '').toUpperCase();
      if (state == 'DONE') {
        final Map<String, Object?> errorResult = _map(status['errorResult']);
        if (errorResult.isNotEmpty) {
          throw StateError('BigQuery job failed: ${jsonEncode(errorResult)}');
        }
        return;
      }
      final int delayMs = min(250 * (attempt + 1), 2000);
      sleep(Duration(milliseconds: delayMs));
    }
    throw TimeoutException(
      'Timed out waiting for BigQuery query job `$jobId` to complete.',
    );
  }

  List<Map<String, Object?>> _readQueryResultsSync({
    required String projectId,
    required String jobId,
    required String? location,
    required int maxResults,
  }) {
    final List<Map<String, Object?>> rows = <Map<String, Object?>>[];
    String? pageToken;

    do {
      final int remaining = maxResults - rows.length;
      if (remaining <= 0) {
        break;
      }

      final Map<String, String> query = <String, String>{
        'maxResults': '$remaining',
        if (location != null && location.isNotEmpty) 'location': location,
        if (pageToken != null && pageToken.isNotEmpty) 'pageToken': pageToken,
      };

      final Map<String, Object?> payload = _requestJsonSync(
        method: 'GET',
        path:
            '/bigquery/v2/projects/${Uri.encodeComponent(projectId)}'
            '/queries/${Uri.encodeComponent(jobId)}',
        queryParameters: query,
      );

      final List<Map<String, Object?>> fields = _listOfMaps(
        _map(payload['schema'])['fields'],
      );
      final List<Map<String, Object?>> rawRows = _listOfMaps(payload['rows']);
      rows.addAll(_decodeRows(rawRows: rawRows, fields: fields));

      pageToken = _string(payload['pageToken']);
    } while (pageToken != null &&
        pageToken.isNotEmpty &&
        rows.length < maxResults);

    if (rows.length > maxResults) {
      return rows.take(maxResults).toList(growable: false);
    }
    return rows;
  }

  List<Map<String, Object?>> _decodeRows({
    required List<Map<String, Object?>> rawRows,
    required List<Map<String, Object?>> fields,
  }) {
    if (fields.isEmpty) {
      return rawRows;
    }

    final List<Map<String, Object?>> rows = <Map<String, Object?>>[];
    for (final Map<String, Object?> row in rawRows) {
      final List<Object?> values = _list(_map(row)['f']);
      final Map<String, Object?> parsed = <String, Object?>{};
      for (int i = 0; i < fields.length; i += 1) {
        final Map<String, Object?> field = fields[i];
        final String name = _string(field['name']) ?? 'column_$i';
        final Object? value = i < values.length ? values[i] : null;
        parsed[name] = _decodeValue(value, field);
      }
      rows.add(parsed);
    }
    return rows;
  }

  Object? _decodeValue(Object? rawValue, Map<String, Object?> field) {
    Object? value = rawValue;
    if (value is Map && value.containsKey('v')) {
      value = value['v'];
    }

    final String mode = (_string(field['mode']) ?? '').toUpperCase();
    final String type = (_string(field['type']) ?? '').toUpperCase();

    if (mode == 'REPEATED') {
      final List<Object?> repeatedValues = _list(value);
      return repeatedValues
          .map((Object? item) {
            if (item is Map && item.containsKey('v')) {
              return _decodeValue(item, <String, Object?>{
                ...field,
                'mode': 'NULLABLE',
              });
            }
            return _decodeValue(
              <String, Object?>{'v': item},
              <String, Object?>{...field, 'mode': 'NULLABLE'},
            );
          })
          .toList(growable: false);
    }

    if (value == null) {
      return null;
    }

    if (type == 'RECORD' || type == 'STRUCT') {
      final List<Map<String, Object?>> nestedFields = _listOfMaps(
        field['fields'],
      );
      final List<Object?> nestedValues = _list(_map(value)['f']);
      final Map<String, Object?> nested = <String, Object?>{};
      for (int i = 0; i < nestedFields.length; i += 1) {
        final Map<String, Object?> nestedField = nestedFields[i];
        final String nestedName = _string(nestedField['name']) ?? 'field_$i';
        final Object? nestedValue = i < nestedValues.length
            ? nestedValues[i]
            : null;
        nested[nestedName] = _decodeValue(nestedValue, nestedField);
      }
      return nested;
    }

    final String text = '$value';
    switch (type) {
      case 'BOOL':
      case 'BOOLEAN':
        return text.toLowerCase() == 'true';
      case 'INT64':
      case 'INTEGER':
        return int.tryParse(text) ?? text;
      case 'FLOAT':
      case 'FLOAT64':
      case 'NUMERIC':
      case 'BIGNUMERIC':
        return num.tryParse(text) ?? text;
      case 'JSON':
        try {
          return jsonDecode(text);
        } on FormatException {
          return text;
        }
      default:
        return value;
    }
  }

  Map<String, Object?> _requestJsonSync({
    required String method,
    required String path,
    Map<String, String>? queryParameters,
    Map<String, Object?>? body,
  }) {
    final Uri uri = Uri.parse(_baseApiUrl).replace(
      path: path,
      queryParameters: queryParameters == null || queryParameters.isEmpty
          ? null
          : queryParameters,
    );
    final String accessToken = _resolveAccessTokenSync();

    final List<String> args = <String>[
      '-sS',
      '-X',
      method.toUpperCase(),
      uri.toString(),
      '-H',
      'Authorization: Bearer $accessToken',
      '-H',
      'Accept: application/json',
      if (userAgents.isNotEmpty) ...<String>[
        '-H',
        'User-Agent: ${userAgents.join(' ')}',
      ],
      if (body != null) ...<String>[
        '-H',
        'Content-Type: application/json',
        '--data-binary',
        jsonEncode(body),
      ],
      '-w',
      '\n%{http_code}',
    ];

    final ProcessResult result = Process.runSync('curl', args);
    if (result.exitCode != 0) {
      throw HttpException(
        'BigQuery API request failed to execute curl command: '
        '${result.stderr}',
        uri: uri,
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
      throw HttpException(
        'BigQuery API request failed ($statusCode): $bodyText',
        uri: uri,
      );
    }

    if (bodyText.trim().isEmpty) {
      return <String, Object?>{};
    }

    final Object? decoded = jsonDecode(bodyText);
    if (decoded is! Map) {
      throw StateError('BigQuery API response is not a JSON object.');
    }
    return decoded.map((Object? key, Object? value) => MapEntry('$key', value));
  }

  String _resolveAccessTokenSync() {
    final String? explicit = tryExtractGoogleAccessToken(credentials);
    if (explicit != null && explicit.isNotEmpty) {
      return explicit;
    }

    const List<String> envKeys = <String>[
      'GOOGLE_OAUTH_ACCESS_TOKEN',
      'GOOGLE_ACCESS_TOKEN',
      'ACCESS_TOKEN',
    ];
    for (final String key in envKeys) {
      final String value = (Platform.environment[key] ?? '').trim();
      if (value.isNotEmpty) {
        return value;
      }
    }

    final ProcessResult gcloud = Process.runSync('gcloud', <String>[
      'auth',
      'application-default',
      'print-access-token',
      '--scopes',
      _bigQueryScopes.join(','),
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

    throw StateError(
      'Unable to resolve BigQuery access token. '
      'Provide oauth2 credentials, set GOOGLE_OAUTH_ACCESS_TOKEN, '
      'or login with `gcloud auth application-default login`.',
    );
  }
}

class _RestBigQueryDatasetListItem implements BigQueryDatasetListItem {
  _RestBigQueryDatasetListItem(this.datasetId);

  @override
  final String datasetId;
}

class _RestBigQueryTableListItem implements BigQueryTableListItem {
  _RestBigQueryTableListItem(this.tableId);

  @override
  final String tableId;
}

class _RestBigQueryResourceInfo implements BigQueryResourceInfo {
  _RestBigQueryResourceInfo(this.payload);

  final Map<String, Object?> payload;

  @override
  Map<String, Object?> toApiRepr() {
    return Map<String, Object?>.from(payload);
  }
}

class _RestBigQueryJobInfo implements BigQueryJobInfo {
  _RestBigQueryJobInfo(this.properties);

  @override
  final Map<String, Object?> properties;
}

class _RestBigQueryQueryJob implements BigQueryQueryJob {
  _RestBigQueryQueryJob({
    required this.statementType,
    required this.destination,
    required this.sessionInfo,
    required this.payload,
  });

  factory _RestBigQueryQueryJob.fromPayload(Map<String, Object?> payload) {
    final Map<String, Object?> statistics = _map(payload['statistics']);
    final Map<String, Object?> queryStats = _map(statistics['query']);
    final Map<String, Object?> configuration = _map(payload['configuration']);
    final Map<String, Object?> queryConfig = _map(configuration['query']);

    final Map<String, Object?> destinationTable = _map(
      queryConfig['destinationTable'],
    );
    final String? destinationProjectId = _string(destinationTable['projectId']);
    final String? destinationDatasetId = _string(destinationTable['datasetId']);
    final String? destinationTableId = _string(destinationTable['tableId']);

    final BigQueryTableReference? destination =
        destinationProjectId == null ||
            destinationDatasetId == null ||
            destinationTableId == null
        ? null
        : BigQueryTableReference(
            dataset: BigQueryDatasetReference(
              projectId: destinationProjectId,
              datasetId: destinationDatasetId,
            ),
            tableId: destinationTableId,
          );

    final Map<String, Object?> sessionInfoMap = _map(queryStats['sessionInfo']);
    final String? sessionId = _string(sessionInfoMap['sessionId']);

    return _RestBigQueryQueryJob(
      statementType:
          _string(queryStats['statementType']) ??
          _string(queryConfig['statementType']),
      destination: destination,
      sessionInfo: sessionId == null || sessionId.isEmpty
          ? null
          : BigQuerySessionInfo(sessionId: sessionId),
      payload: payload,
    );
  }

  @override
  final String? statementType;

  @override
  final BigQueryTableReference? destination;

  @override
  final BigQuerySessionInfo? sessionInfo;

  final Map<String, Object?> payload;

  @override
  Map<String, Object?> toApiRepr() {
    return Map<String, Object?>.from(payload);
  }
}

class _ParsedJobId {
  _ParsedJobId({required this.jobId, this.location});

  final String jobId;
  final String? location;
}

Map<String, Object?> _map(Object? value) {
  if (value is Map<String, Object?>) {
    return Map<String, Object?>.from(value);
  }
  if (value is Map) {
    return value.map((Object? key, Object? item) => MapEntry('$key', item));
  }
  return <String, Object?>{};
}

List<Object?> _list(Object? value) {
  if (value is List<Object?>) {
    return List<Object?>.from(value);
  }
  if (value is List) {
    return value.cast<Object?>();
  }
  return <Object?>[];
}

List<Map<String, Object?>> _listOfMaps(Object? value) {
  if (value is! List) {
    return <Map<String, Object?>>[];
  }
  return value
      .whereType<Object?>()
      .map<Map<String, Object?>>((Object? item) => _map(item))
      .toList(growable: false);
}

String? _string(Object? value) {
  if (value == null) {
    return null;
  }
  final String text = '$value'.trim();
  return text.isEmpty ? null : text;
}
