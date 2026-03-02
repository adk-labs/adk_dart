/// CLI helpers for evaluation storage and session-to-eval conversion.
library;

import '../../evaluation/eval_case.dart';
import '../../evaluation/evaluation_generator.dart';
import '../../evaluation/gcs_eval_set_results_manager.dart';
import '../../evaluation/gcs_eval_sets_manager.dart';
import '../../events/event.dart';
import '../../sessions/session.dart';
import 'envs.dart';

/// Pair of GCS-backed eval managers used by CLI eval commands.
class GcsEvalManagers {
  /// Creates GCS eval manager bundle.
  GcsEvalManagers({
    required this.evalSetsManager,
    required this.evalSetResultsManager,
  });

  /// Eval set metadata manager.
  final GcsEvalSetsManager evalSetsManager;

  /// Eval set result manager.
  final GcsEvalSetResultsManager evalSetResultsManager;
}

/// Converts a [session] event stream into evaluation invocations.
List<Invocation> convertSessionToEvalInvocations(Session? session) {
  final List<Event> events = session?.events ?? <Event>[];
  return EvaluationGenerator.convertEventsToEvalInvocations(events);
}

/// Creates GCS eval managers from a `gs://` [evalStorageUri].
///
/// Throws an [ArgumentError] for unsupported URI schemes.
/// Throws a [StateError] when `GOOGLE_CLOUD_PROJECT` is missing.
GcsEvalManagers createGcsEvalManagersFromUri(String evalStorageUri) {
  if (!evalStorageUri.startsWith('gs://')) {
    throw ArgumentError(
      'Unsupported evals storage URI: $evalStorageUri. Supported URIs: gs://<bucket name>',
    );
  }

  final String bucketName = evalStorageUri.split('://')[1];
  final String? project = getCliEnvironmentValue('GOOGLE_CLOUD_PROJECT');
  if (project == null || project.isEmpty) {
    throw StateError('GOOGLE_CLOUD_PROJECT is not set.');
  }

  return GcsEvalManagers(
    evalSetsManager: GcsEvalSetsManager(bucketName: bucketName),
    evalSetResultsManager: GcsEvalSetResultsManager(bucketName: bucketName),
  );
}
