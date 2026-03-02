/// Credential exchange interfaces and result models.
library;

import '../auth_credential.dart';

/// Error raised when credential exchange fails.
class CredentialExchangeError implements Exception {
  /// Creates a credential exchange error.
  CredentialExchangeError(this.message);

  /// Human-readable error message.
  final String message;

  @override
  String toString() => 'CredentialExchangeError: $message';
}

/// Result of a credential exchange attempt.
class ExchangeResult {
  /// Creates an exchange result.
  const ExchangeResult({required this.credential, required this.wasExchanged});

  /// Resulting credential payload.
  final AuthCredential credential;

  /// Whether an exchange operation actually occurred.
  final bool wasExchanged;
}

/// Interface for converting raw credentials into usable tokens.
abstract class BaseCredentialExchanger {
  /// Exchanges [authCredential] for a usable credential representation.
  Future<ExchangeResult> exchange({
    required AuthCredential authCredential,
    String? authScheme,
  });
}
