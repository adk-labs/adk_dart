import 'dart:io';

import 'package:adk_dart/evaluation.dart';
import 'package:adk_dart/src/agents/llm_agent.dart';
import 'package:adk_dart/src/models/base_llm.dart';
import 'package:adk_dart/src/models/llm_request.dart';
import 'package:adk_dart/src/models/llm_response.dart';
import 'package:adk_dart/src/types/content.dart';
import 'package:test/test.dart';

class _InMemoryGcsStorageStore implements GcsStorageStore {
  final Set<String> buckets = <String>{};
  final Map<(String, String), String> blobs = <(String, String), String>{};

  @override
  Future<bool> bucketExists(String bucketName) async {
    return buckets.contains(bucketName);
  }

  @override
  Future<void> uploadText(
    String bucketName,
    String blobName,
    String contents,
  ) async {
    blobs[(bucketName, blobName)] = contents;
  }

  @override
  Future<String?> downloadText(String bucketName, String blobName) async {
    return blobs[(bucketName, blobName)];
  }

  @override
  Future<List<String>> listBlobNames(String bucketName, {String? prefix}) async {
    final List<String> names = <String>[];
    for (final (String b, String key) in blobs.keys) {
      if (b != bucketName) {
        continue;
      }
      if (prefix == null || key.startsWith(prefix)) {
        names.add(key);
      }
    }
    return names;
  }

  @override
  Future<bool> blobExists(String bucketName, String blobName) async {
    return blobs.containsKey((bucketName, blobName));
  }
}

class _AlternatingLlm extends BaseLlm {
  _AlternatingLlm(this.responses) : super(model: 'alternating');

  final List<String?> responses;
  int _index = 0;

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    final String? reply = responses[_index % responses.length];
    _index += 1;
    if (reply == null) {
      throw StateError('Simulated inference crash');
    }
    yield LlmResponse(content: Content.modelText(reply));
  }
}

class _ScoreEvaluator extends Evaluator {
  _ScoreEvaluator(this._scores);

  final List<double> _scores;
  int _callIndex = 0;

  @override
  EvaluationResult evaluateInvocations({
    required List<Invocation> actualInvocations,
    List<Invocation>? expectedInvocations,
    ConversationScenario? conversationScenario,
  }) {
    final double score = _scores[_callIndex % _scores.length];
    _callIndex += 1;
    return EvaluationResult(
      overallScore: score,
      overallEvalStatus: score >= 0.8 ? EvalStatus.passed : EvalStatus.failed,
    );
  }
}

EvalCaseResult _judgedRun(
  int repetitionIndex, {
  String evalSetId = 'set_1',
  String evalId = 'case_1',
  required double responseMatchScore,
  double threshold = 0.8,
}) {
  final EvalStatus status = responseMatchScore >= threshold
      ? EvalStatus.passed
      : EvalStatus.failed;
  return EvalCaseResult(
    evalSetId: evalSetId,
    evalId: evalId,
    finalEvalStatus: status,
    overallEvalMetricResults: <EvalMetricResultSpec>[
      EvalMetricResultSpec(
        metricName: 'response_match_score',
        score: responseMatchScore,
        threshold: threshold,
        evalStatus: status,
      ),
    ],
    sessionId: 's_$repetitionIndex',
    repetitionIndex: repetitionIndex,
  );
}

EvalCaseResult _crashedRun({
  String evalSetId = 'set_1',
  String evalId = 'case_1',
  required String sessionId,
  int? repetitionIndex,
}) {
  return EvalCaseResult(
    evalSetId: evalSetId,
    evalId: evalId,
    finalEvalStatus: EvalStatus.failed,
    overallEvalMetricResults: const <EvalMetricResultSpec>[],
    evalMetricResultPerInvocation: const <EvalMetricResultPerInvocation>[],
    sessionId: sessionId,
    repetitionIndex: repetitionIndex,
  );
}

