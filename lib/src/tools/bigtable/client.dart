import 'dart:convert';
import 'dart:io';

import '../_google_auth_token.dart';
import '../../version.dart';

const String bigtableUserAgent = 'adk-bigtable-tool google-adk/$adkVersion';

class BigtableInstanceSummary {
  const BigtableInstanceSummary({required this.instanceId});

  final String instanceId;
}

class BigtableInstanceListResult {
  const BigtableInstanceListResult({
    required this.instances,
    this.failedLocations = const <String>[],
  });

  final List<BigtableInstanceSummary> instances;
  final List<String> failedLocations;
}

abstract class BigtableAdminClient {
  BigtableInstanceListResult listInstances();

  BigtableAdminInstance instance(String instanceId);
}

abstract class BigtableAdminInstance {
  String get instanceId;
  String get displayName;
  Object? get state;
  Object? get type;
  Map<String, Object?> get labels;

  void reload();

  Iterable<BigtableTableAdmin> listTables();

  BigtableTableAdmin table(String tableId);
}

abstract class BigtableTableAdmin {
  String get tableId;

  Map<String, Object?> listColumnFamilies();
}

abstract class BigtableDataClient {
  BigtableQueryIterator executeQuery({
    required String query,
    required String instanceId,
    Map<String, Object?>? parameters,
    Map<String, Object?>? parameterTypes,
  });
}

abstract class BigtableQueryIterator implements Iterable<BigtableQueryRow> {
  void close();
}

abstract class BigtableQueryRow {
  Map<String, Object?> get fields;
}

typedef BigtableAdminClientFactory =
    BigtableAdminClient Function({
      required String project,
      required Object credentials,
      required String userAgent,
    });

typedef BigtableDataClientFactory =
    BigtableDataClient Function({
      required String project,
      required Object credentials,
      required String userAgent,
    });

class BigtableClientFactoryNotConfiguredException implements Exception {
  BigtableClientFactoryNotConfiguredException({
    required this.target,
    String? message,
  }) : message =
           message ??
           'Bigtable $target client factory is not configured in adk_dart. '
               'Call setBigtableClientFactories(...) before invoking Bigtable tools.';

  static const String defaultCode = 'BIGTABLE_CLIENT_FACTORY_NOT_CONFIGURED';
  final String target;
  final String message;

  String get code => defaultCode;

  @override
  String toString() => '$code[$target]: $message';
}

BigtableAdminClientFactory _adminClientFactory = _defaultAdminClientFactory;
BigtableDataClientFactory _dataClientFactory = _defaultDataClientFactory;

BigtableAdminClient getBigtableAdminClient({
  required String project,
  required Object credentials,
}) {
  return _adminClientFactory(
    project: project,
    credentials: credentials,
    userAgent: bigtableUserAgent,
  );
}

BigtableDataClient getBigtableDataClient({
  required String project,
  required Object credentials,
}) {
  return _dataClientFactory(
    project: project,
    credentials: credentials,
    userAgent: bigtableUserAgent,
  );
}

void setBigtableClientFactories({
  BigtableAdminClientFactory? adminClientFactory,
  BigtableDataClientFactory? dataClientFactory,
}) {
  if (adminClientFactory != null) {
    _adminClientFactory = adminClientFactory;
  }
  if (dataClientFactory != null) {
    _dataClientFactory = dataClientFactory;
  }
}

void resetBigtableClientFactories() {
  _adminClientFactory = _defaultAdminClientFactory;
  _dataClientFactory = _defaultDataClientFactory;
}

BigtableAdminClient _defaultAdminClientFactory({
  required String project,
  required Object credentials,
  required String userAgent,
}) {
  return _RestBigtableAdminClient(
    project: project,
    credentials: credentials,
    userAgent: userAgent,
  );
}

BigtableDataClient _defaultDataClientFactory({
  required String project,
  required Object credentials,
  required String userAgent,
}) {
  return _RestBigtableDataClient(
    project: project,
    credentials: credentials,
    userAgent: userAgent,
  );
}

const List<String> _bigtableScopes = <String>[
  'https://www.googleapis.com/auth/bigtable.data',
  'https://www.googleapis.com/auth/cloud-platform',
];

class _RestBigtableApiClient {
  _RestBigtableApiClient({
    required this.project,
    required this.credentials,
    required this.userAgent,
  });

  final String project;
  final Object credentials;
  final String userAgent;

  static const String _adminBaseUrl = 'https://bigtableadmin.googleapis.com';
  static const String _dataBaseUrl = 'https://bigtable.googleapis.com';

