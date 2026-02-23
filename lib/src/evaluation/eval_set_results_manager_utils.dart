import 'dart:convert';

import 'eval_result.dart';

String sanitizeEvalSetResultName(String evalSetResultName) {
  return evalSetResultName.replaceAll('/', '_');
}

EvalSetResult createEvalSetResult(
  String appName,
  String evalSetId,
  List<EvalCaseResult> evalCaseResults,
) {
  final double timestamp = DateTime.now().millisecondsSinceEpoch / 1000;
  final String id = '${appName}_${evalSetId}_$timestamp';
  return EvalSetResult(
    evalSetResultId: id,
    evalSetResultName: sanitizeEvalSetResultName(id),
    evalSetId: evalSetId,
    evalCaseResults: evalCaseResults,
    creationTimestamp: timestamp,
  );
}

EvalSetResult parseEvalSetResultJson(String evalSetResultJson) {
  final Object? decoded = jsonDecode(evalSetResultJson);
  if (decoded is Map) {
    return EvalSetResult.fromJson(_castJsonMap(decoded));
  }
  if (decoded is String) {
    final Object? nested = jsonDecode(decoded);
    if (nested is Map) {
      return EvalSetResult.fromJson(_castJsonMap(nested));
    }
  }
  throw FormatException('Invalid eval set result JSON payload.');
}

Map<String, Object?> _castJsonMap(Map map) {
  return map.map((Object? key, Object? value) => MapEntry('$key', value));
}
