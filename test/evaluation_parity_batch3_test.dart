import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

void main() {
  group('evaluation constants and models', () {
    test('EvalConstants exposes expected keys', () {
      expect(EvalConstants.query, 'query');
      expect(EvalConstants.expectedToolUse, 'expected_tool_use');
      expect(EvalConstants.mockToolOutput, 'mock_tool_output');
    });

    test('Rubric and RubricScore serialize and deserialize', () {
      final Rubric rubric = Rubric(
        rubricId: 'r1',
        rubricContent: RubricContent(textProperty: 'Answer is factual'),
        type: 'FINAL_RESPONSE_QUALITY',
      );
      final RubricScore score = RubricScore(
        rubricId: 'r1',
        rationale: 'Contains requested facts',
        score: 1.0,
      );

      expect(Rubric.fromJson(rubric.toJson()).rubricId, 'r1');
      expect(RubricScore.fromJson(score.toJson()).score, 1.0);
    });

    test('ConversationScenario resolves default persona by id', () {
      final ConversationScenario scenario =
          ConversationScenario.fromJson(<String, Object?>{
            'starting_prompt': 'I need to book a flight',
            'conversation_plan': 'Ask for options and then confirm.',
            'user_persona': 'default_goal_oriented',
          });
      expect(scenario.userPersona, isNotNull);
      expect(scenario.userPersona!.id, 'default_goal_oriented');
    });

    test('AppDetails returns instructions and tools by agent', () {
      final AppDetails appDetails = AppDetails(
        agentDetails: <String, AgentDetails>{
          'root': AgentDetails(
            name: 'root',
            instructions: 'Follow the policy.',
            toolDeclarations: <Object?>['toolA'],
          ),
        },
      );
      expect(appDetails.getDeveloperInstructions('root'), 'Follow the policy.');
      expect(appDetails.getToolsByAgentName()['root'], <Object?>['toolA']);
      expect(
        () => appDetails.getDeveloperInstructions('missing'),
        throwsArgumentError,
      );
    });
  });

  group('eval_case tool extraction', () {
    test('reads function call/response from invocation events', () {
      final InvocationEvents events = InvocationEvents(
        invocationEvents: <InvocationEvent>[
          InvocationEvent(
            author: 'agent',
            content: <String, Object?>{
              'parts': <Object?>[
                <String, Object?>{
                  'function_call': <String, Object?>{
                    'name': 'search',
                    'args': <String, Object?>{'q': 'weather'},
                    'id': 'c1',
                  },
                },
                <String, Object?>{
                  'function_response': <String, Object?>{
                    'name': 'search',
                    'response': <String, Object?>{'ok': true},
                    'id': 'c1',
                  },
                },
              ],
            },
          ),
        ],
      );

      final List<EvalJsonMap> calls = getAllToolCalls(events);
      final List<EvalJsonMap> responses = getAllToolResponses(events);
      expect(calls, hasLength(1));
      expect(responses, hasLength(1));
      expect(calls.first['name'], 'search');
      expect(responses.first['id'], 'c1');
    });
  });

  group('trajectory evaluator', () {
    Invocation invocationWithCalls(List<String> calls) {
      return Invocation(
        userContent: <String, Object?>{
          'role': 'user',
          'parts': <Object?>[
            <String, Object?>{'text': 'prompt'},
          ],
        },
        intermediateData: IntermediateData(
          toolUses: calls
              .map(
                (String name) => <String, Object?>{
                  'name': name,
                  'args': <String, Object?>{'v': name},
                },
              )
              .toList(),
        ),
      );
    }

    test('exact match passes only identical trajectories', () async {
      final TrajectoryEvaluator evaluator = TrajectoryEvaluator(
        evalMetric: EvalMetricSpec(
          metricName: PrebuiltMetricNames.toolTrajectoryAvgScore,
          criterion: ToolTrajectoryCriterion(
            threshold: 1.0,
            matchType: MatchType.exact,
          ),
        ),
      );

      final EvaluationResult pass = await evaluator.evaluateInvocations(
        actualInvocations: <Invocation>[
          invocationWithCalls(<String>['a', 'b']),
        ],
        expectedInvocations: <Invocation>[
          invocationWithCalls(<String>['a', 'b']),
        ],
      );
      expect(pass.overallScore, 1.0);
      expect(pass.overallEvalStatus, EvalStatus.passed);

      final EvaluationResult fail = await evaluator.evaluateInvocations(
        actualInvocations: <Invocation>[
          invocationWithCalls(<String>['a', 'b', 'c']),
        ],
        expectedInvocations: <Invocation>[
          invocationWithCalls(<String>['a', 'b']),
        ],
      );
      expect(fail.overallScore, 0.0);
      expect(fail.overallEvalStatus, EvalStatus.failed);
    });

    test('in order and any order match types work', () async {
      final TrajectoryEvaluator inOrder = TrajectoryEvaluator(
        evalMetric: EvalMetricSpec(
          metricName: PrebuiltMetricNames.toolTrajectoryAvgScore,
          criterion: ToolTrajectoryCriterion(
            threshold: 1.0,
            matchType: MatchType.inOrder,
          ),
        ),
      );
      final TrajectoryEvaluator anyOrder = TrajectoryEvaluator(
        evalMetric: EvalMetricSpec(
          metricName: PrebuiltMetricNames.toolTrajectoryAvgScore,
          criterion: ToolTrajectoryCriterion(
            threshold: 1.0,
            matchType: MatchType.anyOrder,
          ),
        ),
      );

      final EvaluationResult inOrderResult = await inOrder.evaluateInvocations(
        actualInvocations: <Invocation>[
          invocationWithCalls(<String>['x', 'a', 'b', 'c']),
        ],
        expectedInvocations: <Invocation>[
          invocationWithCalls(<String>['a', 'b']),
        ],
      );
      expect(inOrderResult.overallScore, 1.0);

      final EvaluationResult anyOrderResult = await anyOrder
          .evaluateInvocations(
            actualInvocations: <Invocation>[
              invocationWithCalls(<String>['b', 'a', 'x']),
            ],
            expectedInvocations: <Invocation>[
              invocationWithCalls(<String>['a', 'b']),
            ],
          );
      expect(anyOrderResult.overallScore, 1.0);
    });
  });

  group('metric evaluator registry', () {
    test(
      'default registry contains prebuilt metrics and resolves evaluator',
      () {
        final MetricEvaluatorRegistry registry =
            getDefaultMetricEvaluatorRegistry();
        final List<MetricInfo> metrics = registry.getRegisteredMetrics();
        expect(
          metrics.map((MetricInfo value) => value.metricName),
          contains(PrebuiltMetricNames.responseMatchScore),
        );

        final Evaluator evaluator = registry.getEvaluator(
          EvalMetricSpec(metricName: PrebuiltMetricNames.responseMatchScore),
        );
        expect(evaluator, isA<ResponseEvaluator>());
      },
    );

    test('custom metric evaluator can execute registered function', () async {
      final MetricEvaluatorRegistry registry = MetricEvaluatorRegistry();
      registry.registerEvaluator(
        metricInfo: MetricInfo(
          metricName: 'custom_metric',
          metricValueInfo: MetricValueInfo(
            interval: Interval(minValue: 0.0, maxValue: 1.0),
          ),
        ),
        evaluatorFactory: (EvalMetricSpec evalMetric) =>
            ResponseEvaluator(evalMetric: evalMetric),
      );

      registerCustomMetricFunction('pkg.metrics.customFn', (
        EvalMetricSpec evalMetric,
        List<Invocation> actualInvocations,
        List<Invocation>? expectedInvocations,
        ConversationScenario? conversationScenario,
      ) {
        return EvaluationResult(
          overallScore: 1.0,
          overallEvalStatus: EvalStatus.passed,
          perInvocationResults: <PerInvocationResult>[],
        );
      });
      addTearDown(() => unregisterCustomMetricFunction('pkg.metrics.customFn'));

      final Evaluator evaluator = registry.getEvaluator(
        EvalMetricSpec(
          metricName: 'custom_metric',
          customFunctionPath: 'pkg.metrics.customFn',
        ),
      );
      expect(evaluator, isA<CustomMetricEvaluator>());

      final EvaluationResult result = await evaluator.evaluateInvocations(
        actualInvocations: <Invocation>[
          Invocation(
            userContent: <String, Object?>{
              'role': 'user',
              'parts': <Object?>[
                <String, Object?>{'text': 'ping'},
              ],
            },
          ),
        ],
      );
      expect(result.overallScore, 1.0);
      expect(result.overallEvalStatus, EvalStatus.passed);
    });
  });

  group('retry options utils', () {
    test('adds default retry options when absent', () {
      final LlmRequest request = LlmRequest();
      expect(request.config.httpOptions, isNull);

      addDefaultRetryOptionsIfNotPresent(request);
      expect(request.config.httpOptions, isNotNull);
      expect(request.config.httpOptions!.retryOptions, isNotNull);
      expect(request.config.httpOptions!.retryOptions!.attempts, 7);
      expect(
        request.config.httpOptions!.retryOptions!.httpStatusCodes,
        contains(429),
      );
    });

    test('does not overwrite existing retry options', () {
      final LlmRequest request = LlmRequest(
        config: GenerateContentConfig(
          httpOptions: HttpOptions(retryOptions: HttpRetryOptions(attempts: 2)),
        ),
      );

      addDefaultRetryOptionsIfNotPresent(request);
      expect(request.config.httpOptions!.retryOptions!.attempts, 2);
    });
  });
}
