import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../_google_auth_token.dart';
import '../../version.dart';

const String spannerUserAgent = 'adk-spanner-tool google-adk/$adkVersion';

enum SpannerDatabaseDialect { googleStandardSql, postgresql, unknown }

class SpannerTable {
  const SpannerTable({required this.tableId});

  final String tableId;
}

abstract class SpannerClient {
  SpannerInstance instance(String instanceId);

  String get userAgent;
  set userAgent(String value);
}

abstract class SpannerInstance {
  bool exists();

  SpannerDatabase database(String databaseId);
}

abstract class SpannerDatabase {
  SpannerDatabaseDialect get databaseDialect;

  bool exists();

  Iterable<SpannerTable> listTables({String schema = '_default'});

  SpannerSnapshot snapshot({bool multiUse = false});

  void reload();

  SpannerUpdateDdlOperation updateDdl(List<String> statements);

  SpannerBatch batch();
}

abstract class SpannerSnapshot {
  SpannerResultSet executeSql({
    required String sql,
    Map<String, Object?>? params,
    Map<String, Object?>? paramTypes,
  });
}

abstract class SpannerResultSet {
  Iterable<Object?> get rows;

  List<Map<String, Object?>> toDictList();

  Object? one();
}

abstract class SpannerUpdateDdlOperation {
  FutureOr<void> result();
}

abstract class SpannerBatch {
  void insertOrUpdate({
    required String table,
    required List<String> columns,
    required List<List<Object?>> values,
  });
}

typedef SpannerClientFactory =
    SpannerClient Function({
      required String project,
      required Object credentials,
    });

class SpannerClientFactoryNotConfiguredException implements Exception {
  SpannerClientFactoryNotConfiguredException([
    this.message =
        'Cloud Spanner client factory is not configured in adk_dart. '
        'Call setSpannerClientFactory(...) before invoking Spanner tools.',
  ]);

  static const String defaultCode = 'SPANNER_CLIENT_FACTORY_NOT_CONFIGURED';
  final String message;

  String get code => defaultCode;

  @override
  String toString() => '$code: $message';
}

SpannerClientFactory _spannerClientFactory = _defaultSpannerClientFactory;

SpannerClient getSpannerClient({
  required String project,
  required Object credentials,
}) {
  final SpannerClient spannerClient = _spannerClientFactory(
    project: project,
    credentials: credentials,
  );
  spannerClient.userAgent = spannerUserAgent;
  return spannerClient;
}

void setSpannerClientFactory(SpannerClientFactory factory) {
  _spannerClientFactory = factory;
}

void resetSpannerClientFactory() {
  _spannerClientFactory = _defaultSpannerClientFactory;
}

SpannerClient _defaultSpannerClientFactory({
  required String project,
  required Object credentials,
}) {
  return _RestSpannerClient(
    project: project,
    credentials: credentials,
    userAgent: spannerUserAgent,
  );
}

const List<String> _spannerScopes = <String>[
  'https://www.googleapis.com/auth/spanner.data',
  'https://www.googleapis.com/auth/cloud-platform',
];

class _RestSpannerClient implements SpannerClient {
  _RestSpannerClient({
    required this.project,
    required this.credentials,
    required String userAgent,
  }) : _userAgent = userAgent;

  final String project;
  final Object credentials;
  String _userAgent;

  static const String _baseApiUrl = 'https://spanner.googleapis.com';

  @override
  SpannerInstance instance(String instanceId) {
    return _RestSpannerInstance(client: this, instanceId: instanceId);
  }

  @override
  String get userAgent => _userAgent;

  @override
  set userAgent(String value) {
    _userAgent = value.trim().isEmpty ? spannerUserAgent : value;
  }

  _ApiResponse request({
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
      '-H',
      'User-Agent: $_userAgent',
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
        'Spanner API curl invocation failed: ${result.stderr}',
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

    return _ApiResponse(statusCode: statusCode, bodyText: bodyText, uri: uri);
  }

  Map<String, Object?> requestJson({
    required String method,
    required String path,
    Map<String, String>? queryParameters,
    Map<String, Object?>? body,
    Set<int> acceptedStatusCodes = const <int>{200},
  }) {
    final _ApiResponse response = request(
      method: method,
      path: path,
      queryParameters: queryParameters,
      body: body,
    );

    if (!acceptedStatusCodes.contains(response.statusCode)) {
      throw HttpException(
        'Spanner API request failed (${response.statusCode}): '
        '${response.bodyText}',
        uri: response.uri,
      );
    }

    if (response.bodyText.trim().isEmpty) {
      return <String, Object?>{};
    }

    final Object? decoded = jsonDecode(response.bodyText);
    if (decoded is! Map) {
      throw StateError('Spanner API response is not a JSON object.');
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
      _spannerScopes.join(','),
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
      'Unable to resolve Cloud Spanner access token. '
      'Provide oauth2 credentials, set GOOGLE_OAUTH_ACCESS_TOKEN, '
      'or login with `gcloud auth application-default login`.',
    );
  }
}

class _RestSpannerInstance implements SpannerInstance {
  _RestSpannerInstance({required this.client, required this.instanceId});

