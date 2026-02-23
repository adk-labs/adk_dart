import 'eval_case.dart';
import 'eval_metrics.dart';
import 'llm_as_judge_utils.dart';
import 'rubric_based_evaluator.dart';

class RubricBasedFinalResponseQualityV1Evaluator extends RubricBasedEvaluator {
  RubricBasedFinalResponseQualityV1Evaluator(EvalMetricSpec evalMetric)
    : super(evalMetric: evalMetric, rubricType: 'FINAL_RESPONSE_QUALITY');

  @override
  String candidateText(Invocation invocation) {
    return getTextFromContent(invocation.finalResponse) ?? '';
  }
}
