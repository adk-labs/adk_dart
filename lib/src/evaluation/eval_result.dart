import 'eval_metric.dart';

enum InferenceStatus { unknown, success, failure }

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
}

class EvalCaseResult {
  EvalCaseResult({required this.evalCaseId, required this.metrics});

  final String evalCaseId;
  final List<EvalMetricResult> metrics;

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
}
