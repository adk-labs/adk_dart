/// OAuth2 credential utility helpers.
library;

import 'auth_credential.dart';
import 'auth_schemes.dart';

/// OAuth2 session input used for token endpoint requests.
class OAuth2SessionData {
  /// Creates OAuth2 session data.
  OAuth2SessionData({
    required this.clientId,
    required this.clientSecret,
    required this.scope,
    this.redirectUri,
    this.state,
    this.tokenEndpointAuthMethod,
  });

  /// OAuth2 client ID.
  final String clientId;

  /// OAuth2 client secret.
  final String clientSecret;

  /// Space-separated scope string.
  final String scope;

  /// Optional redirect URI.
  final String? redirectUri;

  /// Optional state parameter.
  final String? state;

  /// Optional token-endpoint auth method.
  final String? tokenEndpointAuthMethod;
}

/// Result of deriving OAuth2 session config from auth metadata.
class OAuth2SessionResult {
  /// Creates an OAuth2 session result.
  OAuth2SessionResult({this.session, this.tokenEndpoint});

  /// Derived session payload, if available.
  final OAuth2SessionData? session;

  /// Token endpoint URL, if available.
  final String? tokenEndpoint;
}

/// Creates OAuth2 session parameters from [authScheme] and [authCredential].
OAuth2SessionResult createOAuth2Session({
  required Object authScheme,
  required AuthCredential authCredential,
}) {
  String? tokenEndpoint;
  List<String> scopes = <String>[];

  if (authScheme is OpenIdConnectWithConfig) {
    tokenEndpoint = authScheme.tokenEndpoint;
    scopes = List<String>.from(authScheme.scopes);
  } else if (authScheme is ExtendedOAuth2) {
    final OAuthFlow? authorizationCode = authScheme.flows.authorizationCode;
    final OAuthFlow? clientCredentials = authScheme.flows.clientCredentials;
    if ((authorizationCode?.tokenUrl ?? '').isNotEmpty) {
      tokenEndpoint = authorizationCode!.tokenUrl;
      scopes = authorizationCode.scopes.keys.toList();
    } else if ((clientCredentials?.tokenUrl ?? '').isNotEmpty) {
      tokenEndpoint = clientCredentials!.tokenUrl;
      scopes = clientCredentials.scopes.keys.toList();
    } else {
      return OAuth2SessionResult();
    }
  } else {
    return OAuth2SessionResult();
  }

  final OAuth2Auth? oauth2 = authCredential.oauth2;
  if (oauth2 == null ||
      (oauth2.clientId ?? '').isEmpty ||
      (oauth2.clientSecret ?? '').isEmpty ||
      (tokenEndpoint ?? '').isEmpty) {
    return OAuth2SessionResult();
  }

  return OAuth2SessionResult(
    session: OAuth2SessionData(
      clientId: oauth2.clientId!,
      clientSecret: oauth2.clientSecret!,
      scope: scopes.join(' '),
      redirectUri: oauth2.redirectUri,
      state: oauth2.state,
      tokenEndpointAuthMethod: oauth2.tokenEndpointAuthMethod,
    ),
    tokenEndpoint: tokenEndpoint,
  );
}

/// Updates [authCredential] in place with exchanged token fields.
void updateCredentialWithTokens(
  AuthCredential authCredential,
  Map<String, Object?> tokens,
) {
  final OAuth2Auth? oauth2 = authCredential.oauth2;
  if (oauth2 == null || tokens.isEmpty) {
    return;
  }

  oauth2.accessToken = tokens['access_token']?.toString();
  oauth2.refreshToken = tokens['refresh_token']?.toString();
  oauth2.idToken = tokens['id_token']?.toString();
  oauth2.expiresAt = _asInt(tokens['expires_at']);
  oauth2.expiresIn = _asInt(tokens['expires_in']);
}

int? _asInt(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value);
  }
  return null;
}
