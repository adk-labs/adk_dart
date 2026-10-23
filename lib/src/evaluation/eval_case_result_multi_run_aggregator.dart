/// Multi-run aggregation of per-repetition [EvalCaseResult]s.
library;

import 'eval_config.dart';
import 'eval_metric.dart';
import 'eval_metrics.dart';
import 'eval_result.dart';
import 'multi_run_aggregation_methods.dart';

/// Output of running one aggregation method on a metric or across an eval case.
class MethodResult {
  /// Creates a method evaluation result.
  const MethodResult({
    required this.name,
    this.value,
    this.threshold,
    required this.status,
    this.note,
  });

  /// Aggregation method name.
  final String name;

  /// Computed aggregated value (`null` when not evaluated).
  final double? value;

  /// Threshold compared against [value] (`null` when informational).
  final double? threshold;

  /// Resulting evaluation status (`passed`, `failed`, `notEvaluated`, or `informational`).
  final EvalStatus status;

  /// Optional human-readable breakdown (such as per-run pass/fail counts).
  final String? note;

  @override
  bool operator ==(Object other) {
    return other is MethodResult &&
        other.name == name &&
        other.value == value &&
        other.threshold == threshold &&
        other.status == status &&
        other.note == note;
  }

  @override
  int get hashCode => Object.hash(name, value, threshold, status, note);

  @override
  String toString() =>
      'MethodResult(name: $name, value: $value, threshold: $threshold, status: $status, note: $note)';
}

/// Aggregated cross-run result for one `(evalSetId, evalId)` pair.
class MultiRunCaseResult {
  /// Creates an aggregated multi-run case result.
  MultiRunCaseResult({
    required this.evalSetId,
    required this.evalId,
    required this.finalEvalStatus,
    List<EvalMetricResultSpec>? overallEvalMetricResults,
    List<EvalCaseResult>? runs,
    Map<String, MethodResult>? metricMethods,
    List<MethodResult>? crossRunResults,
    this.maxCrashedRuns = 0,
  }) : overallEvalMetricResults =
           overallEvalMetricResults ?? <EvalMetricResultSpec>[],
       runs = runs ?? <EvalCaseResult>[],
       metricMethods = metricMethods ?? <String, MethodResult>{},
       crossRunResults = crossRunResults ?? <MethodResult>[];

  /// Eval-set identifier.
  final String evalSetId;

  /// Eval-case identifier.
  final String evalId;

  /// Alias for [evalId].
  String get evalCaseId => evalId;

  /// Final aggregated evaluation status across runs.
  final EvalStatus finalEvalStatus;

  /// Aggregated per-metric evaluation results.
  final List<EvalMetricResultSpec> overallEvalMetricResults;

  /// Aggregated metric results exposed as [EvalMetricResult] values.
  List<EvalMetricResult> get metrics => overallEvalMetricResults
      .map(
        (EvalMetricResultSpec spec) => EvalMetricResult(
          metric: EvalMetric.values.firstWhere(
            (EvalMetric m) => m.name == spec.metricName,
            orElse: () => EvalMetric.finalResponseExactMatch,
          ),
          metricNameOverride: spec.metricName,
          score: spec.score ?? 0.0,
          threshold: spec.threshold ?? spec.criterion?.threshold,
          evalStatus: spec.evalStatus,
        ),
      )
      .toList(growable: false);

  /// Individual per-repetition [EvalCaseResult]s in repetition order.
  final List<EvalCaseResult> runs;

  /// Per-metric aggregation method results keyed by metric name.
  final Map<String, MethodResult> metricMethods;

  /// Case-level cross-run criterion results.
  final List<MethodResult> crossRunResults;

  /// Maximum number of crashed runs tolerated for this eval case.
  final int maxCrashedRuns;
}

/// Aggregator that combines per-repetition [EvalCaseResult] instances into
/// [MultiRunCaseResult] summaries.
///
/// ```dart
/// final results = EvalCaseResultMultiRunAggregator.aggregate(
///   perRunResults,
///   multiRunConfig: MultiRunConfig(numRuns: 3),
/// );
/// ```
class EvalCaseResultMultiRunAggregator {
  /// Creates a multi-run aggregator with an optional [multiRunConfig].
  const EvalCaseResultMultiRunAggregator({this.multiRunConfig});

  /// Optional configuration controlling cross-run scoring and criteria.
  final MultiRunConfig? multiRunConfig;

  /// Aggregates [evalCaseResults] using [multiRunConfig].
  List<MultiRunCaseResult> aggregateResults(
    List<EvalCaseResult> evalCaseResults,
  ) {
    return aggregateEvalCaseResults(
      evalCaseResults,
      multiRunConfig: multiRunConfig,
    );
  }

