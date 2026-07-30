/// Plugin that provides self-healing model error recovery and reflection guidance.
library;

import 'dart:async';

import '../agents/callback_context.dart';
import '../agents/llm_agent.dart';
import '../models/llm_request.dart';
import '../models/llm_response.dart';
import '../tools/function_tool.dart';
import '../types/content.dart';
import 'base_plugin.dart';
import 'reflect_retry_tool_plugin.dart';

const String reservedToolCallErrorType = 'RESERVED_TOOL_CALL';

/// Provides self-healing, concurrent-safe error recovery for model failures.
class ReflectAndRetryModelPlugin extends BasePlugin {
  /// Creates a reflect-and-retry model plugin.
  ReflectAndRetryModelPlugin({
    super.name = 'reflect_retry_model_plugin',
    this.maxRetries = 3,
    this.throwExceptionIfRetryExceeded = true,
    this.trackingScope = TrackingScope.invocation,
    List<String>? onModelErrors,
  })  : assert(maxRetries >= 0, 'maxRetries must be a non-negative integer.'),
        onModelErrors = onModelErrors ?? <String>['MALFORMED_FUNCTION_CALL'];

  /// Maximum consecutive model failures before giving up.
  final int maxRetries;

  /// If true, returns/raises final error when retry limit is exceeded.
  final bool throwExceptionIfRetryExceeded;

  /// Scope used for tracking failure counters.
  final TrackingScope trackingScope;

  /// Finish reasons / error codes that should trigger reflection and retry.
  final List<String> onModelErrors;

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

  /// Internal framework function tool registered into the model request.
  Map<String, dynamic> adkHandleModelError({
    required String responseType,
    String? errorType,
    String? errorDetails,
    String? finishReason,
    required int retryCount,
  }) {
    return <String, dynamic>{
      'reflection_guidance': '''
The call to the model failed.

**Reflection Guidance:**
- This is retry attempt **$retryCount** of **$maxRetries**
- Analyze the error and the arguments you provided. Do not repeat the exact same call.

Formulate a new plan based on your analysis and try a corrected or different approach.
'''.trim(),
    };
  }

  @override
  Future<LlmResponse?> beforeModelCallback({
    required CallbackContext callbackContext,
    required LlmRequest llmRequest,
  }) async {
    _provideReflectionTool(llmRequest);
    return null;
  }

  @override
  Future<LlmResponse?> afterModelCallback({
    required CallbackContext callbackContext,
    required LlmResponse llmResponse,
  }) async {
    if (_hasReservedToolCall(llmResponse)) {
      return _handleReservedToolCall(
        callbackContext: callbackContext,
        llmResponse: llmResponse,
      );
    }

    if (_checkForModelError(llmResponse)) {
      return _handleModelError(
        callbackContext: callbackContext,
        llmResponse: llmResponse,
      );
    }

    final String scopeKey = _getModelScopeKey(callbackContext);
    final String modelName = _getModelNameFromContext(callbackContext);
    await _resetModelFailureCount(scopeKey, modelName);
    return null;
  }

  void _provideReflectionTool(LlmRequest llmRequest) {
    llmRequest.toolsDict['adkHandleModelError'] = FunctionTool(
      name: 'adkHandleModelError',
      description:
          'A tool that triggers reflection. Reserved for framework use only.',
      func: adkHandleModelError,
    );
  }

  bool _checkForModelError(LlmResponse llmResponse) {
    final String? errorCode = llmResponse.errorCode;
    if (errorCode == null || errorCode.isEmpty) {
      return false;
    }
    final String? finishReason = llmResponse.finishReason;
    return onModelErrors.contains(errorCode) ||
        (finishReason != null && onModelErrors.contains(finishReason));
  }

  bool _hasReservedToolCall(LlmResponse llmResponse) {
    final List<FunctionCall> calls = llmResponse.getFunctionCalls();
    for (final FunctionCall call in calls) {
      if (call.name == 'adkHandleModelError') {
        return true;
      }
    }
    return false;
  }

  Future<LlmResponse?> _handleReservedToolCall({
    required CallbackContext callbackContext,
    required LlmResponse llmResponse,
  }) async {
    final LlmResponse? retryResponse = await _handleModelRetry(
      callbackContext: callbackContext,
      llmResponse: llmResponse,
      errorType: reservedToolCallErrorType,
      errorDetails:
          'Model attempted to call reserved tool adkHandleModelError directly. This tool is reserved for framework use only. Do not call it.',
      finishReason: 'OTHER',
    );
    if (retryResponse != null) {
      return retryResponse;
    }

    return LlmResponse(
      errorCode: reservedToolCallErrorType,
      errorMessage:
          'Model attempted to call reserved tool and retry limit was exceeded.',
    );
  }

  Future<LlmResponse?> _handleModelError({
    required CallbackContext callbackContext,
    required LlmResponse llmResponse,
  }) async {
    final LlmResponse? retryResponse = await _handleModelRetry(
      callbackContext: callbackContext,
      llmResponse: llmResponse,
      errorType: llmResponse.errorCode,
      errorDetails: llmResponse.errorMessage,
      finishReason: llmResponse.finishReason,
    );
    if (retryResponse != null) {
      return retryResponse;
    }

    return llmResponse;
  }

  Future<LlmResponse?> _handleModelRetry({
    required CallbackContext callbackContext,
    required LlmResponse llmResponse,
    required String? errorType,
    required String? errorDetails,
    required String? finishReason,
  }) async {
    final String scopeKey = _getModelScopeKey(callbackContext);
    final String modelName = _getModelNameFromContext(callbackContext);

    final int currentRetries =
        await _incrementModelFailureCount(scopeKey, modelName);

    if (currentRetries <= maxRetries) {
      final Part retryPart = _generateModelRetryPart(
        retryCount: currentRetries,
        errorType: errorType,
        errorDetails: errorDetails,
        finishReason: finishReason,
      );
      return LlmResponse(
        content: Content(
          role: 'model',
          parts: <Part>[retryPart],
        ),
      );
    }

    return null;
  }

  Part _generateModelRetryPart({
    required int retryCount,
    required String? errorType,
    required String? errorDetails,
    required String? finishReason,
  }) {
    return Part.fromFunctionCall(
      name: 'adkHandleModelError',
      args: <String, dynamic>{
        'response_type': reflectAndRetryResponseType,
        'error_type': errorType,
        'error_details': errorDetails,
        'finish_reason': finishReason,
        'retry_count': retryCount,
      },
    );
  }

  String _getModelScopeKey(CallbackContext callbackContext) {
    switch (trackingScope) {
      case TrackingScope.invocation:
        return callbackContext.invocationContext.invocationId;
      case TrackingScope.global:
        return globalScopeKey;
    }
  }

  String _getModelNameFromContext(CallbackContext callbackContext) {
    final Object agent = callbackContext.invocationContext.agent;
    if (agent is LlmAgent && agent.model != null) {
      return '${agent.model}';
    }
    return 'default_model';
  }

  Future<int> _incrementModelFailureCount(
      String scopeKey, String modelName) async {
    return _synchronized<int>(() {
      final Map<String, int> counter =
          _scopedFailureCounters.putIfAbsent(scopeKey, () => <String, int>{});
      final int newCount = (counter[modelName] ?? 0) + 1;
      counter[modelName] = newCount;
      return newCount;
    });
  }

  Future<void> _resetModelFailureCount(
      String scopeKey, String modelName) async {
    await _synchronized<void>(() {
      final Map<String, int>? counter = _scopedFailureCounters[scopeKey];
      counter?.remove(modelName);
    });
  }
}
