import '../auth/auth_credential.dart';
import '../auth/auth_tool.dart';
import '../auth/credential_manager.dart';
import 'base_tool.dart';
import 'tool_context.dart';

abstract class BaseAuthenticatedTool extends BaseTool {
  BaseAuthenticatedTool({
    required super.name,
    required super.description,
    AuthConfig? authConfig,
    this.responseForAuthRequired,
  }) : _authConfig = authConfig,
       _credentialManager =
           (authConfig != null && authConfig.authScheme.isNotEmpty)
           ? CredentialManager(authConfig: authConfig)
           : null;

  final AuthConfig? _authConfig;
  final CredentialManager? _credentialManager;
  final Object? responseForAuthRequired;

  @override
  Future<Object?> run({
    required Map<String, dynamic> args,
    required ToolContext toolContext,
  }) async {
    AuthCredential? credential;
    if (_credentialManager != null && _authConfig != null) {
      credential = await _credentialManager.getAuthCredential(toolContext);
      if (credential == null) {
        await _credentialManager.requestCredential(toolContext);
        return responseForAuthRequired ?? 'Pending User Authorization.';
      }
    }
    return runAuthenticated(
      args: args,
      toolContext: toolContext,
      credential: credential,
    );
  }

  Future<Object?> runAuthenticated({
    required Map<String, dynamic> args,
    required ToolContext toolContext,
    required AuthCredential? credential,
  });
}
