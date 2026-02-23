import '../../models/base_llm.dart';
import '../../models/llm_request.dart';
import '../../models/llm_response.dart';
import '../../models/registry.dart';
import '../../types/content.dart';
import '../_retry_options_utils.dart';
import '../conversation_scenarios.dart';
import '../eval_case.dart';
import '../eval_metrics.dart';
import '../eval_result.dart';
import '../evaluator.dart';
import '../llm_as_judge.dart';
import '../llm_as_judge_utils.dart';
import 'per_turn_user_simulator_quality_prompts.dart';

class PerTurnUserSimulatorQualityV1 extends Evaluator {
  PerTurnUserSimulatorQualityV1(
    EvalMetricSpec evalMetric, {
    BaseLlm Function(String model)? llmFactory,
  }) : _evalMetric = evalMetric,
       _llmFactory = llmFactory ?? LLMRegistry.newLlm {
    if (_evalMetric.criterion == null) {
      throw ArgumentError(
        '`${_evalMetric.metricName}` metric expects a criterion of type '
        '`$LlmBackedUserSimulatorCriterion`.',
      );
    }
    _criterion = _evalMetric.criterion is LlmBackedUserSimulatorCriterion
        ? _evalMetric.criterion! as LlmBackedUserSimulatorCriterion
        : LlmBackedUserSimulatorCriterion.fromJson(
            _evalMetric.criterion!.toJson(),
          );
    _llmOptions = _criterion.judgeModelOptions;
    _stopSignal = _criterion.stopSignal;
    _llm = _llmFactory(_llmOptions.judgeModel);
  }

  final EvalMetricSpec _evalMetric;
  final BaseLlm Function(String model) _llmFactory;
  late final LlmBackedUserSimulatorCriterion _criterion;
  late final JudgeModelOptions _llmOptions;
  late final String _stopSignal;
  late final BaseLlm _llm;

  @override
  Type get criterionType => LlmBackedUserSimulatorCriterion;

  @override
  Future<EvaluationResult> evaluateInvocations({
    required List<Invocation> actualInvocations,
    List<Invocation>? expectedInvocations,
    ConversationScenario? conversationScenario,
  }) async {
    if (conversationScenario == null) {
      throw ArgumentError('conversationScenario is needed by this metric.');
    }
    if (actualInvocations.isEmpty) {
      return EvaluationResult();
    }

    final List<PerInvocationResult> results = <PerInvocationResult>[
      _evaluateFirstTurn(actualInvocations.first, conversationScenario),
    ];

    for (int i = 1; i < actualInvocations.length; i += 1) {
      results.add(
        await _evaluateIntermediateTurn(
          invocationAtStep: actualInvocations[i],
          invocationHistory: actualInvocations.sublist(0, i),
          conversationScenario: conversationScenario,
        ),
      );
    }

    final PerInvocationResult stopSignalEvaluation =
        await _evaluateStopSignalTurn(
          invocationHistory: actualInvocations,
          conversationScenario: conversationScenario,
        );

    if (stopSignalEvaluation.evalStatus == EvalStatus.failed &&
        results.isNotEmpty) {
      results[results.length - 1] = stopSignalEvaluation;
    }

    return _aggregateConversationResults(results);
  }

  PerInvocationResult _evaluateFirstTurn(
    Invocation firstInvocation,
    ConversationScenario conversationScenario,
  ) {
    final String message =
        (getTextFromContent(firstInvocation.userContent) ?? '').trim();
    final String expected = conversationScenario.startingPrompt.trim();
    final double score = message == expected ? 1.0 : 0.0;
    final double threshold = _evalMetric.threshold ?? _criterion.threshold;
    return PerInvocationResult(
      actualInvocation: firstInvocation,
      score: score,
      evalStatus: getEvalStatus(score, threshold),
    );
  }

  Future<PerInvocationResult> _evaluateIntermediateTurn({
    required Invocation invocationAtStep,
    required List<Invocation> invocationHistory,
    required ConversationScenario conversationScenario,
  }) async {
    final String autoRaterPrompt = _formatLlmPrompt(
      invocation: invocationAtStep,
      invocationHistory: invocationHistory,
      conversationScenario: conversationScenario,
    );

    final Object? rawModelConfig = _llmOptions.judgeModelConfig;
    final GenerateContentConfig modelConfig =
        rawModelConfig is GenerateContentConfig
        ? rawModelConfig.copyWith()
        : GenerateContentConfig();
    final LlmRequest llmRequest = LlmRequest(
      model: _llmOptions.judgeModel,
      contents: <Content>[Content.userText(autoRaterPrompt)],
      config: modelConfig,
    );
    addDefaultRetryOptionsIfNotPresent(llmRequest);

    final int numSamples = _llmOptions.numSamples < 1
        ? 1
        : _llmOptions.numSamples;
    final List<PerInvocationResult> samples = <PerInvocationResult>[];
    final double threshold = _evalMetric.threshold ?? _criterion.threshold;

    for (int i = 0; i < numSamples; i += 1) {
      final AutoRaterScore llmScore = await _sampleLlm(llmRequest);
      samples.add(
        PerInvocationResult(
          actualInvocation: invocationAtStep,
          score: llmScore.score,
          evalStatus: getEvalStatus(llmScore.score, threshold),
        ),
      );
    }

    if (samples.isEmpty) {
      return PerInvocationResult(
        actualInvocation: invocationAtStep,
        evalStatus: EvalStatus.notEvaluated,
      );
    }

    return _aggregateSamples(samples);
  }