  final _RestSpannerClient client;
  final String instanceId;

  String get _instancePath =>
      '/v1/projects/${Uri.encodeComponent(client.project)}'
      '/instances/${Uri.encodeComponent(instanceId)}';

  @override
  bool exists() {
    final _ApiResponse response = client.request(
      method: 'GET',
      path: _instancePath,
    );
    if (response.statusCode == 404) {
      return false;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'Spanner instance lookup failed (${response.statusCode}): '
        '${response.bodyText}',
        uri: response.uri,
      );
    }
    return true;
  }

  @override
  SpannerDatabase database(String databaseId) {
    return _RestSpannerDatabase(
      client: client,
      instanceId: instanceId,
      databaseId: databaseId,
    );
  }
}

class _RestSpannerDatabase implements SpannerDatabase {
  _RestSpannerDatabase({
    required this.client,
    required this.instanceId,
    required this.databaseId,
  });

  final _RestSpannerClient client;
  final String instanceId;
  final String databaseId;

  Map<String, Object?> _metadata = <String, Object?>{};

  String get _databasePath =>
      '/v1/projects/${Uri.encodeComponent(client.project)}'
      '/instances/${Uri.encodeComponent(instanceId)}'
      '/databases/${Uri.encodeComponent(databaseId)}';

  String get _databaseName =>
      'projects/${client.project}/instances/$instanceId/databases/$databaseId';

  @override
  SpannerDatabaseDialect get databaseDialect {
    if (_metadata.isEmpty) {
      reload();
    }
    return _parseDialect(_string(_metadata['databaseDialect']));
  }

  @override
  bool exists() {
    final _ApiResponse response = client.request(
      method: 'GET',
      path: _databasePath,
    );
    if (response.statusCode == 404) {
      return false;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'Spanner database lookup failed (${response.statusCode}): '
        '${response.bodyText}',
        uri: response.uri,
      );
    }
    if (response.bodyText.trim().isEmpty) {
      _metadata = <String, Object?>{};
      return true;
    }
    final Object? decoded = jsonDecode(response.bodyText);
    if (decoded is Map) {
      _metadata = decoded.map(
        (Object? key, Object? value) => MapEntry('$key', value),
      );
    }
    return true;
  }

  @override
  Iterable<SpannerTable> listTables({String schema = '_default'}) sync* {
    final SpannerResultSet resultSet = snapshot().executeSql(
      sql:
          'SELECT TABLE_NAME FROM INFORMATION_SCHEMA.TABLES '
          'WHERE TABLE_SCHEMA = @schema ORDER BY TABLE_NAME',
      params: <String, Object?>{'schema': schema},
      paramTypes: const <String, Object?>{'schema': 'STRING'},
    );
    for (final Object? row in resultSet.rows) {
      final List<Object?> values = _asRow(row);
      if (values.isEmpty) {
        continue;
      }
      final String tableName = '${values.first}';
      if (tableName.isNotEmpty) {
        yield SpannerTable(tableId: tableName);
      }
    }
  }

  @override
  SpannerSnapshot snapshot({bool multiUse = false}) {
    return _RestSpannerSnapshot(
      client: client,
      databaseName: _databaseName,
      multiUse: multiUse,
    );
  }

  @override
  void reload() {
    _metadata = client.requestJson(
      method: 'GET',
      path: _databasePath,
      acceptedStatusCodes: const <int>{200},
    );
  }

  @override
  SpannerUpdateDdlOperation updateDdl(List<String> statements) {
    final Map<String, Object?> payload = client.requestJson(
      method: 'POST',
      path: '$_databasePath:updateDdl',
      body: <String, Object?>{'statements': statements},
      acceptedStatusCodes: const <int>{200},
    );
    final String operationName = _string(payload['name']) ?? '';
    return _RestSpannerUpdateDdlOperation(
      client: client,
      operationName: operationName,
    );
  }

  @override
  SpannerBatch batch() {
    return _RestSpannerBatch(client: client, databaseName: _databaseName);
  }
}

