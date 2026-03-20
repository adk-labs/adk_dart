/// Experimental Spanner admin helpers and runtime client abstractions.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../_google_auth_token.dart';
import '../../version.dart';
import 'spanner_credentials.dart';

/// Default ADK user-agent string for Spanner admin requests.
const String spannerAdminUserAgent =
    'adk-spanner-admin-tool google-adk/$adkVersion';

/// REST-style client for Spanner admin APIs.
abstract class SpannerAdminClient {
  /// Lists instance ids within the configured project.
  Iterable<String> listInstances();

  /// Returns instance details for [instanceId].
  Map<String, Object?> getInstance(String instanceId);

  /// Lists instance config ids within the configured project.
  Iterable<String> listInstanceConfigs();

  /// Returns instance config details for [configId].
  Map<String, Object?> getInstanceConfig(String configId);

  /// Creates a new instance and waits for completion.
  FutureOr<void> createInstance({
    required String instanceId,
    required String configId,
    required String displayName,
    int nodes = 1,
  });

  /// Lists database ids within [instanceId].
  Iterable<String> listDatabases(String instanceId);

  /// Creates a database and waits for completion.
  FutureOr<void> createDatabase({
    required String instanceId,
    required String databaseId,
  });

  /// User-agent header value.
  String get userAgent;

  /// Updates the user-agent header value.
  set userAgent(String value);
}

/// Factory for [SpannerAdminClient] instances.
typedef SpannerAdminClientFactory =
    SpannerAdminClient Function({
      required String project,
      required Object credentials,
    });

SpannerAdminClientFactory _spannerAdminClientFactory =
    _defaultSpannerAdminClientFactory;

/// Returns a configured Spanner admin client for [project].
SpannerAdminClient getSpannerAdminClient({
  required String project,
  required Object credentials,
}) {
  final SpannerAdminClient client = _spannerAdminClientFactory(
    project: project,
    credentials: credentials,
  );
  client.userAgent = spannerAdminUserAgent;
  return client;
}

/// Overrides the Spanner admin client factory.
void setSpannerAdminClientFactory(SpannerAdminClientFactory factory) {
  _spannerAdminClientFactory = factory;
}

/// Restores the default Spanner admin client factory.
void resetSpannerAdminClientFactory() {
  _spannerAdminClientFactory = _defaultSpannerAdminClientFactory;
}

/// Lists Spanner instances in [projectId].
Future<Map<String, Object?>> listInstances({
  required String projectId,
  required Object credentials,
}) async {
  try {
    final SpannerAdminClient client = getSpannerAdminClient(
      project: projectId,
      credentials: credentials,
    );
    return <String, Object?>{
      'status': 'SUCCESS',
      'results': client.listInstances().toList(growable: false),
    };
  } catch (error) {
    return <String, Object?>{'status': 'ERROR', 'error_details': '$error'};
  }
}

/// Returns Spanner instance details for [instanceId].
Future<Map<String, Object?>> getInstance({
  required String projectId,
  required String instanceId,
  required Object credentials,
}) async {
  try {
    final SpannerAdminClient client = getSpannerAdminClient(
      project: projectId,
      credentials: credentials,
    );
    return <String, Object?>{
      'status': 'SUCCESS',
      'results': client.getInstance(instanceId),
    };
  } catch (error) {
    return <String, Object?>{'status': 'ERROR', 'error_details': '$error'};
  }
}

/// Lists instance config ids in [projectId].
Future<Map<String, Object?>> listInstanceConfigs({
  required String projectId,
  required Object credentials,
}) async {
  try {
    final SpannerAdminClient client = getSpannerAdminClient(
      project: projectId,
      credentials: credentials,
    );
    return <String, Object?>{
      'status': 'SUCCESS',
      'results': client.listInstanceConfigs().toList(growable: false),
    };
  } catch (error) {
    return <String, Object?>{'status': 'ERROR', 'error_details': '$error'};
  }
}

/// Returns instance config details for [configId].
Future<Map<String, Object?>> getInstanceConfig({
  required String projectId,
  required String configId,
  required Object credentials,
}) async {
  try {
    final SpannerAdminClient client = getSpannerAdminClient(
      project: projectId,
      credentials: credentials,
    );
    return <String, Object?>{
      'status': 'SUCCESS',
      'results': client.getInstanceConfig(configId),
    };
  } catch (error) {
    return <String, Object?>{'status': 'ERROR', 'error_details': '$error'};
  }
}

