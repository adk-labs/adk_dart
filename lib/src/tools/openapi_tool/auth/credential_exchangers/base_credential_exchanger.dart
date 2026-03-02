import '../../../../auth/auth_credential.dart';

/// Error thrown when required auth credentials are missing.
class AuthCredentialMissingError implements Exception {
  /// Creates an auth credential missing error with [message].
  AuthCredentialMissingError(this.message);

  /// The error description.
  final String message;

  @override
  String toString() => 'AuthCredentialMissingError: $message';
}

/// Base interface for converting credentials into request-ready forms.
abstract class BaseAuthCredentialExchanger {
  /// Exchanges [authCredential] for the given [authScheme].
  Future<AuthCredential?> exchangeCredential(
    Object authScheme, [
    AuthCredential? authCredential,
  ]);
}
