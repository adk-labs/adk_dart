import '../evaluation/eval_metric.dart';
import '../evaluation/eval_result.dart';
import '../agents/llm_agent.dart';
import '../types/content.dart';

List<EvalMetric> getDefaultMetricInfo({bool addTrajectoryMetrics = false}) {
  final List<EvalMetric> metrics = <EvalMetric>[
    EvalMetric.finalResponseExactMatch,
    EvalMetric.finalResponseContains,
  ];
  if (addTrajectoryMetrics &&
      !metrics.contains(EvalMetric.finalResponseContains)) {
    metrics.add(EvalMetric.finalResponseContains);
  }
  return metrics;
}

List<String> parseAndGetEvalsToRun({
  required String? evalIds,
  required List<String> availableEvalIds,
}) {
  if (evalIds == null || evalIds.trim().isEmpty) {
    return List<String>.from(availableEvalIds);
  }

  final Set<String> requested = evalIds
      .split(',')
      .map((String value) => value.trim())
      .where((String value) => value.isNotEmpty)
      .toSet();

  final List<String> selected = availableEvalIds
      .where((String id) => requested.contains(id))
      .toList(growable: false);
  if (selected.isEmpty) {
    throw ArgumentError('No matching eval IDs found in `$evalIds`.');
  }
  return selected;
}

String convertContentToText(Content? content) {
  if (content == null) {
    return '';
  }
  return content.parts
      .where((Part part) => part.text != null && part.text!.trim().isNotEmpty)
      .map((Part part) => part.text!.trim())
      .join('\n');
}

String convertToolCallsToText(List<FunctionCall> calls) {
  return calls
      .map((FunctionCall call) => '${call.name}(${call.args})')
      .join('\n');
}

String prettyPrintEvalResult(EvalCaseResult result) {
  final StringBuffer out = StringBuffer();
  out.writeln('EvalCase: ${result.evalCaseId}');
  out.writeln('Status: ${result.finalEvalStatus.name}');
  out.writeln('Overall Score: ${result.overallScore.toStringAsFixed(3)}');
  for (final EvalMetricResult metric in result.metrics) {
    out.writeln(
      '- ${metric.metric.name}: ${metric.score.toStringAsFixed(3)} (passed=${metric.passed})',
    );
  }
  return out.toString().trimRight();
}

Agent getRootAgentFromModule(Agent rootAgent) => rootAgent;

Object? tryGetResetFunc(Object? moduleLike) {
  if (moduleLike is Map<String, Object?> && moduleLike['reset'] is Function) {
    return moduleLike['reset'];
  }
  return null;
}
