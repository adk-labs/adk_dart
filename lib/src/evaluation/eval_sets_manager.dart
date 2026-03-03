import 'eval_case.dart';
import 'eval_set.dart';

/// Persists and mutates evaluation set definitions.
abstract class EvalSetsManager {
  /// Loads one eval set by [evalSetId].
  Future<EvalSet?> getEvalSet(String appName, String evalSetId);

  /// Creates an empty eval set for [appName].
  Future<EvalSet> createEvalSet(String appName, String evalSetId);

  /// Lists eval set identifiers for [appName].
  Future<List<String>> listEvalSets(String appName);

  /// Loads one eval case from an eval set.
  Future<EvalCase?> getEvalCase(
    String appName,
    String evalSetId,
    String evalCaseId,
  );

  /// Adds [evalCase] to an eval set.
  Future<void> addEvalCase(String appName, String evalSetId, EvalCase evalCase);

  /// Replaces an existing eval case with [updatedEvalCase].
  Future<void> updateEvalCase(
    String appName,
    String evalSetId,
    EvalCase updatedEvalCase,
  );

  /// Deletes one eval case by [evalCaseId].
  Future<void> deleteEvalCase(
    String appName,
    String evalSetId,
    String evalCaseId,
  );
}
