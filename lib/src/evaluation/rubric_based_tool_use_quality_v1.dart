import 'eval_case.dart';
import 'eval_metrics.dart';
import 'llm_as_judge_utils.dart';
import 'rubric_based_evaluator.dart';

class RubricBasedToolUseV1Evaluator extends RubricBasedEvaluator {
  RubricBasedToolUseV1Evaluator(EvalMetricSpec evalMetric)
    : super(evalMetric: evalMetric, rubricType: 'TOOL_USE_QUALITY');

  @override
  String candidateText(Invocation invocation) {
    return getToolCallsAndResponsesAsJsonStr(invocation.intermediateData);
  }
}
