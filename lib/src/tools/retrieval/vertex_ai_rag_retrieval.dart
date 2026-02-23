import 'dart:convert';

import '../../models/llm_request.dart';
import '../../utils/model_name_utils.dart';
import '../tool_context.dart';
import 'base_retrieval_tool.dart';

class VertexAiRagResource {
  VertexAiRagResource({required this.path});

  final String path;

  Map<String, Object?> toJson() => <String, Object?>{'path': path};
}

class VertexAiRagStore {
  VertexAiRagStore({
    this.ragCorpora,
    this.ragResources,
    this.similarityTopK,
    this.vectorDistanceThreshold,
  });

  final List<String>? ragCorpora;
  final List<VertexAiRagResource>? ragResources;
  final int? similarityTopK;
  final double? vectorDistanceThreshold;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      if (ragCorpora != null) 'rag_corpora': ragCorpora,
      if (ragResources != null)
        'rag_resources': ragResources!.map((e) => e.toJson()).toList(),
      if (similarityTopK != null) 'similarity_top_k': similarityTopK,
      if (vectorDistanceThreshold != null)
        'vector_distance_threshold': vectorDistanceThreshold,
    };
  }

  @override
  String toString() => jsonEncode(toJson());
}

typedef VertexAiRagQueryHandler =
    Future<List<String>> Function({
      required String text,
      List<VertexAiRagResource>? ragResources,
      List<String>? ragCorpora,
      int? similarityTopK,
      double? vectorDistanceThreshold,
    });

class VertexAiRagRetrieval extends BaseRetrievalTool {
  VertexAiRagRetrieval({
    required super.name,
    required super.description,
    List<String>? ragCorpora,
    List<VertexAiRagResource>? ragResources,
    int? similarityTopK,
    double? vectorDistanceThreshold,
    this.queryHandler,
    bool Function()? modelIdCheckDisabledResolver,
  }) : vertexRagStore = VertexAiRagStore(
         ragCorpora: ragCorpora,
         ragResources: ragResources,
         similarityTopK: similarityTopK,
         vectorDistanceThreshold: vectorDistanceThreshold,
       ),
       _modelIdCheckDisabledResolver =
           modelIdCheckDisabledResolver ?? isGeminiModelIdCheckDisabled;

  final VertexAiRagStore vertexRagStore;
  final VertexAiRagQueryHandler? queryHandler;
  final bool Function() _modelIdCheckDisabledResolver;

  @override
  Future<void> processLlmRequest({
    required ToolContext toolContext,
    required LlmRequest llmRequest,
  }) async {
    final bool modelCheckDisabled = _modelIdCheckDisabledResolver();
    if (isGemini2OrAbove(llmRequest.model) || modelCheckDisabled) {
      llmRequest.config.labels['adk_vertex_ai_rag_retrieval'] =
          'vertex_rag_store';
      llmRequest.config.labels['adk_vertex_ai_rag_store'] = jsonEncode(
        vertexRagStore.toJson(),
      );
      return;
    }
    await super.processLlmRequest(
      toolContext: toolContext,
      llmRequest: llmRequest,
    );
  }

  @override
  Future<Object?> run({
    required Map<String, dynamic> args,
    required ToolContext toolContext,
  }) async {
    final Object? query = args['query'];
    if (query is! String || query.trim().isEmpty) {
      throw ArgumentError('query is required for $name.');
    }

    final VertexAiRagQueryHandler? handler = queryHandler;
    if (handler == null) {
      return 'No matching result found with the config: $vertexRagStore';
    }

    final List<String> results = await handler(
      text: query.trim(),
      ragResources: vertexRagStore.ragResources,
      ragCorpora: vertexRagStore.ragCorpora,
      similarityTopK: vertexRagStore.similarityTopK,
      vectorDistanceThreshold: vertexRagStore.vectorDistanceThreshold,
    );

    if (results.isEmpty) {
      return 'No matching result found with the config: $vertexRagStore';
    }
    return results;
  }
}
