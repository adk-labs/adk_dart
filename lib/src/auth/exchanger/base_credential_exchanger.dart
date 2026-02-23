import '../auth_credential.dart';

class CredentialExchangeError implements Exception {
  CredentialExchangeError(this.message);

  final String message;

  @override
  String toString() => 'CredentialExchangeError: $message';
}

class ExchangeResult {
  const ExchangeResult({required this.credential, required this.wasExchanged});

  final AuthCredential credential;
  final bool wasExchanged;
}

abstract class BaseCredentialExchanger {
  Future<ExchangeResult> exchange({
    required AuthCredential authCredential,
    String? authScheme,
  });
}
