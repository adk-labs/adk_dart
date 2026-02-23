import 'conversation_scenarios.dart';
import 'eval_case.dart';
import 'eval_metrics.dart';
import 'eval_result.dart';
import 'eval_rubrics.dart';

class PerInvocationResult {
  PerInvocationResult({
    required this.actualInvocation,
    this.expectedInvocation,
    this.score,
    this.evalStatus = EvalStatus.notEvaluated,
    this.rubricScores,
  });

  final Invocation actualInvocation;
  final Invocation? expectedInvocation;
  final double? score;
  final EvalStatus evalStatus;
  final List<RubricScore>? rubricScores;
}

class EvaluationResult {
  EvaluationResult({
    this.overallScore,
    this.overallEvalStatus = EvalStatus.notEvaluated,
    List<PerInvocationResult>? perInvocationResults,
    this.overallRubricScores,
  }) : perInvocationResults = perInvocationResults ?? <PerInvocationResult>[];

  final double? overallScore;
  final EvalStatus overallEvalStatus;
  final List<PerInvocationResult> perInvocationResults;
  final List<RubricScore>? overallRubricScores;
}

abstract class Evaluator {
  Type get criterionType => BaseCriterion;

  Future<EvaluationResult> evaluateInvocations({
    required List<Invocation> actualInvocations,
    List<Invocation>? expectedInvocations,
    ConversationScenario? conversationScenario,
  });
}
