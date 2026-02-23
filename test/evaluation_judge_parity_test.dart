import 'dart:collection';

import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

class _QueuedLlm extends BaseLlm {
  _QueuedLlm({required this.outputs}) : super(model: 'queued-judge');

  final Queue<String> outputs;

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    if (outputs.isEmpty) {
      return;
    }
    yield LlmResponse(content: Content.modelText(outputs.removeFirst()));
  }
}

class _RegistryJudgeEvaluator extends LlmAsJudge {
  _RegistryJudgeEvaluator({required EvalMetricSpec evalMetric})
    : super(evalMetric: evalMetric, expectedInvocationsRequired: true);

  @override
  String formatAutoRaterPrompt(
    Invocation actualInvocation,
    Invocation? expectedInvocation,
  ) {
    return getTextFromContent(actualInvocation.finalResponse) ?? '';
  }

  @override
  AutoRaterScore convertAutoRaterResponseToScore(
    LlmResponse autoRaterResponse,
  ) {
    final String text =
        autoRaterResponse.content?.parts
            .map((Part part) => part.text ?? '')
            .join(' ') ??
        '';
    final Label label = parseCritique(text);
    if (label == Label.valid) {
      return AutoRaterScore(score: 1.0);
    }
    if (label == Label.invalid) {
      return AutoRaterScore(score: 0.0);
    }
    return AutoRaterScore();
  }

  @override
  PerInvocationResult aggregatePerInvocationSamples(
    List<PerInvocationResult> perInvocationSamples,
  ) {
    return perInvocationSamples.first;
  }

  @override
  EvaluationResult aggregateInvocationResults(
    List<PerInvocationResult> perInvocationResults,
  ) {
    final double score = perInvocationResults.first.score ?? 0.0;
    return EvaluationResult(
      overallScore: score,
      overallEvalStatus: score >= 0.5 ? EvalStatus.passed : EvalStatus.failed,
      perInvocationResults: perInvocationResults,
    );
  }
}

Invocation _invocation({required String userText, required String modelText}) {
  return Invocation(
    userContent: <String, Object?>{
      'role': 'user',
      'parts': <Object?>[
        <String, Object?>{'text': userText},
      ],
    },
    finalResponse: <String, Object?>{
      'role': 'model',
      'parts': <Object?>[
        <String, Object?>{'text': modelText},
      ],
    },
  );
}

void main() {
  group('llm-as-judge parity', () {
    test('LlmAsJudge resolves and invokes model via LLMRegistry', () async {
      const String judgeModel = 'judge-test-model-v1';
      LLMRegistry.register(
        supportedModels: <RegExp>[RegExp(r'judge-test-model-v1')],
        factory: (String _) => _QueuedLlm(
          outputs: Queue<String>.from(<String>[
            '{"is_the_agent_response_valid":"valid"}',
          ]),
        ),
      );

      final EvalMetricSpec metric = EvalMetricSpec(
        metricName: PrebuiltMetricNames.finalResponseMatchV2,
        criterion: LlmAsAJudgeCriterion(
          threshold: 0.5,
          judgeModelOptions: JudgeModelOptions(
            judgeModel: judgeModel,
            numSamples: 1,
          ),
        ),
      );

      final _RegistryJudgeEvaluator evaluator = _RegistryJudgeEvaluator(
        evalMetric: metric,
      );

      final EvaluationResult result = await evaluator.evaluateInvocations(
        actualInvocations: <Invocation>[
          _invocation(userText: 'q', modelText: 'a'),
        ],
        expectedInvocations: <Invocation>[
          _invocation(userText: 'q', modelText: 'a'),
        ],
      );

      expect(result.overallScore, 1.0);
      expect(result.overallEvalStatus, EvalStatus.passed);
    });
  });

  group('final response match v2 parity', () {
    test('parseCritique supports valid/invalid key variants', () {
      expect(
        parseCritique('{"is_the_agent_response_valid":"valid"}'),
        Label.valid,
      );
      expect(
        parseCritique('{"is_the_agent_response_valid":"false"}'),
        Label.invalid,
      );
      expect(
        parseCritique('{"is_the_agent_response_invalid":"true"}'),
        Label.invalid,
      );
      expect(parseCritique('{"other":true}'), Label.notFound);
    });

    test('majority vote aggregation mirrors python behavior', () async {
      final Queue<String> queued = Queue<String>.from(<String>[
        '{"is_the_agent_response_valid":"valid"}',
        '{"is_the_agent_response_valid":"invalid"}',
        '{"is_the_agent_response_valid":"invalid"}',
      ]);

      final EvalMetricSpec metric = EvalMetricSpec(
        metricName: PrebuiltMetricNames.finalResponseMatchV2,
        criterion: LlmAsAJudgeCriterion(
          threshold: 0.5,
          judgeModelOptions: JudgeModelOptions(numSamples: 3),
        ),
      );

      final FinalResponseMatchV2Evaluator evaluator =
          FinalResponseMatchV2Evaluator(
            metric,
            autoRaterInvoker:
                ({
                  required String prompt,
                  required JudgeModelOptions judgeModelOptions,
                }) async {
                  return LlmResponse(
                    content: Content.modelText(queued.removeFirst()),
                  );
                },
          );

      final EvaluationResult result = await evaluator.evaluateInvocations(
        actualInvocations: <Invocation>[
          _invocation(userText: 'book', modelText: 'bad response'),
        ],
        expectedInvocations: <Invocation>[
          _invocation(userText: 'book', modelText: 'good response'),
        ],
      );

      expect(result.overallScore, 0.0);
      expect(result.overallEvalStatus, EvalStatus.failed);
      expect(result.perInvocationResults, hasLength(1));
      expect(result.perInvocationResults.first.score, 0.0);
    });
  });

  group('per-turn user simulator quality parity', () {
    test('uses LLM prompt grading path and stop-signal turn check', () async {
      final Queue<String> queued = Queue<String>.from(<String>[
        '{"is_valid": true}', // intermediate turn
        '{"is_valid": true}', // stop signal check
      ]);

      final EvalMetricSpec metric = EvalMetricSpec(
        metricName: PrebuiltMetricNames.perTurnUserSimulatorQualityV1,
        criterion: LlmBackedUserSimulatorCriterion(
          threshold: 0.5,
          stopSignal: '</finished>',
          judgeModelOptions: JudgeModelOptions(numSamples: 1),
        ),
      );

      final PerTurnUserSimulatorQualityV1 evaluator =
          PerTurnUserSimulatorQualityV1(
            metric,
            llmFactory: (String _) => _QueuedLlm(outputs: queued),
          );

      final EvaluationResult result = await evaluator.evaluateInvocations(
        actualInvocations: <Invocation>[
          _invocation(userText: 'Start here', modelText: 'Agent asks details'),
          _invocation(userText: 'Book for tomorrow', modelText: 'Done.'),
        ],
        conversationScenario: ConversationScenario(
          startingPrompt: 'Start here',
          conversationPlan: 'Book a reservation and confirm.',
        ),
      );

      expect(result.overallScore, 1.0);
      expect(result.overallEvalStatus, EvalStatus.passed);
      expect(result.perInvocationResults, hasLength(2));
    });
  });
}
