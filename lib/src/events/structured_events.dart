/// Helpers for converting raw runtime events into typed event categories.
library;

import '../types/content.dart';
import 'event.dart';

/// Categories emitted by [toStructuredEvents].
enum EventType {
  /// Model reasoning text.
  thought('thought'),

  /// User-visible text content.
  content('content'),

  /// Model-requested tool call.
  toolCall('tool_call'),

  /// Tool execution result.
  toolResult('tool_result'),

  /// Model-requested code execution.
  callCode('call_code'),

  /// Code execution result.
  codeResult('code_result'),

  /// Runtime error.
  error('error'),

  /// Generic activity/status update.
  activity('activity'),

  /// Request for user confirmation of one or more tool calls.
  toolConfirmation('tool_confirmation'),

  /// Final response marker for the current turn.
  finished('finished');

  const EventType(this.wireName);

  /// Stable wire name matching the upstream JS event type values.
  final String wireName;
}

/// Base class for typed structured events.
abstract class StructuredEvent {
  /// Creates a structured event.
  const StructuredEvent(this.type);

  /// Category of this structured event.
  final EventType type;
}

/// Reasoning text emitted by the model.
class ThoughtEvent extends StructuredEvent {
  /// Creates a thought event.
  const ThoughtEvent(this.content) : super(EventType.thought);

  /// Thought text.
  final String content;
}

/// User-visible text content.
class ContentEvent extends StructuredEvent {
  /// Creates a content event.
  const ContentEvent(this.content) : super(EventType.content);

  /// Text content.
  final String content;
}

/// Request to execute a tool.
class ToolCallEvent extends StructuredEvent {
  /// Creates a tool-call event.
  const ToolCallEvent(this.call) : super(EventType.toolCall);

  /// Function call payload.
  final FunctionCall call;
}

/// Result returned by a tool.
class ToolResultEvent extends StructuredEvent {
  /// Creates a tool-result event.
  const ToolResultEvent(this.result) : super(EventType.toolResult);

  /// Function response payload.
  final FunctionResponse result;
}

/// Request to execute code.
class CallCodeEvent extends StructuredEvent {
  /// Creates a code-call event.
  const CallCodeEvent(this.code) : super(EventType.callCode);

  /// Provider-specific executable-code payload.
  final Object code;
}

/// Result of code execution.
class CodeResultEvent extends StructuredEvent {
  /// Creates a code-result event.
  const CodeResultEvent(this.result) : super(EventType.codeResult);

  /// Provider-specific code-execution-result payload.
  final Object result;
}

/// Runtime error event.
class ErrorEvent extends StructuredEvent {
  /// Creates an error event.
  ErrorEvent({required this.message, this.code, Object? error})
    : error = error ?? Exception(message),
      super(EventType.error);

  /// Error object matching the upstream structured-event shape.
  final Object error;

  /// Error message shown to callers.
  final String message;

  /// Optional provider/runtime error code.
  final String? code;
}

/// Alias for callers that prefer an unambiguous Dart-specific name.
typedef StructuredErrorEvent = ErrorEvent;

/// Generic activity or status event.
class ActivityEvent extends StructuredEvent {
  /// Creates an activity event.
  const ActivityEvent({required this.kind, Map<String, Object?>? detail})
    : detail = detail ?? const <String, Object?>{},
      super(EventType.activity);

  /// Activity kind.
  final String kind;

  /// Activity details.
  final Map<String, Object?> detail;
}

/// Request for user confirmation of tool calls.
class ToolConfirmationEvent extends StructuredEvent {
  /// Creates a tool-confirmation event.
  ToolConfirmationEvent(Map<String, Object> confirmations)
    : confirmations = Map<String, Object>.from(confirmations),
      super(EventType.toolConfirmation);

  /// Confirmation payloads keyed by tool-call ID.
  final Map<String, Object> confirmations;
}

/// Final response marker.
class FinishedEvent extends StructuredEvent {
  /// Creates a finished event.
  const FinishedEvent({this.output, this.hasOutput = false})
    : super(EventType.finished);

  /// Optional structured output attached to the source event.
  final Object? output;

  /// Whether [output] was explicitly present on the source event.
  final bool hasOutput;
}

/// Converts a raw [Event] into typed structured events.
///
/// The conversion mirrors the upstream JS helper while using the Dart event
/// model and [Event.isFinalResponse] for final-response detection.
List<StructuredEvent> toStructuredEvents(Event event) {
  final String? errorCode = event.errorCode;
  if (errorCode != null && errorCode.isNotEmpty) {
    return <StructuredEvent>[
      ErrorEvent(
        code: errorCode,
        message: (event.errorMessage == null || event.errorMessage!.isEmpty)
            ? errorCode
            : event.errorMessage!,
      ),
    ];
  }

  final List<StructuredEvent> events = <StructuredEvent>[];
  for (final Part part in event.content?.parts ?? const <Part>[]) {
    final FunctionCall? functionCall = part.functionCall;
    if (functionCall != null && !_isFunctionCallEmpty(functionCall)) {
      events.add(ToolCallEvent(functionCall));
      continue;
    }

    final FunctionResponse? functionResponse = part.functionResponse;
    if (functionResponse != null &&
        !_isFunctionResponseEmpty(functionResponse)) {
      events.add(ToolResultEvent(functionResponse));
      continue;
    }

    final Object? executableCode = part.executableCode;
    if (!_isEmptyPayload(executableCode)) {
      events.add(CallCodeEvent(executableCode!));
      continue;
    }

    final Object? codeExecutionResult = part.codeExecutionResult;
    if (!_isEmptyPayload(codeExecutionResult)) {
      events.add(CodeResultEvent(codeExecutionResult!));
      continue;
    }

    final String? text = part.text;
    if (text == null || text.isEmpty) {
      continue;
    }
    events.add(part.thought ? ThoughtEvent(text) : ContentEvent(text));
  }

  if (event.actions.requestedToolConfirmations.isNotEmpty) {
    events.add(ToolConfirmationEvent(event.actions.requestedToolConfirmations));
  }

  if (event.isFinalResponse()) {
    events.add(
      FinishedEvent(
        output: event.hasOutput ? event.output : null,
        hasOutput: event.hasOutput,
      ),
    );
  }

  return events;
}

bool _isFunctionCallEmpty(FunctionCall call) {
  return call.name.isEmpty &&
      call.args.isEmpty &&
      (call.id == null || call.id!.isEmpty) &&
      (call.partialArgs == null || call.partialArgs!.isEmpty) &&
      call.willContinue == null;
}

bool _isFunctionResponseEmpty(FunctionResponse response) {
  return response.name.isEmpty &&
      response.response.isEmpty &&
      (response.id == null || response.id!.isEmpty);
}

bool _isEmptyPayload(Object? value) {
  if (value == null) {
    return true;
  }
  if (value is String) {
    return value.isEmpty;
  }
  if (value is Map) {
    return value.isEmpty;
  }
  if (value is Iterable) {
    return value.isEmpty;
  }
  return false;
}
