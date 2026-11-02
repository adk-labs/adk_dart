/// Evaluation storage URI resolution and manager factory helpers.
library;

import 'dart:io';

import 'package:adk_dart/src/evaluation/eval_set_results_manager.dart';
import 'package:adk_dart/src/evaluation/eval_sets_manager.dart';
import 'package:adk_dart/src/evaluation/local_eval_set_results_manager.dart';
import 'package:adk_dart/src/evaluation/local_eval_sets_manager.dart';

import 'envs.dart';
import 'evals.dart' as evals;

/// Environment variable configuring the evaluation storage URI.
const String adkEvalStorageUriEnv = 'ADK_EVAL_STORAGE_URI';

/// Resolves the eval storage URI from an explicit argument or the environment.
///
/// Precedence is the explicit [evalStorageUri], then [adkEvalStorageUriEnv].
/// Returns the URI to use, or `null` to store evals under `agentsDir`.
String? resolveEvalStorageUri(
  String? evalStorageUri, {
  Map<String, String>? environment,
  void Function(String message)? log,
}) {
  if (evalStorageUri != null && evalStorageUri.isNotEmpty) {
    return evalStorageUri;
  }

  final String? envUri =
      environment?[adkEvalStorageUriEnv] ??
      getCliEnvironmentValue(adkEvalStorageUriEnv);
  if (envUri != null && envUri.isNotEmpty) {
    log?.call('Using eval storage URI from $adkEvalStorageUriEnv: $envUri');
    return envUri;
  }

  return null;
}

/// Returns and creates the filesystem directory for a `file://` [evalStorageUri].
///
/// Throws an [ArgumentError] if the URI is not a local `file://` URI with an
/// absolute path, or if the directory cannot be created.
String localEvalDirFromUri(
  String evalStorageUri, {
  bool createDirectory = true,
}) {
  final Uri parsed;
  try {
    parsed = Uri.parse(evalStorageUri);
  } on FormatException {
    throw ArgumentError(
      'Unsupported evals storage URI: $evalStorageUri. Supported URIs: '
      'gs://<bucket name>, file://<path>',
    );
  }

  if (parsed.scheme != 'file') {
    throw ArgumentError(
      'Unsupported evals storage URI: $evalStorageUri. Supported URIs: '
      'gs://<bucket name>, file://<path>',
    );
  }
  final String host = parsed.authority.toLowerCase();
  if (host.isNotEmpty && host != 'localhost') {
    throw ArgumentError(
      'Invalid evals storage URI: $evalStorageUri. file:// URIs must '
      'target the local host, e.g. file:///abs/path',
    );
  }
  if (!parsed.path.startsWith('/')) {
    throw ArgumentError(
      'Invalid evals storage URI: $evalStorageUri. file:// URIs must use '
      'an absolute path, e.g. file:///abs/path',
    );
  }

  final String path = Uri.decodeFull(parsed.path);
  if (createDirectory) {
    try {
      Directory(path).createSync(recursive: true);
    } on FileSystemException catch (exc) {
      throw ArgumentError(
        "Failed to create eval storage directory '$path' for "
        "'$evalStorageUri' (configured via --eval_storage_uri or "
        '$adkEvalStorageUriEnv): $exc',
      );
    }
  }
  return path;
}

/// Creates evaluation managers for [evalStorageUri], [adkEvalStorageUriEnv],
/// or [agentsDir].
///
/// Returns a tuple of `(EvalSetsManager, EvalSetResultsManager)`.
(EvalSetsManager, EvalSetResultsManager) createEvalManagers(
  String? evalStorageUri,
  String agentsDir, {
  EvalSetsManager Function(String agentsDir)? localEvalSetsManagerFactory,
  EvalSetResultsManager Function(String agentsDir)?
  localEvalSetResultsManagerFactory,
  Map<String, String>? environment,
  void Function(String message)? log,
}) {
  final String? uri = resolveEvalStorageUri(
    evalStorageUri,
    environment: environment,
    log: log,
  );
  if (uri != null) {
    final Uri? parsed = Uri.tryParse(uri);
    if (parsed != null && parsed.scheme == 'gs') {
      try {
        final evals.GcsEvalManagers gcs = evals.createGcsEvalManagersFromUri(
          uri,
          environment: environment,
        );
        return (gcs.evalSetsManager, gcs.evalSetResultsManager);
      } on StateError catch (exc) {
        throw ArgumentError(
          "Missing required environment variable 'GOOGLE_CLOUD_PROJECT' for "
          "GCS eval storage URI '$uri' (configured via --eval_storage_uri or "
          '$adkEvalStorageUriEnv): $exc',
        );
      }
    }
  }

  final String localDir = uri != null ? localEvalDirFromUri(uri) : agentsDir;
  final EvalSetsManager Function(String) setsFactory =
      localEvalSetsManagerFactory ?? LocalEvalSetsManager.new;
  final EvalSetResultsManager Function(String) resultsFactory =
      localEvalSetResultsManagerFactory ?? LocalEvalSetResultsManager.new;
  return (setsFactory(localDir), resultsFactory(localDir));
}
