/// Registry for credential refreshers by credential type.
library;

import '../auth_credential.dart';
import 'base_credential_refresher.dart';

/// Holds credential refreshers for supported auth credential types.
class CredentialRefresherRegistry {
  final Map<AuthCredentialType, BaseCredentialRefresher> _refreshers =
      <AuthCredentialType, BaseCredentialRefresher>{};

  /// Registers [refresher] for [credentialType].
  void register(
    AuthCredentialType credentialType,
    BaseCredentialRefresher refresher,
  ) {
    _refreshers[credentialType] = refresher;
  }

  /// Returns the refresher for [credentialType], if any.
  BaseCredentialRefresher? getRefresher(AuthCredentialType credentialType) {
    return _refreshers[credentialType];
  }
}
