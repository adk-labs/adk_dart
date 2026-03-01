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
    useIdToken: serviceAccount.useIdToken,
    audience: serviceAccount.audience,
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
final BigInt _int64Mask = BigInt.parse('ffffffffffffffff', radix: 16);
final BigInt _int64SignBit = BigInt.parse('8000000000000000', radix: 16);
final BigInt _int64Modulus = BigInt.parse('10000000000000000', radix: 16);
