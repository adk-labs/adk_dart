/// In-memory credential persistence implementation.
library;

import '../../agents/callback_context.dart';
import '../auth_credential.dart';
import '../auth_tool.dart';
import 'base_credential_service.dart';

/// Stores credentials in process memory keyed by app and user.
class InMemoryCredentialService extends BaseCredentialService {
  final Map<String, Map<String, Map<String, AuthCredential>>> _credentials =
      <String, Map<String, Map<String, AuthCredential>>>{};

  /// Loads a credential copy for [authConfig], if present.
  @override
  Future<AuthCredential?> loadCredential(
    AuthConfig authConfig,
    CallbackContext callbackContext,
  ) async {
    final Map<String, AuthCredential> bucket = _bucketFor(callbackContext);
    return bucket[authConfig.credentialKey]?.copyWith();
  }

  /// Saves a credential copy for [authConfig], when available.
  @override
  Future<void> saveCredential(
    AuthConfig authConfig,
    CallbackContext callbackContext,
  ) async {
    final Map<String, AuthCredential> bucket = _bucketFor(callbackContext);
    final AuthCredential? exchanged = authConfig.exchangedAuthCredential;
    if (exchanged == null) {
      if (bucket.containsKey(authConfig.credentialKey)) {
        bucket.remove(authConfig.credentialKey);
        return;
      }
      final AuthCredential? fallback = authConfig.rawAuthCredential;
      if (fallback == null) {
        return;
      }
      bucket[authConfig.credentialKey] = fallback.copyWith();
      return;
    }
    bucket[authConfig.credentialKey] = exchanged.copyWith();
  }

  Map<String, AuthCredential> _bucketFor(CallbackContext context) {
    final String appName = context.invocationContext.appName;
    final String userId = context.userId;
    return _credentials
        .putIfAbsent(appName, () => <String, Map<String, AuthCredential>>{})
        .putIfAbsent(userId, () => <String, AuthCredential>{});
  }
}
