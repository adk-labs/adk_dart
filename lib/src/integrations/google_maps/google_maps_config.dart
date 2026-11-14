/// Configuration and Secret Manager credential resolution for Google Maps.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../secret_manager/secret_manager.dart';

/// Error message raised when Secret Manager support is explicitly disabled or unavailable.
const String googleMapsSecretManagerRequiredMessage =
    'Secret Manager support requires google-cloud-secret-manager. '
    "Install it with: pip install 'google-adk[gcp]'.";

/// Callback signature for resolving a Google Maps API key from Secret Manager.
typedef GoogleMapsSecretFetcher =
    FutureOr<String?> Function({
      required String resourceName,
      String? serviceAccountEmail,
      String? agentEngineId,
    });

GoogleMapsSecretFetcher? _customGoogleMapsSecretFetcher;

/// Overrides the Secret Manager fetcher used by [GoogleMapsConfig] in tests.
void setGoogleMapsSecretFetcher(GoogleMapsSecretFetcher? fetcher) {
  _customGoogleMapsSecretFetcher = fetcher;
}

/// Restores the default Secret Manager fetcher used by [GoogleMapsConfig].
void resetGoogleMapsSecretFetcher() {
  _customGoogleMapsSecretFetcher = null;
}

/// Returns `null` if [value] is unset, blank, or still holds a template token.
String? cleanGoogleMapsEnv(String? value) {
  if (value == null || value.isEmpty) {
    return null;
  }
  final String stripped = value.trim();
  if (stripped.isEmpty ||
      stripped.startsWith('<TODO') ||
      stripped.startsWith('<YOUR_')) {
    return null;
  }
  return stripped;
}

/// Manages credentials and default API settings for Google Maps Platform.
///
/// Resolution priority for the Google Maps API key:
/// 1. Explicit `apiKey` passed to [GoogleMapsConfig.new].
/// 2. `MAPS_API_KEY` environment variable.
/// 3. Google Cloud Secret Manager secret specified via [secretResourceName] or
///    `MAPS_API_KEY_SECRET_RESOURCE` (supports optional Service Account
///    impersonation via [serviceAccountEmail] or `GOOGLE_SA_EMAIL`).
///
/// ```dart
/// final config = GoogleMapsConfig(apiKey: 'AIza...');
/// ```
class GoogleMapsConfig {
  /// Creates a [GoogleMapsConfig].
  GoogleMapsConfig({
    String? apiKey,
    String? secretResourceName,
    String? serviceAccountEmail,
    this.defaultPitch = 10,
    this.defaultFov = 120,
    this.defaultSize = '600x400',
    this.timeout = 10.0,
    Map<String, String>? environment,
    GoogleMapsSecretFetcher? secretFetcher,
    this.secretManagerAvailable = true,
    this.httpClient,
    this.onHttpLog,
  }) : _explicitApiKey = cleanGoogleMapsEnv(apiKey),
       _environment = environment,
       _secretFetcher = secretFetcher,
       secretResourceName =
           cleanGoogleMapsEnv(secretResourceName) ??
           cleanGoogleMapsEnv(
             (environment ?? Platform.environment)['MAPS_API_KEY_SECRET_RESOURCE'],
           ),
       serviceAccountEmail =
           cleanGoogleMapsEnv(serviceAccountEmail) ??
           cleanGoogleMapsEnv(
             (environment ?? Platform.environment)['GOOGLE_SA_EMAIL'],
           );

  final String? _explicitApiKey;
  final Map<String, String>? _environment;
  final GoogleMapsSecretFetcher? _secretFetcher;
  String? _cachedApiKey;

  /// Optional Secret Manager secret version resource name.
  final String? secretResourceName;

  /// Optional service account email for IAM credential impersonation.
  final String? serviceAccountEmail;

  /// Default camera pitch in degrees (`-90` to `90`) for Street View requests.
  final int defaultPitch;

  /// Default horizontal field of view in degrees for Street View requests.
  final int defaultFov;

  /// Default image dimensions (`<width>x<height>`) for Street View requests.
  final String defaultSize;

  /// Default HTTP request timeout in seconds.
  final double timeout;

  /// Whether Secret Manager lookup support is available in this runtime.
  final bool secretManagerAvailable;

  /// Optional injected HTTP client used for outbound Google Maps requests.
  final http.Client? httpClient;

  /// Optional callback invoked with redacted HTTP request log lines.
  final void Function(String message)? onHttpLog;

  Map<String, String> get _env => _environment ?? Platform.environment;