/// Creates a Spanner instance and waits for completion.
Future<Map<String, Object?>> createInstance({
  required String projectId,
  required String instanceId,
  required String configId,
  required String displayName,
  required Object credentials,
  int nodes = 1,
}) async {
  try {
    final SpannerAdminClient client = getSpannerAdminClient(
      project: projectId,
      credentials: credentials,
    );
    await client.createInstance(
      instanceId: instanceId,
      configId: configId,
      displayName: displayName,
      nodes: nodes,
    );
    return <String, Object?>{
      'status': 'SUCCESS',
      'results': 'Instance $instanceId created successfully.',
    };
  } catch (error) {
    return <String, Object?>{'status': 'ERROR', 'error_details': '$error'};
  }
}

/// Lists database ids within [instanceId].
Future<Map<String, Object?>> listDatabases({
  required String projectId,
  required String instanceId,
  required Object credentials,
}) async {
  try {
    final SpannerAdminClient client = getSpannerAdminClient(
      project: projectId,
      credentials: credentials,
    );
    return <String, Object?>{
      'status': 'SUCCESS',
      'results': client.listDatabases(instanceId).toList(growable: false),
    };
  } catch (error) {
    return <String, Object?>{'status': 'ERROR', 'error_details': '$error'};
  }
}

/// Creates a database in [instanceId].
Future<Map<String, Object?>> createDatabase({
  required String projectId,
  required String instanceId,
  required String databaseId,
  required Object credentials,
}) async {
  try {
    final SpannerAdminClient client = getSpannerAdminClient(
      project: projectId,
      credentials: credentials,
    );
    await client.createDatabase(instanceId: instanceId, databaseId: databaseId);
    return <String, Object?>{'status': 'SUCCESS'};
  } catch (error) {
    return <String, Object?>{'status': 'ERROR', 'error_details': '$error'};
  }
}

SpannerAdminClient _defaultSpannerAdminClientFactory({
  required String project,
  required Object credentials,
}) {
  return _RestSpannerAdminClient(
    project: project,
    credentials: credentials,
    userAgent: spannerAdminUserAgent,
  );
}

class _RestSpannerAdminClient implements SpannerAdminClient {
  _RestSpannerAdminClient({
    required this.project,
    required this.credentials,
    required String userAgent,
  }) : _userAgent = userAgent;

  final String project;
  final Object credentials;
  String _userAgent;

  static const String _baseApiUrl = 'https://spanner.googleapis.com';

  @override
  String get userAgent => _userAgent;

  @override
  set userAgent(String value) {
    _userAgent = value.trim().isEmpty ? spannerAdminUserAgent : value;
  }

  @override
  Iterable<String> listInstances() sync* {
    final Map<String, Object?> response = requestJson(
      method: 'GET',
      path: '/v1/projects/$project/instances',
    );
    final Object? instances = response['instances'];
    if (instances is! List) {
      return;
    }
    for (final Object? item in instances) {
      if (item is! Map) {
        continue;
      }
      final Object? name = item['name'];
      if (name == null) {
        continue;
      }
      yield '$name'.split('/').last;
    }
  }

  @override
  Map<String, Object?> getInstance(String instanceId) {
    final Map<String, Object?> instance = requestJson(
      method: 'GET',
      path: '/v1/projects/$project/instances/$instanceId',
    );
    return <String, Object?>{
      'instance_id': instanceId,
      'display_name': '${instance['displayName'] ?? ''}',
      'config': instance['config'],
      'node_count': _asInt(instance['nodeCount']),
      'processing_units': _asInt(instance['processingUnits']),
      'labels': _asStringObjectMap(instance['labels']),
    };
  }

  @override
  Iterable<String> listInstanceConfigs() sync* {
    final Map<String, Object?> response = requestJson(
      method: 'GET',
      path: '/v1/projects/$project/instanceConfigs',
    );
    final Object? configs = response['instanceConfigs'];
    if (configs is! List) {
      return;
    }
    for (final Object? item in configs) {
      if (item is! Map) {
        continue;
      }
      final Object? name = item['name'];
      if (name == null) {
        continue;
      }
      yield '$name'.split('/').last;
    }
  }

