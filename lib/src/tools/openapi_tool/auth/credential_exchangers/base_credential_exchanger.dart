import '../../../../auth/auth_credential.dart';

class AuthCredentialMissingError implements Exception {
  AuthCredentialMissingError(this.message);

  final String message;

  @override
  String toString() => 'AuthCredentialMissingError: $message';
}

abstract class BaseAuthCredentialExchanger {
  Future<AuthCredential?> exchangeCredential(
    Object authScheme, [
    AuthCredential? authCredential,
  ]);
}
