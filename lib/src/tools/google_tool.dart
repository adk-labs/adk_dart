import 'dart:async';

import 'function_tool.dart';
import 'tool_context.dart';
import '_google_credentials.dart';

class GoogleTool extends FunctionTool {
  GoogleTool({
    required Function func,
    BaseGoogleCredentialsConfig? credentialsConfig,
    this.toolSettings,
    String? name,
    String? description,
    super.requireConfirmation,
  }) : _credentialsManager = credentialsConfig == null
           ? null
           : GoogleCredentialsManager(credentialsConfig),
       super(func: func, name: name, description: description);

  final GoogleCredentialsManager? _credentialsManager;
  final Object? toolSettings;

  @override
  Future<Object?> run({
    required Map<String, dynamic> args,
    required ToolContext toolContext,
  }) async {
    try {
      final Object? credentials = await _credentialsManager
          ?.getValidCredentials(toolContext);
      if (credentials == null && _credentialsManager != null) {
        return 'User authorization is required to access Google services for $name. Please complete the authorization flow.';
      }

      final Map<String, dynamic> enrichedArgs = Map<String, dynamic>.from(args);
      if (credentials != null) {
        enrichedArgs['credentials'] = credentials;
      }
      if (toolSettings != null) {
        enrichedArgs['settings'] = toolSettings;
      }

      try {
        return await super.run(args: enrichedArgs, toolContext: toolContext);
      } on StateError catch (error, stackTrace) {
        // Mirror Python behavior: only fall back when the callable signature
        // does not accept injected credentials/settings.
        if (!_isInvocationMismatchError(stackTrace)) {
          rethrow;
        }
        return super.run(args: args, toolContext: toolContext);
      }
    } catch (error) {
      return <String, Object?>{'status': 'ERROR', 'error_details': '$error'};
    }
  }

  bool _isInvocationMismatchError(StackTrace stackTrace) {
    final String firstFrame = stackTrace.toString().trim().split('\n').first;
    return firstFrame.contains('FunctionTool._invokeFunction') &&
        firstFrame.contains('function_tool.dart');
  }
}
