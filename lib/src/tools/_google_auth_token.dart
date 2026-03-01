import 'dart:convert';

import 'package:googleapis_auth/auth_io.dart' as auth;
import 'package:http/http.dart' as http;

import '../auth/auth_credential.dart';
import '_google_access_token.dart';
import '_google_credentials.dart';

const List<String> cloudPlatformScope = <String>[
  'https://www.googleapis.com/auth/cloud-platform',
];

String? tryExtractGoogleAccessToken(Object? credentials) {
  if (credentials == null) {
    return null;
  }

  if (credentials is GoogleOAuthCredential) {
    final String token = credentials.accessToken.trim();
    if (token.isNotEmpty) {
      return token;
    }
  }

  if (credentials is AuthCredential) {
    final String token = (credentials.oauth2?.accessToken ?? '').trim();
    if (token.isNotEmpty) {
      return token;
    }
  }

  if (credentials is Map) {
    final String snake = '${credentials['access_token'] ?? ''}'.trim();
    if (snake.isNotEmpty) {
      return snake;
    }
    final String camel = '${credentials['accessToken'] ?? ''}'.trim();
    if (camel.isNotEmpty) {
      return camel;
    }
    final String token = '${credentials['token'] ?? ''}'.trim();
    if (token.isNotEmpty) {
      return token;
    }
  }

  if (credentials is String) {
    final String trimmed = credentials.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    try {
      final Object? decoded = jsonDecode(trimmed);
      if (decoded is Map) {
        return tryExtractGoogleAccessToken(
          decoded.map((Object? key, Object? value) => MapEntry('$key', value)),
        );
      }
    } on FormatException {
      return trimmed;
    }
    return null;
  }

  try {
    final dynamic dynamicCredential = credentials;
    final Object? token = dynamicCredential.accessToken;
    if (token is String && token.trim().isNotEmpty) {
      return token.trim();
    }
  } catch (_) {
    // Ignore dynamic field access failures.
  }

  return null;
}

Future<String> resolveGoogleAccessToken({
  required Object? credentials,
  List<String> scopes = const <String>[],
}) async {
  final String? direct = tryExtractGoogleAccessToken(credentials);
  if (direct != null && direct.isNotEmpty) {
    return direct;
  }

  final String? serviceAccountToken = await _tryResolveServiceAccountToken(
    credentials: credentials,
    scopes: scopes,
  );
  if (serviceAccountToken != null && serviceAccountToken.isNotEmpty) {
    return serviceAccountToken;
  }

  return resolveDefaultGoogleAccessToken(scopes: scopes);
}

Future<String?> _tryResolveServiceAccountToken({
  required Object? credentials,
  required List<String> scopes,
}) async {
  final Map<String, Object?>? json = _extractServiceAccountJson(credentials);
  if (json == null || json.isEmpty) {
    return null;
  }
  final List<String> normalizedScopes = scopes.isEmpty
      ? cloudPlatformScope
      : List<String>.from(scopes);

  final Map<String, dynamic> serviceAccountJson = json.map(
    (String key, Object? value) => MapEntry<String, dynamic>(key, value),
  );

  final auth.ServiceAccountCredentials serviceAccountCredentials;
  try {
    serviceAccountCredentials = auth.ServiceAccountCredentials.fromJson(
      serviceAccountJson,
    );
  } catch (_) {
    return null;
  }

  final http.Client client = http.Client();
  try {
    final auth.AccessCredentials accessCredentials = await auth
        .obtainAccessCredentialsViaServiceAccount(
          serviceAccountCredentials,
          normalizedScopes,
          client,
        );
    final String token = accessCredentials.accessToken.data.trim();
    if (token.isEmpty) {
      return null;
    }
    return token;
  } catch (_) {
    return null;
  } finally {
    client.close();
  }
}

Map<String, Object?>? _extractServiceAccountJson(Object? credentials) {
  if (credentials == null) {
    return null;
  }

  if (credentials is AuthCredential) {
    final ServiceAccountAuth? serviceAccount = credentials.serviceAccount;
    final ServiceAccountCredential? info =
        serviceAccount?.serviceAccountCredential;
    if (info == null) {
      return null;
    }
    return <String, Object?>{
      'type': 'service_account',
      'project_id': info.projectId,
      'private_key_id': info.privateKeyId,
      'private_key': info.privateKey,
      'client_email': info.clientEmail,
      'client_id': info.clientId,
      'auth_uri': info.authUri,
      'token_uri': info.tokenUri,
    };
  }

  if (credentials is String) {
    final String trimmed = credentials.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    try {
      final Object? decoded = jsonDecode(trimmed);
      if (decoded is Map) {
        return decoded.map(
          (Object? key, Object? value) => MapEntry('$key', value),
        );
      }
    } on FormatException {
      return null;
    }
  }

  if (credentials is Map) {
    if ('${credentials['type'] ?? ''}'.trim() == 'service_account') {
      return credentials.map(
        (Object? key, Object? value) => MapEntry('$key', value),
      );
    }
  }

  return null;
}
