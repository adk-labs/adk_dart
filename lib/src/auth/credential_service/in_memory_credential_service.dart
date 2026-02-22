import '../../agents/callback_context.dart';
import '../auth_credential.dart';
import '../auth_tool.dart';
import 'base_credential_service.dart';

class InMemoryCredentialService extends BaseCredentialService {
  final Map<String, Map<String, Map<String, AuthCredential>>> _credentials =
      <String, Map<String, Map<String, AuthCredential>>>{};

  @override
  Future<AuthCredential?> loadCredential(
    AuthConfig authConfig,
    CallbackContext callbackContext,
  ) async {
    final Map<String, AuthCredential> bucket = _bucketFor(callbackContext);
    return bucket[authConfig.credentialKey]?.copyWith();
  }

  @override
  Future<void> saveCredential(
    AuthConfig authConfig,
    CallbackContext callbackContext,
  ) async {
    final AuthCredential? credential =
        authConfig.exchangedAuthCredential ?? authConfig.rawAuthCredential;
    if (credential == null) {
      return;
    }
    final Map<String, AuthCredential> bucket = _bucketFor(callbackContext);
    bucket[authConfig.credentialKey] = credential.copyWith();
  }

  Map<String, AuthCredential> _bucketFor(CallbackContext context) {
    final String appName = context.invocationContext.appName;
    final String userId = context.userId;
    return _credentials
        .putIfAbsent(appName, () => <String, Map<String, AuthCredential>>{})
        .putIfAbsent(userId, () => <String, AuthCredential>{});
  }
}
