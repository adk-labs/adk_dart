/// Credential orchestration service for auth request/exchange/refresh flows.
library;

import '../agents/context.dart';
import '../features/_feature_registry.dart';
import '../integrations/_iam_connectors/gcp_auth_provider.dart';
import '../integrations/_iam_connectors/gcp_iam_connector_auth.dart';
import 'auth_credential.dart';
import 'auth_provider_registry.dart';
import 'auth_tool.dart';
import 'base_auth_provider.dart';
import 'credential_service/base_credential_service.dart';
import 'exchanger/base_credential_exchanger.dart';
import 'exchanger/credential_exchanger_registry.dart';
import 'exchanger/oauth2_credential_exchanger.dart';
import 'exchanger/service_account_credential_exchanger.dart';
import 'refresher/base_credential_refresher.dart';
import 'refresher/credential_refresher_registry.dart';
import 'refresher/oauth2_credential_refresher.dart';

/// Manages credential acquisition, exchange, refresh, and persistence.
class CredentialManager {
  static final AuthProviderRegistry _sharedAuthProviderRegistry =
      AuthProviderRegistry();

  /// Registers [provider] globally for each supported auth scheme.
  static void registerGlobalAuthProvider(BaseAuthProvider provider) {
    for (final Object schemeType in provider.supportedAuthSchemes) {
      _sharedAuthProviderRegistry.register(schemeType, provider);
    }
  }

  /// Clears globally registered auth providers used by tests.
  static void clearGlobalAuthProvidersForTest() {
    _sharedAuthProviderRegistry.clear();
  }

  /// Creates a credential manager for [authConfig].
  CredentialManager({
    required AuthConfig authConfig,
    AuthProviderRegistry? authProviderRegistry,
    CredentialExchangerRegistry? exchangerRegistry,
    CredentialRefresherRegistry? refresherRegistry,
  }) : _authConfig = authConfig,
       _authProviderRegistry = authProviderRegistry ?? AuthProviderRegistry(),
       _exchangerRegistry = exchangerRegistry ?? CredentialExchangerRegistry(),
       _refresherRegistry = refresherRegistry ?? CredentialRefresherRegistry() {
    if (authProviderRegistry == null &&
        isFeatureEnabled(FeatureName.gcpIamConnectorAuth)) {
      _authProviderRegistry.register(
        ManagedAuthSchemeType.gcpIamConnectorAuth.name,
        GcpAuthProvider(),
      );
    }

    if (exchangerRegistry == null) {
      final OAuth2CredentialExchanger oauth2Exchanger =
          OAuth2CredentialExchanger();
      _exchangerRegistry.register(AuthCredentialType.oauth2, oauth2Exchanger);
      _exchangerRegistry.register(
        AuthCredentialType.openIdConnect,
        oauth2Exchanger,
      );
      _exchangerRegistry.register(
        AuthCredentialType.serviceAccount,
        ServiceAccountCredentialExchanger(),
      );
    }

    if (refresherRegistry == null) {
      final OAuth2CredentialRefresher oauth2Refresher =
          OAuth2CredentialRefresher();
      _refresherRegistry.register(AuthCredentialType.oauth2, oauth2Refresher);
      _refresherRegistry.register(
        AuthCredentialType.openIdConnect,
        oauth2Refresher,
      );
    }
  }

  final AuthConfig _authConfig;
  final AuthProviderRegistry _authProviderRegistry;
  final CredentialExchangerRegistry _exchangerRegistry;
  final CredentialRefresherRegistry _refresherRegistry;

  /// Registers a provider for [authSchemeType].
  void registerAuthProvider(Object authSchemeType, BaseAuthProvider provider) {
    _authProviderRegistry.register(authSchemeType, provider);
  }

  /// Registers an exchanger for [credentialType].
  void registerCredentialExchanger(
    AuthCredentialType credentialType,
    BaseCredentialExchanger exchanger,
  ) {
    _exchangerRegistry.register(credentialType, exchanger);
  }

