import 'dart:convert';

import '../auth/auth_credential.dart';
import '../auth/auth_tool.dart';
import '../auth/credential_manager.dart';
import 'tool_context.dart';

class GoogleOAuthCredential {
  GoogleOAuthCredential({
    required this.accessToken,
    this.refreshToken,
    this.clientId,
    this.clientSecret,
    List<String>? scopes,
    this.expiresAt,
    this.expiresIn,
  }) : scopes = scopes ?? <String>[];

  final String accessToken;
  final String? refreshToken;
  final String? clientId;
  final String? clientSecret;
  final List<String> scopes;
  final int? expiresAt;
  final int? expiresIn;

  factory GoogleOAuthCredential.fromJson(Map<String, Object?> json) {
    return GoogleOAuthCredential(
      accessToken: (json['access_token'] ?? '') as String,
      refreshToken: json['refresh_token'] as String?,
      clientId: json['client_id'] as String?,
      clientSecret: json['client_secret'] as String?,
      scopes:
          (json['scopes'] as List?)
              ?.map((Object? value) => '$value')
              .toList() ??
          <String>[],
      expiresAt: json['expires_at'] as int?,
      expiresIn: json['expires_in'] as int?,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'access_token': accessToken,
      if (refreshToken != null) 'refresh_token': refreshToken,
      if (clientId != null) 'client_id': clientId,
      if (clientSecret != null) 'client_secret': clientSecret,
      if (scopes.isNotEmpty) 'scopes': scopes,
      if (expiresAt != null) 'expires_at': expiresAt,
      if (expiresIn != null) 'expires_in': expiresIn,
    };
  }
}

class BaseGoogleCredentialsConfig {
  BaseGoogleCredentialsConfig({
    this.credentials,
    this.externalAccessTokenKey,
    this.clientId,
    this.clientSecret,
    List<String>? scopes,
    this.tokenCacheKey,
  }) : scopes = scopes == null ? null : List<String>.from(scopes) {
    _validate();
  }

  final Object? credentials;
  final String? externalAccessTokenKey;
  String? clientId;
  String? clientSecret;
  List<String>? scopes;
  final String? tokenCacheKey;

  void _validate() {
    if (credentials != null) {
      if (externalAccessTokenKey != null ||
          clientId != null ||
          clientSecret != null ||
          scopes != null) {
        throw ArgumentError(
          'If credentials are provided, externalAccessTokenKey/clientId/clientSecret/scopes must not be provided.',
        );
      }

      final GoogleOAuthCredential? oauthCredential = _toOAuthCredential(
        credentials,
      );
      if (oauthCredential != null) {
        clientId = oauthCredential.clientId;
        clientSecret = oauthCredential.clientSecret;
        scopes = oauthCredential.scopes;
      }
      return;
    }

    if (externalAccessTokenKey != null) {
      if (clientId != null || clientSecret != null || scopes != null) {
        throw ArgumentError(
          'If externalAccessTokenKey is provided, clientId/clientSecret/scopes must not be provided.',
        );
      }
      return;
    }

    if ((clientId?.isNotEmpty ?? false) &&
        (clientSecret?.isNotEmpty ?? false)) {
      return;
    }
    throw ArgumentError(
      'Must provide one of credentials, externalAccessTokenKey, or clientId/clientSecret.',
    );
  }
}

class GoogleCredentialsManager {
  GoogleCredentialsManager(this.credentialsConfig);

  final BaseGoogleCredentialsConfig credentialsConfig;

  Future<Object?> getValidCredentials(ToolContext toolContext) async {
    if (credentialsConfig.externalAccessTokenKey != null) {
      final Object? token =
          toolContext.state[credentialsConfig.externalAccessTokenKey!];
      if (token == null || '$token'.isEmpty) {
        throw ArgumentError(
          'externalAccessTokenKey is provided but no access token exists in toolContext.state.',
        );
      }
      return GoogleOAuthCredential(accessToken: '$token');
    }

    if (credentialsConfig.tokenCacheKey != null) {
      final Object? cached =
          toolContext.state[credentialsConfig.tokenCacheKey!];
      final GoogleOAuthCredential? parsedCached = _toOAuthCredential(cached);
      if (parsedCached != null) {
        return parsedCached;
      }
    }

    final GoogleOAuthCredential? configured = _toOAuthCredential(
      credentialsConfig.credentials,
    );
    if (configured != null) {
      return configured;
    }

    if (credentialsConfig.credentials != null) {
      return credentialsConfig.credentials;
    }

    final AuthConfig authConfig = AuthConfig(
      authScheme: 'oauth2_authorization_code',
      rawAuthCredential: AuthCredential(
        authType: AuthCredentialType.oauth2,
        oauth2: OAuth2Auth(
          clientId: credentialsConfig.clientId,
          clientSecret: credentialsConfig.clientSecret,
        ),
      ),
      credentialKey: credentialsConfig.tokenCacheKey,
    );
    final CredentialManager manager = CredentialManager(authConfig: authConfig);
    AuthCredential? credential = await manager.getAuthCredential(toolContext);
    if (credential == null) {
      await manager.requestCredential(toolContext);
      return null;
    }

    final GoogleOAuthCredential? oauth = _toOAuthCredential(credential);
    if (oauth != null && credentialsConfig.tokenCacheKey != null) {
      toolContext.state[credentialsConfig.tokenCacheKey!] = jsonEncode(
        oauth.toJson(),
      );
    }
    if (oauth == null) {
      await manager.requestCredential(toolContext);
    }
    return oauth;
  }
}

GoogleOAuthCredential? _toOAuthCredential(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is GoogleOAuthCredential) {
    return value;
  }
  if (value is String) {
    if (value.isEmpty) {
      return null;
    }
    try {
      final Object? decoded = jsonDecode(value);
      if (decoded is Map) {
        return GoogleOAuthCredential.fromJson(
          decoded.map((Object? key, Object? value) => MapEntry('$key', value)),
        );
      }
    } catch (_) {
      return GoogleOAuthCredential(accessToken: value);
    }
    return null;
  }
  if (value is Map) {
    return GoogleOAuthCredential.fromJson(
      value.map((Object? key, Object? item) => MapEntry('$key', item)),
    );
  }
  if (value is AuthCredential) {
    final OAuth2Auth? oauth2 = value.oauth2;
    final String? accessToken = oauth2?.accessToken;
    if (accessToken == null || accessToken.isEmpty) {
      return null;
    }
    return GoogleOAuthCredential(
      accessToken: accessToken,
      refreshToken: oauth2?.refreshToken,
      clientId: oauth2?.clientId,
      clientSecret: oauth2?.clientSecret,
      expiresAt: oauth2?.expiresAt,
      expiresIn: oauth2?.expiresIn,
    );
  }
  return null;
}
