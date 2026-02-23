import 'eval_case.dart';

class EvalSet {
  EvalSet({
    required this.evalSetId,
    this.name,
    this.description,
    List<EvalCase>? evalCases,
    this.creationTimestamp = 0,
  }) : evalCases = evalCases ?? <EvalCase>[];

  final String evalSetId;
  final String? name;
  final String? description;
  List<EvalCase> evalCases;
  final double creationTimestamp;

  factory EvalSet.fromJson(Map<String, Object?> json) {
    final Object? rawCases = json['evalCases'] ?? json['eval_cases'];
    final List<EvalCase> cases = <EvalCase>[];
    if (rawCases is List) {
      for (final Object? item in rawCases) {
        if (item is Map) {
          cases.add(EvalCase.fromJson(_castJsonMap(item)));
        }
      }
    }

    return EvalSet(
      evalSetId: (json['evalSetId'] ?? json['eval_set_id'] ?? '') as String,
      name: (json['name'] as String?),
      description: (json['description'] as String?),
      evalCases: cases,
      creationTimestamp: _asDouble(
        json['creationTimestamp'] ?? json['creation_timestamp'],
      ),
    );
  }

  Map<String, Object?> toJson({bool includeNulls = false}) {
    return <String, Object?>{
      'eval_set_id': evalSetId,
      if (includeNulls || name != null) 'name': name,
      if (includeNulls || description != null) 'description': description,
      'eval_cases': evalCases.map((EvalCase value) => value.toJson()).toList(),
      'creation_timestamp': creationTimestamp,
    };
  }
}

double _asDouble(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  return 0;
}

Map<String, Object?> _castJsonMap(Map map) {
  return map.map((Object? key, Object? value) {
    return MapEntry(key.toString(), value);
  });
}
