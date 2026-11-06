/// Session-state-backed credential persistence implementation.
library;

import '../../agents/callback_context.dart';
import '../auth_credential.dart';
import '../auth_tool.dart';
import 'base_credential_service.dart';

/// Stores credentials in callback context state.
class SessionStateCredentialService extends BaseCredentialService {
  /// Creates a session-state credential service.
  SessionStateCredentialService({this.statePrefix = 'auth:'});

  /// State key prefix for persisted credentials.
  final String statePrefix;

  /// Loads a credential copy for [authConfig], if present in state.
  @override
  Future<AuthCredential?> loadCredential(
    AuthConfig authConfig,
    CallbackContext callbackContext,
  ) async {
    final String key = '$statePrefix${authConfig.credentialKey}';
    final Object? raw = callbackContext.state[key];
    if (raw is! AuthCredential) {
      return null;
    }
    return raw.copyWith();
  }

  /// Saves a credential copy for [authConfig] into state.
  @override
  Future<void> saveCredential(
    AuthConfig authConfig,
    CallbackContext callbackContext,
  ) async {
    final String key = '$statePrefix${authConfig.credentialKey}';
    final AuthCredential? exchanged = authConfig.exchangedAuthCredential;
    if (exchanged == null) {
      if (callbackContext.state[key] != null) {
        callbackContext.state[key] = null;
        return;
      }
      final AuthCredential? fallback = authConfig.rawAuthCredential;
      if (fallback == null) {
        return;
      }
      callbackContext.state[key] = fallback.copyWith();
      return;
    }
    callbackContext.state[key] = exchanged.copyWith();
  }
}
