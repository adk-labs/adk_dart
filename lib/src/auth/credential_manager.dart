import '../agents/context.dart';
import 'auth_credential.dart';
import 'auth_tool.dart';
import 'credential_service/base_credential_service.dart';
import 'exchanger/base_credential_exchanger.dart';
import 'exchanger/credential_exchanger_registry.dart';
import 'exchanger/oauth2_credential_exchanger.dart';
import 'exchanger/service_account_credential_exchanger.dart';
import 'refresher/base_credential_refresher.dart';
import 'refresher/credential_refresher_registry.dart';
import 'refresher/oauth2_credential_refresher.dart';

class CredentialManager {
  CredentialManager({
    required AuthConfig authConfig,
    CredentialExchangerRegistry? exchangerRegistry,
    CredentialRefresherRegistry? refresherRegistry,
  }) : _authConfig = authConfig,
       _exchangerRegistry = exchangerRegistry ?? CredentialExchangerRegistry(),
       _refresherRegistry = refresherRegistry ?? CredentialRefresherRegistry() {
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
  final CredentialExchangerRegistry _exchangerRegistry;
  final CredentialRefresherRegistry _refresherRegistry;

  void registerCredentialExchanger(
    AuthCredentialType credentialType,
    BaseCredentialExchanger exchanger,
  ) {
    _exchangerRegistry.register(credentialType, exchanger);
  }

  void registerCredentialRefresher(
    AuthCredentialType credentialType,
    BaseCredentialRefresher refresher,
  ) {
    _refresherRegistry.register(credentialType, refresher);
  }

  Future<void> requestCredential(Context context) async {
    context.requestCredential(_authConfig);
  }

  Future<AuthCredential?> getAuthCredential(Context context) async {
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
    final bool wasExchanged = exchangeResult.wasExchanged;

    bool wasRefreshed = false;
    if (!wasExchanged) {
      final _RefreshOutcome refreshResult = await _refreshCredential(current);
      current = refreshResult.credential;
      wasRefreshed = refreshResult.wasRefreshed;
    }

    if (wasFromAuthResponse || wasExchanged || wasRefreshed) {
      await _saveCredential(context, current);
    }

    return current;
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
    AuthCredential credential,
  ) async {
    _authConfig.exchangedAuthCredential = credential.copyWith();

    final Object? serviceObj = context.invocationContext.credentialService;
    if (serviceObj is BaseCredentialService) {
      await serviceObj.saveCredential(_authConfig, context);
      return;
    }

    context.state[authResponseStateKey(_authConfig.credentialKey)] = credential
        .copyWith();
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

    final AuthCredential refreshed = await refresher.refresh(
      authCredential: credential,
      authScheme: _authConfig.authScheme,
    );
    return _RefreshOutcome(credential: refreshed, wasRefreshed: true);
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
