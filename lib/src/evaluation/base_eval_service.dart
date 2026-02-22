import 'eval_case.dart';
import 'eval_metric.dart';
import 'eval_result.dart';

class InferenceRequest {
  InferenceRequest({
    required this.appName,
    required this.evalCases,
    this.userId = 'eval_user',
  });

  final String appName;
  final List<EvalCase> evalCases;
  final String userId;
}

class EvaluateRequest {
  EvaluateRequest({
    required this.inferenceResults,
    required this.evalCasesById,
    required this.evaluateConfig,
  });

  final List<InferenceResult> inferenceResults;
  final Map<String, EvalCase> evalCasesById;
  final EvaluateConfig evaluateConfig;
}

abstract class BaseEvalService {
  Stream<InferenceResult> performInference(InferenceRequest request);

  Stream<EvalCaseResult> evaluate(EvaluateRequest request);
}
