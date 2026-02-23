import '../auth_credential.dart';
import 'base_credential_exchanger.dart';

typedef ServiceAccountExchangeHandler =
    Future<AuthCredential?> Function(
      ServiceAccountAuth serviceAccount,
      String? authScheme,
    );

/// Optional exchanger hook for service-account based auth credentials.
class ServiceAccountCredentialExchanger extends BaseCredentialExchanger {
  ServiceAccountCredentialExchanger({this.exchangeHandler});

  final ServiceAccountExchangeHandler? exchangeHandler;

  @override
  Future<ExchangeResult> exchange({
    required AuthCredential authCredential,
    String? authScheme,
  }) async {
    if (authCredential.authType != AuthCredentialType.serviceAccount) {
      return ExchangeResult(credential: authCredential, wasExchanged: false);
    }

    final ServiceAccountAuth? serviceAccount = authCredential.serviceAccount;
    if (serviceAccount == null) {
      return ExchangeResult(credential: authCredential, wasExchanged: false);
    }

    final ServiceAccountExchangeHandler? handler = exchangeHandler;
    if (handler == null) {
      return ExchangeResult(credential: authCredential, wasExchanged: false);
    }

    try {
      final AuthCredential? exchanged = await handler(
        serviceAccount,
        authScheme,
      );
      if (exchanged == null) {
        return ExchangeResult(credential: authCredential, wasExchanged: false);
      }
      return ExchangeResult(credential: exchanged, wasExchanged: true);
    } catch (_) {
      return ExchangeResult(credential: authCredential, wasExchanged: false);
    }
  }
}
