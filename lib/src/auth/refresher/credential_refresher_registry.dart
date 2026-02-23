import '../auth_credential.dart';
import 'base_credential_refresher.dart';

class CredentialRefresherRegistry {
  final Map<AuthCredentialType, BaseCredentialRefresher> _refreshers =
      <AuthCredentialType, BaseCredentialRefresher>{};

  void register(
    AuthCredentialType credentialType,
    BaseCredentialRefresher refresher,
  ) {
    _refreshers[credentialType] = refresher;
  }

  BaseCredentialRefresher? getRefresher(AuthCredentialType credentialType) {
    return _refreshers[credentialType];
  }
}
