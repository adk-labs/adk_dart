import 'dart:convert';

import '../../../auth/auth_credential.dart';
import '../../../auth/auth_handler.dart';
import '../../../auth/auth_schemes.dart';
import '../../../auth/auth_tool.dart';
import '../../../auth/refresher/oauth2_credential_refresher.dart';
import '../../tool_context.dart';
import '../auth/credential_exchangers/auto_auth_credential_exchanger.dart';
import '../auth/credential_exchangers/base_credential_exchanger.dart';

class AuthPreparationResult {
  AuthPreparationResult({
    required this.state,
    this.authScheme,
    this.authCredential,
  });

  final String state;
  final Object? authScheme;
  final AuthCredential? authCredential;
}

class ToolContextCredentialStore {
  ToolContextCredentialStore({required this.toolContext});

  final ToolContext? toolContext;

  String _legacyStableDigest(String text) {
    return _stableFnv1a64Hex(text);
  }

  String _getLegacyCredentialKey(
    Object? authScheme,
    AuthCredential? authCredential,
  ) {
    final AuthCredential? normalizedCredential = _normalizeCredentialForKey(
      authCredential,
    );
    final String schemeName = authScheme == null
        ? ''
        : '${_authSchemeTypeName(authScheme)}_${_legacyStableDigest(_canonicalJson(_authSchemeToPrimitive(authScheme)))}';
    final String credentialName = normalizedCredential == null
        ? ''
        : '${normalizedCredential.authType.name}_${_legacyStableDigest(_canonicalJson(_authCredentialToPrimitive(normalizedCredential)))}';
    return '${schemeName}_${credentialName}_existing_exchanged_credential';
  }

  String getCredentialKey(Object? authScheme, AuthCredential? authCredential) {
    final AuthCredential? normalizedCredential = _normalizeCredentialForKey(
      authCredential,
    );
    final String schemeName = authScheme == null
        ? ''
        : '${_authSchemeTypeName(authScheme)}_${_stableFnv1a64Hex(_canonicalJson(_authSchemeToPrimitive(authScheme)))}';
    final String credentialName = normalizedCredential == null
        ? ''
        : '${normalizedCredential.authType.name}_${_stableFnv1a64Hex(_canonicalJson(_authCredentialToPrimitive(normalizedCredential)))}';
    return '${schemeName}_${credentialName}_existing_exchanged_credential';
  }

  AuthCredential? getCredential(
    Object? authScheme,
    AuthCredential? authCredential,
  ) {
    final ToolContext? context = toolContext;
    if (context == null) {
      return null;
    }

    final String tokenKey = getCredentialKey(authScheme, authCredential);
    final AuthCredential? credential = _credentialFromObject(
      context.state[tokenKey],
    );
    if (credential != null) {
      return credential;
    }

    final String legacyKey = _getLegacyCredentialKey(
      authScheme,
      authCredential,
    );
    if (legacyKey == tokenKey) {
      return null;
    }

    final AuthCredential? legacyCredential = _credentialFromObject(
      context.state[legacyKey],
    );
    if (legacyCredential == null) {
      return null;
    }

    context.state[tokenKey] = legacyCredential.copyWith();
    return legacyCredential;
  }

  void storeCredential(String key, AuthCredential? authCredential) {
    if (toolContext == null || authCredential == null) {
      return;
    }
    toolContext!.state[key] = authCredential.copyWith();
  }

  void removeCredential(String key) {
    toolContext?.state.remove(key);
  }
}

class ToolAuthHandler {
  ToolAuthHandler(
    this.toolContext,
    this.authScheme,
    this.authCredential, {
    BaseAuthCredentialExchanger? credentialExchanger,
    this.credentialStore,
    String? credentialKey,
    OAuth2CredentialRefresher? oauth2CredentialRefresher,
  }) : _credentialKey = credentialKey,
       credentialExchanger =
           credentialExchanger ?? AutoAuthCredentialExchanger(),
       _oauth2CredentialRefresher =
           oauth2CredentialRefresher ?? OAuth2CredentialRefresher();

