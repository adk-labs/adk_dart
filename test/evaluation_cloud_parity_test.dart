import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

class _InMemoryGcsStorageStore implements GcsStorageStore {
  final Set<String> _buckets = <String>{};
  final Map<String, Map<String, String>> _objects =
      <String, Map<String, String>>{};

  void createBucket(String name) {
    _buckets.add(name);
    _objects.putIfAbsent(name, () => <String, String>{});
  }

  @override
  Future<bool> bucketExists(String bucketName) async {
    return _buckets.contains(bucketName);
  }

  @override
  Future<bool> blobExists(String bucketName, String blobName) async {
    final Map<String, String>? objects = _objects[bucketName];
    return objects != null && objects.containsKey(blobName);
  }

  @override
  Future<String?> downloadText(String bucketName, String blobName) async {
    return _objects[bucketName]?[blobName];
  }

  @override
  Future<List<String>> listBlobNames(
    String bucketName, {
    String? prefix,
  }) async {
    final Map<String, String>? objects = _objects[bucketName];
    if (objects == null) {
      return <String>[];
    }
    final List<String> names =
        objects.keys
            .where((String key) => prefix == null || key.startsWith(prefix))
            .toList()
          ..sort();
    return names;
  }

  @override
  Future<void> uploadText(
    String bucketName,
    String blobName,
    String contents,
  ) async {
    _objects.putIfAbsent(bucketName, () => <String, String>{});
    _objects[bucketName]![blobName] = contents;
  }
}

Invocation _invocation({required String userText, required String modelText}) {
  return Invocation(
    invocationId: '',
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
  group('GCS eval set manager parity', () {
    test(
      'creates, lists, and updates eval sets in bucket-backed store',
      () async {
        final _InMemoryGcsStorageStore store = _InMemoryGcsStorageStore()
          ..createBucket('eval-bucket');
        final GcsEvalSetsManager manager = GcsEvalSetsManager(
          bucketName: 'eval-bucket',
          storageStore: store,
        );

        final EvalSet created = await manager.createEvalSet('app1', 'set_1');
        expect(created.evalSetId, 'set_1');
        expect(await manager.listEvalSets('app1'), <String>['set_1']);

        await manager.addEvalCase(
          'app1',
          'set_1',
          EvalCase(evalId: 'case_1', input: 'hello'),
        );
        final EvalCase? loadedCase = await manager.getEvalCase(
          'app1',
          'set_1',
          'case_1',
        );
        expect(loadedCase, isNotNull);
        expect(loadedCase!.input, 'hello');

        await manager.updateEvalCase(
          'app1',
          'set_1',
          EvalCase(evalId: 'case_1', input: 'updated'),
        );
        final EvalCase? updated = await manager.getEvalCase(
          'app1',
          'set_1',
          'case_1',
        );
        expect(updated!.input, 'updated');

        await manager.deleteEvalCase('app1', 'set_1', 'case_1');
        expect(await manager.getEvalCase('app1', 'set_1', 'case_1'), isNull);
      },
    );

    test('fails when bucket does not exist', () async {
      final GcsEvalSetsManager manager = GcsEvalSetsManager(
        bucketName: 'missing-bucket',
        storageStore: _InMemoryGcsStorageStore(),
      );
      expect(
        () => manager.createEvalSet('app', 'set1'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('GCS eval result manager parity', () {
    test('saves, lists, and loads eval set results', () async {
      final _InMemoryGcsStorageStore store = _InMemoryGcsStorageStore()
        ..createBucket('results-bucket');
      final GcsEvalSetResultsManager manager = GcsEvalSetResultsManager(
        bucketName: 'results-bucket',
        storageStore: store,
      );

      await manager.saveEvalSetResult('app2', 'setA', <EvalCaseResult>[
        EvalCaseResult(
          evalCaseId: 'case-a',
          evalSetId: 'setA',
          finalEvalStatus: EvalStatus.passed,
          sessionId: 'session-a',
          metrics: <EvalMetricResult>[
            EvalMetricResult(
              metric: EvalMetric.finalResponseExactMatch,
              score: 1.0,
              passed: true,
            ),
          ],
        ),
      ]);

      final List<String> ids = await manager.listEvalSetResults('app2');
      expect(ids, hasLength(1));

      final EvalSetResult loaded = await manager.getEvalSetResult(
        'app2',
        ids.first,
      );
      expect(loaded.evalSetId, 'setA');
      expect(loaded.evalCaseResults.single.evalCaseId, 'case-a');
    });
  });

  group('Vertex AI eval facade parity', () {
    test('evaluates per-invocation scores through injected invoker', () async {
      final VertexAiEvalFacade evaluator = VertexAiEvalFacade(
        threshold: 0.6,
        metricName: 'faithfulness',
        evalInvoker:
            ({
              required List<Map<String, String?>> dataset,
              required List<String> metrics,
            }) async {
              expect(metrics, <String>['faithfulness']);
              expect(dataset.single['response'], 'response');
              return VertexAiEvalOutput(
                summaryMetrics: <VertexAiEvalSummaryMetric>[
                  VertexAiEvalSummaryMetric(meanScore: 0.75),
                ],
              );
            },
      );

      final EvaluationResult result = await evaluator.evaluateInvocations(
        actualInvocations: <Invocation>[
          _invocation(userText: 'prompt', modelText: 'response'),
        ],
        expectedInvocations: <Invocation>[
          _invocation(userText: 'prompt', modelText: 'reference'),
        ],
      );
      expect(result.overallScore, 0.75);
      expect(result.overallEvalStatus, EvalStatus.passed);
      expect(result.perInvocationResults.single.evalStatus, EvalStatus.passed);
    });

    test('matches python truthy behavior for zero scores', () async {
      final VertexAiEvalFacade evaluator = VertexAiEvalFacade(
        threshold: 0.9,
        metricName: 'faithfulness',
        evalInvoker:
            ({
              required List<Map<String, String?>> dataset,
              required List<String> metrics,
            }) async => VertexAiEvalOutput(
              summaryMetrics: <VertexAiEvalSummaryMetric>[
                VertexAiEvalSummaryMetric(meanScore: 0.0),
              ],
            ),
      );

      final EvaluationResult result = await evaluator.evaluateInvocations(
        actualInvocations: <Invocation>[
          _invocation(userText: 'prompt', modelText: 'bad response'),
        ],
        expectedInvocations: <Invocation>[
          _invocation(userText: 'prompt', modelText: 'reference'),
        ],
      );

      expect(result.overallScore, isNull);
      expect(result.overallEvalStatus, EvalStatus.notEvaluated);
      expect(result.perInvocationResults.single.evalStatus, EvalStatus.failed);
    });
  });
}
