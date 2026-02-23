import '../types/content.dart';
import 'base_example_provider.dart';
import 'example.dart';

class VertexAiExampleSearchResult {
  VertexAiExampleSearchResult({
    required this.similarityScore,
    required this.searchKey,
    required List<Content> expectedOutput,
  }) : expectedOutput = expectedOutput
           .map((Content content) => content.copyWith())
           .toList(growable: false);

  final double similarityScore;
  final String searchKey;
  final List<Content> expectedOutput;
}

typedef VertexAiExampleSearcher =
    List<VertexAiExampleSearchResult> Function({
      required String exampleStoreName,
      required String query,
      int topK,
    });

/// Provides examples from a Vertex AI example store.
class VertexAiExampleStore extends BaseExampleProvider {
  VertexAiExampleStore(
    this.examplesStoreName, {
    VertexAiExampleSearcher? searcher,
  }) : _searcher = searcher;

  final String examplesStoreName;
  final VertexAiExampleSearcher? _searcher;

  @override
  List<Example> getExamples(String query) {
    final VertexAiExampleSearcher? searcher = _searcher;
    if (searcher == null) {
      return const <Example>[];
    }

    final List<VertexAiExampleSearchResult> response = searcher(
      exampleStoreName: examplesStoreName,
      query: query,
      topK: 10,
    );

    final List<Example> returnedExamples = <Example>[];
    for (final VertexAiExampleSearchResult result in response) {
      if (result.similarityScore < 0.5) {
        continue;
      }

      returnedExamples.add(
        Example(
          input: Content(
            role: 'user',
            parts: <Part>[Part.text(result.searchKey)],
          ),
          output: result.expectedOutput,
        ),
      );
    }
    return returnedExamples;
  }
}
