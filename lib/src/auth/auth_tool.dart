import 'dart:convert';

import 'auth_credential.dart';

const String toolsetAuthCredentialIdPrefix = '_adk_toolset_auth_';

class AuthConfig {
  AuthConfig({
    required this.authScheme,
    this.rawAuthCredential,
    this.exchangedAuthCredential,
    String? credentialKey,
  }) : credentialKey =
           credentialKey ??
           _buildCredentialKey(
             authScheme: authScheme,
             rawAuthCredential: rawAuthCredential,
           );

  final String authScheme;
  AuthCredential? rawAuthCredential;
  AuthCredential? exchangedAuthCredential;
  String credentialKey;

  AuthConfig copyWith({
    String? authScheme,
    Object? rawAuthCredential = _sentinel,
    Object? exchangedAuthCredential = _sentinel,
    Object? credentialKey = _sentinel,
  }) {
    return AuthConfig(
      authScheme: authScheme ?? this.authScheme,
      rawAuthCredential: identical(rawAuthCredential, _sentinel)
          ? _copyCredential(this.rawAuthCredential)
          : rawAuthCredential as AuthCredential?,
      exchangedAuthCredential: identical(exchangedAuthCredential, _sentinel)
          ? _copyCredential(this.exchangedAuthCredential)
          : exchangedAuthCredential as AuthCredential?,
      credentialKey: identical(credentialKey, _sentinel)
          ? this.credentialKey
          : credentialKey as String?,
    );
  }
}

String _buildCredentialKey({
  required String authScheme,
  required AuthCredential? rawAuthCredential,
}) {
  final Map<String, Object?> payload = <String, Object?>{
    'authScheme': authScheme,
    'authType': rawAuthCredential?.authType.name,
    'resourceRef': rawAuthCredential?.resourceRef,
  };
  final String encoded = jsonEncode(payload);
  return 'adk_${_stableFnv1a64Hex(encoded)}';
}

/// Session state key used by auth preprocessors and credential manager.
String authResponseStateKey(String credentialKey) => 'auth:$credentialKey';
String authTemporaryStateKey(String credentialKey) => 'temp:$credentialKey';

class AuthToolArguments {
  AuthToolArguments({required this.functionCallId, required this.authConfig});

  final String functionCallId;
  final AuthConfig authConfig;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'function_call_id': functionCallId,
      'auth_config': authConfig,
    };
  }
}

String _stableFnv1a64Hex(String value) {
  const int fnvOffsetBasis = 0xcbf29ce484222325;
  const int fnvPrime = 0x100000001b3;
  const int mask64 = 0xFFFFFFFFFFFFFFFF;

  int hash = fnvOffsetBasis;
  for (int i = 0; i < value.length; i += 1) {
    hash ^= value.codeUnitAt(i);
    hash = (hash * fnvPrime) & mask64;
  }
  return hash.toRadixString(16).padLeft(16, '0');
}

AuthCredential? _copyCredential(AuthCredential? credential) {
  if (credential == null) {
    return null;
  }
  return AuthCredential(
    authType: credential.authType,
    resourceRef: credential.resourceRef,
    apiKey: credential.apiKey,
    http: _copyHttpAuth(credential.http),
    oauth2: _copyOAuth2Auth(credential.oauth2),
    serviceAccount: _copyServiceAccountAuth(credential.serviceAccount),
  );
}

HttpAuth? _copyHttpAuth(HttpAuth? http) {
  if (http == null) {
    return null;
  }
  return HttpAuth(
    scheme: http.scheme,
    credentials: HttpCredentials(
      username: http.credentials.username,
      password: http.credentials.password,
      token: http.credentials.token,
    ),
    additionalHeaders: Map<String, String>.from(http.additionalHeaders),
  );
}

OAuth2Auth? _copyOAuth2Auth(OAuth2Auth? oauth2) {
  if (oauth2 == null) {
    return null;
  }
  return OAuth2Auth(
    clientId: oauth2.clientId,
    clientSecret: oauth2.clientSecret,
    authUri: oauth2.authUri,
    state: oauth2.state,
    redirectUri: oauth2.redirectUri,
    authResponseUri: oauth2.authResponseUri,
    authCode: oauth2.authCode,
    accessToken: oauth2.accessToken,
    refreshToken: oauth2.refreshToken,
    idToken: oauth2.idToken,
    expiresAt: oauth2.expiresAt,
    expiresIn: oauth2.expiresIn,
    audience: oauth2.audience,
    tokenEndpointAuthMethod: oauth2.tokenEndpointAuthMethod,
  );
}

ServiceAccountAuth? _copyServiceAccountAuth(
  ServiceAccountAuth? serviceAccount,
) {
  if (serviceAccount == null) {
    return null;
  }
  return ServiceAccountAuth(
    serviceAccountCredential: _copyServiceAccountCredential(
      serviceAccount.serviceAccountCredential,
    ),
    scopes: List<String>.from(serviceAccount.scopes),
    useDefaultCredential: serviceAccount.useDefaultCredential,
  );
}

ServiceAccountCredential? _copyServiceAccountCredential(
  ServiceAccountCredential? serviceAccountCredential,
) {
  if (serviceAccountCredential == null) {
    return null;
  }
  return ServiceAccountCredential(
    projectId: serviceAccountCredential.projectId,
    privateKeyId: serviceAccountCredential.privateKeyId,
    privateKey: serviceAccountCredential.privateKey,
    clientEmail: serviceAccountCredential.clientEmail,
    clientId: serviceAccountCredential.clientId,
    authUri: serviceAccountCredential.authUri,
    tokenUri: serviceAccountCredential.tokenUri,
  );
}

const Object _sentinel = Object();