  final ToolContext? toolContext;
  final Object? authScheme;
  final AuthCredential? authCredential;
  final String? _credentialKey;
  final BaseAuthCredentialExchanger credentialExchanger;
  final ToolContextCredentialStore? credentialStore;
  final OAuth2CredentialRefresher _oauth2CredentialRefresher;

  bool shouldStoreCredential = true;

  String? _getCredentialKeyOverride() {
    if (_credentialKey != null && _credentialKey.isNotEmpty) {
      return _credentialKey;
    }

    final Object? scheme = authScheme;
    if (scheme is Map) {
      final Object? camel = scheme['credentialKey'];
      final Object? snake = scheme['credential_key'];
      if (camel is String && camel.isNotEmpty) {
        return camel;
      }
      if (snake is String && snake.isNotEmpty) {
        return snake;
      }
    }

    return null;
  }

  AuthConfig _buildAuthConfig() {
    return AuthConfig(
      authScheme: _serializeAuthScheme(authScheme),
      rawAuthCredential: authCredential?.copyWith(),
      credentialKey: _getCredentialKeyOverride(),
    );
  }

  static ToolAuthHandler fromToolContext(
    ToolContext? toolContext,
    Object? authScheme,
    AuthCredential? authCredential, {
    BaseAuthCredentialExchanger? credentialExchanger,
    String? credentialKey,
    OAuth2CredentialRefresher? oauth2CredentialRefresher,
  }) {
    final ToolContextCredentialStore? store = toolContext == null
        ? null
        : ToolContextCredentialStore(toolContext: toolContext);
    return ToolAuthHandler(
      toolContext,
      authScheme,
      authCredential?.copyWith(),
      credentialKey: credentialKey,
      credentialExchanger: credentialExchanger,
      credentialStore: store,
      oauth2CredentialRefresher: oauth2CredentialRefresher,
    );
  }

  Future<AuthCredential?> _getExistingCredential() async {
    final ToolContextCredentialStore? store = credentialStore;
    if (store == null) {
      return null;
    }

    AuthCredential? existing = store.getCredential(authScheme, authCredential);
    if (existing?.oauth2 != null) {
      final bool refreshNeeded = await _oauth2CredentialRefresher
          .isRefreshNeeded(
            authCredential: existing!,
            authScheme: _serializeAuthScheme(authScheme),
          );
      if (refreshNeeded) {
        existing = await _oauth2CredentialRefresher.refresh(
          authCredential: existing,
          authScheme: _serializeAuthScheme(authScheme),
        );
      }
    }
    return existing;
  }

  Future<AuthCredential?> _exchangeCredential(AuthCredential credential) async {
    try {
      return await credentialExchanger.exchangeCredential(
        authScheme ?? '',
        credential,
      );
    } catch (_) {
      return null;
    }
  }

  void _storeCredential(AuthCredential credential) {
    if (!shouldStoreCredential) {
      return;
    }
    final ToolContextCredentialStore? store = credentialStore;
    if (store == null) {
      return;
    }

    final String key = store.getCredentialKey(authScheme, authCredential);
    store.storeCredential(key, credential);
  }

  void _requestCredential() {
    final AuthSchemeType? schemeType = _authSchemeType(authScheme);
    if (schemeType == AuthSchemeType.openIdConnect ||
        schemeType == AuthSchemeType.oauth2) {
      final OAuth2Auth? oauth2 = authCredential?.oauth2;
      if (oauth2 == null) {
        throw ArgumentError(
          'authCredential is empty for scheme $schemeType. '
          'Please create AuthCredential using OAuth2Auth.',
        );
      }

      if (oauth2.clientId == null || oauth2.clientId!.isEmpty) {
        throw AuthCredentialMissingError(
          'OAuth2 credentials client_id is missing.',
        );
      }
      if (oauth2.clientSecret == null || oauth2.clientSecret!.isEmpty) {
        throw AuthCredentialMissingError(
          'OAuth2 credentials client_secret is missing.',
        );
      }
    }

    toolContext?.requestCredential(_buildAuthConfig());
  }

