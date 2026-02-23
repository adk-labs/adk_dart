import 'dart:convert';
import 'dart:io';

import '../errors/not_found_error.dart';
import 'eval_case.dart';
import 'eval_set.dart';
import 'eval_sets_manager.dart';
import 'eval_sets_manager_utils.dart';

const String _evalSetFileExtension = '.evalset.json';

EvalSet loadEvalSetFromFile(String evalSetFilePath, String evalSetId) {
  final String content = File(evalSetFilePath).readAsStringSync();
  final Object? decoded = jsonDecode(content);
  if (decoded is Map) {
    return EvalSet.fromJson(_castJsonMap(decoded));
  }
  if (decoded is List) {
    return convertEvalSetToModernSchema(evalSetId, decoded);
  }
  throw ArgumentError('Unsupported eval set format in `$evalSetFilePath`.');
}

EvalSet convertEvalSetToModernSchema(
  String evalSetId,
  List<dynamic> oldFormat,
) {
  final List<EvalCase> evalCases = <EvalCase>[];
  for (final Object? item in oldFormat) {
    if (item is! Map) {
      continue;
    }
    final Map<String, Object?> evalCaseMap = _castJsonMap(item);
    final List<Invocation> invocations = _asList(evalCaseMap['data'])
        .whereType<Map>()
        .map((Map value) {
          return Invocation.fromJson(_castJsonMap(value));
        })
        .toList();
    final Map<String, Object?> initialSession = _castJsonMap(
      evalCaseMap['initial_session'],
    );

    SessionInput? sessionInput;
    if (initialSession.isNotEmpty) {
      sessionInput = SessionInput(
        appName: (initialSession['app_name'] ?? '') as String,
        userId: (initialSession['user_id'] ?? '') as String,
        state: _castJsonMap(initialSession['state']),
      );
    }

    evalCases.add(
      EvalCase(
        evalId: (evalCaseMap['name'] ?? '') as String,
        input: invocations.isEmpty
            ? ''
            : _extractInvocationInput(invocations[0]),
        expectedOutput: invocations.isEmpty
            ? null
            : _extractInvocationFinalResponse(invocations.last),
        conversation: invocations,
        sessionInput: sessionInput,
        creationTimestamp: DateTime.now().millisecondsSinceEpoch / 1000,
      ),
    );
  }

  return EvalSet(
    evalSetId: evalSetId,
    name: evalSetId,
    creationTimestamp: DateTime.now().millisecondsSinceEpoch / 1000,
    evalCases: evalCases,
  );
}

class LocalEvalSetsManager extends EvalSetsManager {
  LocalEvalSetsManager(this._agentsDir);

  final String _agentsDir;

  @override
  Future<EvalSet?> getEvalSet(String appName, String evalSetId) async {
    try {
      final String filePath = _getEvalSetFilePath(appName, evalSetId);
      return loadEvalSetFromFile(filePath, evalSetId);
    } on FileSystemException {
      return null;
    }
  }

  @override
  Future<EvalSet> createEvalSet(String appName, String evalSetId) async {
    _validateId(idName: 'Eval Set ID', idValue: evalSetId);
    final String path = _getEvalSetFilePath(appName, evalSetId);
    final File file = File(path);
    if (await file.exists()) {
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
    await _writeEvalSetToPath(path, evalSet);
    return evalSet;
  }

  @override
  Future<List<String>> listEvalSets(String appName) async {
    final Directory evalSetDir = Directory('$_agentsDir/$appName');
    if (!await evalSetDir.exists()) {
      throw NotFoundError('Eval directory for app `$appName` not found.');
    }
    final List<String> ids = <String>[];
    await for (final FileSystemEntity entity in evalSetDir.list()) {
      if (entity is! File) {
        continue;
      }
      final String base = entity.uri.pathSegments.last;
      if (base.endsWith(_evalSetFileExtension)) {
        ids.add(base.substring(0, base.length - _evalSetFileExtension.length));
      }
    }
    ids.sort();
    return ids;
  }

  @override
  Future<EvalCase?> getEvalCase(
    String appName,
    String evalSetId,
    String evalCaseId,
  ) async {
    final EvalSet? evalSet = await getEvalSet(appName, evalSetId);
    if (evalSet == null) {
      return null;
    }
    return getEvalCaseFromEvalSet(evalSet, evalCaseId);
  }

  @override
  Future<void> addEvalCase(
    String appName,
    String evalSetId,
    EvalCase evalCase,
  ) async {
    final EvalSet evalSet = await getEvalSetFromAppAndId(
      this,
      appName,
      evalSetId,
    );
    final EvalSet updated = addEvalCaseToEvalSet(evalSet, evalCase);
    await _saveEvalSet(appName, evalSetId, updated);
  }

  @override
  Future<void> updateEvalCase(
    String appName,
    String evalSetId,
    EvalCase updatedEvalCase,
  ) async {
    final EvalSet evalSet = await getEvalSetFromAppAndId(
      this,
      appName,
      evalSetId,
    );
    final EvalSet updated = updateEvalCaseInEvalSet(evalSet, updatedEvalCase);
    await _saveEvalSet(appName, evalSetId, updated);
  }

  @override
  Future<void> deleteEvalCase(
    String appName,
    String evalSetId,
    String evalCaseId,
  ) async {
    final EvalSet evalSet = await getEvalSetFromAppAndId(
      this,
      appName,
      evalSetId,
    );
    final EvalSet updated = deleteEvalCaseFromEvalSet(evalSet, evalCaseId);
    await _saveEvalSet(appName, evalSetId, updated);
  }

  String _getEvalSetFilePath(String appName, String evalSetId) {
    return '$_agentsDir/$appName/$evalSetId$_evalSetFileExtension';
  }

  void _validateId({required String idName, required String idValue}) {
    final RegExp regex = RegExp(r'^[a-zA-Z0-9_]+$');
    if (!regex.hasMatch(idValue)) {
      throw ArgumentError(
        'Invalid $idName. $idName should have the `${regex.pattern}` format',
      );
    }
  }

  Future<void> _writeEvalSetToPath(String path, EvalSet evalSet) async {
    final File file = File(path);
    await file.parent.create(recursive: true);
    final String jsonText = const JsonEncoder.withIndent(
      '  ',
    ).convert(evalSet.toJson(includeNulls: false));
    await file.writeAsString(jsonText);
  }

  Future<void> _saveEvalSet(String appName, String evalSetId, EvalSet evalSet) {
    final String filePath = _getEvalSetFilePath(appName, evalSetId);
    return _writeEvalSetToPath(filePath, evalSet);
  }
}

String _extractInvocationInput(Invocation invocation) {
  final List<dynamic> parts = _asList(invocation.userContent['parts']);
  for (final Object? part in parts) {
    if (part is Map) {
      final Object? text = part['text'];
      if (text is String) {
        return text;
      }
    }
  }
  return '';
}

String? _extractInvocationFinalResponse(Invocation invocation) {
  final Map<String, Object?>? finalResponse = invocation.finalResponse;
  if (finalResponse == null) {
    return null;
  }
  final List<dynamic> parts = _asList(finalResponse['parts']);
  for (final Object? part in parts) {
    if (part is Map) {
      final Object? text = part['text'];
      if (text is String) {
        return text;
      }
    }
  }
  return null;
}

List<dynamic> _asList(Object? value) {
  if (value is List) {
    return value;
  }
  return const <dynamic>[];
}

Map<String, Object?> _castJsonMap(Object? value) {
  if (value is Map) {
    return value.map((Object? key, Object? v) => MapEntry('$key', v));
  }
  return <String, Object?>{};
}
