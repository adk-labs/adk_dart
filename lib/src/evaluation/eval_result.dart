/// Evaluation result models used by eval services and CLI output.
library;

import '../sessions/session.dart';
import 'eval_case.dart';
import 'eval_metric.dart';
import 'eval_metrics.dart';

/// Inference execution status for one eval case.
enum InferenceStatus {
  /// Inference status has not been determined.
  unknown,

  /// Inference completed without error.
  success,

  /// Inference failed with an error.
  failure,
}

/// Evaluation pass/fail status.
enum EvalStatus {
  /// Metric score met or exceeded its threshold.
  passed,

  /// Metric score fell below its threshold.
  failed,

  /// Metric was not evaluated or produced no score.
  notEvaluated,

  /// Status for an indicator computed across runs without a pass/fail threshold.
  informational,
}

/// Result of running model inference for an eval case.
class InferenceResult {
  /// Creates an inference result.
  InferenceResult({
    required this.appName,
    String? evalCaseId,
    String? evalId,
    this.userInput = '',
    this.evalSetId = '',
    this.inferences,
    this.responseText,
    this.sessionId,
    this.status = InferenceStatus.unknown,
    this.errorMessage,
    this.repetitionIndex,
  }) : evalCaseId = evalCaseId ?? evalId ?? '';

  /// Application name used for inference.
  final String appName;

  /// Parent eval set identifier.
  final String evalSetId;

  /// Eval case identifier.
  final String evalCaseId;

  /// Alias for [evalCaseId] matching upstream naming.
  String get evalId => evalCaseId;

  /// Input text sent to the model.
  final String userInput;

  /// Optional list of per-turn invocations captured during inference.
  final List<Invocation>? inferences;

  /// Optional model response text.
  final String? responseText;

  /// Optional session identifier used during inference.
  final String? sessionId;

  /// Inference status.
  final InferenceStatus status;

  /// Optional error message.
  final String? errorMessage;

  /// Zero-based index when an eval case is run multiple times (`numRuns > 1`).
  ///
  /// `null` for single-run execution.
  final int? repetitionIndex;
}

/// One metric evaluation result.
class EvalMetricResult {
  /// Creates a metric result.
  EvalMetricResult({
    required this.metric,
    required this.score,
    bool passed = false,
    EvalStatus? evalStatus,
    this.detail,
    this.metricNameOverride,
    this.threshold,
  }) : evalStatus =
           evalStatus ?? (passed ? EvalStatus.passed : EvalStatus.failed),
       passed = evalStatus == null ? passed : evalStatus == EvalStatus.passed;

  /// Metric identifier.
  final EvalMetric metric;

  /// Optional raw metric name when the metric is not one of [EvalMetric].
  final String? metricNameOverride;

  /// Resolved metric name string.
  String get metricName => metricNameOverride ?? metric.name;

  /// Metric score value.
  final double score;

  /// Optional pass/fail threshold for this metric.
  final double? threshold;

  /// Whether this metric passed.
  final bool passed;

  /// Metric evaluation status.
  final EvalStatus evalStatus;

  /// Optional metric detail text.
  final String? detail;

  /// Creates a metric result from JSON.
  factory EvalMetricResult.fromJson(Map<String, Object?> json) {
    final String rawMetricName =
        (json['metric_name'] ?? json['metricName'] ?? json['metric'] ?? '')
            .toString();
    final EvalMetric metric = _evalMetricFromString(rawMetricName);
    final bool? rawPassed = json['passed'] as bool?;
    final Object? rawEvalStatus = json['eval_status'] ?? json['evalStatus'];
    final EvalStatus parsedEvalStatus = rawEvalStatus == null
        ? (rawPassed == null
              ? EvalStatus.notEvaluated
              : (rawPassed ? EvalStatus.passed : EvalStatus.failed))
        : _evalStatusFromString(rawEvalStatus.toString());
    final Object? rawThreshold = json['threshold'];
    return EvalMetricResult(
      metric: metric,
      metricNameOverride: rawMetricName.isEmpty ? null : rawMetricName,
      score: _asDouble(json['score']),
      threshold: rawThreshold is num ? rawThreshold.toDouble() : null,
      evalStatus: parsedEvalStatus,
      detail: _metricDetailFromJson(json),
    );
  }

