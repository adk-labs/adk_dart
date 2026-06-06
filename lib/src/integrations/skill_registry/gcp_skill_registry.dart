/// Google Cloud Skill Registry integration.
library;

import 'dart:convert';
import 'dart:io';

import '../../skills/skill_runtime.dart';
import '../../tools/_google_access_token.dart';

const String _gcpSkillRegistryBaseUrl =
    'https://aiplatform.googleapis.com/v1beta1';
const List<String> _cloudPlatformScopes = <String>[
  'https://www.googleapis.com/auth/cloud-platform',
];

/// HTTP response payload used by [GcpSkillRegistry].
class GcpSkillRegistryHttpResponse {
  /// Creates an HTTP response wrapper.
  GcpSkillRegistryHttpResponse({
    required this.statusCode,
    required this.body,
    Map<String, String>? headers,
  }) : headers = headers ?? <String, String>{};

  /// HTTP status code.
  final int statusCode;

  /// Decoded response body.
  final Map<String, Object?> body;

  /// Response headers.
  final Map<String, String> headers;
}

/// Function that executes one Skill Registry GET request.
typedef GcpSkillRegistryHttpGetProvider =
    Future<GcpSkillRegistryHttpResponse> Function(
      Uri uri, {
      required Map<String, String> headers,
    });

/// Function that executes one Skill Registry POST request.
typedef GcpSkillRegistryHttpPostProvider =
    Future<GcpSkillRegistryHttpResponse> Function(
      Uri uri, {
      required Map<String, String> headers,
      required Map<String, Object?> body,
    });

/// Function that resolves auth headers for Skill Registry requests.
typedef GcpSkillRegistryAuthHeadersProvider =
    Future<Map<String, String>> Function();

/// Google Cloud implementation of [SkillRegistry].
class GcpSkillRegistry extends SkillRegistry {
  /// Creates a Google Cloud Skill Registry client.
  GcpSkillRegistry({
    String? projectId,
    String? location,
    Uri? apiBaseUri,
    GcpSkillRegistryHttpGetProvider? httpGetProvider,
    GcpSkillRegistryHttpPostProvider? httpPostProvider,
    GcpSkillRegistryAuthHeadersProvider? authHeadersProvider,
  }) : projectId =
           (projectId ?? Platform.environment['GOOGLE_CLOUD_PROJECT'] ?? '')
               .trim(),
       location =
           (location ?? Platform.environment['GOOGLE_CLOUD_LOCATION'] ?? '')
               .trim(),
       _apiBaseUri = apiBaseUri ?? Uri.parse(_gcpSkillRegistryBaseUrl),
       _httpGetProvider =
           httpGetProvider ?? _defaultGcpSkillRegistryHttpGetProvider,
       _httpPostProvider =
           httpPostProvider ?? _defaultGcpSkillRegistryHttpPostProvider,
       _authHeadersProvider =
           authHeadersProvider ?? _defaultGcpSkillRegistryAuthHeadersProvider {
    if (this.projectId.isEmpty || this.location.isEmpty) {
      throw ArgumentError('projectId and location must be provided');
    }
  }

  /// Google Cloud project id.
  final String projectId;

  /// Google Cloud location.
  final String location;

  final Uri _apiBaseUri;
  final GcpSkillRegistryHttpGetProvider _httpGetProvider;
  final GcpSkillRegistryHttpPostProvider _httpPostProvider;
  final GcpSkillRegistryAuthHeadersProvider _authHeadersProvider;

  String get _basePath => 'projects/$projectId/locations/$location';

  @override
  Future<Skill> getSkill({required String name, String? version}) async {
    final Map<String, Object?> skillResource = await _makeGetRequest(
      _skillResourceName(name),
    );
    final String? zippedFilesystem =
        _readString(skillResource['zippedFilesystem']) ??
        _readString(skillResource['zipped_filesystem']);
    if (zippedFilesystem == null || zippedFilesystem.trim().isEmpty) {
      throw ArgumentError("Skill '$name' does not contain zipped filesystem.");
    }

    return loadSkillFromZipBytes(base64Decode(zippedFilesystem));
  }

  @override
  Future<List<Frontmatter>> searchSkills({
    required String query,
    Map<String, Object?>? filters,
  }) async {
    final Map<String, Object?> response = await _makePostRequest(
      'skills:retrieve',
      body: <String, Object?>{'query': query},
    );
    final List<Object?> retrievedSkills =
        _readList(response['retrievedSkills']) ??
        _readList(response['retrieved_skills']) ??
        const <Object?>[];

    final List<Frontmatter> results = <Frontmatter>[];
    for (final Object? item in retrievedSkills) {
      if (item is! Map) {
        continue;
      }
      final Map<String, Object?> skill = _toStringObjectMap(item);
      final String skillName =
          _readString(skill['skillName']) ??
          _readString(skill['skill_name']) ??
          '';
      results.add(
        Frontmatter(
          name: skillName.split('/').last,
          description:
              _readString(skill['description']) ??
              _readString(skill['displayDescription']) ??
              '',
        ),
      );
    }
    return results;
  }

  @override
  String getSearchDescription() {
    return 'Searches for relevant skills in Google Cloud Skill Registry.';
  }

