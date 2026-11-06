/// Plugin hooks and implementations for ADK runtime pipelines.
library;

import 'dart:async';
import 'dart:convert';

import '../agents/invocation_context.dart';
import '../events/event.dart';
import '../tools/base_tool.dart';
import '../tools/tool_context.dart';
import '../types/content.dart';
import 'base_plugin.dart';

/// Returns whether [invocationContext] ended in a paused state awaiting
/// long-running tool results, tool confirmation, or authentication.
bool isPausedInvocation(InvocationContext invocationContext) {
  final Set<String> openInterrupts = <String>{};
  final Map<String, String> childToOriginalId = <String, String>{};
  final Map<String, Set<String>> originalToChildIds = <String, Set<String>>{};

  for (final Event event in invocationContext.session.events) {
    if (event.invocationId != invocationContext.invocationId) {
      continue;
    }

    if (event.longRunningToolIds != null) {
      openInterrupts.addAll(event.longRunningToolIds!);
    }
    openInterrupts.addAll(event.actions.requestedToolConfirmations.keys);
    openInterrupts.addAll(event.actions.requestedAuthConfigs.keys);

    for (final FunctionCall call in event.getFunctionCalls()) {
      final String? callId = call.id;
      if (callId == null || callId.isEmpty) {
        continue;
      }
      if (event.longRunningToolIds?.contains(callId) == true ||
          event.actions.requestedToolConfirmations.containsKey(callId) ||
          event.actions.requestedAuthConfigs.containsKey(callId)) {
        openInterrupts.add(callId);
      }
      final Object? originalCall = call.args['originalFunctionCall'];
      if (originalCall is Map && originalCall['id'] is String) {
        final String origId = originalCall['id'] as String;
        childToOriginalId[callId] = origId;
        originalToChildIds.putIfAbsent(origId, () => <String>{}).add(callId);
      }
      final Object? authCallId =
          call.args['function_call_id'] ?? call.args['functionCallId'];
      if (authCallId is String && authCallId.isNotEmpty) {
        childToOriginalId[callId] = authCallId;
        originalToChildIds
            .putIfAbsent(authCallId, () => <String>{})
            .add(callId);
      }
    }

    for (final FunctionResponse response in event.getFunctionResponses()) {
      final String? id = response.id;
      if (id == null || id.isEmpty) {
        continue;
      }
      final bool isReflectAndRetryFailure =
          response.response['response_type'] == reflectAndRetryResponseType;
      if (!isReflectAndRetryFailure &&
          (event.actions.requestedToolConfirmations.containsKey(id) ||
              event.actions.requestedAuthConfigs.containsKey(id))) {
        continue;
      }
      openInterrupts.remove(id);
      final String? origId = childToOriginalId[id];
      if (origId != null) {
        openInterrupts.remove(origId);
      }
      final Set<String>? children = originalToChildIds[id];
      if (children != null) {
        openInterrupts.removeAll(children);
      }
    }
  }

  return openInterrupts.isNotEmpty;
}

/// Response type emitted when this plugin handles a tool failure.
const String reflectAndRetryResponseType =
    'ERROR_HANDLED_BY_REFLECT_AND_RETRY_PLUGIN';

/// Global scope key used when failure counters are shared process-wide.
const String globalScopeKey = '__global_reflect_and_retry_scope__';

/// Scope used to track per-tool retry counts.
enum TrackingScope {
  /// Tracks failure counts per individual invocation.
  invocation,

  /// Tracks failure counts globally across invocations in the process.
  global,
}

/// Structured tool failure payload returned by reflect-and-retry flows.
class ToolFailureResponse {
  /// Creates a tool failure response payload.
  ToolFailureResponse({
    this.responseType = reflectAndRetryResponseType,
    this.errorType = '',
    this.errorDetails = '',
    this.retryCount = 0,
    this.reflectionGuidance = '',
  });

  /// Response type marker.
  final String responseType;

  /// Error class/type string.
  final String errorType;

  /// Error details string.
  final String errorDetails;

  /// Current retry count.
  final int retryCount;

  /// Guidance for model self-correction.
  final String reflectionGuidance;

  /// Serializes this failure response to JSON.
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

/// Context passed to custom guidance callbacks when a tool fails.
class ToolReflectionContext {
  /// Creates a tool reflection context.
  const ToolReflectionContext({
    required this.tool,
    required this.toolArgs,
    required this.toolContext,
    required this.error,
    required this.errorType,
    required this.errorDetails,
    required this.retryCount,
    required this.maxRetries,
  });

  /// The tool that failed.
  final BaseTool tool;

  /// The arguments passed to the tool.
  final Map<String, dynamic> toolArgs;