  /// Serializes this metric result to JSON.
  Map<String, Object?> toJson() {
    final Map<String, Object?> details = <String, Object?>{};
    if (detail != null) {
      details['detail'] = detail;
    }
    return <String, Object?>{
      'metric_name': metricName,
      'score': score,
      if (threshold != null) 'threshold': threshold,
      'eval_status': _evalStatusToJson(evalStatus),
      'details': details,
    };
  }
}

/// Aggregated evaluation result for one eval case.
class EvalCaseResult {
  /// Creates an eval-case result.
  EvalCaseResult({
    String? evalCaseId,
    String? evalId,
    List<EvalMetricResult>? metrics,
    List<EvalMetricResultSpec>? overallEvalMetricResults,
    List<EvalMetricResultPerInvocation>? evalMetricResultPerInvocation,
    this.evalSetId = '',
    this.finalEvalStatus = EvalStatus.notEvaluated,
    this.sessionId = '',
    this.sessionDetails,
    this.userId,
    this.evalSetFile,
    this.repetitionIndex,
  }) : evalCaseId = evalCaseId ?? evalId ?? '',
       metrics =
           metrics ??
           _metricsFromSpecs(overallEvalMetricResults ?? const <EvalMetricResultSpec>[]),
       overallEvalMetricResults =
           overallEvalMetricResults ??
           _specsFromMetrics(metrics ?? const <EvalMetricResult>[]),
       evalMetricResultPerInvocation =
           evalMetricResultPerInvocation ?? const <EvalMetricResultPerInvocation>[];

  /// Eval case identifier.
  final String evalCaseId;

  /// Alias for [evalCaseId] matching upstream naming.
  String get evalId => evalCaseId;

  /// Metric results for this case.
  final List<EvalMetricResult> metrics;

  /// Overall evaluated metric specs for this case across the full conversation.
  final List<EvalMetricResultSpec> overallEvalMetricResults;

  /// Per-invocation evaluated metric results for this case.
  final List<EvalMetricResultPerInvocation> evalMetricResultPerInvocation;

  /// Parent eval set identifier.
  final String evalSetId;

  /// Final evaluation status.
  final EvalStatus finalEvalStatus;

  /// Session ID used for inference.
  final String sessionId;

  /// Optional session details captured during inference.
  final Session? sessionDetails;

  /// Optional user ID used for inference.
  final String? userId;

  /// Optional source eval-set file path.
  final String? evalSetFile;

  /// Zero-based index when an eval case is run multiple times (`numRuns > 1`).
  ///
  /// `null` for single-run execution.
  final int? repetitionIndex;

  static List<EvalMetricResult> _metricsFromSpecs(
    List<EvalMetricResultSpec> specs,
  ) {
    return specs
        .map(
          (EvalMetricResultSpec spec) => EvalMetricResult(
            metric: _evalMetricFromString(spec.metricName),
            metricNameOverride: spec.metricName,
            score: spec.score ?? 0.0,
            threshold: spec.threshold ?? spec.criterion?.threshold,
            evalStatus: spec.evalStatus,
          ),
        )
        .toList(growable: false);
  }

  static List<EvalMetricResultSpec> _specsFromMetrics(
    List<EvalMetricResult> metrics,
  ) {
    return metrics
        .map(
          (EvalMetricResult m) => EvalMetricResultSpec(
            metricName: m.metricName,
            threshold: m.threshold,
            score: m.evalStatus == EvalStatus.notEvaluated ? null : m.score,
            evalStatus: m.evalStatus,
          ),
        )
        .toList(growable: false);
  }

  /// Average score across [metrics].
  double get overallScore {
    if (metrics.isEmpty) {
      return 0;
    }
    final double sum = metrics.fold<double>(
      0,
      (double acc, EvalMetricResult metric) => acc + metric.score,
    );
    return sum / metrics.length;
  }

