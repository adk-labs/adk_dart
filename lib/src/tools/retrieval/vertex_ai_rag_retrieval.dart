/// Vertex AI RAG retrieval tool and configuration models.
library;

import 'dart:async';
import 'dart:convert';

import '../../memory/vertex_ai_rag_memory_service.dart'
    show
        VertexAiRagClient,
        VertexAiRagClientFactory,
        VertexAiRagContext,
        VertexAiRagRetrievalResponse,
        VertexRagStoreRagResource;
import '../../models/llm_request.dart';
import '../../utils/model_name_utils.dart';
import '../../utils/system_environment/system_environment.dart';
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
    this.clientFactory,
    Map<String, String> Function()? environmentProvider,
    bool Function()? modelIdCheckDisabledResolver,
  }) : vertexRagStore = VertexAiRagStore(
         ragCorpora: ragCorpora,
         ragResources: ragResources,
         similarityTopK: similarityTopK,
         vectorDistanceThreshold: vectorDistanceThreshold,
       ),
       _environmentProvider = environmentProvider ?? readSystemEnvironment,
       _modelIdCheckDisabledResolver =
           modelIdCheckDisabledResolver ?? isGeminiModelIdCheckDisabled;

  /// Configured Vertex AI RAG store metadata.
  final VertexAiRagStore vertexRagStore;

  /// Optional handler for explicit tool-call query execution.
  final VertexAiRagQueryHandler? queryHandler;

  /// Optional factory used to build and cache [VertexAiRagClient] instances per
  /// execution [Zone] and `(project, location)` pair.
  final VertexAiRagClientFactory? clientFactory;
  final Map<String, String> Function() _environmentProvider;
  final bool Function() _modelIdCheckDisabledResolver;
  final Expando<Map<(String?, String?), VertexAiRagClient>>
  _apiClientsPerZone =
      Expando<Map<(String?, String?), VertexAiRagClient>>(
        'VertexAiRagRetrieval._apiClientsPerZone',
      );

  /// Resolves `(project, location)` preferring a fully-qualified corpus path
  /// over `GOOGLE_CLOUD_PROJECT` and `GOOGLE_CLOUD_LOCATION`.
  (String?, String?) projectAndLocation() {
    String? storeProject;
    String? storeLocation;
    String? corpusName;
    if (vertexRagStore.ragCorpora != null &&
        vertexRagStore.ragCorpora!.isNotEmpty) {
      corpusName = vertexRagStore.ragCorpora!.first;
    } else if (vertexRagStore.ragResources != null &&
        vertexRagStore.ragResources!.isNotEmpty) {
      corpusName = vertexRagStore.ragResources!.first.path;
    }

    if (corpusName != null && corpusName.startsWith('projects/')) {
      final List<String> parts = corpusName.split('/');
      if (parts.length >= 4 &&
          parts[0] == 'projects' &&
          parts[2] == 'locations') {
        storeProject = _nonEmptyOrNull(parts[1]);
        storeLocation = _nonEmptyOrNull(parts[3]);
      }
    }

    final Map<String, String> env = _environmentProvider();
    return (
      storeProject ?? _nonEmptyOrNull(env['GOOGLE_CLOUD_PROJECT']),
      storeLocation ?? _nonEmptyOrNull(env['GOOGLE_CLOUD_LOCATION']),
    );
  }

  VertexAiRagStore _retrievalStore() {
    return VertexAiRagStore(
      ragCorpora: vertexRagStore.ragCorpora,
      ragResources: vertexRagStore.ragResources,
      vectorDistanceThreshold: vertexRagStore.vectorDistanceThreshold,
    );
  }

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

  /// Executes retrieval through [queryHandler] or [clientFactory] when
  /// provided.
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
    if (handler != null) {
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

    final VertexAiRagClientFactory? factory = clientFactory;
    if (factory == null) {
      return 'No matching result found with the config: $vertexRagStore';
    }

    final (String? project, String? location) = projectAndLocation();
    final Zone currentZone = Zone.current;
    Map<(String?, String?), VertexAiRagClient>? clients =
        _apiClientsPerZone[currentZone];
    if (clients == null) {
      clients = <(String?, String?), VertexAiRagClient>{};
      _apiClientsPerZone[currentZone] = clients;
    }
    final (String?, String?) cacheKey = (project, location);
    VertexAiRagClient? client = clients[cacheKey];
    if (client == null) {
      client = factory(project: project, location: location);
      clients[cacheKey] = client;
    }

    final VertexAiRagStore store = _retrievalStore();
    final VertexAiRagRetrievalResponse response = await client.retrievalQuery(
      text: query.trim(),
      ragResources: store.ragResources
          ?.map((VertexAiRagResource r) => VertexRagStoreRagResource(ragCorpus: r.path))
          .toList(growable: false),
      ragCorpora: store.ragCorpora,
      similarityTopK: vertexRagStore.similarityTopK,
      vectorDistanceThreshold: store.vectorDistanceThreshold,
    );
    if (response.contexts.isEmpty) {
      return 'No matching result found with the config: $vertexRagStore';
    }
    return response.contexts
        .map((VertexAiRagContext context) => context.text)
        .toList(growable: false);
  }
}

String? _nonEmptyOrNull(String? value) {
  if (value == null || value.isEmpty) {
    return null;
  }
  return value;
}
