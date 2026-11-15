/// Shared credential type and argument name classifiers for telemetry redaction.
library;

import '../auth/auth_credential.dart';
import '../auth/auth_schemes.dart';
import '../auth/auth_tool.dart';

/// Placeholder substituted for redacted credential values.
const String redacted = '<redacted>';

/// Class names whose instances hold credential material across ADK,
/// `google.auth`, and Pydantic secret types.
const Set<String> credentialTypeNames = <String>{
  'AuthCredential',
  'AuthConfig',
  'AuthToolArguments',
  'HttpAuth',
  'HttpCredentials',
  'OAuth2Auth',
  'OAuth2Session',
  'OpenIdConnectWithConfig',
  'ServiceAccount',
  'ServiceAccountAuth',
  'ServiceAccountCredential',
  'Credentials',
  'SecretStr',
  'SecretBytes',
};

/// Normalized parameter and mapping-key names that commonly carry secrets.
const Set<String> credentialArgNames = <String>{
  'access_token',
  'additional_headers',
  'api_key',
  'apikey',
  'auth_code',
  'auth_config',
  'auth_credential',
  'auth_header',
  'auth_headers',
  'auth_response_uri',
  'auth_token',
  'authorization',
  'bearer_token',
  'client_secret',
  'code_verifier',
  'cookie',
  'cookies',
  'credential',
  'credentials',
  'id_token',
  'jwt',
  'oauth_token',
  'passphrase',
  'passwd',
  'password',
  'private_key',
  'private_key_id',
  'proxy_authorization',
  'refresh_token',
  'secret',
  'secret_key',
  'service_account_key',
  'session_token',
  'set_cookie',
  'token',
  'x_api_key',
  'x_auth_token',
  'x_goog_api_key',
};

/// Normalized suffixes for compound secret parameter/key names.
const List<String> credentialArgSuffixes = <String>[
  '_api_key',
  '_apikey',
  '_auth_config',
  '_auth_token',
  '_authorization',
  '_bearer_token',
  '_client_secret',
  '_cookie',
  '_cookies',
  '_credential',
  '_credentials',
  '_jwt',
  '_passphrase',
  '_passwd',
  '_password',
  '_private_key',
  '_secret',
  '_secret_key',
  '_token',
];

final RegExp _camelBoundaryRe = RegExp(r'([a-z0-9])([A-Z])');
final RegExp _acronymBoundaryRe = RegExp(r'([A-Z]+)([A-Z][a-z])');

/// Returns `true` if [value] (or [Type] token) is a known credential carrier.
bool isCredentialType(Object? value) {
  if (value == null ||
      value is bool ||
      value is num ||
      value is String ||
      value is Map ||
      value is Iterable) {
    return false;
  }
  if (value is AuthCredential ||
      value is AuthConfig ||
      value is AuthToolArguments ||
      value is HttpAuth ||
      value is HttpCredentials ||
      value is OAuth2Auth ||
      value is OpenIdConnectWithConfig ||
      value is ServiceAccountAuth ||
      value is ServiceAccountCredential) {
    return true;
  }
  final String rawTypeName = value is Type
      ? value.toString()
      : value.runtimeType.toString();
  final String baseTypeName = rawTypeName.split('<').first;
  return credentialTypeNames.contains(baseTypeName);
}

/// Returns `true` if [name] names a secret-bearing parameter or header.
bool isCredentialArgName(String name) {
  final String lowered = name
      .replaceAllMapped(_acronymBoundaryRe, (Match m) => '${m[1]}_${m[2]}')
      .replaceAllMapped(_camelBoundaryRe, (Match m) => '${m[1]}_${m[2]}')
      .toLowerCase()
      .replaceAll('-', '_');
  return credentialArgNames.contains(lowered) ||
      credentialArgSuffixes.any(lowered.endsWith);
}
