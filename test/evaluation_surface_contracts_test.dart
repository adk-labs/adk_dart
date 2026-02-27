import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

class _StubEvalService extends BaseEvalService {
  @override
  Stream<InferenceResult> performInference(InferenceRequest request) async* {
    for (final EvalCase evalCase in request.evalCases) {
      yield InferenceResult(
        appName: request.appName,
        evalCaseId: evalCase.evalId,
        userInput: evalCase.input,
        responseText: evalCase.expectedOutput,
        sessionId: 's_${evalCase.evalId}',
        status: InferenceStatus.success,
      );
    }
  }

  @override
  Stream<EvalCaseResult> evaluate(EvaluateRequest request) async* {
    for (final InferenceResult inference in request.inferenceResults) {
      yield EvalCaseResult(
        evalCaseId: inference.evalCaseId,
        metrics: <EvalMetricResult>[
          EvalMetricResult(
            metric: EvalMetric.finalResponseExactMatch,
            score: 1,
            passed: true,
          ),
        ],
      );
    }
  }
}

void main() {
  group('evaluation surface parity', () {
    test(
      'base eval service request/response contracts are stream-friendly',
      () async {
        final _StubEvalService service = _StubEvalService();
        final EvalCase evalCase = EvalCase(
          evalId: 'e1',
          input: 'hello',
          expectedOutput: 'world',
        );

        final List<InferenceResult> inference = await service
            .performInference(
              InferenceRequest(appName: 'app', evalCases: <EvalCase>[evalCase]),
            )
            .toList();
        expect(inference, hasLength(1));
        expect(inference.first.status, InferenceStatus.success);

        final List<EvalCaseResult> evaluated = await service
            .evaluate(
              EvaluateRequest(
                inferenceResults: inference,
                evalCasesById: <String, EvalCase>{'e1': evalCase},
                evaluateConfig: EvaluateConfig(
                  evalMetrics: <EvalMetric>[EvalMetric.finalResponseExactMatch],
                ),
              ),
            )
            .toList();
        expect(evaluated, hasLength(1));
        expect(evaluated.first.finalEvalStatus, EvalStatus.notEvaluated);
        expect(evaluated.first.overallScore, 1);
      },
    );

    test(
      'EvalCase validates conversation xor scenario and parses legacy fields',
      () {
        final Invocation invocation = Invocation.fromJson(<String, Object?>{
          'query': 'where',
          'reference': 'here',
        });
        final ConversationScenario scenario = ConversationScenario(
          startingPrompt: 'start',
          conversationPlan: 'plan',
        );

        expect(
          () => EvalCase(
            evalId: 'invalid',
            conversation: <Invocation>[invocation],
            conversationScenario: scenario,
          ),
          throwsArgumentError,
        );

        final EvalCase fromLegacy = EvalCase.fromJson(<String, Object?>{
          'eval_id': 'legacy',
          'query': 'hello?',
          'reference': 'hello!',
        });
        expect(fromLegacy.input, 'hello?');
        expect(fromLegacy.expectedOutput, 'hello!');
        expect(fromLegacy.conversation, isNotNull);
        expect(fromLegacy.conversation!.first.finalResponse, isNotNull);
      },
    );

    test('tool extraction utilities handle both intermediate formats', () {
      final IntermediateData intermediate = IntermediateData(
        toolUses: <EvalJsonMap>[
          <String, Object?>{
            'id': 'fc_1',
            'name': 'search',
            'args': <String, Object?>{'q': 'adk'},
          },
        ],
        toolResponses: <EvalJsonMap>[
          <String, Object?>{
            'id': 'fc_1',
            'name': 'search',
            'response': <String, Object?>{'result': 'ok'},
          },
        ],
      );

      expect(getAllToolCalls(intermediate), hasLength(1));
      expect(getAllToolResponses(intermediate), hasLength(1));
      expect(getAllToolCallsWithResponses(intermediate), hasLength(1));

      final InvocationEvents events = InvocationEvents(
        invocationEvents: <InvocationEvent>[
          InvocationEvent(
            author: 'agent',
            content: <String, Object?>{
              'parts': <Object?>[
                <String, Object?>{
                  'function_call': <String, Object?>{
                    'name': 'lookup',
                    'args': <String, Object?>{'q': 'dart'},
                    'id': 'fc_2',
                  },
                },
                <String, Object?>{
                  'function_response': <String, Object?>{
                    'name': 'lookup',
                    'response': <String, Object?>{'result': 'great'},
                    'id': 'fc_2',
                  },
                },
              ],
            },
          ),
        ],
      );

      final List<EvalJsonMap> calls = getAllToolCalls(events);
      final List<EvalJsonMap> responses = getAllToolResponses(events);
      final List<(EvalJsonMap, EvalJsonMap?)> joined =
          getAllToolCallsWithResponses(events);

      expect(calls, hasLength(1));
      expect(calls.first['name'], 'lookup');
      expect(responses, hasLength(1));
      expect(responses.first['id'], 'fc_2');
      expect(joined, hasLength(1));
      expect(joined.first.$2, isNotNull);
    });

    test(
      'eval results parse modern/legacy json and compute aggregate score',
      () {
        final EvalCaseResult result = EvalCaseResult.fromJson(<String, Object?>{
          'eval_id': 'e1',
          'overall_eval_metric_results': <Object?>[
            <String, Object?>{
              'metric': 'finalResponseExactMatch',
              'score': 1.0,
              'passed': true,
            },
            <String, Object?>{
              'metric': 'finalResponseContains',
              'score': 0.5,
              'passed': false,
            },
          ],
          'final_eval_status': 'passed',
          'session_id': 's1',
        });

        expect(result.evalCaseId, 'e1');
        expect(result.metrics, hasLength(2));
        expect(result.finalEvalStatus, EvalStatus.passed);
        expect(result.overallScore, closeTo(0.75, 0.0001));

        final EvalSetResult setResult = EvalSetResult.fromJson(
          <String, Object?>{
            'eval_set_result_id': 'r1',
            'eval_set_id': 'set1',
            'eval_case_results': <Object?>[result.toJson()],
          },
        );
        expect(setResult.evalCaseResults, hasLength(1));
        expect(setResult.toJson()['eval_set_id'], 'set1');
      },
    );

    test('eval metric result supports python metric json contract', () {
      final EvalMetricResult passedResult = EvalMetricResult.fromJson(
        <String, Object?>{
          'metric_name': 'finalResponseExactMatch',
          'score': 1.0,
          'eval_status': 'PASSED',
          'details': <String, Object?>{'detail': 'python detail'},
        },
      );

      expect(passedResult.metric, EvalMetric.finalResponseExactMatch);
      expect(passedResult.evalStatus, EvalStatus.passed);
      expect(passedResult.passed, isTrue);
      expect(passedResult.detail, 'python detail');
      expect(passedResult.toJson(), <String, Object?>{
        'metric_name': 'finalResponseExactMatch',
        'score': 1.0,
        'eval_status': 'passed',
        'details': <String, Object?>{'detail': 'python detail'},
      });

      final EvalMetricResult notEvaluatedResult =
          EvalMetricResult.fromJson(<String, Object?>{
            'metric_name': 'finalResponseContains',
            'score': 0.0,
            'eval_status': 'not_evaluated',
            'details': <String, Object?>{},
          });
      expect(notEvaluatedResult.evalStatus, EvalStatus.notEvaluated);
      expect(notEvaluatedResult.toJson()['eval_status'], 'not_evaluated');

      final EvalMetricResult legacyResult =
          EvalMetricResult.fromJson(<String, Object?>{
            'metric': 'finalResponseContains',
            'score': 0.5,
            'passed': false,
            'detail': 'legacy detail',
          });
      expect(legacyResult.evalStatus, EvalStatus.failed);
      expect(legacyResult.detail, 'legacy detail');
    });
  });
}
