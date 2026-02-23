import 'eval_result.dart';

abstract class EvalSetResultsManager {
  Future<void> saveEvalSetResult(
    String appName,
    String evalSetId,
    List<EvalCaseResult> evalCaseResults,
  );

  Future<EvalSetResult> getEvalSetResult(
    String appName,
    String evalSetResultId,
  );

  Future<List<String>> listEvalSetResults(String appName);
}
