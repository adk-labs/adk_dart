/// Helpers used by CLI evaluation and reporting commands.
library;

import 'package:adk_dart/src/evaluation/eval_case_result_multi_run_aggregator.dart';
import 'package:adk_dart/src/evaluation/eval_config.dart'
    as core_eval_config
    show EvalConfig;
import 'package:adk_dart/src/evaluation/eval_metric.dart';
import 'package:adk_dart/src/evaluation/eval_metrics.dart';
import 'package:adk_dart/src/evaluation/eval_result.dart';
import 'package:adk_dart/src/agents/llm_agent.dart';
import 'package:adk_dart/src/types/content.dart';

export 'package:adk_dart/src/evaluation/eval_case_result_multi_run_aggregator.dart'
    show
        MethodResult,
        MultiRunCaseResult,
        aggregateEvalCaseResults,
        countRunsFailedWithoutMetricResults,
        describeRunStatuses,
        getRunStatus,
        hasPassCountRules,
        loadAggregationMethods;
export 'package:adk_dart/src/evaluation/eval_config.dart'
    show getEvaluationCriteriaOrDefault, getEvalMetricsFromConfig;

/// Converts [evalConfig] criteria into [EvalMetric] values used by the CLI.
List<EvalMetric> resolveCliEvalMetricsFromConfig(
  core_eval_config.EvalConfig evalConfig,
) {
  if (evalConfig.criteria.isEmpty) {
    return getDefaultMetricInfo();
  }
  final List<EvalMetric> metrics = <EvalMetric>[];
  for (final String metricName in evalConfig.criteria.keys) {
    switch (metricName) {
      case 'final_response_exact_match':
        if (!metrics.contains(EvalMetric.finalResponseExactMatch)) {
          metrics.add(EvalMetric.finalResponseExactMatch);
        }
      case 'final_response_contains':
      case 'response_match_score':
      case 'tool_trajectory_avg_score':
      default:
        if (!metrics.contains(EvalMetric.finalResponseContains)) {
          metrics.add(EvalMetric.finalResponseContains);
        }
    }
  }
  return metrics.isEmpty ? getDefaultMetricInfo() : metrics;
}

/// Default metrics used by CLI evaluation runs.
///
/// When [addTrajectoryMetrics] is `true`, trajectory-oriented metrics are
/// included for compatibility with existing evaluation flows.
List<EvalMetric> getDefaultMetricInfo({bool addTrajectoryMetrics = false}) {
  final List<EvalMetric> metrics = <EvalMetric>[
    EvalMetric.finalResponseExactMatch,
  ];
  if (addTrajectoryMetrics &&
      !metrics.contains(EvalMetric.finalResponseContains)) {
    metrics.add(EvalMetric.finalResponseContains);
  }
  return metrics;
}

/// Resolves which eval IDs to run from [evalIds] and [availableEvalIds].
///
/// Returns every available eval ID when [evalIds] is empty.
///
/// Throws an [ArgumentError] when no IDs in [evalIds] match available IDs.
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

/// Converts [content] into a readable multi-line text form.
String convertContentToText(Content? content) {
  if (content == null) {
    return '';
  }
  return content.parts
      .where((Part part) => part.text != null && part.text!.trim().isNotEmpty)
      .map((Part part) => part.text!.trim())
      .join('\n');
}

/// Converts tool [calls] into one line per function invocation.
String convertToolCallsToText(List<FunctionCall> calls) {
  return calls
      .map((FunctionCall call) => '${call.name}(${call.args})')
      .join('\n');
}

/// Formats [result] into a stable human-readable summary block.
String prettyPrintEvalResult(EvalCaseResult result) {
  final StringBuffer out = StringBuffer();
  out.writeln('EvalCase: ${result.evalCaseId}');
  out.writeln('Status: ${result.finalEvalStatus.name}');
  out.writeln('Overall Score: ${result.overallScore.toStringAsFixed(3)}');
  for (final EvalMetricResult metric in result.metrics) {
    out.writeln(
      '- ${metric.metricName}: ${metric.score.toStringAsFixed(3)} (passed=${metric.passed})',
    );
  }
  return out.toString().trimRight();
}

String _evalStatusUpperName(EvalStatus status) {
  switch (status) {
    case EvalStatus.passed:
      return 'PASSED';
    case EvalStatus.failed:
      return 'FAILED';
    case EvalStatus.notEvaluated:
      return 'NOT_EVALUATED';
    case EvalStatus.informational:
      return 'INFORMATIONAL';
  }
}

