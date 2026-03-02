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
