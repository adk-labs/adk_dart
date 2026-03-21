/// Noop auth provider placeholder for GCP IAM connectors.
library;

import '../../agents/context.dart';
import '../../auth/auth_credential.dart';
import '../../auth/auth_tool.dart';
import '../../auth/base_auth_provider.dart';

/// Internal provider used for GCP IAM connector auth schemes.
class GcpAuthProvider extends BaseAuthProvider {
  @override
  Future<AuthCredential?> getAuthCredential(
    AuthConfig authConfig,
    Context context,
  ) {
    throw UnsupportedError('GcpAuthProvider is not yet implemented.');
  }
}
