/// Base abstraction for custom auth integrations.
library;

import '../agents/context.dart';
import 'auth_credential.dart';
import 'auth_tool.dart';

/// Abstract provider that resolves credentials for a custom auth scheme.
abstract class BaseAuthProvider {
  /// Returns an auth credential for [authConfig] in [context], or `null`.
  Future<AuthCredential?> getAuthCredential(
    AuthConfig authConfig,
    Context context,
  );
}
