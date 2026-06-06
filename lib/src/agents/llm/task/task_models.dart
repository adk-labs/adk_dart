/// Data models for task-mode LLM agent delegation.
library;

/// A request to delegate work to a task agent.
class TaskRequest {
  /// Creates a task delegation request.
  TaskRequest({required this.agentName, Map<String, Object?>? input})
    : input = input ?? <String, Object?>{};

  /// Target agent name.
  final String agentName;

  /// Validated task input data.
  final Map<String, Object?> input;

  /// Creates a request from snake_case or camelCase JSON.
  factory TaskRequest.fromJson(Map<String, Object?> json) {
    return TaskRequest(
      agentName: '${json['agent_name'] ?? json['agentName'] ?? ''}',
      input: _toObjectMap(json['input']),
    );
  }

  /// Serializes this request using Python-compatible snake_case keys.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'agent_name': agentName,
      'input': Map<String, Object?>.from(input),
    };
  }
}

/// Result returned by a task agent after completion.
class TaskResult {
  /// Creates a task result.
  TaskResult({required this.output});

  /// Validated task output data.
  final Object? output;

  /// Creates a result from JSON.
  factory TaskResult.fromJson(Map<String, Object?> json) {
    return TaskResult(output: json['output']);
  }

  /// Serializes this task result.
  Map<String, Object?> toJson() {
    return <String, Object?>{'output': output};
  }
}

Map<String, Object?> _toObjectMap(Object? value) {
  if (value is Map<String, Object?>) {
    return Map<String, Object?>.from(value);
  }
  if (value is Map) {
    return value.map((Object? key, Object? item) => MapEntry('$key', item));
  }
  return <String, Object?>{};
}
