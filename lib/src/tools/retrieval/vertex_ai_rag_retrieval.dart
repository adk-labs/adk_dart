/// Vertex AI RAG retrieval tool and configuration models.
library;

import 'dart:convert';

import '../../models/llm_request.dart';
import '../../utils/model_name_utils.dart';
import '../base_tool.dart';
import '../tool_configs.dart';
import '../tool_context.dart';
import 'base_retrieval_tool.dart';

/// Vertex AI RAG resource reference.
class VertexAiRagResource {
  /// Creates a Vertex AI RAG resource reference.
  VertexAiRagResource({required this.path});

  /// Creates a Vertex AI RAG resource reference from a JSON map.
  factory VertexAiRagResource.fromJson(Map<String, Object?> json) {
    final Object? rawPath =
        json['path'] ?? json['rag_corpus'] ?? json['ragCorpus'];
    return VertexAiRagResource(path: '${rawPath ?? ''}');
  }

  /// Resource path in Vertex AI RAG.
  final String path;

  /// Encodes this resource for request metadata.
  Map<String, Object?> toJson() => <String, Object?>{'path': path};

  /// Encodes this resource for Gemini built-in Vertex RAG tooling.
  Map<String, Object?> toVertexJson() => <String, Object?>{'ragCorpus': path};
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

  /// Encodes this configuration for model-side `retrieval.vertexRagStore`.
  Map<String, Object?> toVertexJson() {
    return <String, Object?>{
      if (ragCorpora != null) 'ragCorpora': ragCorpora,
      if (ragResources != null)
        'ragResources': ragResources!.map((e) => e.toVertexJson()).toList(),
      if (similarityTopK != null) 'similarityTopK': similarityTopK,
      if (vectorDistanceThreshold != null)
        'vectorDistanceThreshold': vectorDistanceThreshold,
    };
  }

  /// Returns JSON-encoded store configuration.
  @override
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

  /// Creates a [VertexAiRagRetrieval] tool from a [ToolArgsConfig] payload.
  static VertexAiRagRetrieval fromConfig(
    ToolArgsConfig config, [
    String configAbsPath = '',
  ]) {
    final Map<String, Object?> kwargs = BaseTool.resolveConfigKwargs(
      config,
      const <String, String>{
        'name': 'str',
        'description': 'str',
        'rag_corpora': 'list[str] | None',
        'rag_resources': 'list[VertexAiRagResource] | None',
        'similarity_top_k': 'int | None',
        'vector_distance_threshold': 'float | None',
      },
      modelFactories: <String, Object? Function(Map<String, Object?>)>{
        'VertexAiRagResource': VertexAiRagResource.fromJson,
      },
    );
    final Object? rawCorpora = kwargs['rag_corpora'];
    final Object? rawResources = kwargs['rag_resources'];
    final Object? rawTopK = kwargs['similarity_top_k'];
    final Object? rawThreshold = kwargs['vector_distance_threshold'];

    return VertexAiRagRetrieval(
      name: (kwargs['name'] as String?) ?? '',
      description: (kwargs['description'] as String?) ?? '',
      ragCorpora: rawCorpora is List
          ? rawCorpora.map((Object? e) => '$e').toList(growable: false)
          : null,
      ragResources: rawResources is List
          ? rawResources.whereType<VertexAiRagResource>().toList(growable: false)
          : null,
      similarityTopK: rawTopK is num ? rawTopK.toInt() : null,
      vectorDistanceThreshold: rawThreshold is num
          ? rawThreshold.toDouble()
          : null,
    );
  }

  /// Injects model-side Vertex RAG retrieval for Gemini 2+ requests.
  @override
  Future<void> processLlmRequest({
    required ToolContext toolContext,
    required LlmRequest llmRequest,
  }) async {
    final bool modelCheckDisabled = _modelIdCheckDisabledResolver();
    if (isGeminiEapOr2OrAbove(llmRequest.model) || modelCheckDisabled) {
      llmRequest.config.tools ??= <ToolDeclaration>[];
      llmRequest.config.tools!.add(
        ToolDeclaration(
          retrieval: <String, Object?>{
            'vertexRagStore': vertexRagStore.toVertexJson(),
          },
        ),
      );
      return;
    }
    await super.processLlmRequest(
      toolContext: toolContext,
      llmRequest: llmRequest,
    );
  }

  /// Executes retrieval through [queryHandler] when provided.
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
