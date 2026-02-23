import '../../evaluation/eval_case.dart';
import '../../evaluation/evaluation_generator.dart';
import '../../evaluation/gcs_eval_set_results_manager.dart';
import '../../evaluation/gcs_eval_sets_manager.dart';
import '../../events/event.dart';
import '../../sessions/session.dart';
import 'envs.dart';

class GcsEvalManagers {
  GcsEvalManagers({
    required this.evalSetsManager,
    required this.evalSetResultsManager,
  });

  final GcsEvalSetsManager evalSetsManager;
  final GcsEvalSetResultsManager evalSetResultsManager;
}

List<Invocation> convertSessionToEvalInvocations(Session? session) {
  final List<Event> events = session?.events ?? <Event>[];
  return EvaluationGenerator.convertEventsToEvalInvocations(events);
}

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
