import 'conversation_scenarios.dart';
import 'eval_case.dart';
import 'eval_metrics.dart';
import 'eval_result.dart';
import 'eval_rubrics.dart';

/// Per-invocation evaluation details for one conversation turn.
class PerInvocationResult {
  /// Creates a per-invocation evaluation result.
  PerInvocationResult({
    required this.actualInvocation,
    this.expectedInvocation,
    this.score,
    this.evalStatus = EvalStatus.notEvaluated,
    this.rubricScores,
  });

  /// Invocation produced by the evaluated app.
  final Invocation actualInvocation;

  /// Optional expected invocation used for comparison.
  final Invocation? expectedInvocation;

  /// Numeric score assigned for this invocation.
  final double? score;

  /// Pass/fail/not-evaluated status for this invocation.
  final EvalStatus evalStatus;

  /// Optional rubric breakdown for this invocation.
  final List<RubricScore>? rubricScores;
}

/// Aggregated evaluation result for a full case.
class EvaluationResult {
  /// Creates an aggregated evaluation result.
  EvaluationResult({
    this.overallScore,
    this.overallEvalStatus = EvalStatus.notEvaluated,
    List<PerInvocationResult>? perInvocationResults,
    this.overallRubricScores,
  }) : perInvocationResults = perInvocationResults ?? <PerInvocationResult>[];

  /// Overall case score.
  final double? overallScore;

  /// Overall case status.
  final EvalStatus overallEvalStatus;

  /// Turn-level evaluation details.
  final List<PerInvocationResult> perInvocationResults;

  /// Optional rubric breakdown at case level.
  final List<RubricScore>? overallRubricScores;
}

/// Base interface for scoring one evaluation case.
abstract class Evaluator {
  /// Criterion type expected by this evaluator.
  Type get criterionType => BaseCriterion;

  /// Evaluates conversation invocations and returns structured scores.
  Future<EvaluationResult> evaluateInvocations({
    required List<Invocation> actualInvocations,
    List<Invocation>? expectedInvocations,
    ConversationScenario? conversationScenario,
  });
}
