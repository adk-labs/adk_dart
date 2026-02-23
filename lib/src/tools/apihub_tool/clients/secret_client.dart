import 'dart:convert';
import 'dart:io';

typedef SecretManagerSecretFetcher =
    Future<String> Function({
      required String resourceName,
      String? serviceAccountJson,
      String? authToken,
    });

SecretManagerSecretFetcher _secretManagerSecretFetcher =
    _defaultSecretManagerSecretFetcher;

void setSecretManagerSecretFetcher(SecretManagerSecretFetcher fetcher) {
  _secretManagerSecretFetcher = fetcher;
}

void resetSecretManagerSecretFetcher() {
  _secretManagerSecretFetcher = _defaultSecretManagerSecretFetcher;
}

class SecretManagerClient {
  SecretManagerClient({this.serviceAccountJson, this.authToken})
    : _resolvedAuthToken = _resolveAuthToken(serviceAccountJson, authToken) {
    if (serviceAccountJson != null && serviceAccountJson!.isNotEmpty) {
      try {
        jsonDecode(serviceAccountJson!);
      } on FormatException catch (error) {
        throw ArgumentError('Invalid service account JSON: $error');
      }
    }

    if (_resolvedAuthToken == null &&
        (serviceAccountJson == null || serviceAccountJson!.trim().isEmpty)) {
      throw ArgumentError(
        "'service_account_json' or 'auth_token' are both missing, and error "
        'occurred while trying to use default credentials: '
        'No default credentials provider is configured in adk_dart.',
      );
    }
  }

  final String? serviceAccountJson;
  final String? authToken;
  final String? _resolvedAuthToken;

  Future<String> getSecret(String resourceName) {
    return _secretManagerSecretFetcher(
      resourceName: resourceName,
      serviceAccountJson: serviceAccountJson,
      authToken: _resolvedAuthToken,
    );
  }
}

Future<String> _defaultSecretManagerSecretFetcher({
  required String resourceName,
  String? serviceAccountJson,
  String? authToken,
}) async {
  throw StateError(
    'No default Secret Manager client is available in adk_dart. '
    'Inject a fetcher with setSecretManagerSecretFetcher().',
  );
}

String? _resolveAuthToken(String? serviceAccountJson, String? authToken) {
  if (authToken != null && authToken.isNotEmpty) {
    return authToken;
  }
  if (serviceAccountJson != null && serviceAccountJson.trim().isNotEmpty) {
    final Object? decoded;
    try {
      decoded = jsonDecode(serviceAccountJson);
    } on FormatException {
      return null;
    }
    if (decoded is Map) {
      final Map<String, Object?> map = decoded.map(
        (Object? key, Object? value) => MapEntry('$key', value),
      );
      final Object? token = map['access_token'] ?? map['token'];
      if (token != null && '$token'.isNotEmpty) {
        return '$token';
      }
    }
  }

  final Map<String, String> environment = Platform.environment;
  return environment['GOOGLE_OAUTH_ACCESS_TOKEN'] ??
      environment['GOOGLE_ACCESS_TOKEN'] ??
      environment['ACCESS_TOKEN'];
}
