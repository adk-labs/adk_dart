/// Status of an agent tool execution turn.
enum AdkToolStatus {
  /// Tool call is queued or awaiting approval.
  pending,

  /// Tool is currently executing.
  running,

  /// Tool executed successfully with a return value.
  success,

  /// Tool execution failed with an error.
  error,
}

/// A structured model representing an executed or active tool call turn.
class AdkToolCallInfo {
  /// Creates an [AdkToolCallInfo].
  const AdkToolCallInfo({
    required this.toolName,
    this.callId,
    this.arguments = const <String, dynamic>{},
    this.result,
    this.status = AdkToolStatus.success,
    this.startTime,
    this.endTime,
    this.errorMessage,
  });

  /// The unique call identifier if provided by the model.
  final String? callId;

  /// The name of the invoked tool.
  final String toolName;

  /// The input parameters/arguments passed to the tool.
  final Map<String, dynamic> arguments;

  /// The result returned from tool execution.
  final dynamic result;

  /// The lifecycle status of this tool call.
  final AdkToolStatus status;

  /// Timestamp when execution began.
  final DateTime? startTime;

  /// Timestamp when execution concluded.
  final DateTime? endTime;

  /// Error message if [status] is [AdkToolStatus.error].
  final String? errorMessage;

  /// Total execution duration in milliseconds if timestamps are available.
  int? get durationMs {
    if (startTime != null && endTime != null) {
      return endTime!.difference(startTime!).inMilliseconds;
    }
    return null;
  }

  /// Copies this [AdkToolCallInfo] with optional updated fields.
  AdkToolCallInfo copyWith({
    String? callId,
    String? toolName,
    Map<String, dynamic>? arguments,
    dynamic result,
    AdkToolStatus? status,
    DateTime? startTime,
    DateTime? endTime,
    String? errorMessage,
  }) {
    return AdkToolCallInfo(
      callId: callId ?? this.callId,
      toolName: toolName ?? this.toolName,
      arguments: arguments ?? this.arguments,
      result: result ?? this.result,
      status: status ?? this.status,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}
