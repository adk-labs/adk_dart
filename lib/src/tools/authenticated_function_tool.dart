import '../auth/auth_credential.dart';
import '../auth/auth_tool.dart';
import '../models/llm_request.dart';
import 'base_authenticated_tool.dart';
import 'function_tool.dart';
import 'tool_context.dart';

class AuthenticatedFunctionTool extends BaseAuthenticatedTool {
  AuthenticatedFunctionTool({
    required Function func,
    required String name,
    String description = '',
    AuthConfig? authConfig,
    Object? responseForAuthRequired,
    Object requireConfirmation = false,
  }) : _delegate = FunctionTool(
         func: func,
         name: name,
         description: description,
         requireConfirmation: requireConfirmation,
       ),
       super(
         name: name,
         description: description,
         authConfig: authConfig,
         responseForAuthRequired: responseForAuthRequired,
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