  /// Registers a refresher for [credentialType].
  void registerCredentialRefresher(
    AuthCredentialType credentialType,
    BaseCredentialRefresher refresher,
  ) {
    _refresherRegistry.register(credentialType, refresher);
  }

  /// Requests credentials from the active context.
  Future<void> requestCredential(Context context) async {
    context.requestCredential(_authConfig);
  }

  /// Resolves an auth credential for the active request context.
  Future<AuthCredential?> getAuthCredential(Context context) async {
    final BaseAuthProvider? provider =
        _authProviderRegistry.getProvider(_authConfig.authScheme) ??
        _sharedAuthProviderRegistry.getProvider(_authConfig.authScheme);
    if (provider != null) {
      final AuthCredential? providedCredential = await provider
          .getAuthCredential(_authConfig, context);
      if (providedCredential == null) {
        throw ArgumentError('AuthProvider did not return a credential.');
      }

      final OAuth2Auth? oauth2 = providedCredential.oauth2;
      final bool needsUserConsent =
          oauth2 != null &&
          (oauth2.accessToken == null || oauth2.accessToken!.isEmpty) &&
          (oauth2.authUri?.isNotEmpty ?? false);
      if (needsUserConsent) {
        _authConfig.exchangedAuthCredential = providedCredential.copyWith();
        return null;
      }
      return providedCredential.copyWith();
    }

    _validateCredentialConfig();

    if (_isCredentialReady()) {
      return _authConfig.rawAuthCredential?.copyWith();
    }

    AuthCredential? credential = await _loadExistingCredential(context);
    bool wasFromAuthResponse = false;

    if (credential == null) {
      credential = _loadFromAuthResponse(context);
      wasFromAuthResponse = credential != null;
    }

    if (credential == null) {
      if (_isClientCredentialsFlow()) {
        credential = _authConfig.rawAuthCredential?.copyWith();
      } else {
        return null;
      }
    }

    AuthCredential current = credential!;

    final ExchangeResult exchangeResult = await _exchangeCredential(current);
    current = exchangeResult.credential;
    bool wasExchanged = exchangeResult.wasExchanged;

    if (_hasUnredeemedAuthCode(current)) {
      return null;
    }

    bool wasRefreshed = false;
    if (!wasExchanged) {
      try {
        final _RefreshOutcome refreshResult = await _refreshCredential(current);
        current = refreshResult.credential;
        wasRefreshed = refreshResult.wasRefreshed;
      } on CredentialRevokedError {
        if (wasFromAuthResponse) {
          return null;
        }
        await _saveCredential(context, null);
        final AuthCredential? fresh = _loadFromAuthResponse(context);
        if (fresh == null || _isSameRevokedCredential(fresh, current)) {
          return null;
        }
        wasFromAuthResponse = true;
        current = fresh;
        final ExchangeResult reExchange = await _exchangeCredential(current);
        current = reExchange.credential;
        wasExchanged = reExchange.wasExchanged;
        if (_hasUnredeemedAuthCode(current)) {
          return null;
        }
        if (!wasExchanged) {
          try {
            final _RefreshOutcome retryRefresh = await _refreshCredential(
              current,
            );
            current = retryRefresh.credential;
            wasRefreshed = retryRefresh.wasRefreshed;
          } on CredentialRevokedError {
            return null;
          }
        }
      }
    }

    if (wasFromAuthResponse || wasExchanged || wasRefreshed) {
      await _saveCredential(context, current);
    }

    return current;
  }

  bool _isSameRevokedCredential(
    AuthCredential candidate,
    AuthCredential revoked,
  ) {
    if (_hasUnredeemedAuthCode(candidate)) {
      return false;
    }
    final OAuth2Auth? candidateOauth2 = candidate.oauth2;
    final OAuth2Auth? revokedOauth2 = revoked.oauth2;
    if (candidateOauth2 == null || revokedOauth2 == null) {
      return _sameCredentialValues(candidate, revoked);
    }
    if (candidateOauth2.refreshToken != null &&
        candidateOauth2.refreshToken!.isNotEmpty &&
        candidateOauth2.refreshToken == revokedOauth2.refreshToken) {
      return true;
    }
    return candidateOauth2.accessToken == revokedOauth2.accessToken &&
        candidateOauth2.refreshToken == revokedOauth2.refreshToken;
  }

