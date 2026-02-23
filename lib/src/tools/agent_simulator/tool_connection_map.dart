class StatefulParameter {
  StatefulParameter({
    required this.parameterName,
    List<String>? creatingTools,
    List<String>? consumingTools,
  }) : creatingTools = creatingTools ?? <String>[],
       consumingTools = consumingTools ?? <String>[];

  String parameterName;
  List<String> creatingTools;
  List<String> consumingTools;

  Map<String, Object?> toJson() => <String, Object?>{
    'parameter_name': parameterName,
    'creating_tools': List<String>.from(creatingTools),
    'consuming_tools': List<String>.from(consumingTools),
  };

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

class ToolConnectionMap {
  ToolConnectionMap({List<StatefulParameter>? statefulParameters})
    : statefulParameters = statefulParameters ?? <StatefulParameter>[];

  List<StatefulParameter> statefulParameters;

  Map<String, Object?> toJson() => <String, Object?>{
    'stateful_parameters': statefulParameters
        .map((StatefulParameter parameter) => parameter.toJson())
        .toList(growable: false),
  };

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