  AuthCredential? _getAuthResponse() {
    final ToolContext? context = toolContext;
    if (context == null) {
      return null;
    }
    return AuthHandler(
      authConfig: _buildAuthConfig(),
    ).getAuthResponse(context.state);
  }

  bool _externalExchangeRequired(AuthCredential credential) {
    if (credential.authType != AuthCredentialType.oauth2 &&
        credential.authType != AuthCredentialType.openIdConnect) {
      return false;
    }
    final String? accessToken = credential.oauth2?.accessToken;
    return accessToken == null || accessToken.isEmpty;
  }

  Future<AuthPreparationResult> prepareAuthCredentials() async {
    if (authScheme == null) {
      return AuthPreparationResult(state: 'done');
    }

    final AuthCredential? existingCredential = await _getExistingCredential();
    AuthCredential? credential =
        existingCredential ?? authCredential?.copyWith();

    if (credential == null || _externalExchangeRequired(credential)) {
      credential = _getAuthResponse();
      if (credential != null) {
        _storeCredential(credential);
      } else {
        _requestCredential();
        return AuthPreparationResult(
          state: 'pending',
          authScheme: authScheme,
          authCredential: authCredential,
        );
      }
    }

    final AuthCredential? exchangedCredential = await _exchangeCredential(
      credential,
    );
    return AuthPreparationResult(
      state: 'done',
      authScheme: authScheme,
      authCredential: exchangedCredential,
    );
  }
}

String _serializeAuthScheme(Object? authScheme) {
  if (authScheme == null) {
    return '';
  }
  if (authScheme is SecurityScheme) {
    return _canonicalJson(authScheme.toJson());
  }
  if (authScheme is Map) {
    return _canonicalJson(
      authScheme.map((Object? key, Object? value) => MapEntry('$key', value)),
    );
  }
  return '$authScheme';
}

AuthSchemeType? _authSchemeType(Object? authScheme) {
  if (authScheme is SecurityScheme) {
    return authScheme.type;
  }
  if (authScheme is Map) {
    final String type = '${authScheme['type'] ?? ''}'.toLowerCase();
    switch (type) {
      case 'apikey':
      case 'api_key':
        return AuthSchemeType.apiKey;
      case 'http':
        return AuthSchemeType.http;
      case 'oauth2':
        return AuthSchemeType.oauth2;
      case 'openidconnect':
      case 'openid_connect':
      case 'open_id_connect':
        return AuthSchemeType.openIdConnect;
    }
  }
  return null;
}

String _authSchemeTypeName(Object? authScheme) {
  final AuthSchemeType? type = _authSchemeType(authScheme);
  if (type != null) {
    return type.name;
  }
  if (authScheme is Map) {
    return '${authScheme['type'] ?? ''}';
  }
  return '$authScheme';
}

Object? _authSchemeToPrimitive(Object? authScheme) {
  if (authScheme is SecurityScheme) {
    return authScheme.toJson();
  }
  if (authScheme is Map) {
    return authScheme.map(
      (Object? key, Object? value) => MapEntry('$key', value),
    );
  }
  return authScheme;
}