  /// The tool execution context.
  final ToolContext toolContext;

  /// The exception or error object extracted from the tool execution.
  final Object error;

  /// The error type string (e.g. exception class name or `'ToolError'`).
  final String errorType;

  /// Formatted error details string.
  final String errorDetails;

  /// The current retry attempt (1-indexed), or `maxRetries` when retry limit is exceeded.
  final int retryCount;

  /// Maximum retries configured on the plugin.
  final int maxRetries;
}

/// Callback signature for generating custom tool reflection or retry-exceeded guidance.
typedef ToolGuidanceCallback =
    FutureOr<String?> Function(ToolReflectionContext context);

/// Plugin that provides reflection guidance and bounded retries for tool errors.
class ReflectAndRetryToolPlugin extends BasePlugin {
  /// Creates a reflect-and-retry plugin.
  ReflectAndRetryToolPlugin({
    super.name = 'reflect_retry_tool_plugin',
    this.maxRetries = 3,
    this.throwExceptionIfRetryExceeded = true,
    this.trackingScope = TrackingScope.invocation,
    this.reflectionGuidance,
    this.retryExceededGuidance,
  }) : assert(maxRetries >= 0, 'maxRetries must be non-negative') {
    _validateGuidance(reflectionGuidance, 'reflectionGuidance');
    _validateGuidance(retryExceededGuidance, 'retryExceededGuidance');
  }

  static void _validateGuidance(Object? value, String paramName) {
    if (value != null && value is! String && value is! Function) {
      throw ArgumentError.value(
        value,
        paramName,
        '$paramName must be a String, a callable, or null.',
      );
    }
  }

  /// Maximum retry attempts allowed per tool.
  final int maxRetries;

  /// Whether to throw when retry limit is exceeded.
  final bool throwExceptionIfRetryExceeded;

  /// Scope used for tracking retry counters.
  final TrackingScope trackingScope;

  /// Optional custom guidance (`String` or [ToolGuidanceCallback]) appended to
  /// retry reflection messages.
  final Object? reflectionGuidance;

  /// Optional custom guidance (`String` or [ToolGuidanceCallback]) appended to
  /// retry-exceeded messages.
  final Object? retryExceededGuidance;

  final Map<String, Map<String, int>> _scopedFailureCounters =
      <String, Map<String, int>>{};
  final Expando<bool> _declinedCalls = Expando<bool>(
    'reflect_retry_declined_calls',
  );

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

  /// Intercepts successful tool results and checks for embedded errors.
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
    final String? callId = toolContext.functionCallId;
    if (callId != null &&
        (toolContext.actions.requestedToolConfirmations.containsKey(callId) ||
            toolContext.actions.requestedAuthConfigs.containsKey(callId))) {
      return null;
    }
    final bool wasDeclined = await _synchronized<bool>(() {
      if (_declinedCalls[toolContext] == true) {
        _declinedCalls[toolContext] = null;
        return true;
      }
      return false;
    });
    if (wasDeclined) {
      return null;
    }

    final Object? error = await extractErrorFromResult(
      tool: tool,
      toolArgs: toolArgs,
      toolContext: toolContext,
      result: result,
    );

    if (error != null) {
      return _handleToolError(
        tool,
        toolArgs,
        toolContext,
        error,
        fromOnToolError: false,
      );
    }

    await _resetFailuresForTool(toolContext, tool.name);
    return null;
  }

  /// Extracts an error object from tool [result], if present.
  Future<Object?> extractErrorFromResult({
    required BaseTool tool,
    required Map<String, dynamic> toolArgs,
    required ToolContext toolContext,
    required Map<String, dynamic> result,
  }) async {
    return null;
  }

  /// Handles tool exceptions and returns retry guidance payloads.
  @override
  Future<Map<String, dynamic>?> onToolErrorCallback({
    required BaseTool tool,
    required Map<String, dynamic> toolArgs,
    required ToolContext toolContext,
    required Exception error,
  }) async {
    return _handleToolError(
      tool,
      toolArgs,
      toolContext,
      error,
      fromOnToolError: true,
    );
  }

  @override
  Future<void> afterRunCallback({
    required InvocationContext invocationContext,
  }) async {
    if (isPausedInvocation(invocationContext)) {
      return;
    }
    await _forgetInvocation(invocationContext.invocationId);
  }

  @override
  Future<void> onRunErrorCallback({
    required InvocationContext invocationContext,
    required Object error,
  }) async {
    await _forgetInvocation(invocationContext.invocationId);
  }

