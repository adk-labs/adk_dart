/// Auth flow coordinator for exchanging and storing credentials in state.
library;

import 'dart:convert';
import 'dart:math';

import '../sessions/state.dart';
import 'auth_credential.dart';
import 'auth_tool.dart';
import 'exchanger/base_credential_exchanger.dart';
import 'exchanger/oauth2_credential_exchanger.dart';

/// Builds an [AuthCredential] from a raw token or key string [val] according
/// to [authScheme].
///
/// Throws an [ArgumentError] if [val] is empty or if [authScheme] specifies
/// HTTP `basic` authentication.
AuthCredential credentialFromString(String val, [Object? authScheme]) {
  if (val.isEmpty) {
    throw ArgumentError('Credential string cannot be empty.');
  }

  if (authScheme == null || (authScheme is String && authScheme.isEmpty)) {
    return AuthCredential(
      authType: AuthCredentialType.oauth2,
      oauth2: OAuth2Auth(accessToken: val),
    );
  }

  String? schemeType;
  String httpScheme = 'bearer';

  Object? resolvedScheme = authScheme;
  if (resolvedScheme is String) {
    final String trimmed = resolvedScheme.trim();
    if (trimmed.startsWith('{')) {
      try {
        resolvedScheme = jsonDecode(trimmed);
      } catch (_) {
        schemeType = trimmed.toLowerCase();
      }
    } else {
      final String lower = trimmed.toLowerCase();
      if (lower == 'apikey' || lower == 'api_key') {
        schemeType = 'apikey';
      } else if (lower == 'basic') {
        schemeType = 'http';
        httpScheme = 'basic';
      } else if (lower == 'http' || lower == 'bearer') {
        schemeType = 'http';
        httpScheme = 'bearer';
      } else {
        schemeType = lower;
      }
    }
  }

  if (resolvedScheme is Map) {
    final Object? rawType =
        resolvedScheme['type'] ??
        resolvedScheme['type_'] ??
        resolvedScheme['auth_type'];
    if (rawType != null) {
      schemeType = '$rawType'.trim().toLowerCase();
    }
    final Object? rawHttpScheme = resolvedScheme['scheme'];
    if (rawHttpScheme is String && rawHttpScheme.trim().isNotEmpty) {
      httpScheme = rawHttpScheme.trim();
    }
  } else if (resolvedScheme is! String) {
    final dynamic dyn = resolvedScheme;
    try {
      final Object? rawType = dyn.type_;
      if (rawType != null) {
        schemeType = '$rawType'.split('.').last.toLowerCase();
      }
    } catch (_) {
      try {
        final Object? rawType = dyn.type;
        if (rawType != null) {
          schemeType = '$rawType'.split('.').last.toLowerCase();
        }
      } catch (_) {}
    }
    try {
      final Object? rawHttpScheme = dyn.scheme;
      if (rawHttpScheme is String && rawHttpScheme.isNotEmpty) {
        httpScheme = rawHttpScheme;
      }
    } catch (_) {}
  }

  if (schemeType == 'apikey' || schemeType == 'api_key') {
    return AuthCredential(authType: AuthCredentialType.apiKey, apiKey: val);
  }
  if (schemeType == 'http') {
    if (httpScheme.toLowerCase() == 'basic') {
      throw ArgumentError(
        'HTTP basic authentication requires username and password '
        'credentials, not a raw token string.',
      );
    }
    return AuthCredential(
      authType: AuthCredentialType.http,
      http: HttpAuth(
        scheme: httpScheme,
        credentials: HttpCredentials(token: val),
      ),
    );
  }
  return AuthCredential(
    authType: AuthCredentialType.oauth2,
    oauth2: OAuth2Auth(accessToken: val),
  );
}

/// Internal auth orchestration helper mirroring Python ADK behavior.
///
/// ```dart
/// final handler = AuthHandler(authConfig: authConfig);
/// final requestConfig = handler.generateAuthRequest();
/// await handler.parseAndStoreAuthResponse(sessionState);
/// ```
class AuthHandler {
  /// Creates an auth flow coordinator for [authConfig].
  AuthHandler({
    required this.authConfig,
    OAuth2CredentialExchanger? oauth2Exchanger,
  }) : _oauth2Exchanger = oauth2Exchanger ?? OAuth2CredentialExchanger();

  /// Auth configuration currently being orchestrated.
  final AuthConfig authConfig;
  final OAuth2CredentialExchanger _oauth2Exchanger;

  /// Exchanges the currently stored auth credential for access tokens.
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

