/// One stateful parameter and the tools that create or consume it.
class StatefulParameter {
  /// Creates a stateful parameter mapping entry.
  StatefulParameter({
    required this.parameterName,
    List<String>? creatingTools,
    List<String>? consumingTools,
  }) : creatingTools = creatingTools ?? <String>[],
       consumingTools = consumingTools ?? <String>[];

  /// Parameter name shared across tools.
  String parameterName;

  /// Tools that create or mutate resources keyed by this parameter.
  List<String> creatingTools;

  /// Tools that read resources keyed by this parameter.
  List<String> consumingTools;

  /// Encodes this mapping entry to JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'parameter_name': parameterName,
    'creating_tools': List<String>.from(creatingTools),
    'consuming_tools': List<String>.from(consumingTools),
  };

  /// Decodes a mapping entry from JSON.
  factory StatefulParameter.fromJson(Map<String, Object?> json) {
    return StatefulParameter(
      parameterName: '${json['parameter_name'] ?? ''}',
      creatingTools: (json['creating_tools'] as List?)
          ?.map((Object? value) => '$value')
          .toList(),
      consumingTools: (json['consuming_tools'] as List?)
          ?.map((Object? value) => '$value')
          .toList(),
    );
  }
}

/// Tool-state dependency map discovered by the analyzer.
class ToolConnectionMap {
  /// Creates a tool connection map.
  ToolConnectionMap({List<StatefulParameter>? statefulParameters})
    : statefulParameters = statefulParameters ?? <StatefulParameter>[];

  /// Stateful parameter mappings used by simulation strategies.
  List<StatefulParameter> statefulParameters;

  /// Encodes this map to JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'stateful_parameters': statefulParameters
        .map((StatefulParameter parameter) => parameter.toJson())
        .toList(growable: false),
  };

  /// Decodes a tool connection map from JSON.
  factory ToolConnectionMap.fromJson(Map<String, Object?> json) {
    final List<StatefulParameter> parameters = <StatefulParameter>[];
    final Object? raw = json['stateful_parameters'];
    if (raw is List) {
      for (final Object? value in raw) {
        if (value is Map) {
          parameters.add(
            StatefulParameter.fromJson(
              value.map(
                (Object? key, Object? value) =>
                    MapEntry<String, Object?>('$key', value),
              ),
            ),
          );
        }
      }
    }
    return ToolConnectionMap(statefulParameters: parameters);
  }
}