  Map<String, Object?> requestJson({
    required String method,
    required String baseUrl,
    required String path,
    Map<String, String>? queryParameters,
    Map<String, Object?>? body,
    Set<int> acceptedStatusCodes = const <int>{200},
  }) {
    final _ApiResponse response = request(
      method: method,
      baseUrl: baseUrl,
      path: path,
      queryParameters: queryParameters,
      body: body,
    );
    if (!acceptedStatusCodes.contains(response.statusCode)) {
      throw HttpException(
        'Bigtable API request failed (${response.statusCode}): '
        '${response.bodyText}',
        uri: response.uri,
      );
    }
    if (response.bodyText.trim().isEmpty) {
      return <String, Object?>{};
    }
    final Object? decoded = jsonDecode(response.bodyText);
    if (decoded is! Map) {
      throw StateError('Bigtable API response is not a JSON object.');
    }
    return decoded.map((Object? key, Object? value) => MapEntry('$key', value));
  }

  _ApiResponse request({
    required String method,
    required String baseUrl,
    required String path,
    Map<String, String>? queryParameters,
    Map<String, Object?>? body,
  }) {
    final Uri uri = Uri.parse(baseUrl).replace(
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
      'User-Agent: $userAgent',
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
        'Bigtable API curl invocation failed: ${result.stderr}',
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
      _bigtableScopes.join(','),
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
      'Unable to resolve Bigtable access token. '
      'Provide oauth2 credentials, set GOOGLE_OAUTH_ACCESS_TOKEN, '
      'or login with `gcloud auth application-default login`.',
    );
  }
}

class _RestBigtableAdminClient implements BigtableAdminClient {
  _RestBigtableAdminClient({
    required this.project,
    required this.credentials,
    required this.userAgent,
  }) : _api = _RestBigtableApiClient(
         project: project,
         credentials: credentials,
         userAgent: userAgent,
       );

  final String project;
  final Object credentials;
  final String userAgent;
  final _RestBigtableApiClient _api;

  @override
  BigtableInstanceListResult listInstances() {
    String? pageToken;
    final List<BigtableInstanceSummary> instances = <BigtableInstanceSummary>[];
    final List<String> failedLocations = <String>[];

    do {
      final Map<String, Object?> payload = _api.requestJson(
        method: 'GET',
        baseUrl: _RestBigtableApiClient._adminBaseUrl,
        path: '/v2/projects/${Uri.encodeComponent(project)}/instances',
        queryParameters: <String, String>{
          if (pageToken != null && pageToken.isNotEmpty) 'pageToken': pageToken,
        },
      );

      for (final Map<String, Object?> item in _listOfMaps(
        payload['instances'],
      )) {
        final String name = _string(item['name']) ?? '';
        final String instanceId = name.split('/').isEmpty
            ? ''
            : name.split('/').last;
        if (instanceId.isNotEmpty) {
          instances.add(BigtableInstanceSummary(instanceId: instanceId));
        }
      }

      for (final Object? location in _list(payload['failedLocations'])) {
        final String text = '$location'.trim();
        if (text.isNotEmpty) {
          failedLocations.add(text);
        }
      }

      pageToken = _string(payload['nextPageToken']);
    } while (pageToken != null && pageToken.isNotEmpty);

    return BigtableInstanceListResult(
      instances: instances,
      failedLocations: failedLocations,
    );
  }

  @override
  BigtableAdminInstance instance(String instanceId) {
    return _RestBigtableAdminInstance(
      api: _api,
      project: project,
      instanceId: instanceId,
    );
  }
}

class _RestBigtableAdminInstance implements BigtableAdminInstance {
  _RestBigtableAdminInstance({
    required this.api,
    required this.project,
    required this.instanceId,
  });

  final _RestBigtableApiClient api;
  final String project;
  @override
  final String instanceId;

  Map<String, Object?> _payload = <String, Object?>{};

  String get _instancePath =>
      '/v2/projects/${Uri.encodeComponent(project)}'
      '/instances/${Uri.encodeComponent(instanceId)}';

  @override
  String get displayName {
    if (_payload.isEmpty) {
      reload();
    }
    return _string(_payload['displayName']) ?? '';
  }

  @override
  Object? get state {
    if (_payload.isEmpty) {
      reload();
    }
    return _payload['state'];
  }

  @override
  Object? get type {
    if (_payload.isEmpty) {
      reload();
    }
    return _payload['type'];
  }

  @override
  Map<String, Object?> get labels {
    if (_payload.isEmpty) {
      reload();
    }
    return _map(_payload['labels']);
  }

  @override
  void reload() {
    _payload = api.requestJson(
      method: 'GET',
      baseUrl: _RestBigtableApiClient._adminBaseUrl,
      path: _instancePath,
    );
  }

  @override
  Iterable<BigtableTableAdmin> listTables() sync* {
    String? pageToken;
    do {
      final Map<String, Object?> payload = api.requestJson(
        method: 'GET',
        baseUrl: _RestBigtableApiClient._adminBaseUrl,
        path: '$_instancePath/tables',
        queryParameters: <String, String>{
          if (pageToken != null && pageToken.isNotEmpty) 'pageToken': pageToken,
        },
      );
      for (final Map<String, Object?> item in _listOfMaps(payload['tables'])) {
        final String name = _string(item['name']) ?? '';
        final String tableId = name.split('/').isEmpty
            ? ''
            : name.split('/').last;
        if (tableId.isNotEmpty) {
          yield _RestBigtableTableAdmin(
            api: api,
            project: project,
            instanceId: instanceId,
            tableId: tableId,
            payload: item,
          );
        }
      }
      pageToken = _string(payload['nextPageToken']);
    } while (pageToken != null && pageToken.isNotEmpty);
  }

