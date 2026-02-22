import '../../agents/callback_context.dart';
import '../auth_credential.dart';
import '../auth_tool.dart';

abstract class BaseCredentialService {
  Future<AuthCredential?> loadCredential(
    AuthConfig authConfig,
    CallbackContext callbackContext,
  );

  Future<void> saveCredential(
    AuthConfig authConfig,
    CallbackContext callbackContext,
  );
}
