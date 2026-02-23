import 'dart:async';
import 'dart:convert';

import '../tools/base_tool.dart';
import '../tools/tool_context.dart';
import 'base_plugin.dart';

const String reflectAndRetryResponseType =
    'ERROR_HANDLED_BY_REFLECT_AND_RETRY_PLUGIN';
const String globalScopeKey = '__global_reflect_and_retry_scope__';

enum TrackingScope { invocation, global }

class ToolFailureResponse {
  ToolFailureResponse({
    this.responseType = reflectAndRetryResponseType,
    this.errorType = '',
    this.errorDetails = '',
    this.retryCount = 0,
    this.reflectionGuidance = '',
  });

  final String responseType;
  final String errorType;
  final String errorDetails;
  final int retryCount;
  final String reflectionGuidance;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'response_type': responseType,
      'error_type': errorType,
      'error_details': errorDetails,
      'retry_count': retryCount,
      'reflection_guidance': reflectionGuidance,
    };
  }
}

class ReflectAndRetryToolPlugin extends BasePlugin {
  ReflectAndRetryToolPlugin({
    super.name = 'reflect_retry_tool_plugin',
    this.maxRetries = 3,
    this.throwExceptionIfRetryExceeded = true,
    this.trackingScope = TrackingScope.invocation,
  }) : assert(maxRetries >= 0, 'maxRetries must be non-negative');

  final int maxRetries;
  final bool throwExceptionIfRetryExceeded;
  final TrackingScope trackingScope;

  final Map<String, Map<String, int>> _scopedFailureCounters =
      <String, Map<String, int>>{};

  Future<void> _lock = Future<void>.value();

