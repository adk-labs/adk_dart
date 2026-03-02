/// Shared state model for agent implementations.
library;

/// Generic mutable state holder for agent-local state.
class BaseAgentState {
  /// Creates an agent state object.
  BaseAgentState({Map<String, Object?>? data})
    : data = data ?? <String, Object?>{};

  /// Serialized state payload.
  Map<String, Object?> data;

  /// Returns a JSON-safe copy of [data].
  Map<String, Object?> toJson() => Map<String, Object?>.from(data);

  /// Returns a deep copy of this state object.
  BaseAgentState copy() => BaseAgentState(data: toJson());
}
