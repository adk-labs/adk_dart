/// Google Cloud Parameter Manager client integration for ADK.
library;

import 'dart:convert';
import 'dart:io';

import '../../tools/_google_access_token.dart';

/// Custom parameter version fetcher callback used by [ParameterManagerClient].
typedef ParameterManagerFetcher = Future<String> Function({
  required String resourceName,
  required String accessToken,
  String? location,
});

ParameterManagerFetcher? _customParameterManagerFetcher;

/// Overrides the HTTP parameter fetcher used by [ParameterManagerClient] in
/// tests.
void setParameterManagerFetcher(ParameterManagerFetcher? fetcher) {
  _customParameterManagerFetcher = fetcher;
}

/// Resets the custom parameter fetcher to the default Cloud Parameter Manager
/// HTTP implementation.
void resetParameterManagerFetcher() {
  _customParameterManagerFetcher = null;
}

/// Client for retrieving parameter payloads from Google Cloud Parameter
/// Manager.
///
/// Supports either a service account JSON credential payload
/// (`serviceAccountJson`), an explicit OAuth/Bearer token (`authToken`), or
/// Application Default Credentials when neither is specified. Providing both
/// `serviceAccountJson` and `authToken` throws an [ArgumentError].
///
/// ```dart
/// final client = ParameterManagerClient(
///   authToken: 'ya29.example-token',
///   location: 'us-central1',
/// );
/// final value = await client.getParameter(
///   'projects/my-project/locations/us-central1/parameters/my-param/versions/v1',
/// );
/// ```
class ParameterManagerClient {
  /// Creates a Parameter Manager client.
  ParameterManagerClient({
    String? serviceAccountJson,
    String? authToken,
    String? location,
    Future<String> Function()? defaultTokenResolver,
    ParameterManagerFetcher? fetcher,
  }) : _serviceAccountJson = serviceAccountJson,
       _authToken = authToken,
       _location = location,
       _defaultTokenResolver =
           defaultTokenResolver ?? resolveDefaultGoogleAccessToken,
       _fetcher = fetcher {
    final bool hasServiceAccount =
        serviceAccountJson != null && serviceAccountJson.isNotEmpty;
    final bool hasAuthToken = authToken != null && authToken.isNotEmpty;
    if (hasServiceAccount && hasAuthToken) {
      throw ArgumentError(
        'Cannot provide both serviceAccountJson and authToken. Please provide '
        'only one authentication method, or neither to use Application Default '
        'Credentials.',
      );
    }

    if (hasServiceAccount) {
      try {
        final Object? decoded = jsonDecode(serviceAccountJson);
        if (decoded is! Map<String, dynamic>) {
          throw const FormatException(
            'Credential payload must be a JSON object.',
          );
        }
        _parsedCredentials = decoded;
      } catch (error) {
        throw ArgumentError(
          'Invalid serviceAccountJson: failed to parse JSON. Error: $error',
        );
      }
    }
  }

  final String? _serviceAccountJson;
  final String? _authToken;
  final String? _location;
  final Future<String> Function() _defaultTokenResolver;
  final ParameterManagerFetcher? _fetcher;
  Map<String, dynamic>? _parsedCredentials;
  final Map<String, String> _cache = <String, String>{};

  /// Optional regional location (for example, `'us-central1'`).
  ///
  /// When set, requests are routed to the regional endpoint
  /// `https://parametermanager.{location}.rep.googleapis.com`.
  String? get location => _location;

  /// Effective API endpoint base URL for this client.
  String get apiEndpoint {
    final String? loc = _location?.trim();
    if (loc != null && loc.isNotEmpty) {
      return 'https://parametermanager.$loc.rep.googleapis.com';
    }
    return 'https://parametermanager.googleapis.com';
  }

  /// Retrieves the decoded string payload of a parameter version.
  ///
  /// [resourceName] must be in the format
  /// `projects/*/locations/*/parameters/*/versions/*`.
  Future<String> getParameter(String resourceName) async {
    final String normalizedResource = resourceName.trim();
    if (normalizedResource.isEmpty) {
      throw ArgumentError.value(
        resourceName,
        'resourceName',
        'Parameter version resourceName must not be empty.',
      );
    }

    final String? cached = _cache[normalizedResource];
    if (cached != null) {
      return cached;
    }

    final String token = await _resolveAccessToken();
    final ParameterManagerFetcher fetcher =
        _fetcher ?? _customParameterManagerFetcher ?? _defaultParameterFetcher;
    final String value = await fetcher(
      resourceName: normalizedResource,
      accessToken: token,
      location: _location,
    );
    _cache[normalizedResource] = value;
    return value;
  }

  Future<String> _resolveAccessToken() async {
    if (_authToken != null && _authToken.trim().isNotEmpty) {
      return _authToken.trim();
    }

    if (_parsedCredentials != null) {
      final Object? directToken =
          _parsedCredentials!['access_token'] ?? _parsedCredentials!['token'];
      if (directToken is String && directToken.trim().isNotEmpty) {
        return directToken.trim();
      }
      return _defaultTokenResolver();
    }

    if (_serviceAccountJson != null && _serviceAccountJson.isNotEmpty) {
      return _defaultTokenResolver();
    }

    return _defaultTokenResolver();
  }

  Future<String> _defaultParameterFetcher({
    required String resourceName,
    required String accessToken,
    String? location,
  }) async {
    final String normalizedPath = resourceName.startsWith('/')
        ? resourceName.substring(1)
        : resourceName;
    final String baseHost = (location != null && location.trim().isNotEmpty)
        ? 'https://parametermanager.${location.trim()}.rep.googleapis.com'
        : 'https://parametermanager.googleapis.com';
    final Uri uri = Uri.parse('$baseHost/v1/$normalizedPath');

    final HttpClient httpClient = HttpClient();
    try {
      final HttpClientRequest request = await httpClient.getUrl(uri);
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $accessToken');
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final HttpClientResponse response = await request.close();
      final String body = await utf8.decoder.bind(response).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'Parameter Manager request failed (${response.statusCode}): $body',
          uri: uri,
        );
      }

      final Object? decoded = jsonDecode(body);
      if (decoded is! Map) {
        throw const FormatException(
          'Unexpected Parameter Manager response payload.',
        );
      }
      final Object? payload = decoded['payload'];
      if (payload is! Map) {
        throw const FormatException(
          'Parameter Manager response is missing payload.',
        );
      }
      final Object? encodedData = payload['data'];
      if (encodedData is! String || encodedData.isEmpty) {
        throw const FormatException(
          'Parameter Manager payload is missing base64 data.',
        );
      }

      return utf8.decode(base64Decode(encodedData));
    } finally {
      httpClient.close(force: true);
    }
  }
}
