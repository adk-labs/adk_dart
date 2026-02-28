import 'dart:convert';
import 'dart:io';

import 'package:googleapis_auth/auth_io.dart' as auth;
import 'package:http/http.dart' as http;

import '../../_google_access_token.dart';

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
  SecretManagerClient({this.serviceAccountJson, this.authToken}) {
    if (serviceAccountJson != null && serviceAccountJson!.isNotEmpty) {
      try {
        jsonDecode(serviceAccountJson!);
      } on FormatException catch (error) {
        throw ArgumentError('Invalid service account JSON: $error');
      }
    }
  }

  final String? serviceAccountJson;
  final String? authToken;

  Future<String> getSecret(String resourceName) async {
    final String resolvedAuthToken = await _resolveAuthToken(
      serviceAccountJson: serviceAccountJson,
      authToken: authToken,
    );
    return _secretManagerSecretFetcher(
      resourceName: resourceName,
      serviceAccountJson: serviceAccountJson,
      authToken: resolvedAuthToken,
    );
  }
}

Future<String> _defaultSecretManagerSecretFetcher({
  required String resourceName,
  String? serviceAccountJson,
  String? authToken,
}) async {
  final String token = await _resolveAuthToken(
    serviceAccountJson: serviceAccountJson,
    authToken: authToken,
  );
  final String normalizedResourceName = resourceName.startsWith('/')
      ? resourceName.substring(1)
      : resourceName;
  final Uri uri = Uri.parse(
    'https://secretmanager.googleapis.com/v1/$normalizedResourceName:access',
  );

  final HttpClient client = HttpClient();
  try {
    final HttpClientRequest request = await client.getUrl(uri);
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');

    final HttpClientResponse response = await request.close();
    final String body = await utf8.decodeStream(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'Secret Manager access failed (${response.statusCode}): $body',
      );
    }

    final Object? decoded = body.isEmpty ? null : jsonDecode(body);
    if (decoded is! Map) {
      throw StateError('Secret Manager response is malformed.');
    }
    final Map<String, Object?> payload = _readMap(decoded['payload']);
    final String encoded = _readString(payload['data']) ?? '';
    if (encoded.isEmpty) {
      return '';
    }
    try {
      return utf8.decode(base64Decode(encoded));
    } on FormatException catch (error) {
      throw StateError('Secret Manager payload is not valid base64: $error');
    }
  } finally {
    client.close(force: true);
  }
}

Future<String> _resolveAuthToken({
  String? serviceAccountJson,
  String? authToken,
}) async {
  final String explicitToken = (authToken ?? '').trim();
  if (explicitToken.isNotEmpty) {
    return explicitToken;
  }

  final String? serviceAccountToken = await _resolveServiceAccountToken(
    serviceAccountJson,
  );
  if (serviceAccountToken != null && serviceAccountToken.isNotEmpty) {
    return serviceAccountToken;
  }

  try {
    return await resolveDefaultGoogleAccessToken(
      scopes: const <String>['https://www.googleapis.com/auth/cloud-platform'],
    );
  } catch (error) {
    throw ArgumentError(
      "'service_account_json' or 'auth_token' are both missing, and error "
      'occurred while trying to use default credentials: $error',
    );
  }
}

Future<String?> _resolveServiceAccountToken(String? serviceAccountJson) async {
  final String normalized = (serviceAccountJson ?? '').trim();
  if (normalized.isEmpty) {
    return null;
  }

  final Object? decoded;
  try {
    decoded = jsonDecode(normalized);
  } on FormatException catch (error) {
    throw ArgumentError('Invalid service account JSON: $error');
  }
  if (decoded is! Map) {
    throw ArgumentError('Invalid service account JSON: expected object.');
  }

  final Map<String, Object?> json = decoded.map(
    (Object? key, Object? value) => MapEntry('$key', value),
  );
  final String? embeddedToken = _readString(
    json['access_token'] ??
        json['token'] ??
        _readMap(json['oauth2'])['access_token'],
  );
  if (embeddedToken != null && embeddedToken.trim().isNotEmpty) {
    return embeddedToken.trim();
  }

  final Map<String, dynamic> serviceAccountJsonMap = json.map(
    (String key, Object? value) => MapEntry<String, dynamic>(key, value),
  );

  final auth.ServiceAccountCredentials serviceAccountCredentials;
  try {
    serviceAccountCredentials = auth.ServiceAccountCredentials.fromJson(
      serviceAccountJsonMap,
    );
  } catch (error) {
    throw ArgumentError(
      'Unable to build service account credentials from service_account_json: '
      '$error',
    );
  }

  final http.Client client = http.Client();
  try {
    final auth.AccessCredentials credentials =
        await auth.obtainAccessCredentialsViaServiceAccount(
          serviceAccountCredentials,
          const <String>['https://www.googleapis.com/auth/cloud-platform'],
          client,
        );
    final String token = credentials.accessToken.data.trim();
    if (token.isEmpty) {
      throw StateError('Service account token exchange returned empty token.');
    }
    return token;
  } catch (error) {
    throw ArgumentError(
      'Failed to resolve access token from service_account_json: $error',
    );
  } finally {
    client.close();
  }
}

Map<String, Object?> _readMap(Object? value) {
  if (value is Map<String, Object?>) {
    return Map<String, Object?>.from(value);
  }
  if (value is Map) {
    return value.map((Object? key, Object? item) => MapEntry('$key', item));
  }
  return <String, Object?>{};
}

String? _readString(Object? value) {
  if (value == null) {
    return null;
  }
  final String text = '$value';
  if (text.isEmpty) {
    return null;
  }
  return text;
}
