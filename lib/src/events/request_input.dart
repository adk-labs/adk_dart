/// Request-input event helpers for human-in-the-loop workflows.
library;

import '../flows/llm_flows/functions.dart';
import '../types/content.dart';
import '../types/id.dart';
import 'event.dart';

/// Data used to request additional user input from a workflow or agent.
class RequestInput {
  /// Creates a request-input payload.
  RequestInput({
    String? interruptId,
    this.payload,
    this.message,
    this.responseSchema,
  }) : interruptId = interruptId ?? newAdkId();

  /// Interrupt identifier used to match the eventual response.
  final String interruptId;

  /// Optional provider-specific payload for the client.
  final Object? payload;

  /// Optional message shown to the user.
  final String? message;

  /// Optional JSON schema describing the expected response.
  final Object? responseSchema;

  /// Serializes this request into function-call arguments.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'interruptId': interruptId,
      if (payload != null) 'payload': payload,
      if (message != null) 'message': message,
      if (responseSchema != null) 'response_schema': responseSchema,
    };
  }

  /// Creates a request-input payload from function-call arguments.
  factory RequestInput.fromJson(Map<String, Object?> json) {
    return RequestInput(
      interruptId: (json['interruptId'] ?? json['interrupt_id'] ?? json['id'])
          ?.toString(),
      payload: json['payload'],
      message: json['message']?.toString(),
      responseSchema: json['response_schema'] ?? json['responseSchema'],
    );
  }
}

/// Creates a long-running function-call event for [requestInput].
Event createRequestInputEvent(
  RequestInput requestInput, {
  String invocationId = '',
  String author = '',
  String? role,
}) {
  return Event(
    invocationId: invocationId,
    author: author,
    content: Content(
      role: role,
      parts: <Part>[
        Part.fromFunctionCall(
          name: requestInputFunctionCallName,
          id: requestInput.interruptId,
          args: requestInput.toJson(),
        ),
      ],
    ),
    longRunningToolIds: <String>{requestInput.interruptId},
  );
}

/// Creates a function-response part for a request-input interrupt.
Part createRequestInputResponse(
  String interruptId,
  Map<String, dynamic> response,
) {
  return Part.fromFunctionResponse(
    id: interruptId,
    name: requestInputFunctionCallName,
    response: response,
  );
}

/// Whether [event] contains a request-input function call.
bool hasRequestInputFunctionCall(Event event) {
  return event.getFunctionCalls().any(
    (FunctionCall call) => call.name == requestInputFunctionCallName,
  );
}

/// Returns request-input interrupt ids contained in [event].
List<String> getRequestInputInterruptIds(Event event) {
  return event
      .getFunctionCalls()
      .where((FunctionCall call) => call.name == requestInputFunctionCallName)
      .map((FunctionCall call) => call.id)
      .whereType<String>()
      .toList(growable: false);
}
