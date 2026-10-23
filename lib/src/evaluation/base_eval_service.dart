/// Base contracts for inference and metric evaluation services.
library;

import 'eval_case.dart';
import 'constants.dart';
import 'eval_metric.dart';
import 'eval_result.dart';

/// Options that control how inference is generated for eval cases.
class InferenceConfig {
  /// Creates inference configuration.
  const InferenceConfig({
    this.useLive = false,
    this.liveTimeoutSeconds = defaultLiveTimeoutSeconds,
    this.numRuns = 1,
    this.parallelism = 4,
    this.labels,
  }) : assert(numRuns >= 1, 'Input should be greater than or equal to 1');

  /// Whether to use bidirectional live streaming inference.
  final bool useLive;

  /// Timeout for waiting for model turn completion in live mode.
  final int liveTimeoutSeconds;

  /// Number of times to run each eval case during inference.
  final int numRuns;

  /// Maximum number of eval cases or repetitions to run in parallel.
  final int parallelism;

  /// Optional key-value labels attached to the inference run.
  final Map<String, String>? labels;

  /// Creates a copy of this configuration with the given fields replaced.
  InferenceConfig copyWith({
    bool? useLive,
    int? liveTimeoutSeconds,
    int? numRuns,
    int? parallelism,
    Map<String, String>? labels,
  }) {
    return InferenceConfig(
      useLive: useLive ?? this.useLive,
      liveTimeoutSeconds: liveTimeoutSeconds ?? this.liveTimeoutSeconds,
      numRuns: numRuns ?? this.numRuns,
      parallelism: parallelism ?? this.parallelism,
      labels: labels ?? this.labels,
    );
  }

  /// Decodes an [InferenceConfig] from JSON.
  factory InferenceConfig.fromJson(Map<String, Object?> json) {
    final Object? rawNumRuns = json['numRuns'] ?? json['num_runs'];
    final Object? rawParallelism = json['parallelism'];
    final Object? rawLabels = json['labels'];
    return InferenceConfig(
      useLive: ((json['useLive'] ?? json['use_live']) as bool?) ?? false,
      liveTimeoutSeconds:
          ((json['liveTimeoutSeconds'] ?? json['live_timeout_seconds'])
              as int?) ??
          defaultLiveTimeoutSeconds,
      numRuns: rawNumRuns is int ? rawNumRuns : 1,
      parallelism: rawParallelism is int ? rawParallelism : 4,
      labels: rawLabels is Map
          ? rawLabels.map(
              (Object? k, Object? v) => MapEntry('$k', '$v'),
            )
          : null,
    );
  }

  /// Encodes this configuration to JSON.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'use_live': useLive,
      'live_timeout_seconds': liveTimeoutSeconds,
      'num_runs': numRuns,
      'parallelism': parallelism,
      if (labels != null) 'labels': labels,
    };
  }
}

/// Input for evaluation inference runs.
class InferenceRequest {
  /// Creates an inference request.
  InferenceRequest({
    required this.appName,
    required this.evalCases,
    this.userId = 'eval_user',
    InferenceConfig? inferenceConfig,
  }) : inferenceConfig = inferenceConfig ?? InferenceConfig();

  /// App module name used for execution.
  final String appName;

  /// Evaluation cases to run through the app.
  final List<EvalCase> evalCases;

  /// User identifier used for generated sessions.
  final String userId;

  /// Inference runtime options.
  final InferenceConfig inferenceConfig;
}

/// Input for metric evaluation after inference completes.
class EvaluateRequest {
  /// Creates an evaluation request.
  EvaluateRequest({
    required this.inferenceResults,
    required this.evalCasesById,
    required this.evaluateConfig,
  });

  /// Inference outputs to score.
  final List<InferenceResult> inferenceResults;

  /// Eval cases indexed by case identifier.
  final Map<String, EvalCase> evalCasesById;

  /// Metric configuration to apply.
  final EvaluateConfig evaluateConfig;
}

/// Runs inference and metric scoring pipelines for eval workloads.
abstract class BaseEvalService {
  /// Executes agent inference for each case in [request].
  Stream<InferenceResult> performInference(InferenceRequest request);

  /// Scores inference outputs using the criteria in [request].
  Stream<EvalCaseResult> evaluate(EvaluateRequest request);
}
