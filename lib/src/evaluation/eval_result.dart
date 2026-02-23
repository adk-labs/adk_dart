import 'eval_metric.dart';

enum InferenceStatus { unknown, success, failure }

enum EvalStatus { passed, failed, notEvaluated }

class InferenceResult {
  InferenceResult({
    required this.appName,
    required this.evalCaseId,
    required this.userInput,
    this.responseText,
    this.sessionId,
    this.status = InferenceStatus.unknown,
    this.errorMessage,
  });

  final String appName;
  final String evalCaseId;
  final String userInput;
  final String? responseText;
  final String? sessionId;
  final InferenceStatus status;
  final String? errorMessage;
}

class EvalMetricResult {
  EvalMetricResult({
    required this.metric,
    required this.score,
    this.passed = false,
    this.detail,
  });

  final EvalMetric metric;
  final double score;
  final bool passed;
  final String? detail;

  factory EvalMetricResult.fromJson(Map<String, Object?> json) {
    final String metricName = (json['metric'] ?? '').toString();
    final EvalMetric metric = _evalMetricFromString(metricName);
    return EvalMetricResult(
      metric: metric,
      score: _asDouble(json['score']),
      passed: (json['passed'] as bool?) ?? false,
      detail: json['detail'] as String?,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'metric': metric.name,
      'score': score,
      'passed': passed,
      if (detail != null) 'detail': detail,
    };
  }
}

class EvalCaseResult {
  EvalCaseResult({
    required this.evalCaseId,
    required this.metrics,
    this.evalSetId = '',
    this.finalEvalStatus = EvalStatus.notEvaluated,
    this.sessionId = '',
    this.userId,
    this.evalSetFile,
  });

  final String evalCaseId;
  final List<EvalMetricResult> metrics;
  final String evalSetId;
  final EvalStatus finalEvalStatus;
  final String sessionId;
  final String? userId;
  final String? evalSetFile;

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

class EvalSetResult {
  EvalSetResult({
    required this.evalSetResultId,
    this.evalSetResultName,
    required this.evalSetId,
    List<EvalCaseResult>? evalCaseResults,
    this.creationTimestamp = 0,
  }) : evalCaseResults = evalCaseResults ?? <EvalCaseResult>[];

  final String evalSetResultId;
  final String? evalSetResultName;
  final String evalSetId;
  final List<EvalCaseResult> evalCaseResults;
  final double creationTimestamp;

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
  for (final EvalMetric value in EvalMetric.values) {
    if (value.name == name) {
      return value;
    }
  }
  return EvalMetric.finalResponseExactMatch;
}

EvalStatus _evalStatusFromString(String value) {
  for (final EvalStatus status in EvalStatus.values) {
    if (status.name == value) {
      return status;
    }
  }
  return EvalStatus.notEvaluated;
}

double _asDouble(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  return 0;
}

Map<String, Object?> _castJsonMap(Map map) {
  return map.map((Object? key, Object? value) => MapEntry('$key', value));
}
