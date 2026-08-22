/// Authenticated wrapper for function-based tools.
library;

import '../auth/auth_credential.dart';
import '../models/llm_request.dart';
import 'base_authenticated_tool.dart';
import 'function_tool.dart';
import 'tool_context.dart';

/// Authenticated tool wrapper around a function tool delegate.
class AuthenticatedFunctionTool extends BaseAuthenticatedTool {
  /// Creates an authenticated wrapper around a function tool delegate.
  AuthenticatedFunctionTool({
    required Function func,
    required super.name,
    super.description = '',
    super.authConfig,
    super.responseForAuthRequired,
    Object requireConfirmation = false,
  }) : _delegate = FunctionTool(
         func: func,
         name: name,
         description: description,
         requireConfirmation: requireConfirmation,
       );

  final FunctionTool _delegate;

  @override
  FunctionDeclaration? getDeclaration() {
    return _delegate.getDeclaration();
  }

  @override
  Future<void> processLlmRequest({
    required ToolContext toolContext,
    required LlmRequest llmRequest,
  }) {
    return _delegate.processLlmRequest(
      toolContext: toolContext,
      llmRequest: llmRequest,
    );
  }

  @override
  Future<Object?> runAuthenticated({
    required Map<String, dynamic> args,
    required ToolContext toolContext,
    required AuthCredential? credential,
  }) async {
    if (credential == null) {
      return _delegate.run(args: args, toolContext: toolContext);
    }

    final Map<String, dynamic> argsWithCredential = <String, dynamic>{
      ...args,
      'credential': credential,
    };
    try {
      return await _delegate.run(
        args: argsWithCredential,
        toolContext: toolContext,
      );
    } catch (_) {
      return _delegate.run(args: args, toolContext: toolContext);
    }
  }
}