  /// Static helper that delegates to [aggregateEvalCaseResults].
  static List<MultiRunCaseResult> aggregate(
    List<EvalCaseResult> evalCaseResults, {
    MultiRunConfig? multiRunConfig,
  }) {
    return aggregateEvalCaseResults(
      evalCaseResults,
      multiRunConfig: multiRunConfig,
    );
  }
}

/// Computes the overall [EvalStatus] of a single [evalCaseResult] across its metrics.
EvalStatus getRunStatus(EvalCaseResult evalCaseResult) {
  final List<EvalStatus> metricStatuses = <EvalStatus>[
    for (final EvalMetricResultSpec metricResult
        in evalCaseResult.overallEvalMetricResults)
      if (metricResult.evalStatus != EvalStatus.notEvaluated)
        metricResult.evalStatus,
  ];
  if (metricStatuses.isEmpty) {
    return EvalStatus.notEvaluated;
  }
  if (metricStatuses.every((EvalStatus status) => status == EvalStatus.passed)) {
    return EvalStatus.passed;
  }
  return EvalStatus.failed;
}

/// Returns `true` when [multiRunConfig] configures any pass-count rule or cross-run criterion.
bool hasPassCountRules(MultiRunConfig? multiRunConfig) {
  if (multiRunConfig == null) {
    return false;
  }
  return multiRunConfig.crossRunScoring is MultiRunCriterion ||
      (multiRunConfig.crossRunScoringByMetric?.values.any(
            (Object rule) => rule is MultiRunCriterion,
          ) ??
          false) ||
      (multiRunConfig.crossRunCriteria != null &&
          multiRunConfig.crossRunCriteria!.isNotEmpty);
}

/// Returns the map of built-in and custom [AggregationMethod]s for [multiRunConfig].
Map<String, AggregationMethod> loadAggregationMethods(
  MultiRunConfig? multiRunConfig,
) {
  final Map<String, AggregationMethod> methods = getBuiltInAggregationMethods();
  if (multiRunConfig != null && multiRunConfig.customMethods != null) {
    for (final MapEntry<String, CustomCrossRunMethodConfig> entry
        in multiRunConfig.customMethods!.entries) {
      methods[entry.key] = loadCustomAggregationMethod(entry.key, entry.value);
    }
  }
  return methods;
}

/// Counts runs in [perCaseResults] that failed during inference before metrics ran.
int countRunsFailedWithoutMetricResults(List<EvalCaseResult> perCaseResults) {
  int count = 0;
  for (final EvalCaseResult result in perCaseResults) {
    if (result.finalEvalStatus == EvalStatus.failed &&
        result.overallEvalMetricResults.isEmpty &&
        result.metrics.isEmpty) {
      count += 1;
    }
  }
  return count;
}

/// Formats a human-readable summary of run [statuses] and [crashed] counts.
String describeRunStatuses(List<EvalStatus> statuses, {int crashed = 0}) {
  final int passed = statuses
      .where((EvalStatus s) => s == EvalStatus.passed)
      .length;
  final int failed =
      statuses.where((EvalStatus s) => s == EvalStatus.failed).length - crashed;
  final int notEval = statuses
      .where((EvalStatus s) => s == EvalStatus.notEvaluated)
      .length;
  final List<String> parts = <String>[];
  if (passed > 0 || (failed == 0 && notEval == 0 && crashed == 0)) {
    parts.add('$passed passed');
  }
  if (failed > 0) {
    parts.add('$failed failed');
  }
  if (crashed > 0) {
    parts.add('$crashed crashed');
  }
  if (notEval > 0) {
    parts.add('$notEval not evaluated');
  }
  return parts.isNotEmpty ? parts.join(', ') : '0 runs';
}

MethodResult _runAggregationMethod(
  AggregationMethod method,
  List<RunResult> runs,
  double? threshold, {
  String? note,
}) {
  final double? value = method.compute(runs);
  final EvalStatus status;
  if (value == null) {
    status = EvalStatus.notEvaluated;
  } else if (threshold == null) {
    status = EvalStatus.informational;
  } else if (value >= threshold) {
    status = EvalStatus.passed;
  } else {
    status = EvalStatus.failed;
  }
  return MethodResult(
    name: method.name,
    value: value,
    threshold: threshold,
    status: status,
    note: note,
  );
}

