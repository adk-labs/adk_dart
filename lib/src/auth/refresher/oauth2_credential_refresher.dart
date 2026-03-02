/// OAuth2-based credential refresh helpers.
library;

import '../auth_credential.dart';
import 'base_credential_refresher.dart';

/// Callback signature for refreshing OAuth2 tokens.
typedef OAuth2RefreshHandler =
    Future<Map<String, Object?>> Function(
      OAuth2Auth oauth2,
      String? authScheme,
    );

/// Refreshes OAuth2 credentials when tokens are expired.
class OAuth2CredentialRefresher extends BaseCredentialRefresher {
  /// Creates an OAuth2 credential refresher.
  OAuth2CredentialRefresher({this.refreshHandler});

  /// Refresh handler implementation.
  final OAuth2RefreshHandler? refreshHandler;

  @override
  /// Returns whether [authCredential] should be refreshed.
  Future<bool> isRefreshNeeded({
    required AuthCredential authCredential,
    String? authScheme,
  }) async {
    if (authCredential.authType != AuthCredentialType.oauth2 &&
        authCredential.authType != AuthCredentialType.openIdConnect) {
      return false;
    }

    final OAuth2Auth? oauth2 = authCredential.oauth2;
    if (oauth2 == null) {
      return false;
    }
    if (oauth2.refreshToken == null || oauth2.refreshToken!.isEmpty) {
      return false;
    }

    final int nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final int? expiresAt = oauth2.expiresAt;
    if (expiresAt != null) {
      return nowSeconds >= expiresAt;
    }

    final int? expiresIn = oauth2.expiresIn;
    if (expiresIn != null) {
      return expiresIn <= 0;
    }
    return false;
  }

  @override
  /// Refreshes [authCredential] when a refresh is needed and possible.
  Future<AuthCredential> refresh({
    required AuthCredential authCredential,
    String? authScheme,
  }) async {
    final bool needed = await isRefreshNeeded(
      authCredential: authCredential,
      authScheme: authScheme,
    );
    if (!needed) {
      return authCredential;
    }

    final OAuth2RefreshHandler? handler = refreshHandler;
    if (handler == null) {
      return authCredential;
    }

    final OAuth2Auth? oauth2 = authCredential.oauth2;
    if (oauth2 == null) {
      return authCredential;
    }

    try {
      final Map<String, Object?> tokens = await handler(oauth2, authScheme);
      return _applyTokens(authCredential, tokens);
    } catch (_) {
      return authCredential;
    }
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
