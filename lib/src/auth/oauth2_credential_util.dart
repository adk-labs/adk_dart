import 'auth_credential.dart';
import 'auth_schemes.dart';

class OAuth2SessionData {
  OAuth2SessionData({
    required this.clientId,
    required this.clientSecret,
    required this.scope,
    this.redirectUri,
    this.state,
    this.tokenEndpointAuthMethod,
  });

  final String clientId;
  final String clientSecret;
  final String scope;
  final String? redirectUri;
  final String? state;
  final String? tokenEndpointAuthMethod;
}

class OAuth2SessionResult {
  OAuth2SessionResult({this.session, this.tokenEndpoint});

  final OAuth2SessionData? session;
  final String? tokenEndpoint;
}

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
