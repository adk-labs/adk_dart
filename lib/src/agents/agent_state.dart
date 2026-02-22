class BaseAgentState {
  BaseAgentState({Map<String, Object?>? data})
    : data = data ?? <String, Object?>{};

  Map<String, Object?> data;

  Map<String, Object?> toJson() => Map<String, Object?>.from(data);

  BaseAgentState copy() => BaseAgentState(data: toJson());
}