  /// Creates an eval-case result from JSON.
  factory EvalCaseResult.fromJson(Map<String, Object?> json) {
    final Object? rawMetrics =
        json['metrics'] ??
        json['overallEvalMetricResults'] ??
        json['overall_eval_metric_results'] ??
        json['evalMetricResults'] ??
        json['eval_metric_results'];
    final List<EvalMetricResult> metrics = <EvalMetricResult>[];
    final List<EvalMetricResultSpec> overallSpecs = <EvalMetricResultSpec>[];
    if (rawMetrics is List) {
      for (final Object? item in rawMetrics) {
        if (item is Map) {
          final Map<String, Object?> map = _castJsonMap(item);
          metrics.add(EvalMetricResult.fromJson(map));
          overallSpecs.add(_metricResultSpecFromJson(map));
        }
      }
    }
    final Object? rawRepIndex =
        json['repetitionIndex'] ?? json['repetition_index'];
    return EvalCaseResult(
      evalCaseId:
          (json['evalCaseId'] ?? json['eval_id'] ?? json['evalId'] ?? '')
              .toString(),
      metrics: metrics,
      overallEvalMetricResults: overallSpecs,
      evalSetId: (json['evalSetId'] ?? json['eval_set_id'] ?? '').toString(),
      finalEvalStatus: _evalStatusFromString(
        (json['finalEvalStatus'] ?? json['final_eval_status']).toString(),
      ),
      sessionId: (json['sessionId'] ?? json['session_id'] ?? '').toString(),
      userId: (json['userId'] ?? json['user_id']) as String?,
      evalSetFile: (json['evalSetFile'] ?? json['eval_set_file']) as String?,
      repetitionIndex: rawRepIndex is int
          ? rawRepIndex
          : (rawRepIndex is num ? rawRepIndex.toInt() : null),
    );
  }

  /// Serializes this eval-case result to JSON.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'eval_id': evalCaseId,
      'eval_set_id': evalSetId,
      'final_eval_status': finalEvalStatus.name,
      'overall_eval_metric_results': metrics
          .map((EvalMetricResult value) => value.toJson())
          .toList(),
      'session_id': sessionId,
      if (userId != null) 'user_id': userId,
      if (evalSetFile != null) 'eval_set_file': evalSetFile,
      if (repetitionIndex != null) 'repetition_index': repetitionIndex,
    };
  }
}

/// How one aggregation rule judged the runs of an eval case.
///
/// The rule's target is either a single metric or the whole eval case.
class MethodResult {
  /// Creates a method evaluation result.
  const MethodResult({
    required this.name,
    this.value,
    this.threshold,
    required this.status,
    this.note,
  });

  /// Aggregation method name (e.g. `"mean_over_invocations"`).
  final String name;

  /// Computed aggregated value over the runs (`null` when not evaluated).
  final double? value;

  /// Value needed to pass (`null` when informational).
  final double? threshold;

  /// Resulting evaluation status (`passed`, `failed`, `notEvaluated`, or `informational`).
  final EvalStatus status;

  /// Optional human-readable breakdown (such as per-run pass/fail counts).
  final String? note;

  /// Creates a [MethodResult] from JSON (supporting snake_case and camelCase).
  factory MethodResult.fromJson(Map<String, Object?> json) {
    final Object? rawValue = json['value'];
    final Object? rawThreshold = json['threshold'];
    final Object? rawStatus = json['status'];
    return MethodResult(
      name: (json['name'] ?? '').toString(),
      value: rawValue is num ? rawValue.toDouble() : null,
      threshold: rawThreshold is num ? rawThreshold.toDouble() : null,
      status: rawStatus == null
          ? EvalStatus.notEvaluated
          : _evalStatusFromString(rawStatus.toString()),
      note: json['note'] as String?,
    );
  }

