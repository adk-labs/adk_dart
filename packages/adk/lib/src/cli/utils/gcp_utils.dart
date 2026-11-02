/// Utilities for GCP authentication and Vertex AI Express Mode.
library;

import 'dart:convert';
import 'dart:io';

import 'envs.dart';

const String _vertexAiEndpoint =
    'https://{location}-aiplatform.googleapis.com/v1beta1';
const String _vertexAiMtlsEndpoint =
    'https://{location}-aiplatform.mtls.googleapis.com/v1beta1';

/// Exception thrown when a Vertex AI Express API HTTP request returns an error status.
class VertexExpressHttpException implements Exception {
  /// Creates a Vertex AI Express HTTP exception.
  const VertexExpressHttpException({
    required this.statusCode,
    required this.body,
    required this.uri,
  });

  /// HTTP status code returned by the server.
  final int statusCode;

  /// Raw response body text.
  final String body;

  /// Request URI that failed.
  final Uri uri;

  @override
  String toString() =>
      'VertexExpressHttpException(statusCode: $statusCode, uri: $uri, body: $body)';
}

/// Signature for synchronous process execution used by GCP CLI helpers.
typedef GcloudProcessRunner =
    ProcessResult Function(String executable, List<String> arguments);

/// Signature for synchronous HTTP transport used by Vertex AI Express API helpers.
typedef VertexExpressHttpTransport =
    ({int statusCode, String body}) Function({
      required String method,
      required Uri uri,
      required Map<String, String> headers,
      String? body,
    });

ProcessResult _defaultProcessRunner(
  String executable,
  List<String> arguments,
) => Process.runSync(executable, arguments);

({int statusCode, String body}) _defaultHttpTransport({
  required String method,
  required Uri uri,
  required Map<String, String> headers,
  String? body,
}) {
  final List<String> args = <String>[
    '-s',
    '-S',
    '-X',
    method,
    '-w',
    '\n%{http_code}',
  ];
  headers.forEach((String key, String value) {
    args.addAll(<String>['-H', '$key: $value']);
  });
  if (body != null) {
    args.addAll(<String>['--data-raw', body]);
  }
  args.add(uri.toString());

  final ProcessResult result = Process.runSync('curl', args);
  if (result.exitCode != 0) {
    throw StateError('HTTP request failed for $uri: ${result.stderr}');
  }
  final String output = '${result.stdout}';
  final int lastNewline = output.lastIndexOf('\n');
  if (lastNewline < 0) {
    final int code = int.tryParse(output.trim()) ?? 500;
    return (statusCode: code, body: '');
  }
  final String responseBody = output.substring(0, lastNewline);
  final int statusCode =
      int.tryParse(output.substring(lastNewline + 1).trim()) ?? 500;
  return (statusCode: statusCode, body: responseBody);
}

bool _useClientCertEffective(Map<String, String> env) {
  final String raw = (env['GOOGLE_API_USE_CLIENT_CERTIFICATE'] ?? '')
      .trim()
      .toLowerCase();
  return raw == 'true' || raw == '1';
}

/// Checks if Application Default Credentials exist.
bool checkAdc({
  Map<String, String>? environment,
  GcloudProcessRunner? processRunner,
}) {
  final Map<String, String> env = environment ?? getCliEnvironment();
  for (final String key in const <String>[
    'GOOGLE_OAUTH_ACCESS_TOKEN',
    'GOOGLE_ACCESS_TOKEN',
    'ACCESS_TOKEN',
  ]) {
    final String? token = env[key]?.trim();
    if (token != null && token.isNotEmpty) {
      return true;
    }
  }

  final String? credentialsFile = env['GOOGLE_APPLICATION_CREDENTIALS']?.trim();
  if (credentialsFile != null && credentialsFile.isNotEmpty) {
    return File(credentialsFile).existsSync();
  }

  final String? home = env['HOME'] ?? env['USERPROFILE'];
  if (home != null && home.isNotEmpty) {
    final String sep = Platform.pathSeparator;
    final File unixAdc = File(
      '$home$sep.config${sep}gcloud${sep}application_default_credentials.json',
    );
    if (unixAdc.existsSync()) {
      return true;
    }
  }
  final String? appData = env['APPDATA'];
  if (appData != null && appData.isNotEmpty) {
    final String sep = Platform.pathSeparator;
    final File winAdc = File(
      '$appData${sep}gcloud${sep}application_default_credentials.json',
    );
    if (winAdc.existsSync()) {
      return true;
    }
  }

  final GcloudProcessRunner runner = processRunner ?? _defaultProcessRunner;
  try {
    final ProcessResult result = runner('gcloud', <String>[
      'auth',
      'application-default',
      'print-access-token',
    ]);
    return result.exitCode == 0 && '${result.stdout}'.trim().isNotEmpty;
  } on Object {
    return false;
  }
}

