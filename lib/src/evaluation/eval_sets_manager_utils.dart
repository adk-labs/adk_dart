/// Utility helpers for eval set and eval case CRUD operations.
library;

import '../errors/not_found_error.dart';
import 'eval_case.dart';
import 'eval_set.dart';
import 'eval_sets_manager.dart';

/// The [EvalSet] for [appName] and [evalSetId] from [manager].
///
/// Throws a [NotFoundError] when the eval set does not exist.
Future<EvalSet> getEvalSetFromAppAndId(
  EvalSetsManager manager,
  String appName,
  String evalSetId,
) async {
  final EvalSet? evalSet = await manager.getEvalSet(appName, evalSetId);
  if (evalSet == null) {
    throw NotFoundError('Eval set `$evalSetId` not found.');
  }
  return evalSet;
}

/// The eval case in [evalSet] matching [evalCaseId].
///
/// Returns `null` when no matching eval case exists.
EvalCase? getEvalCaseFromEvalSet(EvalSet evalSet, String evalCaseId) {
  for (final EvalCase evalCase in evalSet.evalCases) {
    if (evalCase.evalId == evalCaseId) {
      return evalCase;
    }
  }
  return null;
}

/// The [evalSet] with [evalCase] appended.
///
/// Throws an [ArgumentError] when another eval case already has the same ID.
EvalSet addEvalCaseToEvalSet(EvalSet evalSet, EvalCase evalCase) {
  final String evalCaseId = evalCase.evalId;
  final bool exists = evalSet.evalCases.any(
    (EvalCase value) => value.evalId == evalCaseId,
  );
  if (exists) {
    throw ArgumentError(
      'Eval id `$evalCaseId` already exists in `${evalSet.evalSetId}` eval set.',
    );
  }
  evalSet.evalCases.add(evalCase);
  return evalSet;
}

/// The [evalSet] with an existing eval case replaced by [updatedEvalCase].
///
/// Throws a [NotFoundError] when the eval case does not exist.
EvalSet updateEvalCaseInEvalSet(EvalSet evalSet, EvalCase updatedEvalCase) {
  final EvalCase? existing = getEvalCaseFromEvalSet(
    evalSet,
    updatedEvalCase.evalId,
  );
  if (existing == null) {
    throw NotFoundError(
      'Eval case `${updatedEvalCase.evalId}` not found in eval set '
      '`${evalSet.evalSetId}`.',
    );
  }
  evalSet.evalCases.remove(existing);
  evalSet.evalCases.add(updatedEvalCase);
  return evalSet;
}

/// The [evalSet] with the eval case identified by [evalCaseId] removed.
///
/// Throws a [NotFoundError] when the eval case does not exist.
EvalSet deleteEvalCaseFromEvalSet(EvalSet evalSet, String evalCaseId) {
  final EvalCase? existing = getEvalCaseFromEvalSet(evalSet, evalCaseId);
  if (existing == null) {
    throw NotFoundError(
      'Eval case `$evalCaseId` not found in eval set `${evalSet.evalSetId}`.',
    );
  }
  evalSet.evalCases.remove(existing);
  return evalSet;
}
