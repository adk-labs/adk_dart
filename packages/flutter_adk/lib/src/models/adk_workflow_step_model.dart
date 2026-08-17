/// Execution status for a workflow pipeline step.
enum AdkStepStatus {
  /// Step is queued and waiting to run.
  pending,

  /// Step is actively executing.
  running,

  /// Step completed successfully.
  completed,

  /// Step execution encountered a failure.
  failed,

  /// Step was skipped by branching logic.
  skipped,
}

/// A structured model representing a single step in a multi-agent workflow.
class AdkWorkflowStep {
  /// Creates an [AdkWorkflowStep].
  const AdkWorkflowStep({
    required this.id,
    required this.label,
    this.description = '',
    this.status = .pending,
    this.output,
    this.errorMessage,
    this.startTime,
    this.endTime,
    this.metadata = const <String, dynamic>{},
  });

  /// Unique identifier of the step or node.
  final String id;

  /// Human-readable label displayed in the timeline.
  final String label;

  /// Detailed description of the step's goal.
  final String description;

  /// Current execution status.
  final AdkStepStatus status;

  /// Output data or artifact produced by this step.
  final dynamic output;

  /// Error message if [status] is [AdkStepStatus.failed].
  final String? errorMessage;

  /// Timestamp when step execution began.
  final DateTime? startTime;

  /// Timestamp when step execution concluded.
  final DateTime? endTime;

  /// Custom metadata tags associated with this step.
  final Map<String, dynamic> metadata;

  /// Total execution duration in milliseconds.
  int? get durationMs {
    if (startTime != null && endTime != null) {
      return endTime!.difference(startTime!).inMilliseconds;
    }
    return null;
  }

  /// Copies this [AdkWorkflowStep] with updated values.
  AdkWorkflowStep copyWith({
    String? id,
    String? label,
    String? description,
    AdkStepStatus? status,
    dynamic output,
    String? errorMessage,
    DateTime? startTime,
    DateTime? endTime,
    Map<String, dynamic>? metadata,
  }) {
    return AdkWorkflowStep(
      id: id ?? this.id,
      label: label ?? this.label,
      description: description ?? this.description,
      status: status ?? this.status,
      output: output ?? this.output,
      errorMessage: errorMessage ?? this.errorMessage,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      metadata: metadata ?? this.metadata,
    );
  }
}