  /// Serializes this [MethodResult] to JSON.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'name': name,
      'value': value,
      'threshold': threshold,
      'status': _evalStatusToJson(status),
      if (note != null) 'note': note,
    };
  }

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

/// Persisted cross-run summary for one eval case across all of its runs.
class MultiRunCaseSummary {
  /// Creates a persisted multi-run case summary.
  MultiRunCaseSummary({
    this.evalSetId = '',
    String? evalId,
    String? evalCaseId,
    required this.finalEvalStatus,
    required this.numRuns,
    required this.passedRuns,
    required this.failedRuns,
    this.crashedRuns = 0,
    this.notEvaluatedRuns = 0,
    this.passRate,
    List<EvalMetricResultSpec>? overallEvalMetricResults,
    List<EvalMetricResult>? metrics,
    Map<String, MethodResult>? metricMethods,
    List<MethodResult>? crossRunResults,
    this.maxCrashedRuns = 0,
  }) : evalId = evalId ?? evalCaseId ?? '',
       overallEvalMetricResults = List<EvalMetricResultSpec>.unmodifiable(
         overallEvalMetricResults ??
             (metrics != null
                 ? EvalCaseResult._specsFromMetrics(metrics)
                 : const <EvalMetricResultSpec>[]),
       ),
       metricMethods = Map<String, MethodResult>.unmodifiable(
         metricMethods ?? const <String, MethodResult>{},
       ),
       crossRunResults = List<MethodResult>.unmodifiable(
         crossRunResults ?? const <MethodResult>[],
       );

  /// Eval set identifier.
  final String evalSetId;

  /// Eval case identifier.
  final String evalId;

  /// Alias for [evalId].
  String get evalCaseId => evalId;

  /// Final status of the eval case across all of its runs.
  final EvalStatus finalEvalStatus;

  /// Total number of runs recorded for this eval case.
  final int numRuns;

  /// Number of runs that passed as a whole (`getRunStatus == EvalStatus.passed`).
  final int passedRuns;

  /// Number of runs that failed as a whole (`getRunStatus == EvalStatus.failed`).
  final int failedRuns;

  /// Number of runs that failed without producing any metric results.
  final int crashedRuns;

  /// Number of non-crashed runs whose whole-run status was [EvalStatus.notEvaluated].
  final int notEvaluatedRuns;

  /// Fraction of decided (passed or failed) runs that passed, or `null` if no run was decided.
  final double? passRate;

  /// One result per metric, aggregated across all runs.
  final List<EvalMetricResultSpec> overallEvalMetricResults;

  /// Aggregated metric results exposed as [EvalMetricResult] values.
  List<EvalMetricResult> get metrics =>
      EvalCaseResult._metricsFromSpecs(overallEvalMetricResults);

  /// How each metric was judged on the runs, keyed by metric name.
  final Map<String, MethodResult> metricMethods;

  /// How each configured cross-run criterion judged the runs, in order.
  final List<MethodResult> crossRunResults;

  /// How many runs may crash before the case fails.
  final int maxCrashedRuns;