  @override
  BigtableTableAdmin table(String tableId) {
    return _RestBigtableTableAdmin(
      api: api,
      project: project,
      instanceId: instanceId,
      tableId: tableId,
    );
  }
}

class _RestBigtableTableAdmin implements BigtableTableAdmin {
  _RestBigtableTableAdmin({
    required this.api,
    required this.project,
    required this.instanceId,
    required this.tableId,
    Map<String, Object?>? payload,
  }) : _payload = payload ?? <String, Object?>{};

  final _RestBigtableApiClient api;
  final String project;
  final String instanceId;
  @override
  final String tableId;

  Map<String, Object?> _payload;

  String get _tablePath =>
      '/v2/projects/${Uri.encodeComponent(project)}'
      '/instances/${Uri.encodeComponent(instanceId)}'
      '/tables/${Uri.encodeComponent(tableId)}';

  @override
  Map<String, Object?> listColumnFamilies() {
    if (_payload.isEmpty || _map(_payload['columnFamilies']).isEmpty) {
      _payload = api.requestJson(
        method: 'GET',
        baseUrl: _RestBigtableApiClient._adminBaseUrl,
        path: _tablePath,
      );
    }
    return _map(_payload['columnFamilies']);
  }
}

class _RestBigtableDataClient implements BigtableDataClient {
  _RestBigtableDataClient({
    required this.project,
    required this.credentials,
    required this.userAgent,
  }) : _api = _RestBigtableApiClient(
         project: project,
         credentials: credentials,
         userAgent: userAgent,
       );

  final String project;
  final Object credentials;
  final String userAgent;
  final _RestBigtableApiClient _api;

  @override
  BigtableQueryIterator executeQuery({
    required String query,
    required String instanceId,
    Map<String, Object?>? parameters,
    Map<String, Object?>? parameterTypes,
  }) {
    final List<BigtableQueryRow> rows = <BigtableQueryRow>[];
    String? pageToken;

    do {
      final Map<String, Object?> payload = _api.requestJson(
        method: 'POST',
        baseUrl: _RestBigtableApiClient._dataBaseUrl,
        path:
            '/v2/projects/${Uri.encodeComponent(project)}'
            '/instances/${Uri.encodeComponent(instanceId)}:executeQuery',
        body: <String, Object?>{
          'query': query,
          if (parameters != null && parameters.isNotEmpty)
            'parameters': _encodeMap(parameters),
          if (parameterTypes != null && parameterTypes.isNotEmpty)
            'parameterTypes': parameterTypes.map(
              (String key, Object? value) =>
                  MapEntry<String, Object?>(key, _toTypeValue(value)),
            ),
          if (pageToken != null && pageToken.isNotEmpty) 'pageToken': pageToken,
        },
      );

      final List<Map<String, Object?>> resultRows = _listOfMaps(
        payload['rows'],
      );
      if (resultRows.isEmpty && payload['results'] is List) {
        resultRows.addAll(_listOfMaps(payload['results']));
      }

      for (final Map<String, Object?> row in resultRows) {
        final Map<String, Object?> fields = row['fields'] is Map
            ? _map(row['fields'])
            : row;
        rows.add(_RestBigtableQueryRow(fields));
      }

      pageToken = _string(payload['nextPageToken']);
    } while (pageToken != null && pageToken.isNotEmpty);

    return _RestBigtableQueryIterator(rows);
  }
}

class _RestBigtableQueryIterator extends Iterable<BigtableQueryRow>
    implements BigtableQueryIterator {
  _RestBigtableQueryIterator(List<BigtableQueryRow> rows)
    : _rows = List<BigtableQueryRow>.from(rows);

  final List<BigtableQueryRow> _rows;
  bool _closed = false;

  @override
  Iterator<BigtableQueryRow> get iterator {
    if (_closed) {
      return const <BigtableQueryRow>[].iterator;
    }
    return _rows.iterator;
  }

  @override
  void close() {
    _closed = true;
  }
}

class _RestBigtableQueryRow implements BigtableQueryRow {
  _RestBigtableQueryRow(Map<String, Object?> fields)
    : _fields = Map<String, Object?>.from(fields);

  final Map<String, Object?> _fields;

  @override
  Map<String, Object?> get fields => Map<String, Object?>.from(_fields);
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

Object? _toTypeValue(Object? value) {
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

Map<String, Object?> _encodeMap(Map<String, Object?> map) {
  return map.map(
    (String key, Object? value) => MapEntry(key, _encodeValue(value)),
  );
}

Object? _encodeValue(Object? value) {
  if (value == null) {
    return null;
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
