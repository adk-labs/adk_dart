/// Pure Dart HTTP client for Vertex AI Agent Engine runtime lifecycle operations.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'cli_deploy.dart';

/// Async provider returning a Google OAuth 2.0 bearer access token.
typedef AgentEngineAccessTokenProvider = Future<String> Function();

const List<String> _defaultAccessTokenEnvKeys = <String>[
  'GOOGLE_OAUTH_ACCESS_TOKEN',
  'GCLOUD_ACCESS_TOKEN',
  'GOOGLE_ACCESS_TOKEN',
  'ACCESS_TOKEN',
];

/// Pure Dart HTTP implementation of [AgentEngineRuntimesClient] targeting the
/// Vertex AI Reasoning Engines REST API (`v1beta1`).
class HttpAgentEngineRuntimesClient implements AgentEngineRuntimesClient {
  /// Creates an [HttpAgentEngineRuntimesClient] for [project] and [region].
  ///
  /// When [endpointBaseUrl] is omitted, requests target
  /// `https://$region-aiplatform.googleapis.com/v1beta1`.
  ///
  /// When [accessTokenProvider] is omitted, bearer tokens are resolved from
  /// [environment] (`GOOGLE_OAUTH_ACCESS_TOKEN`, `GCLOUD_ACCESS_TOKEN`,
  /// `GOOGLE_ACCESS_TOKEN`, `ACCESS_TOKEN`) or via `gcloud auth print-access-token`.
  HttpAgentEngineRuntimesClient({
    required String project,
    required String region,
    String? endpointBaseUrl,
    http.Client? httpClient,
    AgentEngineAccessTokenProvider? accessTokenProvider,
    Map<String, String>? environment,
    this.operationPollInterval = const Duration(seconds: 2),
    this.maxOperationPolls = 60,
  }) : project = project.trim(),
       region = region.trim(),
       endpointBaseUrl = _stripTrailingSlashes(
         (endpointBaseUrl != null && endpointBaseUrl.trim().isNotEmpty)
             ? endpointBaseUrl.trim()
             : 'https://${region.trim()}-aiplatform.googleapis.com/v1beta1',
       ),
       _httpClient = httpClient ?? http.Client(),
       _ownsHttpClient = httpClient == null,
       _accessTokenProvider = accessTokenProvider,
       _environment = environment ?? Platform.environment {
    if (this.project.isEmpty) {
      throw ArgumentError.value(project, 'project', 'Project must not be empty.');
    }
    if (this.region.isEmpty) {
      throw ArgumentError.value(region, 'region', 'Region must not be empty.');
    }
  }

  /// Google Cloud project ID.
  final String project;

  /// Google Cloud region (location).
  final String region;

  /// Base URL of the Vertex AI API endpoint (without trailing slash).
  final String endpointBaseUrl;

  /// Delay between long-running operation poll requests.
  final Duration operationPollInterval;

  /// Maximum number of poll requests before timing out an operation.
  final int maxOperationPolls;

  final http.Client _httpClient;
  final bool _ownsHttpClient;
  final AgentEngineAccessTokenProvider? _accessTokenProvider;
  final Map<String, String> _environment;

  String get _collectionPath =>
      'projects/$project/locations/$region/reasoningEngines';

  /// Closes the underlying HTTP client if it was created by this instance.
  void close() {
    if (_ownsHttpClient) {
      _httpClient.close();
    }
  }

  @override
  Future<List<AgentEngineRuntimeInfo>> list({String? filter}) async {
    final List<AgentEngineRuntimeInfo> results = <AgentEngineRuntimeInfo>[];
    final Set<String> seenPageTokens = <String>{};
    String? pageToken;

    while (true) {
      final Map<String, String> queryParams = <String, String>{
        if (filter != null && filter.isNotEmpty) 'filter': filter,
        if (pageToken != null && pageToken.isNotEmpty) 'pageToken': pageToken,
      };
      final Uri uri = _buildUri(_collectionPath, queryParameters: queryParams);
      final Map<String, Object?> payload = await _sendJson(
        method: 'GET',
        uri: uri,
      );

      final Object? rawItems =
          payload['reasoningEngines'] ?? payload['reasoning_engines'];
      if (rawItems is List) {
        for (final Object? entry in rawItems) {
          if (entry is! Map) {
            continue;
          }
          final Map<String, Object?> item = _asStringKeyedMap(entry);
          final String? name = _nonEmptyString(item['name']);
          if (name == null) {
            continue;
          }
          results.add(
            AgentEngineRuntimeInfo(
              name: name,
              displayName: _nonEmptyString(
                item['displayName'] ?? item['display_name'],
              ),
              updateTime: _nonEmptyString(
                item['updateTime'] ?? item['update_time'],
              ),
            ),
          );
        }
      }

      final String? nextToken = _nonEmptyString(
        payload['nextPageToken'] ?? payload['next_page_token'],
      );
      if (nextToken == null || !seenPageTokens.add(nextToken)) {
        break;
      }
      pageToken = nextToken;
    }

    return results;
  }

