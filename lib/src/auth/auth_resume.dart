/// Shared helpers for finding auth requests and storing auth responses.
library;

import '../events/event.dart';
import '../flows/llm_flows/functions.dart' as flow_functions;
import '../sessions/state.dart';
import '../types/content.dart';
import 'auth_credential.dart';
import 'auth_handler.dart';
import 'auth_tool.dart';

const String _oauthStateKeyPrefix = 'adk_oauth_state:';
const String _oauthCredentialKeyPrefix = 'adk_oauth_credential:';

/// Returns the session state key holding the generated OAuth state.
String oauthStateKey(String interruptId) => '$_oauthStateKeyPrefix$interruptId';

/// Returns the session state key holding the generated OAuth credential.
String oauthCredentialKey(String interruptId) =>
    '$_oauthCredentialKeyPrefix$interruptId';

/// Scans [events] and returns server-issued [AuthToolArguments] by call ID.
Map<String, AuthToolArguments> findRequestedAuthConfigs(
  List<Event> events,
  Set<String> interruptIds,
) {
  if (interruptIds.isEmpty) {
    return <String, AuthToolArguments>{};
  }
  final Map<String, AuthToolArguments> requestedById =
      <String, AuthToolArguments>{};
  for (final Event event in events) {
    for (final FunctionCall call in event.getFunctionCalls()) {
      final String? requestId = call.id;
      if (requestId == null ||
          !interruptIds.contains(requestId) ||
          call.name != flow_functions.requestEucFunctionCallName) {
        continue;
      }
      final String? functionCallId = _readFunctionCallId(call.args);
      final Object? rawAuthConfig =
          call.args['auth_config'] ?? call.args['authConfig'];
      if (rawAuthConfig == null) {
        continue;
      }
      try {
        final AuthConfig authConfig = parseAuthConfigPayload(rawAuthConfig);
        requestedById[requestId] = AuthToolArguments(
          functionCallId: functionCallId ?? '',
          authConfig: authConfig,
        );
      } on ArgumentError {
        continue;
      }
    }
  }
  return requestedById;
}

/// Pins the client's auth [response] to [requested] and stores the credential.
Future<AuthConfig?> storeAuthResponse({
  required AuthConfig requested,
  required Object? response,
  required State state,
  required String interruptId,
}) async {
  AuthCredential? exchangedCredential;
  try {
    exchangedCredential = parseAuthConfigPayload(
      response,
    ).exchangedAuthCredential;
  } on ArgumentError {
    exchangedCredential = _buildCredentialFromValue(requested, response);
  }
  exchangedCredential ??= _buildCredentialFromValue(requested, response);

  if (exchangedCredential == null) {
    return null;
  }

  final Object? generatedState = state[oauthStateKey(interruptId)];
  if (generatedState != null) {
    final OAuth2Auth? oauth2 = exchangedCredential.oauth2;
    if (oauth2 == null || oauth2.state != '$generatedState') {
      return null;
    }
  }

  final String credentialKey = oauthCredentialKey(interruptId);
  Object? storedCredential = state[credentialKey];
  if (storedCredential is Map) {
    storedCredential = parseAuthCredentialPayload(storedCredential);
  }
  if (storedCredential is AuthCredential &&
      storedCredential.oauth2 != null &&
      exchangedCredential.oauth2 != null) {
    exchangedCredential.oauth2!.codeVerifier ??=
        storedCredential.oauth2!.codeVerifier;
    exchangedCredential.oauth2!.codeChallengeMethod ??=
        storedCredential.oauth2!.codeChallengeMethod;
    state[credentialKey] = null;
  }

  final AuthConfig authConfig = requested.copyWith();
  authConfig.exchangedAuthCredential = _mergeCredentialOAuth2Fields(
    exchangedCredential,
    authConfig.exchangedAuthCredential ?? authConfig.rawAuthCredential,
  );

  await AuthHandler(authConfig: authConfig).parseAndStoreAuthResponse(state);
  return authConfig;
}

AuthCredential? _mergeCredentialOAuth2Fields(
  AuthCredential? targetCred,
  AuthCredential? sourceCred,
) {
  if (sourceCred == null) {
    return targetCred;
  }
  if (targetCred == null) {
    return sourceCred.copyWith();
  }
  if (targetCred.oauth2 == null && sourceCred.oauth2 != null) {
    targetCred.oauth2 = sourceCred.oauth2!.copyWith();
  } else if (targetCred.oauth2 != null && sourceCred.oauth2 != null) {
    final OAuth2Auth target = targetCred.oauth2!;
    final OAuth2Auth source = sourceCred.oauth2!;
    target.clientId ??= source.clientId;
    target.clientSecret ??= source.clientSecret;
    target.redirectUri ??= source.redirectUri;
    target.codeVerifier ??= source.codeVerifier;
    target.codeChallengeMethod ??= source.codeChallengeMethod;
    if (target.tokenEndpointAuthMethod == 'client_secret_basic' &&
        source.tokenEndpointAuthMethod != 'client_secret_basic') {
      target.tokenEndpointAuthMethod = source.tokenEndpointAuthMethod;
    }
  }
  return targetCred;
}