  Future<void> _forgetInvocation(String invocationId) async {
    if (trackingScope != TrackingScope.invocation) {
      return;
    }
    await _synchronized<void>(() {
      _scopedFailureCounters.remove(invocationId);
    });
  }

  Future<Map<String, dynamic>?> _handleToolError(
    BaseTool tool,
    Map<String, dynamic> toolArgs,
    ToolContext toolContext,
    Object error, {
    required bool fromOnToolError,
  }) async {
    if (maxRetries == 0) {
      if (throwExceptionIfRetryExceeded) {
        if (fromOnToolError) {
          await _synchronized<void>(() {
            _declinedCalls[toolContext] = true;
          });
        }
        throw _ensureException(error);
      }
      return _getToolRetryExceedMessage(tool, toolArgs, toolContext, error);
    }

    final String scopeKey = _getScopeKey(toolContext);
    return _synchronized<Map<String, dynamic>?>(() async {
      final Map<String, int> toolFailureCounter = _scopedFailureCounters
          .putIfAbsent(scopeKey, () => <String, int>{});
      final int currentRetries = (toolFailureCounter[tool.name] ?? 0) + 1;
      toolFailureCounter[tool.name] = currentRetries;

      if (currentRetries <= maxRetries) {
        return _createToolReflectionResponse(
          tool,
          toolArgs,
          toolContext,
          error,
          currentRetries,
        );
      }

      if (throwExceptionIfRetryExceeded) {
        if (fromOnToolError) {
          _declinedCalls[toolContext] = true;
        }
        throw _ensureException(error);
      }
      return _getToolRetryExceedMessage(tool, toolArgs, toolContext, error);
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

  String _formatErrorType(Object error) {
    return error is Exception ? '${error.runtimeType}' : 'ToolError';
  }

  Future<String?> _resolveGuidance(
    Object? guidance,
    ToolReflectionContext context,
  ) async {
    if (guidance == null) {
      return null;
    }
    final String? text;
    if (guidance is String) {
      text = guidance;
    } else if (guidance is ToolGuidanceCallback) {
      text = await guidance(context);
    } else if (guidance is Function) {
      final Object? result = await Function.apply(guidance, <Object?>[context]);
      text = result as String?;
    } else {
      return null;
    }
    if (text == null) {
      return null;
    }
    final String trimmed = text.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  Future<Map<String, dynamic>> _createToolReflectionResponse(
    BaseTool tool,
    Map<String, dynamic> toolArgs,
    ToolContext toolContext,
    Object error,
    int retryCount,
  ) async {
    final String argsSummary = _safeJson(toolArgs);
    final String errorDetails = _formatErrorDetails(error);
    final String errorType = _formatErrorType(error);
    final String? customGuidance = await _resolveGuidance(
      reflectionGuidance,
      ToolReflectionContext(
        tool: tool,
        toolArgs: Map<String, dynamic>.from(toolArgs),
        toolContext: toolContext,
        error: error,
        errorType: errorType,
        errorDetails: errorDetails,
        retryCount: retryCount,
        maxRetries: maxRetries,
      ),
    );
    final String customSection = customGuidance == null
        ? ''
        : '\n\n**Custom Guidance:**\n$customGuidance';

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
5.  **Wrong Function Name**: Does the error indicates the tool is not found? Please check again and only use available tools.$customSection

Formulate a new plan based on your analysis and try a corrected or different approach.
''';

    return ToolFailureResponse(
      errorType: errorType,
      errorDetails: '$error',
      retryCount: retryCount,
      reflectionGuidance: reflectionMessage.trim(),
    ).toJson();
  }

  Future<Map<String, dynamic>> _getToolRetryExceedMessage(
    BaseTool tool,
    Map<String, dynamic> toolArgs,
    ToolContext toolContext,
    Object error,
  ) async {
    final String errorDetails = _formatErrorDetails(error);
    final String errorType = _formatErrorType(error);
    final String argsSummary = _safeJson(toolArgs);
    final String? customGuidance = await _resolveGuidance(
      retryExceededGuidance,
      ToolReflectionContext(
        tool: tool,
        toolArgs: Map<String, dynamic>.from(toolArgs),
        toolContext: toolContext,
        error: error,
        errorType: errorType,
        errorDetails: errorDetails,
        retryCount: maxRetries,
        maxRetries: maxRetries,
      ),
    );
    final String customSection = customGuidance == null
        ? ''
        : '\n\n**Custom Guidance:**\n$customGuidance';

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
**Do not attempt to use the `${tool.name}` tool again for this task.** You must now try a different approach. Acknowledge the failure and devise a new strategy, potentially using other available tools or informing the user that the task cannot be completed.$customSection
''';

    return ToolFailureResponse(
      errorType: errorType,
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
