/// Abstractions for persisting evaluation execution results.
library;

import 'eval_result.dart';

/// Persists and reads stored eval set execution results.
abstract class EvalSetResultsManager {
  /// Saves [evalCaseResults] for [evalSetId].
  Future<void> saveEvalSetResult(
    String appName,
    String evalSetId,
    List<EvalCaseResult> evalCaseResults,
  );

  /// Loads one stored eval set result by identifier.
  Future<EvalSetResult> getEvalSetResult(
    String appName,
    String evalSetResultId,
  );

  /// Lists stored eval set result identifiers for [appName].
  Future<List<String>> listEvalSetResults(String appName);
}