  /// Parses auth response data and stores normalized credential state.
  Future<void> parseAndStoreAuthResponse(State state) async {
    final AuthCredential? credential =
        authConfig.exchangedAuthCredential ?? authConfig.rawAuthCredential;
    if (credential == null) {
      return;
    }

    final OAuth2Auth? rawOauth2 = authConfig.rawAuthCredential?.oauth2;
    final OAuth2Auth? exchangedOauth2 =
        authConfig.exchangedAuthCredential?.oauth2;
    if (rawOauth2 != null && exchangedOauth2 != null) {
      if ((exchangedOauth2.clientId == null ||
              exchangedOauth2.clientId!.isEmpty) &&
          rawOauth2.clientId != null &&
          rawOauth2.clientId!.isNotEmpty) {
        exchangedOauth2.clientId = rawOauth2.clientId;
      }
      if ((exchangedOauth2.clientSecret == null ||
              exchangedOauth2.clientSecret!.isEmpty) &&
          rawOauth2.clientSecret != null &&
          rawOauth2.clientSecret!.isNotEmpty) {
        exchangedOauth2.clientSecret = rawOauth2.clientSecret;
      }
    }

    if (exchangedOauth2 != null &&
        (exchangedOauth2.authCode == null ||
            exchangedOauth2.authCode!.isEmpty) &&
        exchangedOauth2.authResponseUri != null &&
        exchangedOauth2.authResponseUri!.isNotEmpty) {
      final String? code = Uri.tryParse(
        exchangedOauth2.authResponseUri!,
      )?.queryParameters['code'];
      if (code != null && code.isNotEmpty) {
        exchangedOauth2.authCode = code;
      }
    }

    final String tempKey = authTemporaryStateKey(authConfig.credentialKey);
    final String authKey = authResponseStateKey(authConfig.credentialKey);
    AuthCredential parsed = credential.copyWith();
    state[tempKey] = parsed.copyWith();
    state[authKey] = parsed.copyWith();

    if (_requiresOAuthExchange(parsed)) {
      parsed = await exchangeAuthToken();
      state[tempKey] = parsed.copyWith();
      state[authKey] = parsed.copyWith();
    }
  }

  /// Returns the stored auth response credential, if present.
  AuthCredential? getAuthResponse(State state) {
    final List<String> keys = <String>[
      authTemporaryStateKey(authConfig.credentialKey),
      authResponseStateKey(authConfig.credentialKey),
      authConfig.credentialKey,
    ];
    for (final String key in keys) {
      final Object? value = state[key];
      if (value == null) {
        continue;
      }
      if (value is AuthCredential) {
        return value.copyWith();
      }
      try {
        if (value is String && value.isNotEmpty) {
          return credentialFromString(value, authConfig.authScheme);
        }
      } on Object catch (error) {
        if (error is ArgumentError ||
            error is FormatException ||
            error is TypeError) {
          continue;
        }
        rethrow;
      }
    }
    return null;
  }

  /// Produces an auth request config for interactive auth flows.
  AuthConfig generateAuthRequest() {
    if (!_isOAuthScheme(authConfig.authScheme)) {
      return _redactConfiguredSecrets(authConfig.copyWith());
    }

    final AuthCredential? exchanged = authConfig.exchangedAuthCredential;
    if (exchanged?.oauth2?.authUri?.isNotEmpty == true) {
      return _redactConfiguredSecrets(authConfig.copyWith());
    }

    final AuthCredential? raw = authConfig.rawAuthCredential;
    if (raw == null) {
      throw ArgumentError(
        'Auth scheme `${authConfig.authScheme}` requires auth_credential.',
      );
    }
    final OAuth2Auth? oauth2 = raw.oauth2;
    if (oauth2 == null) {
      throw ArgumentError(
        'Auth scheme `${authConfig.authScheme}` requires oauth2 in auth_credential.',
      );
    }
    final String? codeChallengeMethod = oauth2.codeChallengeMethod;
    if (codeChallengeMethod != null &&
        codeChallengeMethod.isNotEmpty &&
        codeChallengeMethod != 'S256') {
      throw ArgumentError(
        'Unsupported code_challenge_method: $codeChallengeMethod. '
        "Only 'S256' is supported.",
      );
    }

    if (oauth2.authUri?.isNotEmpty == true) {
      return _redactConfiguredSecrets(
        authConfig.copyWith(exchangedAuthCredential: raw.copyWith()),
      );
    }

    final bool hasClientCredentials =
        (oauth2.clientId?.isNotEmpty ?? false) &&
        (oauth2.clientSecret?.isNotEmpty ?? false);
    if (!hasClientCredentials) {
      throw ArgumentError(
        'Auth scheme `${authConfig.authScheme}` requires both client_id and '
        'client_secret in auth_credential.oauth2.',
      );
    }

    final OAuth2Auth synthesizedOauth2 = _synthesizeOAuth2Auth(
      oauth2,
      authConfig.authScheme,
    );
    return _redactConfiguredSecrets(
      authConfig.copyWith(
        exchangedAuthCredential: raw.copyWith(oauth2: synthesizedOauth2),
      ),
    );
  }