  /// Resolves the Maps API key synchronously from memory, environment, or a
  /// synchronous Secret Manager fetcher.
  ///
  /// For asynchronous Secret Manager HTTP resolution, prefer [getApiKeyAsync].
  String? getApiKey() {
    if (_explicitApiKey != null) {
      return _explicitApiKey;
    }
    if (_cachedApiKey != null) {
      return _cachedApiKey;
    }

    final String? envKey = cleanGoogleMapsEnv(_env['MAPS_API_KEY']);
    if (envKey != null) {
      _cachedApiKey = envKey;
      return _cachedApiKey;
    }

    final String? secretRes =
        secretResourceName ??
        cleanGoogleMapsEnv(_env['MAPS_API_KEY_SECRET_RESOURCE']);
    if (secretRes == null) {
      return null;
    }

    if (!secretManagerAvailable) {
      throw UnsupportedError(googleMapsSecretManagerRequiredMessage);
    }

    final GoogleMapsSecretFetcher? fetcher =
        _secretFetcher ?? _customGoogleMapsSecretFetcher;
    if (fetcher == null) {
      return null;
    }

    final String? saEmail =
        serviceAccountEmail ?? cleanGoogleMapsEnv(_env['GOOGLE_SA_EMAIL']);
    final String? agentEngineId = cleanGoogleMapsEnv(
      _env['GOOGLE_CLOUD_AGENT_ENGINE_ID'],
    );

    try {
      final FutureOr<String?> result = fetcher(
        resourceName: secretRes,
        serviceAccountEmail: saEmail,
        agentEngineId: agentEngineId,
      );
      if (result is Future<String?>) {
        return null;
      }
      final String? key = cleanGoogleMapsEnv(result);
      if (key != null) {
        _cachedApiKey = key;
        return _cachedApiKey;
      }
    } catch (exc) {
      developer.log(
        'Secret Manager lookup failed for Maps API key ($secretRes): '
        '${exc.runtimeType}',
        name: 'adk_dart.google_maps',
        level: 900,
      );
    }
    return null;
  }

  /// Asynchronously resolves the Maps API key from memory, environment, or
  /// Google Cloud Secret Manager.
  Future<String?> getApiKeyAsync() async {
    if (_explicitApiKey != null) {
      return _explicitApiKey;
    }
    if (_cachedApiKey != null) {
      return _cachedApiKey;
    }

    final String? envKey = cleanGoogleMapsEnv(_env['MAPS_API_KEY']);
    if (envKey != null) {
      _cachedApiKey = envKey;
      return _cachedApiKey;
    }

    final String? secretRes =
        secretResourceName ??
        cleanGoogleMapsEnv(_env['MAPS_API_KEY_SECRET_RESOURCE']);
    if (secretRes == null) {
      return null;
    }

    if (!secretManagerAvailable) {
      throw UnsupportedError(googleMapsSecretManagerRequiredMessage);
    }

    final String? saEmail =
        serviceAccountEmail ?? cleanGoogleMapsEnv(_env['GOOGLE_SA_EMAIL']);
    final String? agentEngineId = cleanGoogleMapsEnv(
      _env['GOOGLE_CLOUD_AGENT_ENGINE_ID'],
    );
    final GoogleMapsSecretFetcher fetcher =
        _secretFetcher ??
        _customGoogleMapsSecretFetcher ??
        _defaultSecretManagerFetcher;

    try {
      final String? rawSecret = await fetcher(
        resourceName: secretRes,
        serviceAccountEmail: saEmail,
        agentEngineId: agentEngineId,
      );
      final String? key = cleanGoogleMapsEnv(rawSecret);
      if (key != null) {
        _cachedApiKey = key;
        return _cachedApiKey;
      }
    } catch (exc) {
      developer.log(
        'Secret Manager lookup failed for Maps API key ($secretRes): '
        '${exc.runtimeType}',
        name: 'adk_dart.google_maps',
        level: 900,
      );
    }

    return null;
  }

  /// Returns a non-reversible 16-character SHA-256 hex prefix for cache partitioning.
  String getKeyFingerprint() {
    final String? apiKey = getApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      return 'unconfigured';
    }
    return sha256.convert(utf8.encode(apiKey)).toString().substring(0, 16);
  }
}

Future<String?> _defaultSecretManagerFetcher({
  required String resourceName,
  String? serviceAccountEmail,
  String? agentEngineId,
}) async {
  String accessToken = await resolveDefaultGoogleAccessToken(
    scopes: const <String>['https://www.googleapis.com/auth/cloud-platform'],
  );

  if (serviceAccountEmail != null &&
      serviceAccountEmail.isNotEmpty &&
      (agentEngineId == null || agentEngineId.isEmpty)) {
    accessToken = await _impersonateServiceAccountToken(
      sourceAccessToken: accessToken,
      targetServiceAccountEmail: serviceAccountEmail,
    );
  }

  final SecretManagerClient client = SecretManagerClient(authToken: accessToken);
  return client.getSecret(resourceName);
}

Future<String> _impersonateServiceAccountToken({
  required String sourceAccessToken,
  required String targetServiceAccountEmail,
}) async {
  final Uri uri = Uri.parse(
    'https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/'
    '${Uri.encodeComponent(targetServiceAccountEmail)}:generateAccessToken',
  );
  final HttpClient client = HttpClient();
  try {
    final HttpClientRequest request = await client.postUrl(uri);
    request.headers.set(
      HttpHeaders.authorizationHeader,
      'Bearer $sourceAccessToken',
    );
    request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
    request.add(
      utf8.encode(
        jsonEncode(<String, Object?>{
          'scope': const <String>[
            'https://www.googleapis.com/auth/cloud-platform',
          ],
        }),
      ),
    );
    final HttpClientResponse response = await request.close();
    final String body = await utf8.decodeStream(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'IAM Service Account impersonation failed (${response.statusCode})',
        uri: uri,
      );
    }
    final Object? decoded = jsonDecode(body);
    if (decoded is Map && decoded['accessToken'] is String) {
      final String token = (decoded['accessToken'] as String).trim();
      if (token.isNotEmpty) {
        return token;
      }
    }
    throw StateError('IAM generateAccessToken returned an empty accessToken.');
  } finally {
    client.close(force: true);
  }
}

/// Default shared [GoogleMapsConfig] instance.
final GoogleMapsConfig defaultGoogleMapsConfig = GoogleMapsConfig();
