/// Helpers for creating and parsing serialized evaluation set results.
library;

import 'dart:convert';

import 'eval_result.dart';

/// The normalized eval set result name derived from [evalSetResultName].
///
/// This replaces `/` with `_` so the value is safe for path-like storage keys.
String sanitizeEvalSetResultName(String evalSetResultName) {
  return evalSetResultName.replaceAll('/', '_');
}

/// The new [EvalSetResult] instance for one evaluation run.
///
/// The generated identifier combines [appName], [evalSetId], and a UNIX
/// timestamp in seconds.
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

/// The parsed [EvalSetResult] object from [evalSetResultJson].
///
/// Accepts both direct JSON objects and nested JSON-encoded object strings.
/// Throws a [FormatException] when the payload cannot be parsed.
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