List<RunResult> _buildMetricRuns(
  String metricName,
  List<EvalCaseResult> perCaseResults,
) {
  final List<RunResult> runs = <RunResult>[];
  for (final EvalCaseResult caseResult in perCaseResults) {
    EvalMetricResultSpec? overall;
    for (final EvalMetricResultSpec m in caseResult.overallEvalMetricResults) {
      if (m.metricName == metricName) {
        overall = m;
        break;
      }
    }
    final List<double?> invScores = <double?>[];
    for (final EvalMetricResultPerInvocation perInv
        in caseResult.evalMetricResultPerInvocation) {
      for (final EvalMetricResultSpec m in perInv.evalMetricResults) {
        if (m.metricName == metricName) {
          invScores.add(m.score);
        }
      }
    }
    if (overall != null) {
      runs.add(
        RunResult(
          status: overall.evalStatus,
          score: overall.score,
          invocationScores: invScores,
        ),
      );
    } else if (caseResult.finalEvalStatus == EvalStatus.failed &&
        caseResult.overallEvalMetricResults.isEmpty) {
      runs.add(RunResult(status: EvalStatus.failed));
    } else {
      runs.add(RunResult(status: EvalStatus.notEvaluated));
    }
  }
  return runs;
}

(AggregationMethod, double?) _resolveMetricRule(
  String metricName,
  EvalMetricResultSpec template,
  MultiRunConfig? multiRunConfig,
  Map<String, AggregationMethod> methods,
) {
  Object rule = defaultAggregationMethod.name;
  if (multiRunConfig != null) {
    if (multiRunConfig.crossRunScoringByMetric != null &&
        multiRunConfig.crossRunScoringByMetric!.containsKey(metricName)) {
      rule = multiRunConfig.crossRunScoringByMetric![metricName]!;
    } else {
      rule = multiRunConfig.crossRunScoring;
    }
  }
  if (rule is MultiRunCriterion) {
    return (methods[rule.method]!, rule.threshold);
  }
  final String ruleName = rule as String;
  final double? metricThreshold =
      template.threshold ?? template.criterion?.threshold;
  return (methods[ruleName]!, metricThreshold);
}

(List<EvalMetricResultSpec>, Map<String, MethodResult>)
_aggregateMetricsForCase(
  List<EvalCaseResult> perCaseResults,
  MultiRunConfig? multiRunConfig,
  Map<String, AggregationMethod> methods,
) {
  final Map<String, EvalMetricResultSpec> metricTemplates =
      <String, EvalMetricResultSpec>{};
  for (final EvalCaseResult caseResult in perCaseResults) {
    for (final EvalMetricResultSpec m in caseResult.overallEvalMetricResults) {
      metricTemplates.putIfAbsent(m.metricName, () => m);
    }
  }

  final int crashed = countRunsFailedWithoutMetricResults(perCaseResults);
  final List<EvalMetricResultSpec> aggregatedMetrics = <EvalMetricResultSpec>[];
  final Map<String, MethodResult> metricMethods = <String, MethodResult>{};

  for (final MapEntry<String, EvalMetricResultSpec> entry
      in metricTemplates.entries) {
    final String metricName = entry.key;
    final EvalMetricResultSpec template = entry.value;
    final List<RunResult> runs = _buildMetricRuns(metricName, perCaseResults);
    final (AggregationMethod method, double? threshold) = _resolveMetricRule(
      metricName,
      template,
      multiRunConfig,
      methods,
    );
    final String? note = method.usesScores
        ? null
        : describeRunStatuses(
            <EvalStatus>[for (final RunResult r in runs) r.status],
            crashed: crashed,
          );
    final MethodResult methodResult = _runAggregationMethod(
      method,
      runs,
      threshold,
      note: note,
    );
    metricMethods[metricName] = methodResult;

    final double? score = method.usesScores
        ? methodResult.value
        : defaultAggregationMethod.compute(runs);
    final List<EvalStatus> evaluatedRunStatuses = <EvalStatus>[
      for (final RunResult r in runs)
        if (r.status != EvalStatus.notEvaluated) r.status,
    ];
    final EvalStatus evalStatus =
        methodResult.status == EvalStatus.informational
        ? (evaluatedRunStatuses.isEmpty
              ? EvalStatus.notEvaluated
              : (evaluatedRunStatuses.every(
                      (EvalStatus s) => s == EvalStatus.passed,
                    )
                    ? EvalStatus.passed
                    : EvalStatus.failed))
        : methodResult.status;

    aggregatedMetrics.add(
      EvalMetricResultSpec(
        metricName: template.metricName,
        threshold: template.threshold,
        criterion: template.criterion,
        customFunctionPath: template.customFunctionPath,
        score: score,
        evalStatus: evalStatus,
      ),
    );
  }

  return (aggregatedMetrics, metricMethods);
}

