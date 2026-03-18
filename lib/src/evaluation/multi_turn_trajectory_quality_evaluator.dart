/// Multi-turn trajectory quality evaluator backed by Vertex AI Eval semantics.
library;

import 'conversation_scenarios.dart';
import 'eval_case.dart';
import 'eval_metrics.dart';
import 'evaluator.dart';
import 'vertex_ai_eval_facade.dart';

/// Evaluates the overall path taken across a multi-turn conversation.
class MultiTurnTrajectoryQualityV1Evaluator extends Evaluator {
  /// Creates a multi-turn trajectory quality evaluator.
  MultiTurnTrajectoryQualityV1Evaluator({
    required this.evalMetric,
    VertexAiEvalInvoker? evalInvoker,
  }) : _evalInvoker = evalInvoker;

  /// Metric configuration driving this evaluator.
  final EvalMetricSpec evalMetric;

  final VertexAiEvalInvoker? _evalInvoker;

  @override
  Future<EvaluationResult> evaluateInvocations({
    required List<Invocation> actualInvocations,
    List<Invocation>? expectedInvocations,
    ConversationScenario? conversationScenario,
  }) {
    return MultiTurnVertexAiEvalFacade(
      threshold: evalMetric.threshold ?? 1.0,
      metricName: PrebuiltMetricNames.multiTurnTrajectoryQualityV1,
      evalInvoker: _evalInvoker,
    ).evaluateInvocations(
      actualInvocations: actualInvocations,
      expectedInvocations: expectedInvocations,
      conversationScenario: conversationScenario,
    );
  }
}
