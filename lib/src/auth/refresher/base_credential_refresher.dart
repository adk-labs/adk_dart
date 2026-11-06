/// Credential refresh interfaces for expiring auth tokens.
library;

import '../auth_credential.dart';

/// Interface for checking and refreshing credentials.
abstract class BaseCredentialRefresher {
  /// Returns whether [authCredential] requires refresh.
  Future<bool> isRefreshNeeded({
    required AuthCredential authCredential,
    String? authScheme,
  });

  /// Refreshes [authCredential] and returns the updated credential.
  Future<AuthCredential> refresh({
    required AuthCredential authCredential,
    String? authScheme,
  });
}

/// Exception thrown when refreshing an [AuthCredential] fails.
class CredentialRefresherError implements Exception {
  /// Creates a [CredentialRefresherError] with [message].
  const CredentialRefresherError(this.message);

  /// Error details.
  final String message;

  @override
  String toString() => 'CredentialRefresherError: $message';
}

/// Exception thrown when a refresh credential has been permanently revoked or
/// expired (for example, OAuth2 `invalid_grant`).
class CredentialRevokedError extends CredentialRefresherError {
  /// Creates a [CredentialRevokedError] with [message].
  const CredentialRevokedError(super.message);

  @override
  String toString() => 'CredentialRevokedError: $message';
}
