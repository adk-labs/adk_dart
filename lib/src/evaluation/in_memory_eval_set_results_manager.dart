import '../errors/not_found_error.dart';
import 'eval_result.dart';
import 'eval_set_results_manager.dart';
import 'eval_set_results_manager_utils.dart';

class InMemoryEvalSetResultsManager extends EvalSetResultsManager {
  final Map<String, Map<String, EvalSetResult>> _resultsByApp =
      <String, Map<String, EvalSetResult>>{};

  @override
  Future<void> saveEvalSetResult(
    String appName,
    String evalSetId,
    List<EvalCaseResult> evalCaseResults,
  ) async {
    final EvalSetResult result = createEvalSetResult(
      appName,
      evalSetId,
      evalCaseResults,
    );
    final Map<String, EvalSetResult> byId = _resultsByApp.putIfAbsent(
      appName,
      () => <String, EvalSetResult>{},
    );
    byId[result.evalSetResultId] = EvalSetResult.fromJson(result.toJson());
  }

  @override
  Future<EvalSetResult> getEvalSetResult(
    String appName,
    String evalSetResultId,
  ) async {
    final EvalSetResult? result = _resultsByApp[appName]?[evalSetResultId];
    if (result == null) {
      throw NotFoundError('Eval set result `$evalSetResultId` not found.');
    }
    return EvalSetResult.fromJson(result.toJson());
  }

  @override
  Future<List<String>> listEvalSetResults(String appName) async {
    final Map<String, EvalSetResult>? byId = _resultsByApp[appName];
    if (byId == null) {
      return <String>[];
    }
    final List<String> ids = byId.keys.toList(growable: false)..sort();
    return ids;
  }
}
