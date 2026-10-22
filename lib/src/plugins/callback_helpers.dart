/// Shared callback helpers and tool-result classification types for observability plugins.
library;

import '../events/event.dart';
import '../tools/base_tool.dart';
import '../tools/tool_context.dart';
import 'reflect_retry_tool_plugin.dart';

/// Error codes copied from an `LlmResponse` into [Event.errorCode] when the
/// model stops or is blocked.
///
/// These represent model termination reasons rather than durable workflow node
/// failures.
const Set<String> llmResponseErrorCodes = <String>{
  'FINISH_REASON_UNSPECIFIED',
  'STOP',
  'MAX_TOKENS',
  'SAFETY',
  'RECITATION',
  'LANGUAGE',
  'OTHER',
  'BLOCKLIST',
  'PROHIBITED_CONTENT',
  'SPII',
  'MALFORMED_FUNCTION_CALL',
  'IMAGE_SAFETY',
  'UNEXPECTED_TOOL_CALL',
  'IMAGE_PROHIBITED_CONTENT',
  'NO_IMAGE',
  'BLOCKED_REASON_UNSPECIFIED',
  'MODEL_ARMOR',
  'JAILBREAK',
};

const String _mcpToolErrorMessage =
    'Tool returned an MCP result with isError=true.';
const String _reflectAndRetryToolErrorMessage =
    'Tool raised an error that ReflectAndRetryToolPlugin handled.';
const String _classifiedToolErrorMessage =
    'tool_result_classifier classified the tool result as an error.';

const Set<String> _resultFieldNames = <String>{
  'response_type',
  'error_details',
  'error_type',
  'isError',
  'is_error',
};

/// Returns whether [event] reports that a durable workflow node failed.
///
/// Partial events and events whose [Event.errorCode] is a model finish or
/// blocked reason are not treated as workflow node failures.
bool isDurableNodeError(Event event) {
  final String? code = event.errorCode;
  return event.partial != true &&
      code != null &&
      code.isNotEmpty &&
      !llmResponseErrorCodes.contains(code);
}

/// Verdict returned by a [ToolResultClassifier] for a tool result.
///
/// ```dart
/// ToolResultClassification? classify({
///   required BaseTool tool,
///   required Map<String, dynamic> toolArgs,
///   required ToolContext toolContext,
///   required Object? result,
/// }) {
///   if (result is Map && result['status'] == 'ERROR') {
///     return ToolResultClassification(
///       status: 'ERROR',
///       errorMessage: 'Tool reported status=ERROR',
///     );
///   }
///   return null;
/// }
/// ```
class ToolResultClassification {
  /// Creates a tool result classification verdict.
  ///
  /// Throws an [ArgumentError] if [status] is not `'OK'` or `'ERROR'`.
  ToolResultClassification({required this.status, this.errorMessage}) {
    if (status != 'OK' && status != 'ERROR') {
      throw ArgumentError.value(
        status,
        'status',
        "status must be 'OK' or 'ERROR'.",
      );
    }
  }

  /// Classification status: `'OK'` for a completed call or `'ERROR'` for a
  /// tool error.
  final String status;

  /// Optional error message recorded when [status] is `'ERROR'`.
  final String? errorMessage;
}

/// Synchronous classifier signature used by observability plugins to classify
/// tool results that report failures without throwing.
typedef ToolResultClassifier =
    ToolResultClassification? Function({
      required BaseTool tool,
      required Map<String, dynamic> toolArgs,
      required ToolContext toolContext,
      required Object? result,
    });

Map<String, Object?> _extractResultFields(Object? result) {
  if (result is Map) {
    final Map<String, Object?> fields = <String, Object?>{};
    for (final MapEntry<Object?, Object?> entry in result.entries) {
      final Object? key = entry.key;
      if (key is String && _resultFieldNames.contains(key)) {
        fields[key] = entry.value;
      }
    }
    return fields;
  }
  return const <String, Object?>{};
}

String? _retryAnswerErrorMessage(Map<String, Object?> fields) {
  if (fields['response_type'] != reflectAndRetryResponseType) {
    return null;
  }
  for (final String key in const <String>['error_details', 'error_type']) {
    final Object? value = fields[key];
    if (value is String && value.isNotEmpty) {
      return value;
    }
  }
  return _reflectAndRetryToolErrorMessage;
}

String? _mcpErrorMessage(Map<String, Object?> fields) {
  if (fields['isError'] == true || fields['is_error'] == true) {
    return _mcpToolErrorMessage;
  }
  return null;
}

String? _classificationErrorMessage(ToolResultClassification classification) {
  if (classification.status == 'OK') {
    return null;
  }
  if (classification.status != 'ERROR') {
    throw ArgumentError('ToolResultClassification.status is not OK or ERROR.');
  }
  final String? message = classification.errorMessage;
  if (message == null || message.isEmpty) {
    return _classifiedToolErrorMessage;
  }
  return message;
}

/// Returns the error message to record when [result] reports a tool failure,
/// or `null` when [result] should be recorded as a completed tool call.
String? classifyToolResultError({
  required BaseTool tool,
  required Map<String, dynamic> toolArgs,
  required ToolContext toolContext,
  required Object? result,
  ToolResultClassifier? toolResultClassifier,
  void Function(String message)? onWarning,
}) {
  final Map<String, Object?> fields = _extractResultFields(result);
  final String? retryMessage = _retryAnswerErrorMessage(fields);
  if (retryMessage != null) {
    return retryMessage;
  }
  if (toolResultClassifier != null) {
    bool classifierFailed = false;
    try {
      final ToolResultClassification? classification = toolResultClassifier(
        tool: tool,
        toolArgs: toolArgs,
        toolContext: toolContext,
        result: result,
      );
      if (classification != null) {
        return _classificationErrorMessage(classification);
      }
    } on Exception {
      classifierFailed = true;
    } on Error {
      classifierFailed = true;
    }
    if (classifierFailed && onWarning != null) {
      onWarning(
        'tool_result_classifier failed or returned an unusable verdict for '
        'tool ${tool.name}; applying the built-in rule instead.',
      );
    }
  }
  return _mcpErrorMessage(fields);
}

final Expando<WeakReference<ToolContext>> _recordedToolErrorsByPlugin =
    Expando<WeakReference<ToolContext>>('adk_tool_errors_recorded');

/// Marks that [plugin] recorded the failure of [toolContext] in
/// `onToolErrorCallback`.
void markToolErrorRecorded(Object plugin, ToolContext toolContext) {
  _recordedToolErrorsByPlugin[plugin] = WeakReference<ToolContext>(toolContext);
}

/// Reports and clears whether [plugin] already recorded the failure of
/// [toolContext].
bool popToolErrorRecorded(Object plugin, ToolContext toolContext) {
  final WeakReference<ToolContext>? ref = _recordedToolErrorsByPlugin[plugin];
  if (ref == null || !identical(ref.target, toolContext)) {
    return false;
  }
  _recordedToolErrorsByPlugin[plugin] = null;
  return true;
}
