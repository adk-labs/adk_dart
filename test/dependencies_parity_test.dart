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
      expect(
        vertexai.preview.rag.lexicalRelevance(
          query: 'book flight',
          context: 'please book my flight',
        ),
        greaterThan(0),
      );
    });
  });
}
