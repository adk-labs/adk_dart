import 'dart:convert';

import 'auth_credential.dart';

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
  return 'adk_${encoded.hashCode.abs()}';
}
