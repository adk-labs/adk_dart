import 'dart:collection';

import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

Invocation _invocation({
  required String userText,
  required String modelText,
  Object? intermediateData,
}) {
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
    intermediateData: intermediateData,
  );
}

RubricsBasedCriterion _criterion({required int numSamples}) {
  return RubricsBasedCriterion(
    threshold: 0.5,
    judgeModelOptions: JudgeModelOptions(numSamples: numSamples),
    rubrics: <Rubric>[
      Rubric(
        rubricId: 'r1',
        rubricContent: RubricContent(
          textProperty: 'Does the response satisfy the property?',
        ),
      ),
    ],
  );
}

void main() {
  group('rubric based evaluator parity', () {
    test('tool-use evaluator applies majority vote across samples', () async {
      final Queue<String> queued = Queue<String>.from(<String>[
        'Property: Does the response satisfy the property?\nRationale: yes sample\nVerdict: yes',
        'Property: Does the response satisfy the property?\nRationale: no sample\nVerdict: no',
        'Property: Does the response satisfy the property?\nRationale: yes sample\nVerdict: yes',
      ]);
      final EvalMetricSpec metric = EvalMetricSpec(
        metricName: PrebuiltMetricNames.rubricBasedToolUseQualityV1,
        criterion: _criterion(numSamples: 3),
      );

      final RubricBasedToolUseV1Evaluator evaluator =
          RubricBasedToolUseV1Evaluator(
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
          _invocation(
            userText: 'Book a ticket',
            modelText: 'Calling tool',
            intermediateData: InvocationEvents(
              invocationEvents: <InvocationEvent>[
                InvocationEvent(
                  author: 'root',
                  content: <String, Object?>{
                    'parts': <Object?>[
                      <String, Object?>{
                        'function_call': <String, Object?>{
                          'name': 'create_ticket',
                          'args': <String, Object?>{'user_id': 'u1'},
                        },
                      },
                    ],
                  },
                ),
              ],
            ),
          ),
        ],
      );

      expect(result.overallScore, 1.0);
      expect(result.overallEvalStatus, EvalStatus.passed);
      expect(result.perInvocationResults, hasLength(1));
      expect(result.perInvocationResults.first.score, 1.0);
      expect(result.perInvocationResults.first.rubricScores, isNotNull);
      expect(
        result.perInvocationResults.first.rubricScores!.first.rubricId,
        'r1',
      );
    });

    test(
      'final-response evaluator summarizes rubric means across invocations',
      () async {
        final Queue<String> queued = Queue<String>.from(<String>[
          'Property: Does the response satisfy the property?\nRationale: yes sample\nVerdict: yes',
          'Property: Does the response satisfy the property?\nRationale: no sample\nVerdict: no',
        ]);
        final EvalMetricSpec metric = EvalMetricSpec(
          metricName: PrebuiltMetricNames.rubricBasedFinalResponseQualityV1,
          criterion: _criterion(numSamples: 1),
        );

        final RubricBasedFinalResponseQualityV1Evaluator evaluator =
            RubricBasedFinalResponseQualityV1Evaluator(
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
            _invocation(userText: 'q1', modelText: 'a1'),
            _invocation(userText: 'q2', modelText: 'a2'),
          ],
        );

        expect(result.perInvocationResults, hasLength(2));
        expect(result.perInvocationResults[0].score, 1.0);
        expect(result.perInvocationResults[1].score, 0.0);
        expect(result.overallScore, 0.5);
        expect(result.overallEvalStatus, EvalStatus.passed);
        expect(result.overallRubricScores, isNotNull);
        expect(result.overallRubricScores, hasLength(1));
        expect(result.overallRubricScores!.first.rubricId, 'r1');
        expect(result.overallRubricScores!.first.score, 0.5);
      },
    );
  });
}