  Future<T> _synchronized<T>(FutureOr<T> Function() action) {
    final Completer<T> completer = Completer<T>();
    _lock = _lock.then((_) async {
      try {
        completer.complete(await action());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  @override
  Future<Map<String, dynamic>?> afterToolCallback({
    required BaseTool tool,
    required Map<String, dynamic> toolArgs,
    required ToolContext toolContext,
    required Map<String, dynamic> result,
  }) async {
    if (result['response_type'] == reflectAndRetryResponseType) {
      return null;
    }

    final Object? error = await extractErrorFromResult(
      tool: tool,
      toolArgs: toolArgs,
      toolContext: toolContext,
      result: result,
    );

    if (error != null) {
      return _handleToolError(tool, toolArgs, toolContext, error);
    }

    await _resetFailuresForTool(toolContext, tool.name);
    return null;
  }

  Future<Object?> extractErrorFromResult({
    required BaseTool tool,
    required Map<String, dynamic> toolArgs,
    required ToolContext toolContext,
    required Map<String, dynamic> result,
  }) async {
    return null;
  }

  @override
  Future<Map<String, dynamic>?> onToolErrorCallback({
    required BaseTool tool,
    required Map<String, dynamic> toolArgs,
    required ToolContext toolContext,
    required Exception error,
  }) async {
    return _handleToolError(tool, toolArgs, toolContext, error);
  }

  Future<Map<String, dynamic>?> _handleToolError(
    BaseTool tool,
    Map<String, dynamic> toolArgs,
    ToolContext toolContext,
    Object error,
  ) async {
    if (maxRetries == 0) {
      if (throwExceptionIfRetryExceeded) {
        throw _ensureException(error);
      }
      return _getToolRetryExceedMessage(tool, toolArgs, error);
    }

    final String scopeKey = _getScopeKey(toolContext);
    return _synchronized<Map<String, dynamic>?>(() {
      final Map<String, int> toolFailureCounter = _scopedFailureCounters
          .putIfAbsent(scopeKey, () => <String, int>{});
      final int currentRetries = (toolFailureCounter[tool.name] ?? 0) + 1;
      toolFailureCounter[tool.name] = currentRetries;

      if (currentRetries <= maxRetries) {
        return _createToolReflectionResponse(
          tool,
          toolArgs,
          error,
          currentRetries,
        );
      }

      if (throwExceptionIfRetryExceeded) {
        throw _ensureException(error);
      }
      return _getToolRetryExceedMessage(tool, toolArgs, error);
    });
  }

  String _getScopeKey(ToolContext toolContext) {
    switch (trackingScope) {
      case TrackingScope.invocation:
        return toolContext.invocationId;
      case TrackingScope.global:
        return globalScopeKey;
    }
  }

  Future<void> _resetFailuresForTool(
    ToolContext toolContext,
    String toolName,
  ) async {
    final String scopeKey = _getScopeKey(toolContext);
    await _synchronized<void>(() {
      final Map<String, int>? state = _scopedFailureCounters[scopeKey];
      state?.remove(toolName);
    });
  }

  Exception _ensureException(Object error) {
    if (error is Exception) {
      return error;
    }
    return Exception('$error');
  }

  String _formatErrorDetails(Object error) {
    if (error is Exception) {
      return '${error.runtimeType}: $error';
    }
    return '$error';
  }

  Map<String, dynamic> _createToolReflectionResponse(
    BaseTool tool,
    Map<String, dynamic> toolArgs,
    Object error,
    int retryCount,
  ) {
    final String argsSummary = _safeJson(toolArgs);
    final String errorDetails = _formatErrorDetails(error);

    final String reflectionMessage =
        '''
The call to tool `${tool.name}` failed.

**Error Details:**
```
$errorDetails
```

**Tool Arguments Used:**
```json
$argsSummary
```

**Reflection Guidance:**
This is retry attempt **$retryCount of $maxRetries**. Analyze the error and the arguments you provided. Do not repeat the exact same call. Consider the following before your next attempt:

1.  **Invalid Parameters**: Does the error suggest that one or more arguments are incorrect, badly formatted, or missing? Review the tool's schema and your arguments.
2.  **State or Preconditions**: Did a previous step fail or not produce the necessary state/resource for this tool to succeed?
3.  **Alternative Approach**: Is this the right tool for the job? Could another tool or a different sequence of steps achieve the goal?
4.  **Simplify the Task**: Can you break the problem down into smaller, simpler steps?
5.  **Wrong Function Name**: Does the error indicates the tool is not found? Please check again and only use available tools.

Formulate a new plan based on your analysis and try a corrected or different approach.
''';

    return ToolFailureResponse(
      errorType: error is Exception ? '${error.runtimeType}' : 'ToolError',
      errorDetails: '$error',
      retryCount: retryCount,
      reflectionGuidance: reflectionMessage.trim(),
    ).toJson();
  }

  Map<String, dynamic> _getToolRetryExceedMessage(
    BaseTool tool,
    Map<String, dynamic> toolArgs,
    Object error,
  ) {
    final String errorDetails = _formatErrorDetails(error);
    final String argsSummary = _safeJson(toolArgs);

    final String reflectionMessage =
        '''
The tool `${tool.name}` has failed consecutively $maxRetries times and the retry limit has been exceeded.

**Last Error:**
```
$errorDetails
```

**Last Arguments Used:**
```json
$argsSummary
```

**Final Instruction:**
**Do not attempt to use the `${tool.name}` tool again for this task.** You must now try a different approach. Acknowledge the failure and devise a new strategy, potentially using other available tools or informing the user that the task cannot be completed.
''';

    return ToolFailureResponse(
      errorType: error is Exception ? '${error.runtimeType}' : 'ToolError',
      errorDetails: '$error',
      retryCount: maxRetries,
      reflectionGuidance: reflectionMessage.trim(),
    ).toJson();
  }

  String _safeJson(Map<String, dynamic> value) {
    try {
      const JsonEncoder encoder = JsonEncoder.withIndent('  ');
      return encoder.convert(value);
    } catch (_) {
      return value.toString();
    }
  }
}
