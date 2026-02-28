import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

void main() {
  group('rouge scorer parity', () {
    test('computes rouge1 precision/recall/fmeasure', () {
      final RougeScorer scorer = RougeScorer(metrics: <String>['rouge1']);
      final Map<String, RougeScore> result = scorer.score(
        target: 'book a table for two',
        prediction: 'book table for two people',
      );

      expect(result.containsKey('rouge1'), isTrue);
      final RougeScore score = result['rouge1']!;
      expect(score.precision, greaterThan(0));
      expect(score.recall, greaterThan(0));
      expect(score.fmeasure, greaterThan(0));
    });

    test('accepts rouge1 aliases and rejects unsupported metrics', () {
      final RougeScorer scorer = RougeScorer(
        metrics: <String>['rouge1', 'rouge-1', 'rouge_1'],
      );
      final Map<String, RougeScore> result = scorer.score(
        target: 'book a table',
        prediction: 'book table now',
      );

      expect(
        result.keys,
        containsAll(<String>['rouge1', 'rouge-1', 'rouge_1']),
      );
      expect(
        () => RougeScorer(metrics: <String>['rouge2']),
        throwsArgumentError,
      );
      expect(() => RougeScorer(metrics: <String>[]), throwsArgumentError);
    });

    test('handles non-ascii tokens instead of dropping them', () {
      final RougeScorer scorer = RougeScorer(metrics: <String>['rouge1']);
      final Map<String, RougeScore> result = scorer.score(
        target: '서울에서 맛집 추천해줘',
        prediction: '서울 맛집 추천 부탁해',
      );

      expect(result['rouge1']!.fmeasure, greaterThan(0));
    });
  });

  group('vertexai dependency parity', () {
    test('module exposes client, types, and preview helpers', () async {
      final VertexAiClient client = vertexai.client(apiKey: 'fake-key');
      final VertexAiEvaluationDataset dataset = vertexai.types
          .evaluationDataset(
            evalDatasetRows: <Map<String, String?>>[
              <String, String?>{
                'prompt': 'What is the capital of France?',
                'reference': 'Paris is the capital of France.',
                'response': 'Paris is the capital.',
              },
            ],
          );

      final VertexAiDependencyEvalResult result = await client.evals.evaluate(
        dataset: dataset,
        metrics: <String>['groundedness'],
      );
      expect(result.summaryMetrics, hasLength(1));
      expect(result.summaryMetrics.first.meanScore, greaterThan(0));

      expect(
        vertexai.preview.exampleStores.normalizeExampleId(' Example Id '),
        'example_id',
      );
      expect(identical(vertexai.preview.exampleStores, exampleStores), isTrue);
      expect(identical(vertexai.preview.rag, rag), isTrue);
      expect(
        vertexai.preview.rag.lexicalRelevance(
          query: 'book flight',
          context: 'please book my flight',
        ),
        greaterThan(0),
      );
    });

    test('validates metrics and normalizes dataset rows defensively', () async {
      final VertexAiClient client = vertexai.client(
        project: 'p',
        location: 'us',
      );
      final Map<String, String?> row = <String, String?>{
        'prompt': 'What is the capital of France?',
        'reference': '   ',
        'response': ' France capital ',
      };
      final VertexAiEvaluationDataset dataset = vertexai.types
          .evaluationDataset(evalDatasetRows: <Map<String, String?>>[row]);
      row['response'] = 'Lyon';

      final VertexAiDependencyEvalResult result = await client.evals.evaluate(
        dataset: dataset,
        metrics: <String>['groundedness', 'recall'],
      );
      expect(result.summaryMetrics.first.meanScore, greaterThan(0));
      expect(client.isConfigured, isTrue);

      await expectLater(
        client.evals.evaluate(dataset: dataset, metrics: <String>[]),
        throwsArgumentError,
      );
      await expectLater(
        client.evals.evaluate(dataset: dataset, metrics: <String>[' ']),
        throwsArgumentError,
      );
    });

    test('example id normalization and rag relevance handle edge cases', () {
      expect(
        exampleStores.normalizeExampleId(
          ' Example: ID 2026/02 ',
          maxLength: 12,
        ),
        'example_id_2',
      );
      expect(exampleStores.normalizeExampleId(' --- '), 'example');

      expect(
        rag.lexicalRelevance(
          query: 'book flight',
          context: 'please book my flight',
        ),
        1.0,
      );
      expect(
        rag.lexicalRelevance(query: 'book flight', context: 'reserve hotel'),
        0.0,
      );
    });
  });

  group('dependency container parity', () {
    test('latest registration wins and optional resolution works', () {
      final DependencyContainer container = DependencyContainer();

      container.registerSingleton<String>('singleton');
      container.registerFactory<String>(() => 'factory');
      expect(container.resolve<String>(), 'factory');

      container.registerFactory<int>(() => 7);
      expect(container.resolve<int>(), 7);
      expect(container.resolveOrNull<double>(), isNull);
      expect(container.contains<int>(), isTrue);

      expect(container.unregister<int>(), isTrue);
      expect(container.contains<int>(), isFalse);
      expect(container.unregister<int>(), isFalse);
    });
  });
}