  @override
  Future<AgentEngineRuntimeInfo> create({Map<String, Object?>? config}) async {
    final Uri uri = _buildUri(_collectionPath);
    final Map<String, Object?> rawPayload = await _sendJson(
      method: 'POST',
      uri: uri,
      body: config ?? const <String, Object?>{},
    );
    final Map<String, Object?> resolved = await _resolveOperationIfNeeded(
      rawPayload,
    );
    return _extractRuntimeInfo(resolved);
  }

  @override
  Future<String> update({
    required String name,
    required Map<String, Object?> config,
  }) async {
    final String normalizedName = normalizeResourceName(name);
    final String updateMask = config.keys
        .map((String key) => key.trim())
        .where((String key) => key.isNotEmpty)
        .join(',');
    final Uri uri = _buildUri(
      normalizedName,
      queryParameters: <String, String>{
        if (updateMask.isNotEmpty) 'updateMask': updateMask,
      },
    );
    final Map<String, Object?> rawPayload = await _sendJson(
      method: 'PATCH',
      uri: uri,
      body: config,
    );
    if (rawPayload.isEmpty) {
      return normalizedName;
    }
    final Map<String, Object?> resolved = await _resolveOperationIfNeeded(
      rawPayload,
    );
    final String? updatedName = _tryExtractResourceName(resolved);
    return updatedName ?? normalizedName;
  }

  @override
  Future<void> delete({required String name}) async {
    final String normalizedName = normalizeResourceName(name);
    final Uri uri = _buildUri(normalizedName);
    final Map<String, Object?> rawPayload = await _sendJson(
      method: 'DELETE',
      uri: uri,
    );
    if (rawPayload.isNotEmpty) {
      await _resolveOperationIfNeeded(rawPayload);
    }
  }

  /// Normalizes a short reasoning engine ID or full resource name into
  /// `projects/{project}/locations/{region}/reasoningEngines/{id}`.
  String normalizeResourceName(String name) {
    final String trimmed = name.trim().replaceFirst(RegExp(r'^/+'), '');
    if (trimmed.isEmpty) {
      throw ArgumentError.value(name, 'name', 'Resource name must not be empty.');
    }
    if (trimmed.startsWith('projects/')) {
      return trimmed;
    }
    return '$_collectionPath/$trimmed';
  }

  Uri _buildUri(String relativePath, {Map<String, String>? queryParameters}) {
    final String cleanPath = relativePath.replaceFirst(RegExp(r'^/+'), '');
    final Uri base = Uri.parse('$endpointBaseUrl/$cleanPath');
    if (queryParameters == null || queryParameters.isEmpty) {
      return base;
    }
    return base.replace(
      queryParameters: <String, String>{
        ...base.queryParameters,
        ...queryParameters,
      },
    );
  }

  Future<Map<String, Object?>> _sendJson({
    required String method,
    required Uri uri,
    Map<String, Object?>? body,
  }) async {
    final String accessToken = await _resolveAccessToken();
    final http.Request request = http.Request(method, uri);
    request.headers['Authorization'] = 'Bearer $accessToken';
    request.headers['Accept'] = 'application/json';
    if (body != null) {
      request.headers['Content-Type'] = 'application/json; charset=utf-8';
      request.body = jsonEncode(body);
    }

    final http.StreamedResponse streamed;
    try {
      streamed = await _httpClient.send(request);
    } on Object catch (error) {
      throw AgentEngineDeployException(
        'Vertex AI Agent Engine API $method $uri transport error: $error',
        cause: error,
      );
    }

    final http.Response response = await http.Response.fromStream(streamed);
    final String responseText = response.body;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final String detail = _extractHttpErrorDetail(
        responseText,
        response.reasonPhrase,
      );
      throw AgentEngineDeployException(
        'Vertex AI Agent Engine API $method $uri failed '
        '(HTTP ${response.statusCode}): $detail',
      );
    }

