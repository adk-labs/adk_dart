/// Shared judge-model evaluation workflow and scoring helpers.
library;

import '../models/base_llm.dart';
import '../models/llm_request.dart';
import '../models/llm_response.dart';
import '../models/registry.dart';
import '../types/content.dart';
import '_retry_options_utils.dart';
import 'conversation_scenarios.dart';
import 'eval_case.dart';
import 'eval_metrics.dart';
import 'eval_rubrics.dart';
import 'evaluator.dart';
import 'llm_as_judge_utils.dart';

/// Function signature used to invoke the auto-rater model.
typedef AutoRaterInvoker =
    Future<LlmResponse> Function({
      required String prompt,
      required JudgeModelOptions judgeModelOptions,
    });

/// Parsed scoring output from one auto-rater response.
class AutoRaterScore {
  /// Creates an auto-rater score payload.
  AutoRaterScore({this.score, this.rubricScores});

  /// Scalar score assigned by the auto-rater.
  final double? score;

  /// Optional rubric-level scores from the auto-rater response.
  final List<RubricScore>? rubricScores;
}

/// Base evaluator that delegates scoring to a judge LLM.
abstract class LlmAsJudge extends Evaluator {
  /// Creates a judge-based evaluator from [evalMetric].
  LlmAsJudge({
    required EvalMetricSpec evalMetric,
    required this.expectedInvocationsRequired,
    AutoRaterInvoker? autoRaterInvoker,
  }) : _autoRaterInvoker = autoRaterInvoker {
    if (evalMetric.criterion == null) {
      throw ArgumentError(
        '`${evalMetric.metricName}` metric requires criterion for judge-based evaluation.',
      );
    }
    _criterion = evalMetric.criterion!;
    _judgeModelOptions = _extractJudgeOptions(_criterion);
    _judgeModel = _setupAutoRater();
  }

  final bool expectedInvocationsRequired;
  final AutoRaterInvoker? _autoRaterInvoker;

  late final BaseCriterion _criterion;
  late final JudgeModelOptions _judgeModelOptions;
  late final BaseLlm _judgeModel;

  /// Criterion used to interpret judge scores.
  BaseCriterion get criterion => _criterion;

  /// Judge model settings used for auto-rater requests.
  JudgeModelOptions get judgeModelOptions => _judgeModelOptions;

  Future<LlmResponse> _invokeAutoRater(String prompt) async {
    final AutoRaterInvoker? invoker = _autoRaterInvoker;
    if (invoker != null) {
      return invoker(prompt: prompt, judgeModelOptions: _judgeModelOptions);
    }

    final Object? rawModelConfig = _judgeModelOptions.judgeModelConfig;
    final GenerateContentConfig config = rawModelConfig is GenerateContentConfig
        ? rawModelConfig.copyWith()
        : GenerateContentConfig();
    final LlmRequest llmRequest = LlmRequest(
      model: _judgeModelOptions.judgeModel,
      contents: <Content>[Content.userText(prompt)],
      config: config,
    );
    addDefaultRetryOptionsIfNotPresent(llmRequest);

    await for (final LlmResponse response in _judgeModel.generateContent(
      llmRequest,
      stream: false,
    )) {
      return response;
    }

    // Keep deterministic fallback for non-emitting model adapters.
    return LlmResponse(content: Content.modelText(prompt));
  }

  BaseLlm _setupAutoRater() {
    return LLMRegistry.newLlm(_judgeModelOptions.judgeModel);
  }

  /// Formats the prompt sent to the auto-rater model.
  String formatAutoRaterPrompt(
    Invocation actualInvocation,
    Invocation? expectedInvocation,
  );

  /// Converts one auto-rater response into score data.
  AutoRaterScore convertAutoRaterResponseToScore(LlmResponse autoRaterResponse);

  /// Aggregates repeated samples for a single invocation.
  PerInvocationResult aggregatePerInvocationSamples(
    List<PerInvocationResult> perInvocationSamples,
  );

  /// Aggregates invocation-level scores into a final evaluation result.
  EvaluationResult aggregateInvocationResults(
    List<PerInvocationResult> perInvocationResults,
  );

  @override
  /// Evaluates actual invocations by prompting a judge model per invocation.
  Future<EvaluationResult> evaluateInvocations({
    required List<Invocation> actualInvocations,
    List<Invocation>? expectedInvocations,
    ConversationScenario? conversationScenario,
  }) async {
    if (conversationScenario != null) {
      // Per-invocation judge metrics currently ignore conversation scenarios.
    }
    if (expectedInvocationsRequired && expectedInvocations == null) {
      throw ArgumentError('expectedInvocations is needed by this metric.');
    }

    final List<Invocation?> expected = expectedInvocations == null
        ? List<Invocation?>.filled(actualInvocations.length, null)
        : expectedInvocations.cast<Invocation?>();

    final int count = actualInvocations.length < expected.length
        ? actualInvocations.length
        : expected.length;
    if (count == 0) {
      return EvaluationResult();
    }

    final List<PerInvocationResult> perInvocationResults =
        <PerInvocationResult>[];
    for (int i = 0; i < count; i += 1) {
      final Invocation actual = actualInvocations[i];
      final Invocation? expectedInvocation = expected[i];
      final String prompt = formatAutoRaterPrompt(actual, expectedInvocation);
      final int numSamples = _judgeModelOptions.numSamples < 1
          ? 1
          : _judgeModelOptions.numSamples;

      final List<PerInvocationResult> samples = <PerInvocationResult>[];
      for (int sampleIndex = 0; sampleIndex < numSamples; sampleIndex += 1) {
        final LlmResponse autoRaterResponse = await _invokeAutoRater(prompt);
        final AutoRaterScore score = convertAutoRaterResponseToScore(
          autoRaterResponse,
        );
        samples.add(
          PerInvocationResult(
            actualInvocation: actual,
            expectedInvocation: expectedInvocation,
            score: score.score,
            evalStatus: getEvalStatus(score.score, _criterion.threshold),
            rubricScores: score.rubricScores,
          ),
        );
      }

      if (samples.isNotEmpty) {
        perInvocationResults.add(aggregatePerInvocationSamples(samples));
      }
    }

    if (perInvocationResults.isEmpty) {
      return EvaluationResult();
    }
    return aggregateInvocationResults(perInvocationResults);
  }
}

JudgeModelOptions _extractJudgeOptions(BaseCriterion criterion) {
  if (criterion is LlmAsAJudgeCriterion) {
    return criterion.judgeModelOptions;
  }
  if (criterion is RubricsBasedCriterion) {
    return criterion.judgeModelOptions;
  }
  if (criterion is HallucinationsCriterion) {
    return criterion.judgeModelOptions;
  }
  if (criterion is LlmBackedUserSimulatorCriterion) {
    return criterion.judgeModelOptions;
  }
  return JudgeModelOptions(numSamples: 1);
}