void main() {
  group('Upstream 287c0b0e6 — MultiRunCaseSummary & MethodResult models', () {
    test('MethodResult round-trips snake_case and camelCase JSON', () {
      const MethodResult original = MethodResult(
        name: 'mean_over_invocations',
        value: 0.85,
        threshold: 0.8,
        status: EvalStatus.passed,
        note: '2 passed, 1 failed',
      );

      final Map<String, Object?> serialized = original.toJson();
      expect(serialized['name'], 'mean_over_invocations');
      expect(serialized['value'], 0.85);
      expect(serialized['threshold'], 0.8);
      expect(serialized['status'], 'passed');
      expect(serialized['note'], '2 passed, 1 failed');

      final MethodResult roundTripped = MethodResult.fromJson(serialized);
      expect(roundTripped, equals(original));

      final MethodResult fromCamel = MethodResult.fromJson(<String, Object?>{
        'name': 'pass_rate',
        'value': null,
        'threshold': null,
        'status': 'NOT_EVALUATED',
      });
      expect(fromCamel.status, EvalStatus.notEvaluated);
      expect(fromCamel.value, isNull);
    });

    test('MultiRunCaseSummary round-trips snake_case and camelCase JSON', () {
      final MultiRunCaseSummary summary = MultiRunCaseSummary(
        evalSetId: 'eval_set_alpha',
        evalId: 'case_alpha',
        finalEvalStatus: EvalStatus.passed,
        numRuns: 4,
        passedRuns: 2,
        failedRuns: 1,
        crashedRuns: 1,
        notEvaluatedRuns: 0,
        passRate: 2 / 3,
        overallEvalMetricResults: <EvalMetricResultSpec>[
          EvalMetricResultSpec(
            metricName: 'response_match_score',
            score: 0.8,
            threshold: 0.8,
            evalStatus: EvalStatus.passed,
          ),
        ],
        metricMethods: <String, MethodResult>{
          'response_match_score': const MethodResult(
            name: 'mean_over_invocations',
            value: 0.8,
            threshold: 0.8,
            status: EvalStatus.passed,
          ),
        },
        crossRunResults: const <MethodResult>[
          MethodResult(
            name: 'pass_at_3',
            value: 1.0,
            threshold: 0.9,
            status: EvalStatus.passed,
            note: '2 passed, 1 failed, 1 crashed',
          ),
        ],
        maxCrashedRuns: 1,
      );

      final Map<String, Object?> json = summary.toJson();
      expect(json['eval_set_id'], 'eval_set_alpha');
      expect(json['eval_id'], 'case_alpha');
      expect(json['num_runs'], 4);
      expect(json['passed_runs'], 2);
      expect(json['failed_runs'], 1);
      expect(json['crashed_runs'], 1);
      expect(json['not_evaluated_runs'], 0);
      expect(json['pass_rate'], closeTo(2 / 3, 1e-9));
      expect(json['max_crashed_runs'], 1);

      final MultiRunCaseSummary fromSnake = MultiRunCaseSummary.fromJson(json);
      expect(fromSnake, equals(summary));

      final MultiRunCaseSummary fromCamel = MultiRunCaseSummary.fromJson(
        <String, Object?>{
          'evalSetId': 'eval_set_alpha',
          'evalId': 'case_alpha',
          'finalEvalStatus': 'PASSED',
          'numRuns': 4,
          'passedRuns': 2,
          'failedRuns': 1,
          'crashedRuns': 1,
          'notEvaluatedRuns': 0,
          'passRate': 2 / 3,
          'overallEvalMetricResults': <Map<String, Object?>>[
            <String, Object?>{
              'metricName': 'response_match_score',
              'score': 0.8,
              'threshold': 0.8,
              'evalStatus': 'PASSED',
            },
          ],
          'metricMethods': <String, Object?>{
            'response_match_score': <String, Object?>{
              'name': 'mean_over_invocations',
              'value': 0.8,
              'threshold': 0.8,
              'status': 'PASSED',
            },
          },
          'crossRunResults': <Map<String, Object?>>[
            <String, Object?>{
              'name': 'pass_at_3',
              'value': 1.0,
              'threshold': 0.9,
              'status': 'PASSED',
              'note': '2 passed, 1 failed, 1 crashed',
            },
          ],
          'maxCrashedRuns': 1,
        },
      );
      expect(fromCamel, equals(summary));
    });
  });

  group('Upstream 287c0b0e6 — Aggregator summarizeEvalCaseResults', () {
    test(
      'summarizeEvalCaseResults records passed, failed, crashed, notEvaluated runs and passRate',
      () {
        final List<EvalCaseResult> runs = <EvalCaseResult>[
          _judgedRun(0, responseMatchScore: 1.0),
          _judgedRun(1, responseMatchScore: 0.6),
          _judgedRun(2, responseMatchScore: 0.9),
          _crashedRun(sessionId: 's3', repetitionIndex: 3),
        ];

        final List<MultiRunCaseSummary> summaries = summarizeEvalCaseResults(
          runs,
          multiRunConfig: MultiRunConfig(maxCrashedRuns: 1),
        );

        expect(summaries, hasLength(1));
        final MultiRunCaseSummary summary = summaries.single;
        expect(summary.numRuns, 4);
        expect(summary.passedRuns, 2);
        expect(summary.failedRuns, 1);
        expect(summary.crashedRuns, 1);
        expect(summary.notEvaluatedRuns, 0);
        expect(summary.passRate, closeTo(2 / 3, 1e-9));
        expect(summary.finalEvalStatus, EvalStatus.passed);

        // Verify alias helper returns identical summary.
        final List<MultiRunCaseSummary> viaAlias = buildMultiRunCaseSummaries(
          runs,
          multiRunConfig: MultiRunConfig(maxCrashedRuns: 1),
        );
        expect(viaAlias, equals(summaries));
      },
    );

    test(
      'summarizeEvalCaseResults sets passRate to null when all runs are crashed or notEvaluated',
      () {
        final List<EvalCaseResult> runs = <EvalCaseResult>[
          EvalCaseResult(
            evalSetId: 'set_1',
            evalId: 'uneval_case',
            finalEvalStatus: EvalStatus.notEvaluated,
            overallEvalMetricResults: <EvalMetricResultSpec>[
              EvalMetricResultSpec(
                metricName: 'info_metric',
                score: 0.5,
                evalStatus: EvalStatus.informational,
              ),
            ],
            sessionId: 's0',
            repetitionIndex: 0,
          ),
          _crashedRun(
            evalId: 'uneval_case',
            sessionId: 's1',
            repetitionIndex: 1,
          ),
        ];

        final MultiRunCaseSummary summary = summarizeEvalCaseResults(
          runs,
          multiRunConfig: MultiRunConfig(maxCrashedRuns: 1),
        ).single;

        expect(summary.numRuns, 2);
        expect(summary.passedRuns, 0);
        expect(summary.failedRuns, 0);
        expect(summary.crashedRuns, 1);
        expect(summary.notEvaluatedRuns, 1);
        expect(summary.passRate, isNull);
      },
    );
  });

  group('Upstream 287c0b0e6 — Local, GCS, and InMemory EvalSetResultsManager', () {
    test('LocalEvalSetResultsManager persists and loads multiRunCaseSummaries', () async {
      final Directory tempDir = await Directory.systemTemp.createTemp(
        'adk_eval_multi_run_local_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final LocalEvalSetResultsManager manager = LocalEvalSetResultsManager(
        tempDir.path,
      );
      final List<EvalCaseResult> caseResults = <EvalCaseResult>[
        _judgedRun(0, evalSetId: 'suite_a', evalId: 'case1', responseMatchScore: 1.0),
        _judgedRun(1, evalSetId: 'suite_a', evalId: 'case1', responseMatchScore: 0.6),
      ];
      final List<MultiRunCaseSummary> summaries = <MultiRunCaseSummary>[
        MultiRunCaseSummary(
          evalSetId: 'suite_a',
          evalId: 'case1',
          finalEvalStatus: EvalStatus.passed,
          numRuns: 2,
          passedRuns: 1,
          failedRuns: 1,
          passRate: 0.5,
          metricMethods: <String, MethodResult>{
            'response_match_score': const MethodResult(
              name: 'mean_over_invocations',
              value: 0.8,
              threshold: 0.8,
              status: EvalStatus.passed,
            ),
          },
        ),
      ];

      await manager.saveEvalSetResult(
        'demo_app',
        'suite_a',
        caseResults,
        multiRunCaseSummaries: summaries,
      );

      final List<String> ids = await manager.listEvalSetResults('demo_app');
      expect(ids, hasLength(1));

      final EvalSetResult retrieved = await manager.getEvalSetResult(
        'demo_app',
        ids.single,
      );
      expect(retrieved.multiRunCaseSummaries, equals(summaries));
    });

    test('GcsEvalSetResultsManager persists and loads multiRunCaseSummaries', () async {
      final _InMemoryGcsStorageStore store = _InMemoryGcsStorageStore()
        ..buckets.add('eval-bucket');
      final GcsEvalSetResultsManager manager = GcsEvalSetResultsManager(
        bucketName: 'eval-bucket',
        storageStore: store,
      );

      final List<EvalCaseResult> caseResults = <EvalCaseResult>[
        _judgedRun(0, evalSetId: 'test_eval_set', evalId: 'eval_case_1', responseMatchScore: 1.0),
        _judgedRun(1, evalSetId: 'test_eval_set', evalId: 'eval_case_1', responseMatchScore: 0.9),
      ];
      final List<MultiRunCaseSummary> summaries = <MultiRunCaseSummary>[
        MultiRunCaseSummary(
          evalSetId: 'test_eval_set',
          evalId: 'eval_case_1',
          finalEvalStatus: EvalStatus.passed,
          numRuns: 2,
          passedRuns: 2,
          failedRuns: 0,
          passRate: 1.0,
        ),
      ];

      await manager.saveEvalSetResult(
        'test_app',
        'test_eval_set',
        caseResults,
        multiRunCaseSummaries: summaries,
      );

      final List<String> ids = await manager.listEvalSetResults('test_app');
      expect(ids, hasLength(1));

      final EvalSetResult retrieved = await manager.getEvalSetResult(
        'test_app',
        ids.single,
      );
      expect(retrieved.multiRunCaseSummaries, equals(summaries));
    });

    test('InMemoryEvalSetResultsManager persists and loads multiRunCaseSummaries', () async {
      final InMemoryEvalSetResultsManager manager =
          InMemoryEvalSetResultsManager();
      final List<MultiRunCaseSummary> summaries = <MultiRunCaseSummary>[
        MultiRunCaseSummary(
          evalSetId: 'mem_set',
          evalId: 'case_mem',
          finalEvalStatus: EvalStatus.failed,
          numRuns: 3,
          passedRuns: 1,
          failedRuns: 2,
          passRate: 1 / 3,
        ),
      ];

      await manager.saveEvalSetResult(
        'mem_app',
        'mem_set',
        <EvalCaseResult>[],
        multiRunCaseSummaries: summaries,
      );

      final List<String> ids = await manager.listEvalSetResults('mem_app');
      final EvalSetResult retrieved = await manager.getEvalSetResult(
        'mem_app',
        ids.single,
      );
      expect(retrieved.multiRunCaseSummaries, equals(summaries));
    });
  });

  group('Upstream 287c0b0e6 — LocalEvalService multi-run persistence', () {
    test(
      'evaluate persists multiRunCaseSummaries when case has multiple runs or multiRunConfig',
      () async {
        final InMemoryEvalSetResultsManager resultsManager =
            InMemoryEvalSetResultsManager();
        final MetricEvaluatorRegistry registry = MetricEvaluatorRegistry();
        final _ScoreEvaluator sharedEvaluator = _ScoreEvaluator(<double>[
          1.0,
          0.6,
        ]);
        registry.registerEvaluator(
          metricInfo: MetricInfo(
            metricName: 'response_match_score',
            metricValueInfo: MetricValueInfo(
              interval: Interval(minValue: 0.0, maxValue: 1.0),
            ),
          ),
          evaluatorFactory: (EvalMetricSpec metric) => sharedEvaluator,
        );

        final Agent agent = Agent(
          name: 'eval_agent',
          model: _AlternatingLlm(<String?>['answer_ok', 'answer_partial']),
        );
        final LocalEvalService evalService = LocalEvalService(
          rootAgent: agent,
          appName: 'test_app',
          evalSetResultsManager: resultsManager,
          metricEvaluatorRegistry: registry,
        );

        final InferenceResult inf0 = InferenceResult(
          appName: 'test_app',
          evalSetId: 'set1',
          evalCaseId: 'case1',
          userInput: 'prompt',
          responseText: 'answer_ok',
          sessionId: 's0',
          status: InferenceStatus.success,
          repetitionIndex: 0,
        );
        final InferenceResult inf1 = InferenceResult(
          appName: 'test_app',
          evalSetId: 'set1',
          evalCaseId: 'case1',
          userInput: 'prompt',
          responseText: 'answer_partial',
          sessionId: 's1',
          status: InferenceStatus.success,
          repetitionIndex: 1,
        );

        final EvaluateRequest request = EvaluateRequest(
          inferenceResults: <InferenceResult>[inf0, inf1],
          evaluateConfig: EvaluateConfig(
            evalMetricSpecs: <EvalMetricSpec>[
              EvalMetricSpec(metricName: 'response_match_score', threshold: 0.8),
            ],
            multiRunConfig: MultiRunConfig(numRuns: 2),
            parallelism: 1,
          ),
        );

        final List<EvalCaseResult> evaluated =
            await evalService.evaluate(request).toList();
        expect(evaluated, hasLength(2));

        final List<String> savedIds = await resultsManager.listEvalSetResults(
          'test_app',
        );
        expect(savedIds, hasLength(1));

        final EvalSetResult saved = await resultsManager.getEvalSetResult(
          'test_app',
          savedIds.single,
        );
        expect(saved.multiRunCaseSummaries, isNotNull);
        expect(saved.multiRunCaseSummaries, hasLength(1));

        final MultiRunCaseSummary summary = saved.multiRunCaseSummaries!.single;
        expect(summary.evalId, 'case1');
        expect(summary.numRuns, 2);
        expect(summary.passedRuns, 1);
        expect(summary.failedRuns, 1);
        expect(summary.crashedRuns, 0);
        expect(summary.passRate, 0.5);
        expect(summary.finalEvalStatus, EvalStatus.passed);
      },
    );

    test(
      'evaluate omits multiRunCaseSummaries on single-run eval without multiRunConfig',
      () async {
        final InMemoryEvalSetResultsManager resultsManager =
            InMemoryEvalSetResultsManager();
        final Agent agent = Agent(
          name: 'eval_agent',
          model: _AlternatingLlm(<String?>['hello']),
        );
        final LocalEvalService evalService = LocalEvalService(
          rootAgent: agent,
          appName: 'single_app',
          evalSetResultsManager: resultsManager,
        );

        final List<EvalCaseResult> evaluated = await evalService
            .evaluate(
              EvaluateRequest(
                inferenceResults: <InferenceResult>[
                  InferenceResult(
                    appName: 'single_app',
                    evalSetId: 'single_set',
                    evalCaseId: 'case_single',
                    userInput: 'hi',
                    responseText: 'hello',
                    sessionId: 's_single',
                    status: InferenceStatus.success,
                  ),
                ],
                evalCasesById: <String, EvalCase>{
                  'case_single': EvalCase(
                    evalId: 'case_single',
                    input: 'hi',
                    expectedOutput: 'hello',
                  ),
                },
                evaluateConfig: EvaluateConfig(),
              ),
            )
            .toList();

        expect(evaluated, hasLength(1));
        final List<String> savedIds = await resultsManager.listEvalSetResults(
          'single_app',
        );
        final EvalSetResult saved = await resultsManager.getEvalSetResult(
          'single_app',
          savedIds.single,
        );
        expect(saved.multiRunCaseSummaries, isNull);
      },
    );
  });
}
