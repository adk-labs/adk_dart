import '../auth_credential.dart';
import 'base_credential_exchanger.dart';

class CredentialExchangerRegistry {
  final Map<AuthCredentialType, BaseCredentialExchanger> _exchangers =
      <AuthCredentialType, BaseCredentialExchanger>{};

  void register(
    AuthCredentialType credentialType,
    BaseCredentialExchanger exchanger,
  ) {
    _exchangers[credentialType] = exchanger;
  }

  BaseCredentialExchanger? getExchanger(AuthCredentialType credentialType) {
    return _exchangers[credentialType];
  }
}
