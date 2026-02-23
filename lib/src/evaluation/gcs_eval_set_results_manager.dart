import 'dart:convert';

import '../errors/not_found_error.dart';
import 'eval_result.dart';
import 'eval_set_results_manager.dart';
import 'eval_set_results_manager_utils.dart';
import 'gcs_storage_store.dart';

const String _evalHistoryDir = 'evals/eval_history';
const String _evalSetResultFileExtension = '.evalset_result.json';

class GcsEvalSetResultsManager extends EvalSetResultsManager {
  GcsEvalSetResultsManager({
    required this.bucketName,
    GcsStorageStore? storageStore,
  }) : _storageStore = storageStore ?? FileSystemGcsStorageStore();

  final String bucketName;
  final GcsStorageStore _storageStore;

  String getEvalHistoryDir(String appName) => '$appName/$_evalHistoryDir';

  String getEvalSetResultBlobName(String appName, String evalSetResultId) {
    return '${getEvalHistoryDir(appName)}/'
        '$evalSetResultId$_evalSetResultFileExtension';
  }

  Future<void> _ensureBucketExists() async {
    if (!await _storageStore.bucketExists(bucketName)) {
      throw ArgumentError(
        'Bucket `$bucketName` does not exist. Please create it before using '
        'the GcsEvalSetResultsManager.',
      );
    }
  }

  Future<void> _writeEvalSetResult(String blobName, EvalSetResult result) {
    final String jsonText = const JsonEncoder.withIndent(
      '  ',
    ).convert(result.toJson());
    return _storageStore.uploadText(bucketName, blobName, jsonText);
  }

  @override
  Future<void> saveEvalSetResult(
    String appName,
    String evalSetId,
    List<EvalCaseResult> evalCaseResults,
  ) async {
    await _ensureBucketExists();
    final EvalSetResult result = createEvalSetResult(
      appName,
      evalSetId,
      evalCaseResults,
    );
    await _writeEvalSetResult(
      getEvalSetResultBlobName(appName, result.evalSetResultId),
      result,
    );
  }

  @override
  Future<EvalSetResult> getEvalSetResult(
    String appName,
    String evalSetResultId,
  ) async {
    await _ensureBucketExists();
    final String blobName = getEvalSetResultBlobName(appName, evalSetResultId);
    final String? data = await _storageStore.downloadText(bucketName, blobName);
    if (data == null) {
      throw NotFoundError('Eval set result `$evalSetResultId` not found.');
    }
    return parseEvalSetResultJson(data);
  }

  @override
  Future<List<String>> listEvalSetResults(String appName) async {
    await _ensureBucketExists();
    final List<String> blobNames = await _storageStore.listBlobNames(
      bucketName,
      prefix: getEvalHistoryDir(appName),
    );
    final List<String> ids = <String>[];
    for (final String blobName in blobNames) {
      if (!blobName.endsWith(_evalSetResultFileExtension)) {
        continue;
      }
      final String basename = blobName.split('/').last;
      ids.add(
        basename.substring(
          0,
          basename.length - _evalSetResultFileExtension.length,
        ),
      );
    }
    ids.sort();
    return ids;
  }
}