    if (responseText.trim().isEmpty) {
      return const <String, Object?>{};
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(responseText);
    } on FormatException catch (error) {
      throw AgentEngineDeployException(
        'Vertex AI Agent Engine API $method $uri returned invalid JSON: '
        '${error.message}',
        cause: error,
      );
    }

    if (decoded is! Map) {
      throw AgentEngineDeployException(
        'Vertex AI Agent Engine API $method $uri returned unexpected JSON '
        'payload type: ${decoded.runtimeType}',
      );
    }
    return _asStringKeyedMap(decoded);
  }

  Future<Map<String, Object?>> _resolveOperationIfNeeded(
    Map<String, Object?> payload,
  ) async {
    if (!_isOperationPayload(payload)) {
      return payload;
    }

    Map<String, Object?> current = payload;
    int polls = 0;

    while (current['done'] != true) {
      final String? operationName = _nonEmptyString(current['name']);
      if (operationName == null) {
        throw const AgentEngineDeployException(
          'Vertex AI Agent Engine operation response is missing operation name.',
        );
      }
      if (polls >= maxOperationPolls) {
        throw AgentEngineDeployException(
          'Timed out waiting for Vertex AI Agent Engine operation '
          '$operationName after $maxOperationPolls polls.',
        );
      }
      polls += 1;
      if (operationPollInterval > Duration.zero) {
        await Future<void>.delayed(operationPollInterval);
      }
      current = await _sendJson(
        method: 'GET',
        uri: _buildUri(operationName),
      );
    }

    final Object? opError = current['error'];
    if (opError != null) {
      final String detail = _formatOperationError(opError);
      throw AgentEngineDeployException(
        'Vertex AI Agent Engine operation failed: $detail',
      );
    }

    return current;
  }

  bool _isOperationPayload(Map<String, Object?> payload) {
    if (payload.containsKey('done')) {
      return true;
    }
    final String? name = _nonEmptyString(payload['name']);
    return name != null && name.contains('/operations/');
  }

  AgentEngineRuntimeInfo _extractRuntimeInfo(Map<String, Object?> payload) {
    final Object? responseObj = payload['response'];
    if (responseObj is Map) {
      final Map<String, Object?> responseMap = _asStringKeyedMap(responseObj);
      final String? name = _nonEmptyString(responseMap['name']);
      if (name != null) {
        return AgentEngineRuntimeInfo(
          name: name,
          displayName: _nonEmptyString(
            responseMap['displayName'] ?? responseMap['display_name'],
          ),
          updateTime: _nonEmptyString(
            responseMap['updateTime'] ?? responseMap['update_time'],
          ),
        );
      }
    }

    final String? resolvedName = _tryExtractResourceName(payload);
    if (resolvedName != null) {
      return AgentEngineRuntimeInfo(
        name: resolvedName,
        displayName: _nonEmptyString(
          payload['displayName'] ?? payload['display_name'],
        ),
        updateTime: _nonEmptyString(
          payload['updateTime'] ?? payload['update_time'],
        ),
      );
    }

    throw AgentEngineDeployException(
      'Vertex AI Agent Engine create response did not include a resource name: '
      '${jsonEncode(payload)}',
    );
  }

  String? _tryExtractResourceName(Map<String, Object?> payload) {
    final Object? responseObj = payload['response'];
    if (responseObj is Map) {
      final Map<String, Object?> responseMap = _asStringKeyedMap(responseObj);
      final String? responseName = _nonEmptyString(responseMap['name']);
      if (responseName != null && !responseName.contains('/operations/')) {
        return responseName;
      }
    }

    final String? directName = _nonEmptyString(payload['name']);
    if (directName != null && !directName.contains('/operations/')) {
      return directName;
    }

    final Object? metadataObj = payload['metadata'];
    if (metadataObj is Map) {
      final Map<String, Object?> metadata = _asStringKeyedMap(metadataObj);
      final Object? genericObj =
          metadata['genericMetadata'] ?? metadata['generic_metadata'];
      if (genericObj is Map) {
        final Map<String, Object?> generic = _asStringKeyedMap(genericObj);
        final String? genericName = _nonEmptyString(
          generic['target'] ??
              generic['resourceName'] ??
              generic['resource_name'] ??
              generic['name'],
        );
        if (genericName != null && !genericName.contains('/operations/')) {
          return genericName;
        }
      }
      final String? metaTarget = _nonEmptyString(
        metadata['target'] ??
            metadata['resourceName'] ??
            metadata['resource_name'] ??
            metadata['reasoningEngine'] ??
            metadata['reasoning_engine'],
      );
      if (metaTarget != null && !metaTarget.contains('/operations/')) {
        return metaTarget;
      }
    }

    if (directName != null && directName.contains('/operations/')) {
      final String prefix = directName.split('/operations/').first;
      if (prefix.contains('/reasoningEngines/')) {
        return prefix;
      }
    }

    return null;
  }

  Future<String> _resolveAccessToken() async {
    if (_accessTokenProvider != null) {
      final String token = (await _accessTokenProvider()).trim();
      if (token.isEmpty) {
        throw const AgentEngineDeployException(
          'Access token provider returned an empty token.',
        );
      }
      return token;
    }

    for (final String key in _defaultAccessTokenEnvKeys) {
      final String? value = _environment[key]?.trim();
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }

    final String? fromGcloud = await _resolveAccessTokenFromGcloud();
    if (fromGcloud != null && fromGcloud.isNotEmpty) {
      return fromGcloud;
    }

    throw const AgentEngineDeployException(
      'Unable to obtain a Google Cloud access token for Vertex AI Agent Engine. '
      'Set GOOGLE_OAUTH_ACCESS_TOKEN or GCLOUD_ACCESS_TOKEN, or authenticate '
      'with `gcloud auth login` / `gcloud auth application-default login`.',
    );
  }

  Future<String?> _resolveAccessTokenFromGcloud() async {
    const List<List<String>> commands = <List<String>>[
      <String>['auth', 'print-access-token'],
      <String>['auth', 'application-default', 'print-access-token'],
    ];

    for (final List<String> args in commands) {
      try {
        final ProcessResult result = await Process.run(
          'gcloud',
          args,
          environment: _environment,
          runInShell: Platform.isWindows,
        ).timeout(const Duration(seconds: 5));
        if (result.exitCode == 0) {
          final String token = '${result.stdout}'.trim();
          if (token.isNotEmpty) {
            return token;
          }
        }
      } on ProcessException {
        return null;
      } on TimeoutException {
        continue;
      }
    }
    return null;
  }

  static String _stripTrailingSlashes(String value) {
    return value.replaceFirst(RegExp(r'/+$'), '');
  }

  static Map<String, Object?> _asStringKeyedMap(Map<Object?, Object?> raw) {
    return raw.map((Object? key, Object? value) => MapEntry('$key', value));
  }

  static String? _nonEmptyString(Object? value) {
    if (value is! String) {
      return null;
    }
    final String trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static String _extractHttpErrorDetail(String body, String? reasonPhrase) {
    final String trimmed = body.trim();
    if (trimmed.isNotEmpty) {
      try {
        final Object? decoded = jsonDecode(trimmed);
        if (decoded is Map) {
          final Object? errorObj = decoded['error'];
          if (errorObj is Map) {
            final String? message = _nonEmptyString(errorObj['message']);
            final String? status = _nonEmptyString(errorObj['status']);
            if (message != null && status != null) {
              return '$status: $message';
            }
            if (message != null) {
              return message;
            }
          }
          final String? topMessage = _nonEmptyString(decoded['message']);
          if (topMessage != null) {
            return topMessage;
          }
        }
      } on FormatException {
        // Fall through to raw body.
      }
      return trimmed;
    }
    return (reasonPhrase != null && reasonPhrase.trim().isNotEmpty)
        ? reasonPhrase.trim()
        : 'Unknown HTTP error';
  }

  static String _formatOperationError(Object error) {
    if (error is Map) {
      final String? message = _nonEmptyString(error['message']);
      final Object? code = error['code'];
      if (message != null && code != null) {
        return 'code $code: $message';
      }
      if (message != null) {
        return message;
      }
      return jsonEncode(error);
    }
    return '$error';
  }
}