Object? _authCredentialToPrimitive(AuthCredential credential) {
  final HttpAuth? http = credential.http;
  final OAuth2Auth? oauth2 = credential.oauth2;
  final ServiceAccountAuth? serviceAccount = credential.serviceAccount;

  return <String, Object?>{
    'authType': credential.authType.name,
    'resourceRef': credential.resourceRef,
    'apiKey': credential.apiKey,
    if (http != null)
      'http': <String, Object?>{
        'scheme': http.scheme,
        'credentials': <String, Object?>{
          'username': http.credentials.username,
          'password': http.credentials.password,
          'token': http.credentials.token,
        },
        'additionalHeaders': Map<String, String>.from(http.additionalHeaders),
      },
    if (oauth2 != null)
      'oauth2': <String, Object?>{
        'clientId': oauth2.clientId,
        'clientSecret': oauth2.clientSecret,
        'authUri': oauth2.authUri,
        'state': oauth2.state,
        'redirectUri': oauth2.redirectUri,
        'authResponseUri': oauth2.authResponseUri,
        'authCode': oauth2.authCode,
        'accessToken': oauth2.accessToken,
        'refreshToken': oauth2.refreshToken,
        'expiresAt': oauth2.expiresAt,
        'expiresIn': oauth2.expiresIn,
        'audience': oauth2.audience,
        'tokenEndpointAuthMethod': oauth2.tokenEndpointAuthMethod,
      },
    if (serviceAccount != null)
      'serviceAccount': <String, Object?>{
        'serviceAccountCredential':
            serviceAccount.serviceAccountCredential == null
            ? null
            : <String, Object?>{
                'projectId': serviceAccount.serviceAccountCredential!.projectId,
                'privateKeyId':
                    serviceAccount.serviceAccountCredential!.privateKeyId,
                'privateKey':
                    serviceAccount.serviceAccountCredential!.privateKey,
                'clientEmail':
                    serviceAccount.serviceAccountCredential!.clientEmail,
                'clientId': serviceAccount.serviceAccountCredential!.clientId,
                'authUri': serviceAccount.serviceAccountCredential!.authUri,
                'tokenUri': serviceAccount.serviceAccountCredential!.tokenUri,
              },
        'scopes': List<String>.from(serviceAccount.scopes),
        'useDefaultCredential': serviceAccount.useDefaultCredential,
        'useIdToken': serviceAccount.useIdToken,
        'audience': serviceAccount.audience,
      },
  };
}

AuthCredential? _credentialFromObject(Object? value) {
  if (value is AuthCredential) {
    return value.copyWith();
  }
  if (value is! Map) {
    return null;
  }

  final Map<String, Object?> map = value.map(
    (Object? key, Object? item) => MapEntry('$key', item),
  );
  final AuthCredentialType? authType = _authCredentialTypeFromString(
    _readString(map['authType']) ?? _readString(map['auth_type']),
  );
  if (authType == null) {
    return null;
  }

  return AuthCredential(
    authType: authType,
    resourceRef:
        _readString(map['resourceRef']) ?? _readString(map['resource_ref']),
    apiKey: _readString(map['apiKey']) ?? _readString(map['api_key']),
    http: _httpAuthFromObject(map['http']),
    oauth2: _oauth2FromObject(map['oauth2']),
    serviceAccount: _serviceAccountFromObject(
      map['serviceAccount'] ?? map['service_account'],
    ),
  );
}

HttpAuth? _httpAuthFromObject(Object? value) {
  if (value is HttpAuth) {
    return value;
  }
  if (value is! Map) {
    return null;
  }

  final Map<String, Object?> map = value.map(
    (Object? key, Object? item) => MapEntry('$key', item),
  );
  final Map<String, String> headers = <String, String>{};
  final Object? additionalHeaders =
      map['additionalHeaders'] ?? map['additional_headers'];
  if (additionalHeaders is Map) {
    for (final MapEntry<Object?, Object?> entry in additionalHeaders.entries) {
      final Object? key = entry.key;
      if (key is String) {
        headers[key] = '${entry.value ?? ''}';
      }
    }
  }

  final Map<String, Object?> credentialsMap = _readMap(
    map['credentials'] ?? map,
  );
  return HttpAuth(
    scheme: _readString(map['scheme']) ?? 'bearer',
    credentials: HttpCredentials(
      username: _readString(credentialsMap['username']),
      password: _readString(credentialsMap['password']),
      token: _readString(credentialsMap['token']),
    ),
    additionalHeaders: headers,
  );
}