  @override
  Map<String, Object?> getInstanceConfig(String configId) {
    final Map<String, Object?> config = requestJson(
      method: 'GET',
      path: '/v1/projects/$project/instanceConfigs/$configId',
    );
    final List<Object?> replicas = <Object?>[];
    final Object? rawReplicas = config['replicas'];
    if (rawReplicas is List) {
      for (final Object? replica in rawReplicas) {
        if (replica is! Map) {
          continue;
        }
        replicas.add(<String, Object?>{
          'location': replica['location'],
          'type': replica['type'],
          'default_leader_location': replica['defaultLeaderLocation'],
        });
      }
    }
    return <String, Object?>{
      'name': config['name'],
      'display_name': config['displayName'],
      'replicas': replicas,
      'labels': _asStringObjectMap(config['labels']),
    };
  }

  @override
  Future<void> createInstance({
    required String instanceId,
    required String configId,
    required String displayName,
    int nodes = 1,
  }) async {
    final Map<String, Object?> operation = requestJson(
      method: 'POST',
      path: '/v1/projects/$project/instances',
      queryParameters: <String, String>{'instanceId': instanceId},
      body: <String, Object?>{
        'displayName': displayName,
        'config': 'projects/$project/instanceConfigs/$configId',
        'nodeCount': nodes,
      },
    );
    await _waitForOperation(operation);
  }

  @override
  Iterable<String> listDatabases(String instanceId) sync* {
    final Map<String, Object?> response = requestJson(
      method: 'GET',
      path: '/v1/projects/$project/instances/$instanceId/databases',
    );
    final Object? databases = response['databases'];
    if (databases is! List) {
      return;
    }
    for (final Object? item in databases) {
      if (item is! Map) {
        continue;
      }
      final Object? name = item['name'];
      if (name == null) {
        continue;
      }
      yield '$name'.split('/').last;
    }
  }

  @override
  Future<void> createDatabase({
    required String instanceId,
    required String databaseId,
  }) async {
    final Map<String, Object?> operation = requestJson(
      method: 'POST',
      path: '/v1/projects/$project/instances/$instanceId/databases',
      body: <String, Object?>{
        'createStatement': 'CREATE DATABASE `$databaseId`',
      },
    );
    await _waitForOperation(operation);
  }

  Future<void> _waitForOperation(Map<String, Object?> operation) async {
    final Object? name = operation['name'];
    if (name == null) {
      return;
    }

    final DateTime deadline = DateTime.now().add(const Duration(minutes: 5));
    Map<String, Object?> current = operation;
    while (!_isOperationDone(current)) {
      if (DateTime.now().isAfter(deadline)) {
        throw TimeoutException(
          'Timed out waiting for Spanner admin operation.',
        );
      }
      await Future<void>.delayed(const Duration(seconds: 1));
      current = requestJson(method: 'GET', path: '/v1/$name');
    }

    final Object? error = current['error'];
    if (error != null) {
      throw StateError('Spanner admin operation failed: $error');
    }
  }

  bool _isOperationDone(Map<String, Object?> operation) {
    final Object? done = operation['done'];
    if (done is bool) {
      return done;
    }
    return '$done'.toLowerCase() == 'true';
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
        'Spanner admin API curl invocation failed: ${result.stderr}',
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
        'Spanner admin API request failed (${response.statusCode}): '
        '${response.bodyText}',
        uri: response.uri,
      );
    }
    if (response.bodyText.trim().isEmpty) {
      return <String, Object?>{};
    }
    final Object? decoded = jsonDecode(response.bodyText);
    if (decoded is! Map) {
      throw StateError('Spanner admin API response is not a JSON object.');
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
      spannerDefaultScope.join(','),
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
      'Unable to resolve Cloud Spanner admin access token. '
      'Provide oauth2 credentials, set GOOGLE_OAUTH_ACCESS_TOKEN, '
      'or login with `gcloud auth application-default login`.',
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

int? _asInt(Object? value) {
  if (value is int) {
    return value;
  }
  return int.tryParse('$value');
}

Map<String, Object?> _asStringObjectMap(Object? value) {
  if (value is! Map) {
    return <String, Object?>{};
  }
  return value.map((Object? key, Object? value) => MapEntry('$key', value));
}
