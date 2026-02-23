import 'eval_case.dart';
import 'eval_set.dart';

abstract class EvalSetsManager {
  Future<EvalSet?> getEvalSet(String appName, String evalSetId);

  Future<EvalSet> createEvalSet(String appName, String evalSetId);

  Future<List<String>> listEvalSets(String appName);

  Future<EvalCase?> getEvalCase(
    String appName,
    String evalSetId,
    String evalCaseId,
  );

  Future<void> addEvalCase(String appName, String evalSetId, EvalCase evalCase);

  Future<void> updateEvalCase(
    String appName,
    String evalSetId,
    EvalCase updatedEvalCase,
  );

  Future<void> deleteEvalCase(
    String appName,
    String evalSetId,
    String evalCaseId,
  );
}
