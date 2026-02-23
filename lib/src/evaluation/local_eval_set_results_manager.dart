import 'dart:convert';
import 'dart:io';

import '../errors/not_found_error.dart';
import 'eval_result.dart';
import 'eval_set_results_manager.dart';
import 'eval_set_results_manager_utils.dart';

const String _adkEvalHistoryDir = '.adk/eval_history';
const String _evalSetResultFileExtension = '.evalset_result.json';

class LocalEvalSetResultsManager extends EvalSetResultsManager {
  LocalEvalSetResultsManager(this._agentsDir);

  final String _agentsDir;

  @override
  Future<void> saveEvalSetResult(
    String appName,
    String evalSetId,
    List<EvalCaseResult> evalCaseResults,
  ) async {
    final EvalSetResult evalSetResult = createEvalSetResult(
      appName,
      evalSetId,
      evalCaseResults,
    );

    final String appEvalHistoryDir = _getEvalHistoryDir(appName);
    await Directory(appEvalHistoryDir).create(recursive: true);
    final String filePath =
        '$appEvalHistoryDir/${evalSetResult.evalSetResultName}$_evalSetResultFileExtension';
    final String jsonText = const JsonEncoder.withIndent(
      '  ',
    ).convert(evalSetResult.toJson());
    await File(filePath).writeAsString(jsonText);
  }

  @override
  Future<EvalSetResult> getEvalSetResult(
    String appName,
    String evalSetResultId,
  ) async {
    final String filePath =
        '${_getEvalHistoryDir(appName)}/$evalSetResultId$_evalSetResultFileExtension';
    final File file = File(filePath);
    if (!await file.exists()) {
      throw NotFoundError('Eval set result `$evalSetResultId` not found.');
    }
    final String content = await file.readAsString();
    return parseEvalSetResultJson(content);
  }

  @override
  Future<List<String>> listEvalSetResults(String appName) async {
    final Directory dir = Directory(_getEvalHistoryDir(appName));
    if (!await dir.exists()) {
      return <String>[];
    }

    final List<String> ids = <String>[];
    await for (final FileSystemEntity entity in dir.list()) {
      if (entity is! File) {
        continue;
      }
      final String basename = entity.uri.pathSegments.last;
      if (!basename.endsWith(_evalSetResultFileExtension)) {
        continue;
      }
      ids.add(
        basename.substring(
          0,
          basename.length - _evalSetResultFileExtension.length,
        ),
      );
    }
    return ids;
  }

  String _getEvalHistoryDir(String appName) {
    return '$_agentsDir/$appName/$_adkEvalHistoryDir';
  }
}