/// Prompts the user to login via `gcloud auth application-default login`.
///
/// Throws a [StateError] if `gcloud` is not installed or fails to run.
void loginAdc({GcloudProcessRunner? processRunner}) {
  final GcloudProcessRunner runner = processRunner ?? _defaultProcessRunner;
  try {
    final ProcessResult result = runner('gcloud', <String>[
      'auth',
      'application-default',
      'login',
    ]);
    if (result.exitCode != 0) {
      throw StateError(
        'gcloud is not installed or failed to run. '
        'Please install gcloud to login to Application Default Credentials.',
      );
    }
  } on Object {
    throw StateError(
      'gcloud is not installed or failed to run. '
      'Please install gcloud to login to Application Default Credentials.',
    );
  }
}

/// Gets the ADC access token.
///
/// Throws a [StateError] when Application Default Credentials are not found.
String getAccessToken({
  Map<String, String>? environment,
  GcloudProcessRunner? processRunner,
}) {
  final Map<String, String> env = environment ?? getCliEnvironment();
  for (final String key in const <String>[
    'GOOGLE_OAUTH_ACCESS_TOKEN',
    'GOOGLE_ACCESS_TOKEN',
    'ACCESS_TOKEN',
  ]) {
    final String? token = env[key]?.trim();
    if (token != null && token.isNotEmpty) {
      return token;
    }
  }

  final GcloudProcessRunner runner = processRunner ?? _defaultProcessRunner;
  try {
    final ProcessResult result = runner('gcloud', <String>[
      'auth',
      'application-default',
      'print-access-token',
    ]);
    if (result.exitCode == 0) {
      return '${result.stdout}'.trim();
    }
  } on Object {
    // Fall through to StateError below.
  }

  throw StateError('Application Default Credentials not found.');
}

/// Calls a Vertex AI Express API endpoint and returns the decoded JSON map.
Map<String, Object?> callVertexExpressApi(
  String method,
  String action, {
  String location = 'us-central1',
  Map<String, Object?>? data,
  Map<String, Object?>? params,
  Map<String, String>? environment,
  GcloudProcessRunner? processRunner,
  VertexExpressHttpTransport? httpTransport,
}) {
  final Map<String, String> env = environment ?? getCliEnvironment();
  final String token = getAccessToken(
    environment: env,
    processRunner: processRunner,
  );

  final String template = _useClientCertEffective(env)
      ? _vertexAiMtlsEndpoint
      : _vertexAiEndpoint;
  final String endpoint = template.replaceAll('{location}', location);
  Uri uri = Uri.parse('$endpoint/vertexExpress$action');
  if (params != null && params.isNotEmpty) {
    uri = uri.replace(
      queryParameters: <String, String>{
        ...uri.queryParameters,
        for (final MapEntry<String, Object?> entry in params.entries)
          if (entry.value != null) entry.key: '${entry.value}',
      },
    );
  }

  final String normalizedMethod = method.toUpperCase();
  if (normalizedMethod != 'GET' && normalizedMethod != 'POST') {
    throw ArgumentError('Unsupported method: $method');
  }

  final Map<String, String> headers = <String, String>{
    'Content-Type': 'application/json',
    if (token.isNotEmpty) 'Authorization': 'Bearer $token',
  };

  final VertexExpressHttpTransport transport =
      httpTransport ?? _defaultHttpTransport;
  final ({int statusCode, String body}) response = transport(
    method: normalizedMethod,
    uri: uri,
    headers: headers,
    body: normalizedMethod == 'POST' && data != null ? jsonEncode(data) : null,
  );

  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw VertexExpressHttpException(
      statusCode: response.statusCode,
      body: response.body,
      uri: uri,
    );
  }

  if (response.body.trim().isEmpty) {
    return <String, Object?>{};
  }
  final Object? decoded = jsonDecode(response.body);
  if (decoded is Map) {
    return decoded.map(
      (Object? key, Object? value) => MapEntry('$key', value),
    );
  }
  return <String, Object?>{};
}

