/// Multi-turn tool-use quality evaluator backed by Vertex AI Eval semantics.
library;

import 'conversation_scenarios.dart';
import 'eval_case.dart';
import 'eval_metrics.dart';
import 'evaluator.dart';
import 'vertex_ai_eval_facade.dart';

/// Evaluates tool usage quality across a full multi-turn conversation.
class MultiTurnToolUseQualityV1Evaluator extends Evaluator {
  /// Creates a multi-turn tool-use quality evaluator.
  MultiTurnToolUseQualityV1Evaluator({
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
      metricName: PrebuiltMetricNames.multiTurnToolUseQualityV1,
      evalInvoker: _evalInvoker,
    ).evaluateInvocations(
      actualInvocations: actualInvocations,
      expectedInvocations: expectedInvocations,
      conversationScenario: conversationScenario,
    );
  }
}
