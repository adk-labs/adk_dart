import '../tool_context.dart';
import 'base_retrieval_tool.dart';

class RetrievalResult {
  RetrievalResult({required this.text});

  final String text;
}

abstract class BaseRetriever {
  List<RetrievalResult> retrieve(String query);
}

class LlamaIndexRetrieval extends BaseRetrievalTool {
  LlamaIndexRetrieval({
    required super.name,
    required super.description,
    required this.retriever,
  });

  final BaseRetriever retriever;

  @override
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
