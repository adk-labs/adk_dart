import 'dart:convert';

import 'eval_case.dart';
import 'eval_set.dart';
import 'eval_sets_manager.dart';
import 'eval_sets_manager_utils.dart';
import 'gcs_storage_store.dart';

const String _evalSetsDir = 'evals/eval_sets';
const String _evalSetFileExtension = '.evalset.json';

class GcsEvalSetsManager extends EvalSetsManager {
  GcsEvalSetsManager({required this.bucketName, GcsStorageStore? storageStore})
    : _storageStore = storageStore ?? FileSystemGcsStorageStore();

  final String bucketName;
  final GcsStorageStore _storageStore;

  String getEvalSetsDir(String appName) => '$appName/$_evalSetsDir';

  String getEvalSetBlobName(String appName, String evalSetId) {
    return '${getEvalSetsDir(appName)}/$evalSetId$_evalSetFileExtension';
  }

  void validateId({required String idName, required String idValue}) {
    final RegExp pattern = RegExp(r'^[a-zA-Z0-9_]+$');
    if (!pattern.hasMatch(idValue)) {
      throw ArgumentError(
        'Invalid $idName. $idName should have the `${pattern.pattern}` format',
      );
    }
  }

  Future<EvalSet?> _loadEvalSetFromBlob(String blobName) async {
    final String? data = await _storageStore.downloadText(bucketName, blobName);
    if (data == null) {
      return null;
    }
    final Object? decoded = jsonDecode(data);
    if (decoded is! Map) {
      throw ArgumentError('Unsupported eval set JSON in blob `$blobName`.');
    }
    return EvalSet.fromJson(
      decoded.map(
        (Object? key, Object? value) =>
            MapEntry<String, Object?>('$key', value),
      ),
    );
  }

  Future<void> _writeEvalSetToBlob(String blobName, EvalSet evalSet) {
    final String jsonText = const JsonEncoder.withIndent(
      '  ',
    ).convert(evalSet.toJson(includeNulls: false));
    return _storageStore.uploadText(bucketName, blobName, jsonText);
  }

  Future<void> _saveEvalSet(String appName, String evalSetId, EvalSet evalSet) {
    final String blobName = getEvalSetBlobName(appName, evalSetId);
    return _writeEvalSetToBlob(blobName, evalSet);
  }

  Future<void> _ensureBucketExists() async {
    if (!await _storageStore.bucketExists(bucketName)) {
      throw ArgumentError(
        'Bucket `$bucketName` does not exist. Please create it before using '
        'the GcsEvalSetsManager.',
      );
    }
  }

  @override
  Future<EvalSet?> getEvalSet(String appName, String evalSetId) async {
    await _ensureBucketExists();
    return _loadEvalSetFromBlob(getEvalSetBlobName(appName, evalSetId));
  }

  @override
  Future<EvalSet> createEvalSet(String appName, String evalSetId) async {
    await _ensureBucketExists();
    validateId(idName: 'Eval Set ID', idValue: evalSetId);
    final String blobName = getEvalSetBlobName(appName, evalSetId);
    if (await _storageStore.blobExists(bucketName, blobName)) {
      throw ArgumentError(
        'Eval set `$evalSetId` already exists for app `$appName`.',
      );
    }
    final EvalSet evalSet = EvalSet(
      evalSetId: evalSetId,
      name: evalSetId,
      evalCases: <EvalCase>[],
      creationTimestamp: DateTime.now().millisecondsSinceEpoch / 1000,
    );
    await _writeEvalSetToBlob(blobName, evalSet);
    return evalSet;
  }

  @override
  Future<List<String>> listEvalSets(String appName) async {
    await _ensureBucketExists();
    final List<String> blobNames = await _storageStore.listBlobNames(
      bucketName,
      prefix: getEvalSetsDir(appName),
    );
    final List<String> evalSets = <String>[];
    for (final String blobName in blobNames) {
      if (!blobName.endsWith(_evalSetFileExtension)) {
        continue;
      }
      final String basename = blobName.split('/').last;
      evalSets.add(
        basename.substring(0, basename.length - _evalSetFileExtension.length),
      );
    }
    evalSets.sort();
    return evalSets;
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
}
