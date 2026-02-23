import '../../../../auth/auth_credential.dart';
import 'base_credential_exchanger.dart';

typedef ServiceAccountTokenResolver =
    Future<String?> Function(ServiceAccountAuth serviceAccount);

class ServiceAccountCredentialExchanger extends BaseAuthCredentialExchanger {
  ServiceAccountCredentialExchanger({this.tokenResolver});

  final ServiceAccountTokenResolver? tokenResolver;

  @override
  Future<AuthCredential?> exchangeCredential(
    Object authScheme, [
    AuthCredential? authCredential,
  ]) async {
    final AuthCredential? credential = authCredential;
    final ServiceAccountAuth? serviceAccount = credential?.serviceAccount;
    if (credential == null ||
        serviceAccount == null ||
        (!serviceAccount.useDefaultCredential &&
            serviceAccount.serviceAccountCredential == null)) {
      throw AuthCredentialMissingError(
        'Service account credentials are missing. '
        'Provide serviceAccountCredential or set useDefaultCredential=true.',
      );
    }

    final ServiceAccountTokenResolver? resolver = tokenResolver;
    if (resolver == null) {
      return null;
    }
    final String? token = await resolver(serviceAccount);
    if (token == null || token.isEmpty) {
      throw AuthCredentialMissingError(
        'Failed to exchange service account token.',
      );
    }
    return AuthCredential(
      authType: AuthCredentialType.http,
      http: HttpAuth(
        scheme: 'bearer',
        credentials: HttpCredentials(token: token),
      ),
    );
  }
}
