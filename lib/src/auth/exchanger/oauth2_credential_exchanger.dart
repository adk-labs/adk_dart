import '../auth_credential.dart';
import 'base_credential_exchanger.dart';

typedef OAuth2ExchangeHandler =
    Future<Map<String, Object?>> Function(
      OAuth2Auth oauth2,
      String? authScheme,
    );

class OAuth2CredentialExchanger extends BaseCredentialExchanger {
  OAuth2CredentialExchanger({this.exchangeHandler});

  final OAuth2ExchangeHandler? exchangeHandler;

  @override
  Future<ExchangeResult> exchange({
    required AuthCredential authCredential,
    String? authScheme,
  }) async {
    if (authCredential.authType != AuthCredentialType.oauth2 &&
        authCredential.authType != AuthCredentialType.openIdConnect) {
      return ExchangeResult(credential: authCredential, wasExchanged: false);
    }

    final OAuth2Auth? oauth2 = authCredential.oauth2;
    if (oauth2 == null) {
      return ExchangeResult(credential: authCredential, wasExchanged: false);
    }

    if (_isTokenAlreadyAvailable(oauth2)) {
      return ExchangeResult(credential: authCredential, wasExchanged: false);
    }

    final OAuth2ExchangeHandler? handler = exchangeHandler;
    if (handler == null) {
      return ExchangeResult(credential: authCredential, wasExchanged: false);
    }

    try {
      final Map<String, Object?> tokens = await handler(oauth2, authScheme);
      final AuthCredential updated = _applyTokens(authCredential, tokens);
      final bool exchanged = updated.oauth2?.accessToken?.isNotEmpty ?? false;
      return ExchangeResult(credential: updated, wasExchanged: exchanged);
    } catch (_) {
      return ExchangeResult(credential: authCredential, wasExchanged: false);
    }
  }

  bool _isTokenAlreadyAvailable(OAuth2Auth oauth2) {
    final String? accessToken = oauth2.accessToken;
    return accessToken != null && accessToken.isNotEmpty;
  }

  AuthCredential _applyTokens(
    AuthCredential original,
    Map<String, Object?> tokens,
  ) {
    final OAuth2Auth? oauth2 = original.oauth2;
    if (oauth2 == null) {
      return original;
    }

    final OAuth2Auth updated = OAuth2Auth(
      clientId: oauth2.clientId,
      clientSecret: oauth2.clientSecret,
      authUri: oauth2.authUri,
      state: oauth2.state,
      redirectUri: oauth2.redirectUri,
      authResponseUri: oauth2.authResponseUri,
      authCode: oauth2.authCode,
      accessToken: _readToken(tokens, 'access_token') ?? oauth2.accessToken,
      refreshToken: _readToken(tokens, 'refresh_token') ?? oauth2.refreshToken,
      idToken: _readToken(tokens, 'id_token') ?? oauth2.idToken,
      expiresAt:
          _readInt(tokens, 'expires_at') ??
          _deriveExpiresAt(_readInt(tokens, 'expires_in'), oauth2.expiresAt),
      expiresIn: _readInt(tokens, 'expires_in') ?? oauth2.expiresIn,
      audience: oauth2.audience,
      tokenEndpointAuthMethod: oauth2.tokenEndpointAuthMethod,
    );
    return original.copyWith(oauth2: updated);
  }

  String? _readToken(Map<String, Object?> tokens, String key) {
    final Object? raw = tokens[key];
    if (raw is String && raw.isNotEmpty) {
      return raw;
    }
    return null;
  }

  int? _readInt(Map<String, Object?> tokens, String key) {
    final Object? raw = tokens[key];
    if (raw is int) {
      return raw;
    }
    if (raw is num) {
      return raw.toInt();
    }
    if (raw is String) {
      return int.tryParse(raw);
    }
    return null;
  }

  int? _deriveExpiresAt(int? expiresIn, int? currentExpiresAt) {
    if (expiresIn == null) {
      return currentExpiresAt;
    }
    final int nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return nowSeconds + expiresIn;
  }
}