AuthCredential? _buildCredentialFromValue(
  AuthConfig authConfig,
  Object? value,
) {
  final AuthCredential? rawCred = authConfig.rawAuthCredential;
  if (rawCred != null &&
      rawCred.authType == AuthCredentialType.apiKey &&
      (value is String || value is num) &&
      value is! bool) {
    return AuthCredential(
      authType: AuthCredentialType.apiKey,
      apiKey: '$value',
    );
  }
  return parseAuthCredentialPayload(value);
}

String? _readFunctionCallId(Map<String, dynamic> args) {
  final Object? raw =
      args['function_call_id'] ??
      args['functionCallId'] ??
      args['function_call'];
  if (raw is String && raw.isNotEmpty) {
    return raw;
  }
  return null;
}

/// Parses an [AuthConfig] from a dynamic payload.
AuthConfig parseAuthConfigPayload(Object? raw) {
  if (raw is AuthConfig) {
    return raw.copyWith();
  }
  if (raw is! Map) {
    throw ArgumentError('Invalid auth config response: $raw');
  }

  final Map<Object?, Object?> map = raw;
  final String? authScheme =
      _readString(map['authScheme']) ??
      _readString(map['auth_scheme']) ??
      _readString(map['scheme']);
  final AuthCredential? rawAuthCredential = parseAuthCredentialPayload(
    map['rawAuthCredential'] ?? map['raw_auth_credential'],
  );
  final AuthCredential? exchangedAuthCredential = parseAuthCredentialPayload(
    map['exchangedAuthCredential'] ?? map['exchanged_auth_credential'],
  );
  if (authScheme == null &&
      rawAuthCredential == null &&
      exchangedAuthCredential == null) {
    throw ArgumentError('Invalid auth config response: $raw');
  }

  return AuthConfig(
    authScheme: authScheme ?? 'unknown',
    credentialKey:
        _readString(map['credentialKey']) ?? _readString(map['credential_key']),
    rawAuthCredential: rawAuthCredential,
    exchangedAuthCredential: exchangedAuthCredential,
  );
}

/// Parses an [AuthCredential] from a dynamic payload.
AuthCredential? parseAuthCredentialPayload(Object? raw) {
  if (raw is AuthCredential) {
    return raw.copyWith();
  }
  if (raw is! Map) {
    return null;
  }

  final Map<Object?, Object?> map = raw;
  final AuthCredentialType? authType = _parseAuthCredentialType(
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
    http: _parseHttpAuth(map['http']),
    oauth2: _parseOAuth2Auth(map['oauth2']),
    serviceAccount: _parseServiceAccountAuth(
      map['serviceAccount'] ?? map['service_account'],
    ),
  );
}

HttpAuth? _parseHttpAuth(Object? raw) {
  if (raw is HttpAuth) {
    return raw.copyWith();
  }
  if (raw is! Map) {
    return null;
  }
  final Map<Object?, Object?> map = raw;

  final Object? rawCreds = map['credentials'];
  final Map<Object?, Object?> credMap = rawCreds is Map ? rawCreds : map;
  final HttpCredentials credentials = HttpCredentials(
    username: _readString(credMap['username']),
    password: _readString(credMap['password']),
    token: _readString(credMap['token']),
  );

  final Map<String, String> headers = <String, String>{};
  final Object? additionalHeaders =
      map['additionalHeaders'] ?? map['additional_headers'];
  if (additionalHeaders is Map) {
    for (final MapEntry<Object?, Object?> entry in additionalHeaders.entries) {
      final Object? key = entry.key;
      if (key is! String) {
        continue;
      }
      headers[key] = '${entry.value ?? ''}';
    }
  }

  return HttpAuth(
    scheme: _readString(map['scheme']) ?? 'bearer',
    credentials: credentials,
    additionalHeaders: headers,
  );
}

