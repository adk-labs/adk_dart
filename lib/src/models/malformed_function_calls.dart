/// Reports function calls whose arguments are not a JSON object.
library;

import 'dart:developer' as developer;

import 'llm_response.dart';

const Set<String?> _finishReasonsThatExplainNothing = <String?>{
  null,
  '',
  'STOP',
  'OTHER',
  'FINISH_REASON_UNSPECIFIED',
};

/// Marks a [response] that had function calls with malformed arguments.
///
/// A function call is malformed when its arguments are not a JSON object. The
/// caller leaves those calls out of the content and keeps the others. The
/// response reports `MALFORMED_FUNCTION_CALL`, or the finish reason it already
/// has when that says the model was cut short.
///
/// Mutates [response] in place and returns it. When [names] is empty,
/// [response] is returned untouched.
LlmResponse reportMalformedFunctionCalls(
  LlmResponse response,
  Iterable<Object?> names,
) {
  final List<Object?> nameList = names.toList(growable: false);
  if (nameList.isEmpty) {
    return response;
  }
  final String listed = nameList
      .map(
        (Object? name) =>
            (name is String && name.isNotEmpty) ? name : '<unnamed>',
      )
      .join(', ');
  developer.log(
    'Discarded function calls whose arguments are not a JSON object: $listed',
    name: 'adk_dart.models.malformed_function_calls',
    level: 900,
  );
  if (response.content != null && response.content!.parts.isEmpty) {
    response.content = null;
  }
  if (_finishReasonsThatExplainNothing.contains(response.finishReason)) {
    response.finishReason = 'MALFORMED_FUNCTION_CALL';
  }
  response.errorCode = response.finishReason;
  final String message =
      'Arguments for the following function calls were not a valid JSON '
      'object: $listed';
  response.errorMessage =
      (response.errorMessage != null && response.errorMessage!.isNotEmpty)
      ? '${response.errorMessage}. $message'
      : message;
  return response;
}
