import '../../../../auth/auth_credential.dart';
import 'base_credential_exchanger.dart';
import 'oauth2_exchanger.dart';
import 'service_account_exchanger.dart';

/// Credential exchanger that delegates by [AuthCredentialType].
class AutoAuthCredentialExchanger extends BaseAuthCredentialExchanger {
  /// Creates an auto exchanger with optional [customExchangers].
  AutoAuthCredentialExchanger({
    Map<AuthCredentialType, BaseAuthCredentialExchanger>? customExchangers,
  }) : exchangers = <AuthCredentialType, BaseAuthCredentialExchanger>{
         AuthCredentialType.oauth2: OAuth2CredentialExchanger(),
         AuthCredentialType.openIdConnect: OAuth2CredentialExchanger(),
         AuthCredentialType.serviceAccount: ServiceAccountCredentialExchanger(),
         ...?customExchangers,
       };

  /// Registered exchangers by credential type.
  final Map<AuthCredentialType, BaseAuthCredentialExchanger> exchangers;

  /// Exchanges [authCredential] using a registered type-specific exchanger.
  @override
  Future<AuthCredential?> exchangeCredential(
    Object authScheme, [
    AuthCredential? authCredential,
  ]) async {
    final AuthCredential? credential = authCredential;
    if (credential == null) {
      return null;
    }
    final BaseAuthCredentialExchanger? exchanger =
        exchangers[credential.authType];
    if (exchanger == null) {
      return credential;
    }
    return exchanger.exchangeCredential(authScheme, credential);
  }
}