OAuth2Auth? _parseOAuth2Auth(Object? raw) {
  if (raw is OAuth2Auth) {
    return raw.copyWith();
  }
  if (raw is! Map) {
    return null;
  }
  final Map<Object?, Object?> map = raw;
  return OAuth2Auth(
    clientId: _readString(map['clientId']) ?? _readString(map['client_id']),
    clientSecret:
        _readString(map['clientSecret']) ?? _readString(map['client_secret']),
    authUri: _readString(map['authUri']) ?? _readString(map['auth_uri']),
    nonce: _readString(map['nonce']),
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
    idToken: _readString(map['idToken']) ?? _readString(map['id_token']),
    expiresAt: _readInt(map['expiresAt']) ?? _readInt(map['expires_at']),
    expiresIn: _readInt(map['expiresIn']) ?? _readInt(map['expires_in']),
    audience: _readString(map['audience']),
    prompt: _readString(map['prompt']),
    codeVerifier:
        _readString(map['codeVerifier']) ?? _readString(map['code_verifier']),
    codeChallengeMethod:
        _readString(map['codeChallengeMethod']) ??
        _readString(map['code_challenge_method']),
    tokenEndpointAuthMethod:
        _readString(
          map['tokenEndpointAuthMethod'] ?? map['token_endpoint_auth_method'],
        ) ??
        'client_secret_basic',
  );
}

ServiceAccountAuth? _parseServiceAccountAuth(Object? raw) {
  if (raw is ServiceAccountAuth) {
    return raw.copyWith();
  }
  if (raw is! Map) {
    return null;
  }
  final Map<Object?, Object?> map = raw;

  ServiceAccountCredential? credential;
  final Object? rawCredential =
      map['serviceAccountCredential'] ?? map['service_account_credential'];
  if (rawCredential is ServiceAccountCredential) {
    credential = rawCredential.copyWith();
  } else if (rawCredential is Map) {
    final Map<Object?, Object?> c = rawCredential;
    final String? projectId =
        _readString(c['projectId']) ?? _readString(c['project_id']);
    final String? privateKeyId =
        _readString(c['privateKeyId']) ?? _readString(c['private_key_id']);
    final String? privateKey =
        _readString(c['privateKey']) ?? _readString(c['private_key']);
    final String? clientEmail =
        _readString(c['clientEmail']) ?? _readString(c['client_email']);
    final String? clientId =
        _readString(c['clientId']) ?? _readString(c['client_id']);
    final String? authUri =
        _readString(c['authUri']) ?? _readString(c['auth_uri']);
    final String? tokenUri =
        _readString(c['tokenUri']) ?? _readString(c['token_uri']);
    if (projectId != null &&
        privateKeyId != null &&
        privateKey != null &&
        clientEmail != null &&
        clientId != null &&
        authUri != null &&
        tokenUri != null) {
      credential = ServiceAccountCredential(
        projectId: projectId,
        privateKeyId: privateKeyId,
        privateKey: privateKey,
        clientEmail: clientEmail,
        clientId: clientId,
        authUri: authUri,
        tokenUri: tokenUri,
      );
    }
  }

  final List<String> scopes = <String>[];
  final Object? rawScopes = map['scopes'];
  if (rawScopes is List) {
    for (final Object? scope in rawScopes) {
      if (scope is String) {
        scopes.add(scope);
      }
    }
  }

  return ServiceAccountAuth(
    serviceAccountCredential: credential,
    scopes: scopes,
    useDefaultCredential:
        _readBool(map['useDefaultCredential']) ??
        _readBool(map['use_default_credential']) ??
        false,
    useIdToken:
        _readBool(map['useIdToken']) ??
        _readBool(map['use_id_token']) ??
        false,
    audience: _readString(map['audience']),
  );
}

AuthCredentialType? _parseAuthCredentialType(String? value) {
  if (value == null || value.isEmpty) {
    return null;
  }
  for (final AuthCredentialType type in AuthCredentialType.values) {
    if (type.name.toLowerCase() == value.toLowerCase()) {
      return type;
    }
  }

  switch (value.toLowerCase()) {
    case 'api_key':
      return AuthCredentialType.apiKey;
    case 'open_id_connect':
    case 'openidconnect':
    case 'openid_connect':
      return AuthCredentialType.openIdConnect;
    case 'service_account':
      return AuthCredentialType.serviceAccount;
    default:
      return null;
  }
}

String? _readString(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is String) {
    return value;
  }
  return '$value';
}

int? _readInt(Object? value) {
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

bool? _readBool(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is bool) {
    return value;
  }
  if (value is String) {
    if (value.toLowerCase() == 'true') {
      return true;
    }
    if (value.toLowerCase() == 'false') {
      return false;
    }
  }
  return null;
}