  Future<Map<String, Object?>> _makeGetRequest(String path) async {
    final Uri uri = _buildRequestUri(path);
    try {
      final GcpSkillRegistryHttpResponse response = await _httpGetProvider(
        uri,
        headers: <String, String>{
          ...await _authHeadersProvider(),
          'Content-Type': 'application/json',
        },
      );
      _throwIfUnsuccessful(response);
      return response.body;
    } on SocketException catch (error) {
      throw StateError('API request failed (network error): $error');
    } on HandshakeException catch (error) {
      throw StateError('API request failed (network error): $error');
    } catch (error) {
      if (error is StateError || error is ArgumentError) {
        rethrow;
      }
      throw StateError('API request failed: $error');
    }
  }

  Future<Map<String, Object?>> _makePostRequest(
    String path, {
    required Map<String, Object?> body,
  }) async {
    final Uri uri = _buildRequestUri(path);
    try {
      final GcpSkillRegistryHttpResponse response = await _httpPostProvider(
        uri,
        headers: <String, String>{
          ...await _authHeadersProvider(),
          'Content-Type': 'application/json',
        },
        body: body,
      );
      _throwIfUnsuccessful(response);
      return response.body;
    } on SocketException catch (error) {
      throw StateError('API request failed (network error): $error');
    } on HandshakeException catch (error) {
      throw StateError('API request failed (network error): $error');
    } catch (error) {
      if (error is StateError || error is ArgumentError) {
        rethrow;
      }
      throw StateError('API request failed: $error');
    }
  }

  String _skillResourceName(String name) {
    final String trimmed = name.trim();
    if (trimmed.startsWith('projects/')) {
      return trimmed;
    }
    return '$_basePath/skills/$trimmed';
  }

  Uri _buildRequestUri(String path) {
    final String base = _apiBaseUri.toString().replaceFirst(RegExp(r'/+$'), '');
    final String resolvedPath = path.startsWith('projects/')
        ? path
        : '$_basePath/$path';
    return Uri.parse('$base/$resolvedPath');
  }
}

void _throwIfUnsuccessful(GcpSkillRegistryHttpResponse response) {
  if (response.statusCode >= 200 && response.statusCode < 300) {
    return;
  }
  throw StateError(
    'API request failed with status ${response.statusCode}: '
    '${_responseBodySummary(response.body)}',
  );
}

Future<GcpSkillRegistryHttpResponse> _defaultGcpSkillRegistryHttpGetProvider(
  Uri uri, {
  required Map<String, String> headers,
}) async {
  final HttpClient client = HttpClient();
  client.connectionTimeout = const Duration(seconds: 5);
  try {
    final HttpClientRequest request = await client.getUrl(uri);
    headers.forEach(request.headers.set);
    final HttpClientResponse response = await request.close();
    return _decodeHttpResponse(response);
  } finally {
    client.close(force: true);
  }
}

Future<GcpSkillRegistryHttpResponse> _defaultGcpSkillRegistryHttpPostProvider(
  Uri uri, {
  required Map<String, String> headers,
  required Map<String, Object?> body,
}) async {
  final HttpClient client = HttpClient();
  client.connectionTimeout = const Duration(seconds: 5);
  try {
    final HttpClientRequest request = await client.postUrl(uri);
    headers.forEach(request.headers.set);
    request.write(jsonEncode(body));
    final HttpClientResponse response = await request.close();
    return _decodeHttpResponse(response);
  } finally {
    client.close(force: true);
  }
}

Future<GcpSkillRegistryHttpResponse> _decodeHttpResponse(
  HttpClientResponse response,
) async {
  final String bodyText = await utf8.decoder.bind(response).join();
  final Object? decoded = bodyText.trim().isEmpty
      ? <String, Object?>{}
      : jsonDecode(bodyText);
  final Map<String, Object?> body = decoded is Map
      ? _toStringObjectMap(decoded)
      : <String, Object?>{};
  final Map<String, String> responseHeaders = <String, String>{};
  response.headers.forEach((String key, List<String> values) {
    responseHeaders[key] = values.join(',');
  });
  return GcpSkillRegistryHttpResponse(
    statusCode: response.statusCode,
    body: body,
    headers: responseHeaders,
  );
}

Future<Map<String, String>>
_defaultGcpSkillRegistryAuthHeadersProvider() async {
  final String token = await resolveDefaultGoogleAccessToken(
    scopes: _cloudPlatformScopes,
  );
  return <String, String>{'Authorization': 'Bearer $token'};
}

String? _readString(Object? value) {
  if (value is String && value.isNotEmpty) {
    return value;
  }
  return null;
}

List<Object?>? _readList(Object? value) {
  return value is List ? value : null;
}

Map<String, Object?> _toStringObjectMap(Map value) {
  return value.map(
    (Object? key, Object? innerValue) =>
        MapEntry<String, Object?>('$key', innerValue),
  );
}

String _responseBodySummary(Map<String, Object?> body) {
  final Object? error = body['error'];
  if (error != null) {
    return '$error';
  }
  final String encoded = jsonEncode(body);
  return encoded.length <= 200 ? encoded : '${encoded.substring(0, 200)}...';
}
