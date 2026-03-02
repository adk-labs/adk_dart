/// Registry for credential exchangers by credential type.
library;

import '../auth_credential.dart';
import 'base_credential_exchanger.dart';

/// Holds credential exchangers for supported auth credential types.
class CredentialExchangerRegistry {
  final Map<AuthCredentialType, BaseCredentialExchanger> _exchangers =
      <AuthCredentialType, BaseCredentialExchanger>{};

  /// Registers [exchanger] for [credentialType].
  void register(
    AuthCredentialType credentialType,
    BaseCredentialExchanger exchanger,
  ) {
    _exchangers[credentialType] = exchanger;
  }

  /// Returns the exchanger for [credentialType], if any.
  BaseCredentialExchanger? getExchanger(AuthCredentialType credentialType) {
    return _exchangers[credentialType];
  }
}