  Future<PerInvocationResult> _evaluateStopSignalTurn({
    required List<Invocation> invocationHistory,
    required ConversationScenario conversationScenario,
  }) {
    return _evaluateIntermediateTurn(
      invocationAtStep: _getStopSignalInvocation(_stopSignal),
      invocationHistory: invocationHistory,
      conversationScenario: conversationScenario,
    );
  }

  String _formatLlmPrompt({
    required Invocation invocation,
    required List<Invocation> invocationHistory,
    required ConversationScenario conversationScenario,
  }) {
    return getPerTurnUserSimulatorQualityPrompt(
      conversationPlan: conversationScenario.conversationPlan,
      conversationHistory: _formatConversationHistory(invocationHistory),
      generatedUserResponse: getTextFromContent(invocation.userContent) ?? '',
      stopSignal: _stopSignal,
      userPersona: conversationScenario.userPersona,
    );
  }

  Future<AutoRaterScore> _sampleLlm(LlmRequest llmRequest) async {
    await for (final LlmResponse response in _llm.generateContent(
      llmRequest,
      stream: false,
    )) {
      return _convertLlmResponseToScore(response);
    }
    return AutoRaterScore();
  }

  AutoRaterScore _convertLlmResponseToScore(LlmResponse llmResponse) {
    final String responseText =
        llmResponse.content?.parts
            .map((Part part) => part.text ?? '')
            .join('\n') ??
        '';
    if (responseText.trim().isEmpty) {
      return AutoRaterScore();
    }
    final Label label = _parseLlmResponse(responseText);
    if (label == Label.valid) {
      return AutoRaterScore(score: 1.0);
    }
    if (label == Label.invalid) {
      return AutoRaterScore(score: 0.0);
    }
    return AutoRaterScore();
  }

  PerInvocationResult _aggregateSamples(List<PerInvocationResult> samples) {
    final List<PerInvocationResult> positive = <PerInvocationResult>[];
    final List<PerInvocationResult> negative = <PerInvocationResult>[];
    for (final PerInvocationResult sample in samples) {
      if (sample.score == 1.0) {
        positive.add(sample);
      } else if (sample.score == 0.0) {
        negative.add(sample);
      }
    }
    if (positive.isEmpty && negative.isEmpty) {
      return samples.first;
    }
    if (positive.length > negative.length) {
      return positive.first;
    }
    return negative.first;
  }

  EvaluationResult _aggregateConversationResults(
    List<PerInvocationResult> perInvocationResults,
  ) {
    if (perInvocationResults.isEmpty) {
      return EvaluationResult();
    }

    double numValid = 0.0;
    for (final PerInvocationResult result in perInvocationResults) {
      if (result.evalStatus == EvalStatus.passed && result.score != null) {
        numValid += result.score!;
      }
    }

    final double overall = numValid / perInvocationResults.length;
    final double threshold = _evalMetric.threshold ?? _criterion.threshold;
    return EvaluationResult(
      overallScore: overall,
      overallEvalStatus: getEvalStatus(overall, threshold),
      perInvocationResults: perInvocationResults,
    );
  }
}

String _formatConversationHistory(List<Invocation> invocations) {
  final List<String> history = <String>[];
  for (final Invocation invocation in invocations) {
    final String? userText = getTextFromContent(invocation.userContent);
    if (userText != null && userText.isNotEmpty) {
      history.add('user: $userText');
    }
    final EvalJsonMap? finalResponse = invocation.finalResponse;
    if (finalResponse != null) {
      final String role = (finalResponse['role'] as String?) ?? 'model';
      final String? responseText = getTextFromContent(finalResponse);
      if (responseText != null && responseText.isNotEmpty) {
        history.add('$role: $responseText');
      }
    }
  }
  return history.join('\n\n');
}

Label _parseLlmResponse(String response) {
  final RegExp matchExpr = RegExp(
    r'"is_valid"\s*:\s*\[*\s*"?([^"\]]*)"?\s*\]*\s*[,}\n]',
    caseSensitive: false,
    multiLine: true,
  );
  final RegExpMatch? match = matchExpr.firstMatch(response);
  if (match == null) {
    return Label.notFound;
  }

  final String label = (match.group(1) ?? '')
      .replaceAll(',', '')
      .replaceAll('}', '')
      .trim()
      .toLowerCase();
  if (label == Label.valid.value || label == Label.trueLabel.value) {
    return Label.valid;
  }
  if (label == Label.invalid.value ||
      label == Label.falseLabel.value ||
      label == Label.almost.value ||
      label == 'partially' ||
      label == 'partially_valid') {
    return Label.invalid;
  }
  return Label.notFound;
}

Invocation _getStopSignalInvocation(String stopSignal) {
  return Invocation(
    invocationId: 'stop_signal_proxy_invocation',
    userContent: <String, Object?>{
      'role': 'user',
      'parts': <Object?>[
        <String, Object?>{'text': stopSignal},
      ],
    },
  );
}
