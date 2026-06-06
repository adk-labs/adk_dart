import 'dart:collection';

import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

Invocation _invocation({
  required String userText,
  required String modelText,
  Object? intermediateData,
  AppDetails? appDetails,
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
    appDetails: appDetails,
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

RubricsBasedCriterion _trajectoryCriterion({required int numSamples}) {
  return RubricsBasedCriterion(
    threshold: 0.5,
    judgeModelOptions: JudgeModelOptions(numSamples: numSamples),
    rubrics: <Rubric>[
      Rubric(
        rubricId: 'tool',
        rubricContent: RubricContent(
          textProperty: 'The agent uses the correct tool.',
        ),
        type: 'TOOL_USAGE',
      ),
      Rubric(
        rubricId: 'intent',
        rubricContent: RubricContent(
          textProperty: 'The agent fulfills the user intent.',
        ),
        type: 'FULFILL_USER_INTENT',
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

    test(
      'multi-turn trajectory evaluator scores final turn with full dialogue',
      () async {
        String? capturedPrompt;
        final Queue<String> queued = Queue<String>.from(<String>[
          'Property: The agent uses the correct tool.\n'
              'Rationale: yes sample\n'
              'Verdict: yes\n'
              'Property: The agent fulfills the user intent.\n'
              'Rationale: yes sample\n'
              'Verdict: yes',
        ]);
        final EvalMetricSpec metric = EvalMetricSpec(
          metricName:
              PrebuiltMetricNames.rubricBasedMultiTurnTrajectoryQualityV1,
          criterion: _trajectoryCriterion(numSamples: 1),
        );
        final AppDetails appDetails = AppDetails(
          agentDetails: <String, AgentDetails>{
            'banking_agent': AgentDetails(
              name: 'banking_agent',
              instructions: 'You are a banking assistant.',
              toolDeclarations: <Object?>[
                ToolDeclaration(
                  functionDeclarations: <FunctionDeclaration>[
                    FunctionDeclaration(
                      name: 'get_balance',
                      description: 'Read the current balance.',
                    ),
                  ],
                ),
              ],
            ),
          },
        );

        final RubricBasedMultiTurnTrajectoryEvaluator evaluator =
            RubricBasedMultiTurnTrajectoryEvaluator(
              metric,
              autoRaterInvoker:
                  ({
                    required String prompt,
                    required JudgeModelOptions judgeModelOptions,
                  }) async {
                    capturedPrompt = prompt;
                    return LlmResponse(
                      content: Content.modelText(queued.removeFirst()),
                    );
                  },
            );

        final EvaluationResult result = await evaluator.evaluateInvocations(
          actualInvocations: <Invocation>[
            _invocation(
              userText: 'What is my balance?',
              modelText: 'Your balance is 100.',
              appDetails: appDetails,
              intermediateData: InvocationEvents(
                invocationEvents: <InvocationEvent>[
                  InvocationEvent(
                    author: 'banking_agent',
                    content: <String, Object?>{
                      'parts': <Object?>[
                        <String, Object?>{
                          'function_call': <String, Object?>{
                            'name': 'get_balance',
                            'args': <String, Object?>{'account_id': '123'},
                          },
                        },
                      ],
                    },
                  ),
                  InvocationEvent(
                    author: 'banking_agent',
                    content: <String, Object?>{
                      'parts': <Object?>[
                        <String, Object?>{
                          'function_response': <String, Object?>{
                            'name': 'get_balance',
                            'response': <String, Object?>{'balance': 100},
                          },
                        },
                      ],
                    },
                  ),
                ],
              ),
            ),
            _invocation(
              userText: 'Transfer 50.',
              modelText: 'Transfer complete.',
              appDetails: appDetails,
            ),
          ],
        );

        expect(result.overallScore, 1.0);
        expect(result.overallEvalStatus, EvalStatus.passed);
        expect(result.overallRubricScores, hasLength(2));
        expect(result.perInvocationResults, hasLength(2));
        expect(
          result.perInvocationResults.first.evalStatus,
          EvalStatus.notEvaluated,
        );
        expect(result.perInvocationResults.first.score, isNull);
        expect(result.perInvocationResults.last.score, 1.0);
        expect(result.perInvocationResults.last.evalStatus, EvalStatus.passed);

        final String prompt = capturedPrompt!;
        expect(prompt, contains('USER TURN 1: What is my balance?'));
        expect(
          prompt,
          contains('AGENT (banking_agent) TURN 1 (tool call): get_balance('),
        );
        expect(prompt, contains('"account_id":"123"'));
        expect(
          prompt,
          contains(
            'AGENT (banking_agent) TURN 1 (tool output): get_balance ->',
          ),
        );
        expect(prompt, contains('"balance":100'));
        expect(prompt, contains('AGENT (agent) TURN 2: Transfer complete.'));
        expect(prompt, contains('You are a banking assistant.'));
        expect(prompt, contains('get_balance'));
        expect(prompt, contains('Read the current balance.'));
        expect(prompt, contains('The agent uses the correct tool.'));
        expect(prompt, contains('TOOL_USAGE'));
        expect(prompt, contains('The agent fulfills the user intent.'));
        expect(prompt, contains('FULFILL_USER_INTENT'));
        expect(prompt, contains('For each property starting with a new line'));
      },
    );

    test('multi-turn trajectory evaluator is registered', () {
      final EvalMetricSpec metric = EvalMetricSpec(
        metricName: PrebuiltMetricNames.rubricBasedMultiTurnTrajectoryQualityV1,
        criterion: _trajectoryCriterion(numSamples: 1),
      );

      final Evaluator evaluator = defaultMetricEvaluatorRegistry.getEvaluator(
        metric,
      );
      final Iterable<String> registeredMetricNames =
          defaultMetricEvaluatorRegistry.getRegisteredMetrics().map(
            (MetricInfo metricInfo) => metricInfo.metricName,
          );

      expect(evaluator, isA<RubricBasedMultiTurnTrajectoryEvaluator>());
      expect(
        registeredMetricNames,
        contains(PrebuiltMetricNames.rubricBasedMultiTurnTrajectoryQualityV1),
      );
    });
  });
}