/// Retrieves existing Express project info, or `null` if none exists.
Map<String, Object?>? retrieveExpressProject({
  String location = 'us-central1',
  Map<String, String>? environment,
  GcloudProcessRunner? processRunner,
  VertexExpressHttpTransport? httpTransport,
}) {
  try {
    final Map<String, Object?> response = callVertexExpressApi(
      'GET',
      ':retrieveExpressProject',
      location: location,
      params: const <String, Object?>{'get_default_api_key': true},
      environment: environment,
      processRunner: processRunner,
      httpTransport: httpTransport,
    );
    final Object? rawProject = response['expressProject'];
    if (rawProject is! Map || rawProject.isEmpty) {
      return null;
    }
    final Map<String, Object?> project = rawProject.map(
      (Object? key, Object? value) => MapEntry('$key', value),
    );
    return <String, Object?>{
      'project_id': project['projectId'],
      'api_key': project['defaultApiKey'],
      'region': project['region'] ?? location,
    };
  } on VertexExpressHttpException catch (e) {
    if (e.statusCode == 404) {
      return null;
    }
    rethrow;
  }
}

/// Checks if the user is eligible for Express Mode.
bool checkExpressEligibility({
  String location = 'us-central1',
  Map<String, String>? environment,
  GcloudProcessRunner? processRunner,
  VertexExpressHttpTransport? httpTransport,
}) {
  try {
    final Map<String, Object?> result = callVertexExpressApi(
      'GET',
      '/Eligibility:check',
      location: location,
      environment: environment,
      processRunner: processRunner,
      httpTransport: httpTransport,
    );
    final Object? eligibility = result['eligibility'];
    return eligibility == 'ELIGIBLE' || eligibility == 'IN_SCOPE';
  } on VertexExpressHttpException {
    return false;
  } on FormatException {
    return false;
  }
}

/// Signs up for Express Mode in [location].
Map<String, Object?> signUpExpress({
  String location = 'us-central1',
  Map<String, String>? environment,
  GcloudProcessRunner? processRunner,
  VertexExpressHttpTransport? httpTransport,
}) {
  final Map<String, Object?> project = callVertexExpressApi(
    'POST',
    ':signUp',
    location: location,
    data: <String, Object?>{
      'region': location,
      'tos_accepted': true,
      'get_default_api_key': true,
    },
    environment: environment,
    processRunner: processRunner,
    httpTransport: httpTransport,
  );
  return <String, Object?>{
    'project_id': project['projectId'],
    'api_key': project['defaultApiKey'],
    'region': project['region'] ?? location,
  };
}

/// Lists GCP projects available to the user up to [limit].
///
/// Returns a list of `(projectId, displayName)` records.
List<(String, String)> listGcpProjects({
  int limit = 20,
  GcloudProcessRunner? processRunner,
}) {
  if (limit <= 0) {
    return <(String, String)>[];
  }
  final GcloudProcessRunner runner = processRunner ?? _defaultProcessRunner;
  try {
    final ProcessResult result = runner('gcloud', <String>[
      'projects',
      'list',
      '--format=json',
      '--limit=$limit',
    ]);
    if (result.exitCode != 0) {
      return <(String, String)>[];
    }
    final Object? decoded = jsonDecode('${result.stdout}');
    if (decoded is! List) {
      return <(String, String)>[];
    }
    final List<(String, String)> projects = <(String, String)>[];
    for (final Object? item in decoded) {
      if (projects.length >= limit) {
        break;
      }
      if (item is Map) {
        final String projectId = '${item['projectId'] ?? ''}'.trim();
        if (projectId.isEmpty) {
          continue;
        }
        final String name = '${item['name'] ?? ''}'.trim();
        projects.add((projectId, name.isEmpty ? projectId : name));
      }
    }
    return projects;
  } on Object {
    return <(String, String)>[];
  }
}
