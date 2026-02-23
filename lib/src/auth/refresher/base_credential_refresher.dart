import '../auth_credential.dart';

abstract class BaseCredentialRefresher {
  Future<bool> isRefreshNeeded({
    required AuthCredential authCredential,
    String? authScheme,
  });

  Future<AuthCredential> refresh({
    required AuthCredential authCredential,
    String? authScheme,
  });
}