List<MethodResult> _evaluateCrossRunCriteria(
  List<EvalCaseResult> perCaseResults,
  MultiRunConfig? multiRunConfig,
  Map<String, AggregationMethod> methods,
) {
  if (multiRunConfig == null ||
      multiRunConfig.crossRunCriteria == null ||
      multiRunConfig.crossRunCriteria!.isEmpty) {
    return <MethodResult>[];
  }
  final List<RunResult> caseRuns = <RunResult>[
    for (final EvalCaseResult r in perCaseResults)
      RunResult(status: r.finalEvalStatus),
  ];
  final String runBreakdown = describeRunStatuses(
    <EvalStatus>[for (final RunResult r in caseRuns) r.status],
    crashed: countRunsFailedWithoutMetricResults(perCaseResults),
  );
  return <MethodResult>[
    for (final MultiRunCriterion criterion in multiRunConfig.crossRunCriteria!)
      _runAggregationMethod(
        methods[criterion.method]!,
        caseRuns,
        criterion.threshold,
        note: runBreakdown,
      ),
  ];
}

/// Groups [evalCaseResults] by `(evalSetId, evalId)` and aggregates each case across runs.
List<MultiRunCaseResult> aggregateEvalCaseResults(
  List<EvalCaseResult> evalCaseResults, {
  MultiRunConfig? multiRunConfig,
}) {
  final Map<String, AggregationMethod> methods = loadAggregationMethods(
    multiRunConfig,
  );
  final int maxCrashedRuns = multiRunConfig?.maxCrashedRuns ?? 0;

  final List<(String, String)> groupOrder = <(String, String)>[];
  final Map<(String, String), List<(int, EvalCaseResult)>> grouped =
      <(String, String), List<(int, EvalCaseResult)>>{};

  for (int i = 0; i < evalCaseResults.length; i += 1) {
    final EvalCaseResult result = evalCaseResults[i];
    final (String, String) key = (result.evalSetId, result.evalId);
    if (!grouped.containsKey(key)) {
      groupOrder.add(key);
      grouped[key] = <(int, EvalCaseResult)>[];
    }
    grouped[key]!.add((i, result));
  }

  final List<MultiRunCaseResult> aggregated = <MultiRunCaseResult>[];
  for (final (String evalSetId, String evalId) in groupOrder) {
    final List<(int, EvalCaseResult)> indexedGroup =
        grouped[(evalSetId, evalId)]!;
    indexedGroup.sort(((int, EvalCaseResult) a, (int, EvalCaseResult) b) {
      final int aHasRep = a.$2.repetitionIndex != null ? 0 : 1;
      final int bHasRep = b.$2.repetitionIndex != null ? 0 : 1;
      if (aHasRep != bHasRep) {
        return aHasRep.compareTo(bHasRep);
      }
      final int repCompare = (a.$2.repetitionIndex ?? 0).compareTo(
        b.$2.repetitionIndex ?? 0,
      );
      if (repCompare != 0) {
        return repCompare;
      }
      return a.$1.compareTo(b.$1);
    });
    final List<EvalCaseResult> ordered = <EvalCaseResult>[
      for (final (int _, EvalCaseResult item) in indexedGroup) item,
    ];

    final (
      List<EvalMetricResultSpec> aggMetrics,
      Map<String, MethodResult> metricMethods,
    ) = _aggregateMetricsForCase(
      ordered,
      multiRunConfig,
      methods,
    );
    final List<MethodResult> crossRunResults = _evaluateCrossRunCriteria(
      ordered,
      multiRunConfig,
      methods,
    );

    final int crashed = countRunsFailedWithoutMetricResults(ordered);
    final List<EvalStatus> gatedStatuses = <EvalStatus>[
      for (final EvalMetricResultSpec m in aggMetrics)
        if (m.evalStatus != EvalStatus.notEvaluated &&
            m.evalStatus != EvalStatus.informational)
          m.evalStatus,
      for (final MethodResult c in crossRunResults)
        if (c.status != EvalStatus.notEvaluated &&
            c.status != EvalStatus.informational)
          c.status,
    ];

    final EvalStatus finalStatus;
    if (crashed > maxCrashedRuns) {
      finalStatus = EvalStatus.failed;
    } else if (gatedStatuses.isNotEmpty) {
      finalStatus = gatedStatuses.every(
            (EvalStatus s) => s == EvalStatus.passed,
          )
          ? EvalStatus.passed
          : EvalStatus.failed;
    } else if (ordered.any(
      (EvalCaseResult r) => r.finalEvalStatus == EvalStatus.failed,
    )) {
      finalStatus = EvalStatus.failed;
    } else {
      finalStatus = EvalStatus.notEvaluated;
    }

    aggregated.add(
      MultiRunCaseResult(
        evalSetId: evalSetId,
        evalId: evalId,
        finalEvalStatus: finalStatus,
        overallEvalMetricResults: aggMetrics,
        runs: ordered,
        metricMethods: metricMethods,
        crossRunResults: crossRunResults,
        maxCrashedRuns: maxCrashedRuns,
      ),
    );
  }

  return aggregated;
}