  /// Creates a [MultiRunCaseSummary] from JSON (supporting snake_case and camelCase).
  factory MultiRunCaseSummary.fromJson(Map<String, Object?> json) {
    final List<EvalMetricResultSpec> overallSpecs = <EvalMetricResultSpec>[];
    final Object? rawOverallMetrics =
        json['overall_eval_metric_results'] ?? json['overallEvalMetricResults'];
    if (rawOverallMetrics is List) {
      for (final Object? item in rawOverallMetrics) {
        if (item is Map) {
          overallSpecs.add(_metricResultSpecFromJson(_castJsonMap(item)));
        }
      }
    }

    final Map<String, MethodResult> parsedMetricMethods =
        <String, MethodResult>{};
    final Object? rawMetricMethods =
        json['metric_methods'] ?? json['metricMethods'];
    if (rawMetricMethods is Map) {
      for (final MapEntry<Object?, Object?> entry in rawMetricMethods.entries) {
        if (entry.value is Map) {
          parsedMetricMethods['${entry.key}'] = MethodResult.fromJson(
            _castJsonMap(entry.value as Map),
          );
        }
      }
    }

    final List<MethodResult> parsedCrossRunResults = <MethodResult>[];
    final Object? rawCrossRunResults =
        json['cross_run_results'] ?? json['crossRunResults'];
    if (rawCrossRunResults is List) {
      for (final Object? item in rawCrossRunResults) {
        if (item is Map) {
          parsedCrossRunResults.add(
            MethodResult.fromJson(_castJsonMap(item)),
          );
        }
      }
    }

    final Object? rawPassRate = json['pass_rate'] ?? json['passRate'];
    return MultiRunCaseSummary(
      evalSetId: (json['eval_set_id'] ?? json['evalSetId'] ?? '').toString(),
      evalId:
          (json['eval_id'] ?? json['evalId'] ?? json['evalCaseId'] ?? '')
              .toString(),
      finalEvalStatus: _evalStatusFromString(
        (json['final_eval_status'] ?? json['finalEvalStatus'] ?? '').toString(),
      ),
      numRuns: _asInt(json['num_runs'] ?? json['numRuns']),
      passedRuns: _asInt(json['passed_runs'] ?? json['passedRuns']),
      failedRuns: _asInt(json['failed_runs'] ?? json['failedRuns']),
      crashedRuns: _asInt(json['crashed_runs'] ?? json['crashedRuns']),
      notEvaluatedRuns: _asInt(
        json['not_evaluated_runs'] ?? json['notEvaluatedRuns'],
      ),
      passRate: rawPassRate is num ? rawPassRate.toDouble() : null,
      overallEvalMetricResults: overallSpecs,
      metricMethods: parsedMetricMethods,
      crossRunResults: parsedCrossRunResults,
      maxCrashedRuns: _asInt(json['max_crashed_runs'] ?? json['maxCrashedRuns']),
    );
  }

  /// Serializes this [MultiRunCaseSummary] to JSON.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'eval_set_id': evalSetId,
      'eval_id': evalId,
      'final_eval_status': _evalStatusToJson(finalEvalStatus),
      'num_runs': numRuns,
      'passed_runs': passedRuns,
      'failed_runs': failedRuns,
      'crashed_runs': crashedRuns,
      'not_evaluated_runs': notEvaluatedRuns,
      'pass_rate': passRate,
      'overall_eval_metric_results': overallEvalMetricResults
          .map((EvalMetricResultSpec value) => value.toJson())
          .toList(),
      'metric_methods': metricMethods.map(
        (String key, MethodResult value) => MapEntry(key, value.toJson()),
      ),
      'cross_run_results': crossRunResults
          .map((MethodResult value) => value.toJson())
          .toList(),
      'max_crashed_runs': maxCrashedRuns,
    };
  }

  static bool _metricSpecsEqual(
    List<EvalMetricResultSpec> a,
    List<EvalMetricResultSpec> b,
  ) {
    if (a.length != b.length) {
      return false;
    }
    for (int i = 0; i < a.length; i += 1) {
      final EvalMetricResultSpec x = a[i];
      final EvalMetricResultSpec y = b[i];
      if (x.metricName != y.metricName ||
          x.threshold != y.threshold ||
          x.score != y.score ||
          x.evalStatus != y.evalStatus ||
          x.customFunctionPath != y.customFunctionPath) {
        return false;
      }
    }
    return true;
  }

  static bool _metricMethodsEqual(
    Map<String, MethodResult> a,
    Map<String, MethodResult> b,
  ) {
    if (a.length != b.length) {
      return false;
    }
    for (final MapEntry<String, MethodResult> entry in a.entries) {
      if (b[entry.key] != entry.value) {
        return false;
      }
    }
    return true;
  }

  static bool _methodListEqual(List<MethodResult> a, List<MethodResult> b) {
    if (a.length != b.length) {
      return false;
    }
    for (int i = 0; i < a.length; i += 1) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }

  @override
  bool operator ==(Object other) {
    return other is MultiRunCaseSummary &&
        other.evalSetId == evalSetId &&
        other.evalId == evalId &&
        other.finalEvalStatus == finalEvalStatus &&
        other.numRuns == numRuns &&
        other.passedRuns == passedRuns &&
        other.failedRuns == failedRuns &&
        other.crashedRuns == crashedRuns &&
        other.notEvaluatedRuns == notEvaluatedRuns &&
        other.passRate == passRate &&
        other.maxCrashedRuns == maxCrashedRuns &&
        _metricSpecsEqual(
          other.overallEvalMetricResults,
          overallEvalMetricResults,
        ) &&
        _metricMethodsEqual(other.metricMethods, metricMethods) &&
        _methodListEqual(other.crossRunResults, crossRunResults);
  }

  @override
  int get hashCode => Object.hash(
    evalSetId,
    evalId,
    finalEvalStatus,
    numRuns,
    passedRuns,
    failedRuns,
    crashedRuns,
    notEvaluatedRuns,
    passRate,
    maxCrashedRuns,
    Object.hashAll(
      overallEvalMetricResults.map(
        (EvalMetricResultSpec m) =>
            Object.hash(m.metricName, m.threshold, m.score, m.evalStatus),
      ),
    ),
    Object.hashAllUnordered(
      metricMethods.entries.map(
        (MapEntry<String, MethodResult> e) => Object.hash(e.key, e.value),
      ),
    ),
    Object.hashAll(crossRunResults),
  );
}

