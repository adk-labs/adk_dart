/// Service-account credential exchanger for OpenAPI tools.
library;

import '../../../../auth/auth_credential.dart';
import 'base_credential_exchanger.dart';

/// Callback used to exchange service-account auth for an access token.
typedef ServiceAccountTokenResolver =
    Future<String?> Function(ServiceAccountAuth serviceAccount);

/// Exchanges service-account credentials into HTTP bearer credentials.
class ServiceAccountCredentialExchanger extends BaseAuthCredentialExchanger {
  /// Creates a service-account exchanger with optional [tokenResolver].
  ServiceAccountCredentialExchanger({this.tokenResolver});

  /// Resolver used to mint or fetch an access token.
  final ServiceAccountTokenResolver? tokenResolver;

  /// Exchanges [authCredential] for [authScheme] using [tokenResolver].
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
    if (serviceAccount.useIdToken &&
        (serviceAccount.audience == null || serviceAccount.audience!.isEmpty)) {
      throw AuthCredentialMissingError(
        'audience is required when useIdToken=true for service account auth.',
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
