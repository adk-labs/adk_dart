import 'dart:collection';

import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

class _QueuedLlm extends BaseLlm {
  _QueuedLlm({required this.outputs, required String model})
    : super(model: model);

  final Queue<String> outputs;
  final List<LlmRequest> requests = <LlmRequest>[];

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    requests.add(request);
    if (outputs.isEmpty) {
      return;
    }
    yield LlmResponse(content: Content.modelText(outputs.removeFirst()));
  }
}

Invocation _invocation({
  required String userPrompt,
  required String finalResponse,
  Object? intermediateData,
  AppDetails? appDetails,
}) {
  return Invocation(
    userContent: <String, Object?>{
      'role': 'user',
      'parts': <Object?>[
        <String, Object?>{'text': userPrompt},
      ],
    },
    finalResponse: <String, Object?>{
      'role': 'model',
      'parts': <Object?>[
        <String, Object?>{'text': finalResponse},
      ],
    },
    intermediateData: intermediateData,
    appDetails: appDetails,
  );
}

void main() {
  group('hallucinations_v1 parity', () {
    test('runs segmentation + validator workflow and scores labels', () async {
      const String modelId = 'hallu-test-model-v1';
      late _QueuedLlm queuedLlm;
      LLMRegistry.register(
        supportedModels: <RegExp>[RegExp('^${RegExp.escape(modelId)}\$')],
        factory: (String _) {
          queuedLlm = _QueuedLlm(
            model: modelId,
            outputs: Queue<String>.from(<String>[
              '<sentence>Alpha is grounded.</sentence>\n<sentence>Beta is unsupported.</sentence>',
              'sentence: Alpha is grounded.\nlabel: supported\nrationale: present in context\nsupporting_excerpt: Alpha evidence\ncontradicting_excerpt: null\n\nsentence: Beta is unsupported.\nlabel: unsupported\nrationale: missing in context\nsupporting_excerpt: null\ncontradicting_excerpt: null',
            ]),
          );
          return queuedLlm;
        },
      );

      final EvalMetricSpec metric = EvalMetricSpec(
        metricName: PrebuiltMetricNames.hallucinationsV1,
        criterion: HallucinationsCriterion(
          threshold: 0.6,
          judgeModelOptions: JudgeModelOptions(judgeModel: modelId),
        ),
      );

      final HallucinationsV1Evaluator evaluator = HallucinationsV1Evaluator(
        metric,
      );

      final EvaluationResult result = await evaluator.evaluateInvocations(
        actualInvocations: <Invocation>[
          _invocation(
            userPrompt: 'Tell me about alpha and beta.',
            finalResponse: 'Alpha is grounded. Beta is unsupported.',
          ),
        ],
      );

      expect(result.overallScore, closeTo(0.5, 1e-9));
      expect(result.overallEvalStatus, EvalStatus.failed);
      expect(result.perInvocationResults, hasLength(1));
      expect(result.perInvocationResults.first.score, closeTo(0.5, 1e-9));
      expect(queuedLlm.requests, hasLength(2));
    });

    test(
      'evaluates intermediate NL responses and includes tool context in prompt',
      () async {
        const String modelId = 'hallu-test-model-v2';
        late _QueuedLlm queuedLlm;
        LLMRegistry.register(
          supportedModels: <RegExp>[RegExp('^${RegExp.escape(modelId)}\$')],
          factory: (String _) {
            queuedLlm = _QueuedLlm(
              model: modelId,
              outputs: Queue<String>.from(<String>[
                '<sentence>Interim answer.</sentence>',
                'sentence: Interim answer.\nlabel: supported\nrationale: grounded\nsupporting_excerpt: tool output\ncontradicting_excerpt: null',
                '<sentence>Final answer.</sentence>',
                'sentence: Final answer.\nlabel: supported\nrationale: grounded\nsupporting_excerpt: tool output\ncontradicting_excerpt: null',
              ]),
            );
            return queuedLlm;
          },
        );

        final EvalMetricSpec metric = EvalMetricSpec(
          metricName: PrebuiltMetricNames.hallucinationsV1,
          criterion: HallucinationsCriterion(
            threshold: 0.9,
            evaluateIntermediateNlResponses: true,
            judgeModelOptions: JudgeModelOptions(judgeModel: modelId),
          ),
        );

        final InvocationEvents invocationEvents = InvocationEvents(
          invocationEvents: <InvocationEvent>[
            InvocationEvent(
              author: 'root',
              content: <String, Object?>{
                'parts': <Object?>[
                  <String, Object?>{
                    'function_call': <String, Object?>{
                      'name': 'search',
                      'args': <String, Object?>{'q': 'alpha'},
                      'id': 'call_1',
                    },
                  },
                  <String, Object?>{
                    'function_response': <String, Object?>{
                      'name': 'search',
                      'response': <String, Object?>{'result': 'alpha evidence'},
                      'id': 'call_1',
                    },
                  },
                  <String, Object?>{'text': 'Interim answer.'},
                ],
              },
            ),
          ],
        );

        final AppDetails appDetails = AppDetails(
          agentDetails: <String, AgentDetails>{
            'root': AgentDetails(
              name: 'root',
              instructions: 'Be factual.',
              toolDeclarations: <Object?>[
                <String, Object?>{'name': 'search'},
              ],
            ),
          },
        );

        final HallucinationsV1Evaluator evaluator = HallucinationsV1Evaluator(
          metric,
        );

        final EvaluationResult result = await evaluator.evaluateInvocations(
          actualInvocations: <Invocation>[
            _invocation(
              userPrompt: 'What happened?',
              finalResponse: 'Final answer.',
              intermediateData: invocationEvents,
              appDetails: appDetails,
            ),
          ],
        );

        expect(result.overallScore, 1.0);
        expect(result.overallEvalStatus, EvalStatus.passed);
        expect(queuedLlm.requests, hasLength(4));

        final String finalValidatorPrompt =
            queuedLlm.requests[3].contents.first.parts.first.text ?? '';
        expect(finalValidatorPrompt, contains('Developer instructions:'));
        expect(finalValidatorPrompt, contains('Be factual.'));
        expect(finalValidatorPrompt, contains('tool_calls:'));
        expect(finalValidatorPrompt, contains('tool_outputs:'));
        expect(finalValidatorPrompt, contains('Interim answer.'));
      },
    );

    test('returns not evaluated when segmenter yields no sentences', () async {
      const String modelId = 'hallu-test-model-v3';
      late _QueuedLlm queuedLlm;
      LLMRegistry.register(
        supportedModels: <RegExp>[RegExp('^${RegExp.escape(modelId)}\$')],
        factory: (String _) {
          queuedLlm = _QueuedLlm(
            model: modelId,
            outputs: Queue<String>.from(<String>['no sentence tags here']),
          );
          return queuedLlm;
        },
      );

      final EvalMetricSpec metric = EvalMetricSpec(
        metricName: PrebuiltMetricNames.hallucinationsV1,
        criterion: HallucinationsCriterion(
          threshold: 0.5,
          judgeModelOptions: JudgeModelOptions(judgeModel: modelId),
        ),
      );

      final HallucinationsV1Evaluator evaluator = HallucinationsV1Evaluator(
        metric,
      );

      final EvaluationResult result = await evaluator.evaluateInvocations(
        actualInvocations: <Invocation>[
          _invocation(
            userPrompt: 'Prompt',
            finalResponse: 'Potentially unsupported answer.',
          ),
        ],
      );

      expect(result.overallScore, isNull);
      expect(result.overallEvalStatus, EvalStatus.notEvaluated);
      expect(
        result.perInvocationResults.first.evalStatus,
        EvalStatus.notEvaluated,
      );
      expect(queuedLlm.requests, hasLength(1));
    });
  });
}