/// Aggregated result for an eval-set execution.
class EvalSetResult {
  /// Creates an eval-set result.
  EvalSetResult({
    required this.evalSetResultId,
    this.evalSetResultName,
    required this.evalSetId,
    List<EvalCaseResult>? evalCaseResults,
    this.multiRunCaseSummaries,
    this.creationTimestamp = 0,
  }) : evalCaseResults = evalCaseResults ?? <EvalCaseResult>[];

  /// Eval-set result identifier.
  final String evalSetResultId;

  /// Optional display name for this result.
  final String? evalSetResultName;

  /// Eval-set identifier.
  final String evalSetId;

  /// Per-case evaluation results.
  final List<EvalCaseResult> evalCaseResults;

  /// Optional persisted multi-run summaries for each eval case.
  final List<MultiRunCaseSummary>? multiRunCaseSummaries;

  /// Creation timestamp in seconds since epoch.
  final double creationTimestamp;

  /// Creates an eval-set result from JSON.
  factory EvalSetResult.fromJson(Map<String, Object?> json) {
    final List<EvalCaseResult> caseResults = <EvalCaseResult>[];
    final Object? raw = json['evalCaseResults'] ?? json['eval_case_results'];
    if (raw is List) {
      for (final Object? item in raw) {
        if (item is Map) {
          caseResults.add(EvalCaseResult.fromJson(_castJsonMap(item)));
        }
      }
    }

    List<MultiRunCaseSummary>? summaries;
    final Object? rawSummaries =
        json['multiRunCaseSummaries'] ?? json['multi_run_case_summaries'];
    if (rawSummaries is List) {
      summaries = <MultiRunCaseSummary>[
        for (final Object? item in rawSummaries)
          if (item is Map) MultiRunCaseSummary.fromJson(_castJsonMap(item)),
      ];
    }

    return EvalSetResult(
      evalSetResultId:
          (json['evalSetResultId'] ?? json['eval_set_result_id'] ?? '')
              .toString(),
      evalSetResultName:
          (json['evalSetResultName'] ?? json['eval_set_result_name'])
              as String?,
      evalSetId: (json['evalSetId'] ?? json['eval_set_id'] ?? '').toString(),
      evalCaseResults: caseResults,
      multiRunCaseSummaries: summaries,
      creationTimestamp: _asDouble(
        json['creationTimestamp'] ?? json['creation_timestamp'],
      ),
    );
  }

