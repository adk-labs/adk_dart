/// Credential persistence interfaces for auth flows.
library;

import '../../agents/callback_context.dart';
import '../auth_credential.dart';
import '../auth_tool.dart';

/// Storage interface for loading and saving auth credentials.
abstract class BaseCredentialService {
  /// Loads a credential for [authConfig] within [callbackContext].
  Future<AuthCredential?> loadCredential(
    AuthConfig authConfig,
    CallbackContext callbackContext,
  );

  /// Saves a credential for [authConfig] within [callbackContext].
  Future<void> saveCredential(
    AuthConfig authConfig,
    CallbackContext callbackContext,
  );
}