  bool _sameCredentialValues(AuthCredential a, AuthCredential b) {
    if (a.authType != b.authType ||
        a.resourceRef != b.resourceRef ||
        a.apiKey != b.apiKey) {
      return false;
    }
    if (a.http?.scheme != b.http?.scheme ||
        a.http?.credentials.username != b.http?.credentials.username ||
        a.http?.credentials.password != b.http?.credentials.password ||
        a.http?.credentials.token != b.http?.credentials.token) {
      return false;
    }
    final OAuth2Auth? oa = a.oauth2;
    final OAuth2Auth? ob = b.oauth2;
    if ((oa == null) != (ob == null)) {
      return false;
    }
    if (oa != null && ob != null) {
      if (oa.clientId != ob.clientId ||
          oa.clientSecret != ob.clientSecret ||
          oa.authUri != ob.authUri ||
          oa.nonce != ob.nonce ||
          oa.state != ob.state ||
          oa.redirectUri != ob.redirectUri ||
          oa.authResponseUri != ob.authResponseUri ||
          oa.authCode != ob.authCode ||
          oa.accessToken != ob.accessToken ||
          oa.refreshToken != ob.refreshToken ||
          oa.idToken != ob.idToken ||
          oa.expiresAt != ob.expiresAt ||
          oa.expiresIn != ob.expiresIn ||
          oa.audience != ob.audience) {
        return false;
      }
    }
    return true;
  }

  bool _hasUnredeemedAuthCode(AuthCredential credential) {
    if (credential.authType != AuthCredentialType.oauth2 &&
        credential.authType != AuthCredentialType.openIdConnect) {
      return false;
    }
    final OAuth2Auth? oauth2 = credential.oauth2;
    if (oauth2 == null) {
      return false;
    }
    final bool hasAuthCode =
        (oauth2.authCode != null && oauth2.authCode!.isNotEmpty) ||
        (oauth2.authResponseUri != null && oauth2.authResponseUri!.isNotEmpty);
    final bool hasAccessToken =
        oauth2.accessToken != null && oauth2.accessToken!.isNotEmpty;
    return hasAuthCode && !hasAccessToken;
  }

  Future<AuthCredential?> _loadExistingCredential(Context context) async {
    final Object? serviceObj = context.invocationContext.credentialService;
    if (serviceObj is! BaseCredentialService) {
      return null;
    }
    return serviceObj.loadCredential(_authConfig, context);
  }

  AuthCredential? _loadFromAuthResponse(Context context) {
    final String key = authResponseStateKey(_authConfig.credentialKey);
    final Object? value =
        context.state[key] ?? context.state[_authConfig.credentialKey];
    if (value is! AuthCredential) {
      return null;
    }
    return value.copyWith();
  }

  Future<void> _saveCredential(
    Context context,
    AuthCredential? credential,
  ) async {
    _authConfig.exchangedAuthCredential = credential?.copyWith();

    final Object? serviceObj = context.invocationContext.credentialService;
    if (serviceObj is BaseCredentialService) {
      await serviceObj.saveCredential(_authConfig, context);
      return;
    }

    if (credential != null) {
      context.state[authResponseStateKey(_authConfig.credentialKey)] =
          credential.copyWith();
    }
  }

  Future<ExchangeResult> _exchangeCredential(AuthCredential credential) async {
    final BaseCredentialExchanger? exchanger = _exchangerRegistry.getExchanger(
      credential.authType,
    );
    if (exchanger == null) {
      return ExchangeResult(credential: credential, wasExchanged: false);
    }
    return exchanger.exchange(
      authCredential: credential,
      authScheme: _authConfig.authScheme,
    );
  }

