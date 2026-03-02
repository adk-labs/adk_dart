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

  @override
  /// Loads a credential copy for [authConfig], if present in state.
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

  @override
  /// Saves a credential copy for [authConfig] into state.
  Future<void> saveCredential(
    AuthConfig authConfig,
    CallbackContext callbackContext,
  ) async {
    final AuthCredential? credential =
        authConfig.exchangedAuthCredential ?? authConfig.rawAuthCredential;
    if (credential == null) {
      return;
    }
    final String key = '$statePrefix${authConfig.credentialKey}';
    callbackContext.state[key] = credential.copyWith();
  }
}