OAuth2Auth? _oauth2FromObject(Object? value) {
  if (value is OAuth2Auth) {
    return value;
  }
  if (value is! Map) {
    return null;
  }
  final Map<String, Object?> map = value.map(
    (Object? key, Object? item) => MapEntry('$key', item),
  );

  return OAuth2Auth(
    clientId: _readString(map['clientId']) ?? _readString(map['client_id']),
    clientSecret:
        _readString(map['clientSecret']) ?? _readString(map['client_secret']),
    authUri: _readString(map['authUri']) ?? _readString(map['auth_uri']),
    state: _readString(map['state']),
    redirectUri:
        _readString(map['redirectUri']) ?? _readString(map['redirect_uri']),
    authResponseUri:
        _readString(map['authResponseUri']) ??
        _readString(map['auth_response_uri']),
    authCode: _readString(map['authCode']) ?? _readString(map['auth_code']),
    accessToken:
        _readString(map['accessToken']) ?? _readString(map['access_token']),
    refreshToken:
        _readString(map['refreshToken']) ?? _readString(map['refresh_token']),
    expiresAt: _readInt(map['expiresAt']) ?? _readInt(map['expires_at']),
    expiresIn: _readInt(map['expiresIn']) ?? _readInt(map['expires_in']),
    audience: _readString(map['audience']),
    tokenEndpointAuthMethod:
        _readString(map['tokenEndpointAuthMethod']) ??
        _readString(map['token_endpoint_auth_method']) ??
        'client_secret_basic',
  );
}

ServiceAccountAuth? _serviceAccountFromObject(Object? value) {
  if (value is ServiceAccountAuth) {
    return value;
  }
  if (value is! Map) {
    return null;
  }

  final Map<String, Object?> map = value.map(
    (Object? key, Object? item) => MapEntry('$key', item),
  );
  final Map<String, Object?> credentialMap = _readMap(
    map['serviceAccountCredential'] ?? map['service_account_credential'],
  );

  ServiceAccountCredential? credential;
  if (credentialMap.isNotEmpty) {
    credential = ServiceAccountCredential(
      projectId:
          _readString(credentialMap['projectId']) ??
          _readString(credentialMap['project_id']) ??
          '',
      privateKeyId:
          _readString(credentialMap['privateKeyId']) ??
          _readString(credentialMap['private_key_id']) ??
          '',
      privateKey:
          _readString(credentialMap['privateKey']) ??
          _readString(credentialMap['private_key']) ??
          '',
      clientEmail:
          _readString(credentialMap['clientEmail']) ??
          _readString(credentialMap['client_email']) ??
          '',
      clientId:
          _readString(credentialMap['clientId']) ??
          _readString(credentialMap['client_id']) ??
          '',
      authUri:
          _readString(credentialMap['authUri']) ??
          _readString(credentialMap['auth_uri']) ??
          '',
      tokenUri:
          _readString(credentialMap['tokenUri']) ??
          _readString(credentialMap['token_uri']) ??
          '',
    );
  }

  final List<String> scopes = _readList(
    map['scopes'],
  ).map((Object? value) => '$value').toList(growable: false);
  return ServiceAccountAuth(
    serviceAccountCredential: credential,
    scopes: scopes,
    useDefaultCredential: _readBool(
      map['useDefaultCredential'] ?? map['use_default_credential'],
    ),
    useIdToken: _readBool(map['useIdToken'] ?? map['use_id_token']),
    audience: _readString(map['audience']),
  );
}

AuthCredential? _normalizeCredentialForKey(AuthCredential? credential) {
  if (credential == null) {
    return null;
  }
  final AuthCredential clone = credential.copyWith();
  final OAuth2Auth? oauth2 = clone.oauth2;
  if (oauth2 != null) {
    clone.oauth2 = OAuth2Auth(
      clientId: oauth2.clientId,
      clientSecret: oauth2.clientSecret,
      authUri: null,
      state: null,
      redirectUri: oauth2.redirectUri,
      authResponseUri: null,
      authCode: null,
      accessToken: null,
      refreshToken: null,
      expiresAt: null,
      expiresIn: null,
      audience: oauth2.audience,
      tokenEndpointAuthMethod: oauth2.tokenEndpointAuthMethod,
    );
  }
  return clone;
}

