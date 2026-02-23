import '../errors/not_found_error.dart';
import 'eval_case.dart';
import 'eval_set.dart';
import 'eval_sets_manager.dart';

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

EvalCase? getEvalCaseFromEvalSet(EvalSet evalSet, String evalCaseId) {
  for (final EvalCase evalCase in evalSet.evalCases) {
    if (evalCase.evalId == evalCaseId) {
      return evalCase;
    }
  }
  return null;
}

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