  /// Serializes this eval-set result to JSON.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'eval_set_result_id': evalSetResultId,
      if (evalSetResultName != null) 'eval_set_result_name': evalSetResultName,
      'eval_set_id': evalSetId,
      'eval_case_results': evalCaseResults
          .map((EvalCaseResult value) => value.toJson())
          .toList(),
      if (multiRunCaseSummaries != null)
        'multi_run_case_summaries': multiRunCaseSummaries!
            .map((MultiRunCaseSummary value) => value.toJson())
            .toList(),
      'creation_timestamp': creationTimestamp,
    };
  }
}

EvalMetric _evalMetricFromString(String name) {
  final String normalizedName = _normalizeSnakeLike(name);
  for (final EvalMetric value in EvalMetric.values) {
    if (value.name == name ||
        _normalizeSnakeLike(value.name) == normalizedName) {
      return value;
    }
  }
  return EvalMetric.finalResponseExactMatch;
}

EvalStatus _evalStatusFromString(String value) {
  final String normalized = _normalizeSnakeLike(value);
  switch (normalized) {
    case 'passed':
    case '1':
      return EvalStatus.passed;
    case 'failed':
    case '2':
      return EvalStatus.failed;
    case 'not_evaluated':
    case '3':
      return EvalStatus.notEvaluated;
    case 'informational':
    case '4':
      return EvalStatus.informational;
  }
  return EvalStatus.notEvaluated;
}

String _evalStatusToJson(EvalStatus status) {
  switch (status) {
    case EvalStatus.passed:
      return 'passed';
    case EvalStatus.failed:
      return 'failed';
    case EvalStatus.notEvaluated:
      return 'not_evaluated';
    case EvalStatus.informational:
      return 'informational';
  }
}

EvalMetricResultSpec _metricResultSpecFromJson(Map<String, Object?> json) {
  final String metricName =
      (json['metric_name'] ?? json['metricName'] ?? json['metric'] ?? '')
          .toString();
  final bool? rawPassed = json['passed'] as bool?;
  final Object? rawEvalStatus = json['eval_status'] ?? json['evalStatus'];
  final EvalStatus parsedEvalStatus = rawEvalStatus == null
      ? (rawPassed == null
            ? EvalStatus.notEvaluated
            : (rawPassed ? EvalStatus.passed : EvalStatus.failed))
      : _evalStatusFromString(rawEvalStatus.toString());
  final Object? rawThreshold = json['threshold'];
  final Object? rawScore = json['score'];
  final Object? rawCriterion = json['criterion'];
  return EvalMetricResultSpec(
    metricName: metricName,
    threshold: rawThreshold is num ? rawThreshold.toDouble() : null,
    criterion: rawCriterion == null ? null : BaseCriterion.fromJson(rawCriterion),
    customFunctionPath:
        (json['custom_function_path'] ?? json['customFunctionPath']) as String?,
    score: rawScore is num ? rawScore.toDouble() : null,
    evalStatus: parsedEvalStatus,
  );
}

double _asDouble(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  return 0;
}

int _asInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return 0;
}

String? _metricDetailFromJson(Map<String, Object?> json) {
  final Object? rawDetails = json.containsKey('details')
      ? json['details']
      : json['detail'];
  if (rawDetails == null) {
    return null;
  }
  if (rawDetails is String) {
    return rawDetails;
  }
  if (rawDetails is Map) {
    final Object? nestedDetail = rawDetails['detail'];
    if (nestedDetail is String) {
      return nestedDetail;
    }
    return null;
  }
  return '$rawDetails';
}

String _normalizeSnakeLike(String value) {
  final String trimmed = value.trim();
  if (trimmed.isEmpty) {
    return '';
  }
  final String withUnderscores = trimmed.replaceAllMapped(
    RegExp(r'([a-z0-9])([A-Z])'),
    (Match match) => '${match.group(1)}_${match.group(2)}',
  );
  return withUnderscores
      .replaceAll('-', '_')
      .replaceAll(' ', '_')
      .toLowerCase();
}

Map<String, Object?> _castJsonMap(Map map) {
  return map.map((Object? key, Object? value) => MapEntry('$key', value));
}
