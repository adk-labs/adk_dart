import '../../../../auth/auth_credential.dart';
import '../../../../auth/auth_schemes.dart';
import 'base_credential_exchanger.dart';

class OAuth2CredentialExchanger extends BaseAuthCredentialExchanger {
  @override
  Future<AuthCredential?> exchangeCredential(
    Object authScheme, [
    AuthCredential? authCredential,
  ]) async {
    final AuthCredential? credential = authCredential;
    if (credential == null) {
      throw AuthCredentialMissingError(
        'auth_credential is empty. Please create AuthCredential using OAuth2Auth.',
      );
    }
    final AuthSchemeType? schemeType = _authSchemeType(authScheme);
    if (schemeType != AuthSchemeType.openIdConnect &&
        schemeType != AuthSchemeType.oauth2) {
      throw ArgumentError(
        'Invalid security scheme, expected openIdConnect/oauth2 but got $schemeType.',
      );
    }

    if (credential.http != null) {
      return credential;
    }
    final String? accessToken = credential.oauth2?.accessToken;
    if (accessToken == null || accessToken.isEmpty) {
      return null;
    }
    return AuthCredential(
      authType: AuthCredentialType.http,
      http: HttpAuth(
        scheme: 'bearer',
        credentials: HttpCredentials(token: accessToken),
      ),
    );
  }
}

AuthSchemeType? _authSchemeType(Object? scheme) {
  if (scheme is SecurityScheme) {
    return scheme.type;
  }
  if (scheme is Map) {
    final String type = '${scheme['type'] ?? ''}'.toLowerCase();
    switch (type) {
      case 'oauth2':
        return AuthSchemeType.oauth2;
      case 'openidconnect':
      case 'openid_connect':
      case 'open_id_connect':
        return AuthSchemeType.openIdConnect;
      case 'apikey':
      case 'api_key':
        return AuthSchemeType.apiKey;
      case 'http':
        return AuthSchemeType.http;
    }
  }
  return null;
}
