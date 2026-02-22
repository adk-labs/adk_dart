import '../../agents/callback_context.dart';
import '../auth_credential.dart';
import '../auth_tool.dart';
import 'base_credential_service.dart';

class SessionStateCredentialService extends BaseCredentialService {
  SessionStateCredentialService({this.statePrefix = 'auth:'});

  final String statePrefix;

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
    final String key = '$statePrefix${authConfig.credentialKey}';
    callbackContext.state[key] = credential.copyWith();
  }
}