class _RestSpannerSnapshot implements SpannerSnapshot {
  _RestSpannerSnapshot({
    required this.client,
    required this.databaseName,
    required this.multiUse,
  });

  final _RestSpannerClient client;
  final String databaseName;
  final bool multiUse;

  String? _sessionName;

  @override
  SpannerResultSet executeSql({
    required String sql,
    Map<String, Object?>? params,
    Map<String, Object?>? paramTypes,
  }) {
    final String sessionName = _resolveSessionName();
    try {
      final Map<String, Object?> body = <String, Object?>{
        'sql': sql,
        if (params != null && params.isNotEmpty) 'params': _encodeMap(params),
        if (paramTypes != null && paramTypes.isNotEmpty)
          'paramTypes': paramTypes.map(
            (String key, Object? value) =>
                MapEntry<String, Object?>(key, _toSpannerType(value)),
          ),
      };
      final Map<String, Object?> payload = client.requestJson(
        method: 'POST',
        path: '/v1/$sessionName:executeSql',
        body: body,
        acceptedStatusCodes: const <int>{200},
      );
      final Map<String, Object?> resultSet = _map(payload['resultSet']);
      return _RestSpannerResultSet.fromResultSet(resultSet);
    } finally {
      if (!multiUse) {
        _deleteSession(sessionName);
      }
    }
  }

  String _resolveSessionName() {
    if (multiUse && _sessionName != null) {
      return _sessionName!;
    }

    final Map<String, Object?> payload = client.requestJson(
      method: 'POST',
      path: '/v1/$databaseName/sessions',
      body: const <String, Object?>{},
      acceptedStatusCodes: const <int>{200},
    );
    final String name = _string(payload['name']) ?? '';
    if (name.isEmpty) {
      throw StateError('Spanner session creation failed: empty session name.');
    }
    if (multiUse) {
      _sessionName = name;
    }
    return name;
  }

  void _deleteSession(String sessionName) {
    final _ApiResponse response = client.request(
      method: 'DELETE',
      path: '/v1/$sessionName',
    );
    if (response.statusCode == 404) {
      return;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'Spanner session deletion failed (${response.statusCode}): '
        '${response.bodyText}',
        uri: response.uri,
      );
    }
  }
}

class _RestSpannerResultSet implements SpannerResultSet {
  _RestSpannerResultSet({
    required List<List<Object?>> rows,
    required List<String> fieldNames,
  }) : _rows = rows,
       _fieldNames = fieldNames;

  factory _RestSpannerResultSet.fromResultSet(Map<String, Object?> resultSet) {
    final List<Map<String, Object?>> fieldSpecs = _listOfMaps(
      _map(_map(resultSet['metadata'])['rowType'])['fields'],
    );
    final List<String> fieldNames = fieldSpecs
        .map((Map<String, Object?> field) => _string(field['name']) ?? '')
        .toList(growable: false);

    final List<List<Object?>> rows = <List<Object?>>[];
    for (final Map<String, Object?> row in _listOfMaps(resultSet['rows'])) {
      final List<Object?> values = _list(row['values']);
      final List<Object?> decodedRow = <Object?>[];
      for (int i = 0; i < values.length; i += 1) {
        final Map<String, Object?> type = i < fieldSpecs.length
            ? _map(fieldSpecs[i]['type'])
            : <String, Object?>{};
        decodedRow.add(_decodeSpannerValue(values[i], type));
      }
      rows.add(decodedRow);
    }

    return _RestSpannerResultSet(rows: rows, fieldNames: fieldNames);
  }

  final List<List<Object?>> _rows;
  final List<String> _fieldNames;

  @override
  Iterable<Object?> get rows => _rows;

  @override
  List<Map<String, Object?>> toDictList() {
    final List<Map<String, Object?>> result = <Map<String, Object?>>[];
    for (final List<Object?> row in _rows) {
      final Map<String, Object?> map = <String, Object?>{};
      for (int i = 0; i < _fieldNames.length; i += 1) {
        final String key = _fieldNames[i].isEmpty
            ? 'column_$i'
            : _fieldNames[i];
        map[key] = i < row.length ? row[i] : null;
      }
      result.add(map);
    }
    return result;
  }

  @override
  Object? one() {
    if (_rows.isEmpty) {
      return null;
    }
    return List<Object?>.from(_rows.first);
  }
}

class _RestSpannerUpdateDdlOperation implements SpannerUpdateDdlOperation {
  _RestSpannerUpdateDdlOperation({
    required this.client,
    required this.operationName,
  });

