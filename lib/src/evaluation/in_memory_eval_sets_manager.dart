import '../errors/not_found_error.dart';
import 'eval_case.dart';
import 'eval_set.dart';
import 'eval_sets_manager.dart';

class InMemoryEvalSetsManager extends EvalSetsManager {
  final Map<String, Map<String, EvalSet>> _evalSets =
      <String, Map<String, EvalSet>>{};
  final Map<String, Map<String, Map<String, EvalCase>>> _evalCases =
      <String, Map<String, Map<String, EvalCase>>>{};

  void _ensureAppExists(String appName) {
    _evalSets.putIfAbsent(appName, () => <String, EvalSet>{});
    _evalCases.putIfAbsent(appName, () => <String, Map<String, EvalCase>>{});
  }

  @override
  Future<EvalSet?> getEvalSet(String appName, String evalSetId) async {
    _ensureAppExists(appName);
    return _evalSets[appName]![evalSetId];
  }

  @override
  Future<EvalSet> createEvalSet(String appName, String evalSetId) async {
    _ensureAppExists(appName);
    if (_evalSets[appName]!.containsKey(evalSetId)) {
      throw ArgumentError(
        'EvalSet $evalSetId already exists for app $appName.',
      );
    }

    final EvalSet evalSet = EvalSet(
      evalSetId: evalSetId,
      name: evalSetId,
      evalCases: <EvalCase>[],
      creationTimestamp: DateTime.now().millisecondsSinceEpoch / 1000,
    );
    _evalSets[appName]![evalSetId] = evalSet;
    _evalCases[appName]![evalSetId] = <String, EvalCase>{};
    return evalSet;
  }

  @override
  Future<List<String>> listEvalSets(String appName) async {
    if (!_evalSets.containsKey(appName)) {
      return <String>[];
    }
    return _evalSets[appName]!.keys.toList();
  }

  @override
  Future<EvalCase?> getEvalCase(
    String appName,
    String evalSetId,
    String evalCaseId,
  ) async {
    if (!_evalCases.containsKey(appName)) {
      return null;
    }
    if (!_evalCases[appName]!.containsKey(evalSetId)) {
      return null;
    }
    return _evalCases[appName]![evalSetId]![evalCaseId];
  }

  @override
  Future<void> addEvalCase(
    String appName,
    String evalSetId,
    EvalCase evalCase,
  ) async {
    _ensureAppExists(appName);
    if (!_evalSets[appName]!.containsKey(evalSetId)) {
      throw NotFoundError('EvalSet $evalSetId not found for app $appName.');
    }
    if (_evalCases[appName]![evalSetId]!.containsKey(evalCase.evalId)) {
      throw ArgumentError(
        'EvalCase ${evalCase.evalId} already exists in EvalSet '
        '$evalSetId for app $appName.',
      );
    }

    _evalCases[appName]![evalSetId]![evalCase.evalId] = evalCase;
    _evalSets[appName]![evalSetId]!.evalCases.add(evalCase);
  }

  @override
  Future<void> updateEvalCase(
    String appName,
    String evalSetId,
    EvalCase updatedEvalCase,
  ) async {
    _ensureAppExists(appName);
    if (!_evalSets[appName]!.containsKey(evalSetId)) {
      throw NotFoundError('EvalSet $evalSetId not found for app $appName.');
    }
    if (!_evalCases[appName]![evalSetId]!.containsKey(updatedEvalCase.evalId)) {
      throw NotFoundError(
        'EvalCase ${updatedEvalCase.evalId} not found in EvalSet '
        '$evalSetId for app $appName.',
      );
    }

    _evalCases[appName]![evalSetId]![updatedEvalCase.evalId] = updatedEvalCase;
    final List<EvalCase> cases = _evalSets[appName]![evalSetId]!.evalCases;
    for (int i = 0; i < cases.length; i += 1) {
      if (cases[i].evalId == updatedEvalCase.evalId) {
        cases[i] = updatedEvalCase;
        break;
      }
    }
  }

  @override
  Future<void> deleteEvalCase(
    String appName,
    String evalSetId,
    String evalCaseId,
  ) async {
    _ensureAppExists(appName);
    if (!_evalSets[appName]!.containsKey(evalSetId)) {
      throw NotFoundError('EvalSet $evalSetId not found for app $appName.');
    }
    if (!_evalCases[appName]![evalSetId]!.containsKey(evalCaseId)) {
      throw NotFoundError(
        'EvalCase $evalCaseId not found in EvalSet $evalSetId for app $appName.',
      );
    }
    _evalCases[appName]![evalSetId]!.remove(evalCaseId);
    _evalSets[appName]![evalSetId]!.evalCases.removeWhere(
      (EvalCase value) => value.evalId == evalCaseId,
    );
  }
}