  Future<_RefreshOutcome> _refreshCredential(AuthCredential credential) async {
    final BaseCredentialRefresher? refresher = _refresherRegistry.getRefresher(
      credential.authType,
    );
    if (refresher == null) {
      return _RefreshOutcome(credential: credential, wasRefreshed: false);
    }

    final bool needed = await refresher.isRefreshNeeded(
      authCredential: credential,
      authScheme: _authConfig.authScheme,
    );
    if (!needed) {
      return _RefreshOutcome(credential: credential, wasRefreshed: false);
    }

    final AuthCredential? raw = _authConfig.rawAuthCredential;
    if (raw != null &&
        _isClientCredentialsFlow() &&
        credential.oauth2 != null &&
        (credential.oauth2!.refreshToken == null ||
            credential.oauth2!.refreshToken!.isEmpty)) {
      final ExchangeResult exchangeResult = await _exchangeCredential(
        raw.copyWith(),
      );
      return _RefreshOutcome(
        credential: exchangeResult.wasExchanged
            ? exchangeResult.credential
            : credential,
        wasRefreshed: exchangeResult.wasExchanged,
      );
    }

    try {
      final AuthCredential refreshed = await refresher.refresh(
        authCredential: credential,
        authScheme: _authConfig.authScheme,
      );
      return _RefreshOutcome(
        credential: refreshed,
        wasRefreshed: !_sameCredentialValues(refreshed, credential),
      );
    } on CredentialRevokedError {
      if (raw == null || !_isClientCredentialsFlow()) {
        rethrow;
      }
      final ExchangeResult exchangeResult = await _exchangeCredential(
        raw.copyWith(),
      );
      if (!exchangeResult.wasExchanged) {
        rethrow;
      }
      return _RefreshOutcome(
        credential: exchangeResult.credential,
        wasRefreshed: true,
      );
    }
  }

  bool _isCredentialReady() {
    final AuthCredential? raw = _authConfig.rawAuthCredential;
    if (raw == null) {
      return false;
    }
    return raw.authType == AuthCredentialType.apiKey ||
        raw.authType == AuthCredentialType.http;
  }

  bool _isClientCredentialsFlow() {
    final AuthCredential? raw = _authConfig.rawAuthCredential;
    if (raw == null) {
      return false;
    }

    if (raw.authType != AuthCredentialType.oauth2 &&
        raw.authType != AuthCredentialType.openIdConnect) {
      return false;
    }

    final String scheme = _authConfig.authScheme.toLowerCase();
    if (scheme.contains('authorization_code')) {
      return false;
    }

    final OAuth2Auth? oauth2 = raw.oauth2;
    if (oauth2 == null) {
      return false;
    }

    final bool hasClientCredentials =
        (oauth2.clientId?.isNotEmpty ?? false) &&
        (oauth2.clientSecret?.isNotEmpty ?? false);
    final bool hasAuthorizationResponse =
        (oauth2.authCode?.isNotEmpty ?? false) ||
        (oauth2.authResponseUri?.isNotEmpty ?? false);
    return hasClientCredentials && !hasAuthorizationResponse;
  }

  void _validateCredentialConfig() {
    final String scheme = _authConfig.authScheme.toLowerCase();
    final bool schemeNeedsRawCredential =
        scheme.contains('oauth2') || scheme.contains('openid');
    if (schemeNeedsRawCredential && _authConfig.rawAuthCredential == null) {
      throw ArgumentError(
        'rawAuthCredential is required for auth scheme `${_authConfig.authScheme}`.',
      );
    }

    final AuthCredential? raw = _authConfig.rawAuthCredential;
    if (raw == null) {
      return;
    }
    if (raw.authType == AuthCredentialType.oauth2 ||
        raw.authType == AuthCredentialType.openIdConnect) {
      if (raw.oauth2 == null) {
        throw ArgumentError(
          'authConfig.rawAuthCredential.oauth2 is required for credential '
          'type `${raw.authType}`.',
        );
      }
    }
  }
}

class _RefreshOutcome {
  _RefreshOutcome({required this.credential, required this.wasRefreshed});

  final AuthCredential credential;
  final bool wasRefreshed;
}
