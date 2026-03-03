/// Base contracts for inference and metric evaluation services.
library;

import 'eval_case.dart';
import 'eval_metric.dart';
import 'eval_result.dart';

/// Input for evaluation inference runs.
class InferenceRequest {
  /// Creates an inference request.
  InferenceRequest({
    required this.appName,
    required this.evalCases,
    this.userId = 'eval_user',
  });

  /// App module name used for execution.
  final String appName;

  /// Evaluation cases to run through the app.
  final List<EvalCase> evalCases;

  /// User identifier used for generated sessions.
  final String userId;
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