  OAuth2Auth _synthesizeOAuth2Auth(OAuth2Auth oauth2, String authScheme) {
    final _ExtractedSchemeAuthEndpoint? endpoint =
        _extractSchemeAuthorizationEndpoint(authScheme);
    if (endpoint == null || endpoint.authorizationUrl.isEmpty) {
      return oauth2.copyWith();
    }

    final Uri? parsedBase = Uri.tryParse(endpoint.authorizationUrl);
    if (parsedBase == null) {
      return oauth2.copyWith();
    }

    final String state = (oauth2.state != null && oauth2.state!.isNotEmpty)
        ? oauth2.state!
        : _generateRandomState();
    final Map<String, String> queryParams = <String, String>{
      ...parsedBase.queryParameters,
      'response_type': endpoint.isImplicit ? 'token' : 'code',
      if (oauth2.clientId != null && oauth2.clientId!.isNotEmpty)
        'client_id': oauth2.clientId!,
      if (oauth2.redirectUri != null && oauth2.redirectUri!.isNotEmpty)
        'redirect_uri': oauth2.redirectUri!,
      'state': state,
      if (endpoint.scopes.isNotEmpty) 'scope': endpoint.scopes.join(' '),
      if (oauth2.audience != null && oauth2.audience!.isNotEmpty)
        'audience': oauth2.audience!,
      if (oauth2.prompt != null && oauth2.prompt!.isNotEmpty)
        'prompt': oauth2.prompt!,
      if (oauth2.nonce != null && oauth2.nonce!.isNotEmpty)
        'nonce': oauth2.nonce!,
    };
    final Uri authUri = parsedBase.replace(queryParameters: queryParams);
    return oauth2.copyWith(authUri: authUri.toString(), state: state);
  }

  _ExtractedSchemeAuthEndpoint? _extractSchemeAuthorizationEndpoint(
    String authScheme,
  ) {
    final String trimmed = authScheme.trim();
    if (!trimmed.startsWith('{')) {
      return null;
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(trimmed);
    } catch (_) {
      return null;
    }
    if (decoded is! Map) {
      return null;
    }

    final String? directEndpoint = _nonEmptyString(
      decoded['authorization_endpoint'] ??
          decoded['authorizationEndpoint'] ??
          decoded['authorization_url'] ??
          decoded['authorizationUrl'] ??
          decoded['open_id_connect_url'] ??
          decoded['openIdConnectUrl'],
    );
    if (directEndpoint != null) {
      return _ExtractedSchemeAuthEndpoint(
        authorizationUrl: directEndpoint,
        scopes: _extractScopeList(decoded['scopes']),
      );
    }

    final Object? flowsRaw = decoded['flows'];
    if (flowsRaw is Map) {
      for (final String flowKey in <String>[
        'authorization_code',
        'authorizationCode',
        'implicit',
        'client_credentials',
        'clientCredentials',
        'password',
      ]) {
        final Object? flow = flowsRaw[flowKey];
        if (flow is Map) {
          final String? url = _nonEmptyString(
            flow['authorization_url'] ?? flow['authorizationUrl'],
          );
          if (url != null) {
            return _ExtractedSchemeAuthEndpoint(
              authorizationUrl: url,
              scopes: _extractScopeList(flow['scopes'] ?? decoded['scopes']),
              isImplicit: flowKey == 'implicit',
            );
          }
        }
      }
    }
    return null;
  }

  List<String> _extractScopeList(Object? rawScopes) {
    if (rawScopes is List) {
      return rawScopes
          .map((Object? item) => '$item'.trim())
          .where((String item) => item.isNotEmpty)
          .toList(growable: false);
    }
    if (rawScopes is Map) {
      return rawScopes.keys
          .map((Object? key) => '$key'.trim())
          .where((String key) => key.isNotEmpty)
          .toList(growable: false);
    }
    return const <String>[];
  }

  String? _nonEmptyString(Object? value) {
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
    return null;
  }

  String _generateRandomState() {
    final Random random = Random.secure();
    final List<int> bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  AuthConfig _redactConfiguredSecrets(AuthConfig config) {
    for (final AuthCredential? credential in <AuthCredential?>[
      config.rawAuthCredential,
      config.exchangedAuthCredential,
    ]) {
      if (credential == null) {
        continue;
      }
      credential.apiKey = null;
      if (credential.oauth2 != null) {
        credential.oauth2!.clientSecret = null;
      }
      if (credential.http != null) {
        credential.http!.credentials.password = null;
        credential.http!.credentials.token = null;
        credential.http!.additionalHeaders.clear();
      }
    }
    return config;
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

class _ExtractedSchemeAuthEndpoint {
  const _ExtractedSchemeAuthEndpoint({
    required this.authorizationUrl,
    this.scopes = const <String>[],
    this.isImplicit = false,
  });

  final String authorizationUrl;
  final List<String> scopes;
  final bool isImplicit;
}