/// Formats one cross-run [MethodResult] line with [label].
String formatMethodResult(MethodResult result, {required String label}) {
  final String valStr =
      result.value != null ? result.value!.toStringAsFixed(4) : 'None';
  final String threshStr =
      result.threshold != null ? ' (Threshold: ${result.threshold})' : '';
  final String noteStr = (result.note != null && result.note!.isNotEmpty)
      ? ' [${result.note}]'
      : '';
  return '  $label: $valStr$threshStr (${_evalStatusUpperName(result.status)})$noteStr';
}

/// Describes crashed runs for [result], or returns `null` when none crashed.
String? describeCrashedRuns(MultiRunCaseResult result) {
  final int crashed = countRunsFailedWithoutMetricResults(result.runs);
  if (crashed == 0) {
    return null;
  }
  if (crashed > result.maxCrashedRuns) {
    return '  Crashed runs: $crashed/${result.runs.length} '
        '(max allowed: ${result.maxCrashedRuns}) (FAILED)';
  }
  return '  Crashed runs: $crashed/${result.runs.length} '
      '(within max allowed: ${result.maxCrashedRuns})';
}

/// Formats aggregated multi-run evaluation results across [numRuns] runs.
String prettyPrintEvalResultsAcrossRuns(
  List<MultiRunCaseResult> aggregateEvalResults, {
  required int numRuns,
}) {
  final StringBuffer out = StringBuffer();
  for (final MultiRunCaseResult aggResult in aggregateEvalResults) {
    out.writeln(
      '*********************************************************************\n'
      'Eval Call Summary across $numRuns runs (by metric across all runs)\n'
      'Eval ID: ${aggResult.evalId}\n'
      'Overall Eval Status: ${_evalStatusUpperName(aggResult.finalEvalStatus)}\n'
      '---------------------------------------------------------------------',
    );
    final String? crashLine = describeCrashedRuns(aggResult);
    if (crashLine != null) {
      out.writeln(crashLine);
    }
    for (final EvalMetricResultSpec metricResult
        in aggResult.overallEvalMetricResults) {
      final MethodResult? methodResult =
          aggResult.metricMethods[metricResult.metricName];
      if (methodResult != null) {
        final String label =
            '${metricResult.metricName} [${methodResult.name}]';
        out.writeln(formatMethodResult(methodResult, label: label));
      } else {
        final double? thresh =
            metricResult.threshold ?? metricResult.criterion?.threshold;
        final String valStr = metricResult.score != null
            ? metricResult.score!.toStringAsFixed(4)
            : 'None';
        out.writeln(
          '  ${metricResult.metricName}: $valStr '
          '(Threshold: $thresh) (${_evalStatusUpperName(metricResult.evalStatus)})',
        );
      }
    }

    if (aggResult.crossRunResults.isNotEmpty) {
      out.writeln(
        '---------------------------------------------------------------------\n'
        'Across-run criteria (on whole-case pass/fail):',
      );
      for (final MethodResult methodResult in aggResult.crossRunResults) {
        out.writeln(
          formatMethodResult(methodResult, label: methodResult.name),
        );
      }
    }

    if (numRuns > 1) {
      out.writeln(
        '---------------------------------------------------------------------\n'
        'Per-run details:',
      );
      for (int i = 0; i < aggResult.runs.length; i += 1) {
        final int runIdx = i + 1;
        final EvalCaseResult caseResult = aggResult.runs[i];
        out.writeln(
          '\n=== Run $runIdx/$numRuns '
          '(session: ${caseResult.sessionId}, '
          'status: ${_evalStatusUpperName(caseResult.finalEvalStatus)}) ===',
        );
        out.writeln(prettyPrintEvalResult(caseResult));
      }
    }
  }
  return out.toString().trimRight();
}

/// Returns [rootAgent] for CLI module compatibility.
Agent getRootAgentFromModule(Agent rootAgent) => rootAgent;

/// Returns a `reset` callback from [moduleLike] when one is provided.
Object? tryGetResetFunc(Object? moduleLike) {
  if (moduleLike is Map<String, Object?> && moduleLike['reset'] is Function) {
    return moduleLike['reset'];
  }
  return null;
}