String _canonicalJson(Object? value) {
  if (value is Map) {
    final List<String> keys = value.keys.map((Object? key) => '$key').toList()
      ..sort();
    final StringBuffer buffer = StringBuffer('{');
    for (int i = 0; i < keys.length; i += 1) {
      if (i > 0) {
        buffer.write(',');
      }
      final String key = keys[i];
      buffer
        ..write(jsonEncode(key))
        ..write(':')
        ..write(_canonicalJson(value[key]));
    }
    buffer.write('}');
    return buffer.toString();
  }

  if (value is List) {
    final StringBuffer buffer = StringBuffer('[');
    for (int i = 0; i < value.length; i += 1) {
      if (i > 0) {
        buffer.write(',');
      }
      buffer.write(_canonicalJson(value[i]));
    }
    buffer.write(']');
    return buffer.toString();
  }

  return jsonEncode(value);
}

String _stableFnv1a64Hex(String value) {
  final BigInt fnvOffsetBasis = _signedInt64FromHex('cbf29ce484222325');
  final BigInt fnvPrime = BigInt.parse('100000001b3', radix: 16);

  BigInt hash = fnvOffsetBasis;
  for (int i = 0; i < value.length; i += 1) {
    hash = _toSignedInt64(hash ^ BigInt.from(value.codeUnitAt(i)));
    hash = _toSignedInt64(hash * fnvPrime);
  }
  return hash.toRadixString(16).padLeft(16, '0');
}

BigInt _signedInt64FromHex(String value) {
  return _toSignedInt64(BigInt.parse(value, radix: 16));
}

BigInt _toSignedInt64(BigInt value) {
  final BigInt masked = value & _int64Mask;
  if (masked >= _int64SignBit) {
    return masked - _int64Modulus;
  }
  return masked;
}

AuthCredentialType? _authCredentialTypeFromString(String? value) {
  final String normalized = (value ?? '').toLowerCase();
  switch (normalized) {
    case 'apikey':
    case 'api_key':
      return AuthCredentialType.apiKey;
    case 'http':
      return AuthCredentialType.http;
    case 'oauth2':
      return AuthCredentialType.oauth2;
    case 'openidconnect':
    case 'open_id_connect':
    case 'openid_connect':
      return AuthCredentialType.openIdConnect;
    case 'serviceaccount':
    case 'service_account':
      return AuthCredentialType.serviceAccount;
  }
  return null;
}

Map<String, Object?> _readMap(Object? value) {
  if (value is Map<String, Object?>) {
    return Map<String, Object?>.from(value);
  }
  if (value is Map) {
    return value.map((Object? key, Object? item) => MapEntry('$key', item));
  }
  return <String, Object?>{};
}

List<Object?> _readList(Object? value) {
  if (value is List<Object?>) {
    return List<Object?>.from(value);
  }
  if (value is List) {
    return value.cast<Object?>();
  }
  return <Object?>[];
}

String? _readString(Object? value) {
  if (value == null) {
    return null;
  }
  final String text = '$value';
  return text.isEmpty ? null : text;
}

int? _readInt(Object? value) {
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

bool _readBool(Object? value) {
  if (value is bool) {
    return value;
  }
  if (value is num) {
    return value != 0;
  }
  if (value is String) {
    final String normalized = value.toLowerCase();
    return normalized == 'true' || normalized == '1';
  }
  return false;
}

final BigInt _int64Mask = BigInt.parse('ffffffffffffffff', radix: 16);
final BigInt _int64SignBit = BigInt.parse('8000000000000000', radix: 16);
final BigInt _int64Modulus = BigInt.parse('10000000000000000', radix: 16);
