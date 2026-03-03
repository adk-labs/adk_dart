/// Retriever adapters that emulate llama-index style behavior.
library;

import '../tool_context.dart';
import 'base_retrieval_tool.dart';

/// One retrieval hit returned by a retriever implementation.
class RetrievalResult {
  /// Creates a retrieval result with [text].
  RetrievalResult({required this.text});

  /// Retrieved text payload.
  final String text;
}

/// Retrieval backend interface used by [LlamaIndexRetrieval].
abstract class BaseRetriever {
  /// Retrieves ranked results for [query].
  List<RetrievalResult> retrieve(String query);
}

/// Retrieval tool adapter backed by a synchronous [BaseRetriever].
class LlamaIndexRetrieval extends BaseRetrievalTool {
  /// Creates a retrieval tool with an injected [retriever].
  LlamaIndexRetrieval({
    required super.name,
    required super.description,
    required this.retriever,
  });

  /// Backend retriever implementation.
  final BaseRetriever retriever;

  @override
  /// Executes retrieval for the required `query` argument.
  Future<Object?> run({
    required Map<String, dynamic> args,
    required ToolContext toolContext,
  }) async {
    final Object? queryValue = args['query'];
    if (queryValue is! String || queryValue.trim().isEmpty) {
      throw ArgumentError('query is required for $name.');
    }
    final List<RetrievalResult> results = retriever.retrieve(queryValue.trim());
    if (results.isEmpty) {
      throw StateError(
        'No retrieval result found for query `${queryValue.trim()}`.',
      );
    }
    return results.first.text;
  }
}