  final _RestSpannerClient client;
  final String operationName;

  @override
  void result() {
    if (operationName.isEmpty) {
      return;
    }
    const int maxAttempts = 180;
    for (int attempt = 0; attempt < maxAttempts; attempt += 1) {
      final Map<String, Object?> payload = client.requestJson(
        method: 'GET',
        path: '/v1/$operationName',
        acceptedStatusCodes: const <int>{200},
      );
      final bool done = payload['done'] == true;
      if (done) {
        final Map<String, Object?> error = _map(payload['error']);
        if (error.isNotEmpty) {
          throw StateError(
            'Spanner DDL operation failed: ${jsonEncode(error)}',
          );
        }
        return;
      }
      sleep(const Duration(seconds: 1));
    }
    throw TimeoutException(
      'Timed out waiting for Spanner operation `$operationName`.',
    );
  }
}

class _RestSpannerBatch implements SpannerBatch {
  _RestSpannerBatch({required this.client, required this.databaseName});

  final _RestSpannerClient client;
  final String databaseName;

  @override
  void insertOrUpdate({
    required String table,
    required List<String> columns,
    required List<List<Object?>> values,
  }) {
    if (values.isEmpty) {
      return;
    }
    client.requestJson(
      method: 'POST',
      path: '/v1/$databaseName:commit',
      body: <String, Object?>{
        'singleUseTransaction': <String, Object?>{
          'readWrite': <String, Object?>{},
        },
        'mutations': <Map<String, Object?>>[
          <String, Object?>{
            'insertOrUpdate': <String, Object?>{
              'table': table,
              'columns': columns,
              'values': values
                  .map((List<Object?> row) => _encodeList(row))
                  .toList(growable: false),
            },
          },
        ],
      },
      acceptedStatusCodes: const <int>{200},
    );
  }
}

class _ApiResponse {
  _ApiResponse({
    required this.statusCode,
    required this.bodyText,
    required this.uri,
  });

  final int statusCode;
  final String bodyText;
  final Uri uri;
}

SpannerDatabaseDialect _parseDialect(String? value) {
  switch ((value ?? '').toUpperCase()) {
    case 'GOOGLE_STANDARD_SQL':
      return SpannerDatabaseDialect.googleStandardSql;
    case 'POSTGRESQL':
      return SpannerDatabaseDialect.postgresql;
    default:
      return SpannerDatabaseDialect.unknown;
  }
}

Object? _toSpannerType(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is Map<String, Object?>) {
    return Map<String, Object?>.from(value);
  }
  if (value is Map) {
    return value.map((Object? key, Object? item) => MapEntry('$key', item));
  }
  if (value is String) {
    return <String, Object?>{'code': value};
  }
  return <String, Object?>{'code': '$value'};
}

Object? _encodeMap(Map<String, Object?> map) {
  return map.map(
    (String key, Object? value) => MapEntry(key, _encodeValue(value)),
  );
}

List<Object?> _encodeList(List<Object?> list) {
  return list.map<Object?>(_encodeValue).toList(growable: false);
}

Object? _encodeValue(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is DateTime) {
    return value.toUtc().toIso8601String();
  }
  if (value is int) {
    return '$value';
  }
  if (value is num || value is bool || value is String) {
    return value;
  }
  if (value is List) {
    return value.map<Object?>(_encodeValue).toList(growable: false);
  }
  if (value is Map) {
    return value.map(
      (Object? key, Object? item) => MapEntry('$key', _encodeValue(item)),
    );
  }
  return '$value';
}

Object? _decodeSpannerValue(Object? value, Map<String, Object?> type) {
  if (value == null) {
    return null;
  }
  final String code = (_string(type['code']) ?? '').toUpperCase();
  switch (code) {
    case 'BOOL':
      if (value is bool) {
        return value;
      }
      return '$value'.toLowerCase() == 'true';
    case 'INT64':
      return int.tryParse('$value') ?? '$value';
    case 'FLOAT32':
    case 'FLOAT64':
      return num.tryParse('$value') ?? '$value';
    case 'ARRAY':
      final Map<String, Object?> elementType = _map(type['arrayElementType']);
      return _list(value)
          .map<Object?>(
            (Object? item) => _decodeSpannerValue(item, elementType),
          )
          .toList(growable: false);
    case 'STRUCT':
      return _list(value);
    default:
      return value;
  }
}

List<Object?> _asRow(Object? row) {
  if (row is List<Object?>) {
    return List<Object?>.from(row);
  }
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
