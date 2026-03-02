/// Evaluation result models used by eval services and CLI output.
library;

import 'eval_metric.dart';

/// Inference execution status for one eval case.
enum InferenceStatus { unknown, success, failure }

/// Evaluation pass/fail status.
enum EvalStatus { passed, failed, notEvaluated }

/// Result of running model inference for an eval case.
class InferenceResult {
  /// Creates an inference result.
  InferenceResult({
    required this.appName,
    required this.evalCaseId,
    required this.userInput,
    this.responseText,
    this.sessionId,
    this.status = InferenceStatus.unknown,
    this.errorMessage,
  });

  /// Application name used for inference.
  final String appName;

  /// Eval case identifier.
  final String evalCaseId;

  /// Input text sent to the model.
  final String userInput;

  /// Optional model response text.
  final String? responseText;

  /// Optional session identifier used during inference.
  final String? sessionId;

  /// Inference status.
  final InferenceStatus status;

  /// Optional error message.
  final String? errorMessage;
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
  }) : evalStatus =
           evalStatus ?? (passed ? EvalStatus.passed : EvalStatus.failed),
       passed = evalStatus == null ? passed : evalStatus == EvalStatus.passed;

  /// Metric identifier.
  final EvalMetric metric;

  /// Metric score value.
  final double score;

  /// Whether this metric passed.
  final bool passed;

  /// Metric evaluation status.
  final EvalStatus evalStatus;

  /// Optional metric detail text.
  final String? detail;

  /// Creates a metric result from JSON.
  factory EvalMetricResult.fromJson(Map<String, Object?> json) {
    final String metricName =
        (json['metric_name'] ?? json['metricName'] ?? json['metric'] ?? '')
            .toString();
    final EvalMetric metric = _evalMetricFromString(metricName);
    final bool? rawPassed = json['passed'] as bool?;
    final Object? rawEvalStatus = json['eval_status'] ?? json['evalStatus'];
    final EvalStatus parsedEvalStatus = rawEvalStatus == null
        ? (rawPassed == null
              ? EvalStatus.notEvaluated
              : (rawPassed ? EvalStatus.passed : EvalStatus.failed))
        : _evalStatusFromString(rawEvalStatus.toString());
    return EvalMetricResult(
      metric: metric,
      score: _asDouble(json['score']),
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
      'metric_name': metric.name,
      'score': score,
      'eval_status': _evalStatusToJson(evalStatus),
      'details': details,
    };
  }
}

/// Aggregated evaluation result for one eval case.
class EvalCaseResult {
  /// Creates an eval-case result.
  EvalCaseResult({
    required this.evalCaseId,
    required this.metrics,
    this.evalSetId = '',
    this.finalEvalStatus = EvalStatus.notEvaluated,
    this.sessionId = '',
    this.userId,
    this.evalSetFile,
  });

  /// Eval case identifier.
  final String evalCaseId;

  /// Metric results for this case.
  final List<EvalMetricResult> metrics;

  /// Parent eval set identifier.
  final String evalSetId;

  /// Final evaluation status.
  final EvalStatus finalEvalStatus;

  /// Session ID used for inference.
  final String sessionId;

  /// Optional user ID used for inference.
  final String? userId;

  /// Optional source eval-set file path.
  final String? evalSetFile;

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
    if (rawMetrics is List) {
      for (final Object? item in rawMetrics) {
        if (item is Map) {
          metrics.add(EvalMetricResult.fromJson(_castJsonMap(item)));
        }
      }
    }
    return EvalCaseResult(
      evalCaseId:
          (json['evalCaseId'] ?? json['eval_id'] ?? json['evalId'] ?? '')
              .toString(),
      metrics: metrics,
      evalSetId: (json['evalSetId'] ?? json['eval_set_id'] ?? '').toString(),
      finalEvalStatus: _evalStatusFromString(
        (json['finalEvalStatus'] ?? json['final_eval_status']).toString(),
      ),
      sessionId: (json['sessionId'] ?? json['session_id'] ?? '').toString(),
      userId: (json['userId'] ?? json['user_id']) as String?,
      evalSetFile: (json['evalSetFile'] ?? json['eval_set_file']) as String?,
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
    };
  }
}

/// Aggregated result for an eval-set execution.
class EvalSetResult {
  /// Creates an eval-set result.
  EvalSetResult({
    required this.evalSetResultId,
    this.evalSetResultName,
    required this.evalSetId,
    List<EvalCaseResult>? evalCaseResults,
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

    return EvalSetResult(
      evalSetResultId:
          (json['evalSetResultId'] ?? json['eval_set_result_id'] ?? '')
              .toString(),
      evalSetResultName:
          (json['evalSetResultName'] ?? json['eval_set_result_name'])
              as String?,
      evalSetId: (json['evalSetId'] ?? json['eval_set_id'] ?? '').toString(),
      evalCaseResults: caseResults,
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
      return EvalStatus.passed;
    case 'failed':
      return EvalStatus.failed;
    case 'not_evaluated':
      return EvalStatus.notEvaluated;
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
  }
}

double _asDouble(Object? value) {
  if (value is num) {
    return value.toDouble();
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
