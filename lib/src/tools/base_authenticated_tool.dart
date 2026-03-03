/// Base abstractions for tools that require authenticated credentials.
library;

import '../auth/auth_credential.dart';
import '../auth/auth_tool.dart';
import '../auth/credential_manager.dart';
import 'base_tool.dart';
import 'tool_context.dart';

/// Base tool that resolves credentials before executing protected calls.
abstract class BaseAuthenticatedTool extends BaseTool {
  /// Creates an authenticated tool wrapper.
  ///
  /// If [authConfig] is present, credentials are loaded through an internal
  /// [CredentialManager] before [runAuthenticated] is called.
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

  /// Fallback payload returned when user authorization is still required.
  final Object? responseForAuthRequired;

  @override
  /// Resolves credentials and delegates to [runAuthenticated].
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

  /// Executes the tool with resolved [credential] information.
  Future<Object?> runAuthenticated({
    required Map<String, dynamic> args,
    required ToolContext toolContext,
    required AuthCredential? credential,
  });
}
