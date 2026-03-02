/// Vertex AI-backed example provider and result models.
library;

import '../types/content.dart';
import 'base_example_provider.dart';
import 'example.dart';

/// Result row returned by Vertex AI example search.
class VertexAiExampleSearchResult {
  /// Creates an example search result.
  VertexAiExampleSearchResult({
    required this.similarityScore,
    required this.searchKey,
    required List<Content> expectedOutput,
  }) : expectedOutput = expectedOutput
           .map((Content content) => content.copyWith())
           .toList(growable: false);

  /// Similarity score for the matched example.
  final double similarityScore;

  /// Search key or query text from the stored example.
  final String searchKey;

  /// Expected output sequence for the matched example.
  final List<Content> expectedOutput;
}

/// Searcher signature for querying a Vertex AI example store.
typedef VertexAiExampleSearcher =
    List<VertexAiExampleSearchResult> Function({
      required String exampleStoreName,
      required String query,
      int topK,
    });

/// Provides examples from a Vertex AI example store.
class VertexAiExampleStore extends BaseExampleProvider {
  /// Creates a Vertex AI example store provider.
  VertexAiExampleStore(
    this.examplesStoreName, {
    VertexAiExampleSearcher? searcher,
  }) : _searcher = searcher;

  /// Example store resource name.
  final String examplesStoreName;
  final VertexAiExampleSearcher? _searcher;

  @override
  /// Returns relevant examples for [query].
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
