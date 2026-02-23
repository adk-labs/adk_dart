import '../sessions/state.dart';
import 'auth_credential.dart';
import 'auth_tool.dart';
import 'exchanger/base_credential_exchanger.dart';
import 'exchanger/oauth2_credential_exchanger.dart';

/// Internal auth orchestration helper mirroring Python ADK behavior.
class AuthHandler {
  AuthHandler({
    required this.authConfig,
    OAuth2CredentialExchanger? oauth2Exchanger,
  }) : _oauth2Exchanger = oauth2Exchanger ?? OAuth2CredentialExchanger();

  final AuthConfig authConfig;
  final OAuth2CredentialExchanger _oauth2Exchanger;

  Future<AuthCredential> exchangeAuthToken() async {
    final AuthCredential? credential = authConfig.exchangedAuthCredential;
    if (credential == null) {
      throw StateError('Missing exchanged auth credential for token exchange.');
    }
    final ExchangeResult result = await _oauth2Exchanger.exchange(
      authCredential: credential,
      authScheme: authConfig.authScheme,
    );
    return result.credential;
  }

  Future<void> parseAndStoreAuthResponse(State state) async {
    final AuthCredential? credential =
        authConfig.exchangedAuthCredential ?? authConfig.rawAuthCredential;
    if (credential == null) {
      return;
    }

    AuthCredential parsed = credential.copyWith();
    if (_requiresOAuthExchange(parsed)) {
      parsed = await exchangeAuthToken();
    }

    state[authTemporaryStateKey(authConfig.credentialKey)] = parsed.copyWith();
    state[authResponseStateKey(authConfig.credentialKey)] = parsed.copyWith();
  }

  AuthCredential? getAuthResponse(State state) {
    final Object? value =
        state[authTemporaryStateKey(authConfig.credentialKey)] ??
        state[authResponseStateKey(authConfig.credentialKey)];
    if (value is! AuthCredential) {
      return null;
    }
    return value.copyWith();
  }

  AuthConfig generateAuthRequest() {
    if (!_isOAuthScheme(authConfig.authScheme)) {
      return authConfig.copyWith();
    }

    final AuthCredential? exchanged = authConfig.exchangedAuthCredential;
    if (exchanged?.oauth2?.authUri?.isNotEmpty == true) {
      return authConfig.copyWith();
    }

    final AuthCredential? raw = authConfig.rawAuthCredential;
    if (raw == null) {
      return authConfig.copyWith();
    }
    final OAuth2Auth? oauth2 = raw.oauth2;
    if (oauth2 == null) {
      return authConfig.copyWith();
    }

    if (oauth2.authUri?.isNotEmpty == true) {
      return authConfig.copyWith(exchangedAuthCredential: raw.copyWith());
    }

    final bool hasClientCredentials =
        (oauth2.clientId?.isNotEmpty ?? false) &&
        (oauth2.clientSecret?.isNotEmpty ?? false);
    if (!hasClientCredentials) {
      return authConfig.copyWith();
    }

    // Dart runtime currently does not synthesize provider-specific auth URI.
    // Keep parity with Python fallback behavior by forwarding credential info.
    return authConfig.copyWith(exchangedAuthCredential: raw.copyWith());
  }

  bool _isOAuthScheme(String authScheme) {
    final String normalized = authScheme.toLowerCase();
    return normalized.contains('oauth2') || normalized.contains('openid');
  }

  bool _requiresOAuthExchange(AuthCredential credential) {
    if (credential.authType != AuthCredentialType.oauth2 &&
        credential.authType != AuthCredentialType.openIdConnect) {
      return false;
    }

    final OAuth2Auth? oauth2 = credential.oauth2;
    if (oauth2 == null) {
      return false;
    }

    if (oauth2.accessToken?.isNotEmpty == true) {
      return false;
    }

    return (oauth2.authCode?.isNotEmpty == true) ||
        (oauth2.authResponseUri?.isNotEmpty == true);
  }
}
