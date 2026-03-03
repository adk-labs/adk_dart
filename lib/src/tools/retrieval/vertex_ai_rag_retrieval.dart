/// Vertex AI RAG retrieval tool and configuration models.
library;

import 'dart:convert';

import '../../models/llm_request.dart';
import '../../utils/model_name_utils.dart';
import '../tool_context.dart';
import 'base_retrieval_tool.dart';

/// Vertex AI RAG resource reference.
class VertexAiRagResource {
  /// Creates a Vertex AI RAG resource reference.
  VertexAiRagResource({required this.path});

  /// Resource path in Vertex AI RAG.
  final String path;

  /// Encodes this resource for request metadata.
  Map<String, Object?> toJson() => <String, Object?>{'path': path};
}

/// Store-level RAG query configuration used by [VertexAiRagRetrieval].
class VertexAiRagStore {
  /// Creates Vertex AI RAG store configuration.
  VertexAiRagStore({
    this.ragCorpora,
    this.ragResources,
    this.similarityTopK,
    this.vectorDistanceThreshold,
  });

  /// Optional RAG corpora names.
  final List<String>? ragCorpora;

  /// Optional explicit RAG resources.
  final List<VertexAiRagResource>? ragResources;

  /// Optional top-K similarity limit.
  final int? similarityTopK;

  /// Optional vector-distance filter threshold.
  final double? vectorDistanceThreshold;

  /// Encodes this configuration for metadata transport.
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
  /// Returns JSON-encoded store configuration.
  String toString() => jsonEncode(toJson());
}

/// Callback signature for live Vertex AI RAG querying.
typedef VertexAiRagQueryHandler =
    Future<List<String>> Function({
      required String text,
      List<VertexAiRagResource>? ragResources,
      List<String>? ragCorpora,
      int? similarityTopK,
      double? vectorDistanceThreshold,
    });

/// Retrieval tool that integrates with Vertex AI RAG.
class VertexAiRagRetrieval extends BaseRetrievalTool {
  /// Creates a Vertex AI RAG retrieval tool.
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

  /// Configured Vertex AI RAG store metadata.
  final VertexAiRagStore vertexRagStore;

  /// Optional handler for explicit tool-call query execution.
  final VertexAiRagQueryHandler? queryHandler;
  final bool Function() _modelIdCheckDisabledResolver;

  @override
  /// Injects RAG labels for Gemini 2+ requests before model execution.
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
  /// Executes retrieval through [queryHandler] when provided.
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
