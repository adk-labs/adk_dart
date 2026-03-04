/// Vertex AI Search built-in retrieval tool helpers.
library;

import 'dart:convert';

import '../models/llm_request.dart';
import '../utils/model_name_utils.dart';
import 'base_tool.dart';
import 'tool_context.dart';

/// One Vertex AI Search data store reference.
class VertexAiSearchDataStoreSpec {
  /// Creates a data store specification.
  VertexAiSearchDataStoreSpec({required this.dataStore});

  /// Fully qualified data store resource name.
  final String dataStore;

  /// Encodes this spec for retrieval configuration.
  Map<String, Object?> toJson() {
    return <String, Object?>{'data_store': dataStore};
  }
}

/// Retrieval configuration used by [VertexAiSearchTool].
class VertexAiSearchConfig {
  /// Creates a Vertex AI Search retrieval configuration.
  VertexAiSearchConfig({
    this.datastore,
    this.dataStoreSpecs,
    this.engine,
    this.filter,
    this.maxResults,
  });

  /// Optional single data store identifier.
  final String? datastore;

  /// Optional list of data store specs.
  final List<VertexAiSearchDataStoreSpec>? dataStoreSpecs;

  /// Optional search engine identifier.
  final String? engine;

  /// Optional filter expression.
  final String? filter;

  /// Optional maximum number of results.
  final int? maxResults;

  /// Encodes this configuration for retrieval declarations.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      if (datastore != null) 'datastore': datastore,
      if (dataStoreSpecs != null)
        'data_store_specs': dataStoreSpecs!.map((e) => e.toJson()).toList(),
      if (engine != null) 'engine': engine,
      if (filter != null) 'filter': filter,
      if (maxResults != null) 'max_results': maxResults,
    };
  }
}

/// Built-in retrieval tool wrapper for Vertex AI Search.
class VertexAiSearchTool extends BaseTool {
  /// Creates a Vertex AI Search tool configuration.
  VertexAiSearchTool({
    this.dataStoreId,
    this.dataStoreSpecs,
    this.searchEngineId,
    this.filter,
    this.maxResults,
    this.bypassMultiToolsLimit = false,
    bool Function()? modelIdCheckDisabledResolver,
  }) : _modelIdCheckDisabledResolver =
           modelIdCheckDisabledResolver ?? isGeminiModelIdCheckDisabled,
       super(name: 'vertex_ai_search', description: 'vertex_ai_search') {
    if ((dataStoreId == null && searchEngineId == null) ||
        (dataStoreId != null && searchEngineId != null)) {
      throw ArgumentError(
        'Either data_store_id or search_engine_id must be specified.',
      );
    }
    if (dataStoreSpecs != null && searchEngineId == null) {
      throw ArgumentError(
        'search_engine_id must be specified if data_store_specs is specified.',
      );
    }
  }

  /// Data store identifier used for retrieval requests.
  final String? dataStoreId;

  /// Explicit data store specs used with search engine mode.
  final List<VertexAiSearchDataStoreSpec>? dataStoreSpecs;

  /// Search engine identifier used for retrieval requests.
  final String? searchEngineId;

  /// Optional filter expression applied to retrieval.
  final String? filter;

  /// Maximum number of retrieval results.
  final int? maxResults;

  /// Whether Gemini 1.x multi-tool constraints are bypassed.
  final bool bypassMultiToolsLimit;
  final bool Function() _modelIdCheckDisabledResolver;

  /// Builds retrieval config to inject into model requests.
  VertexAiSearchConfig buildVertexAiSearchConfig(ToolContext toolContext) {
    return VertexAiSearchConfig(
      datastore: dataStoreId,
      dataStoreSpecs: dataStoreSpecs,
      engine: searchEngineId,
      filter: filter,
      maxResults: maxResults,
    );
  }

  @override
  /// Returns `null` because retrieval executes through model-side tooling.
  Future<Object?> run({
    required Map<String, dynamic> args,
    required ToolContext toolContext,
  }) async {
    return null;
  }

  @override
  /// Injects Vertex AI Search retrieval declarations into [llmRequest].
  Future<void> processLlmRequest({
    required ToolContext toolContext,
    required LlmRequest llmRequest,
  }) async {
    final bool modelCheckDisabled = _modelIdCheckDisabledResolver();
    final String? modelName = llmRequest.model;
    llmRequest.config.tools ??= <ToolDeclaration>[];

    if (isGeminiModel(modelName) || modelCheckDisabled) {
      if (!bypassMultiToolsLimit &&
          isGemini1Model(modelName) &&
          llmRequest.config.tools!.isNotEmpty) {
        throw ArgumentError(
          'Vertex AI search tool cannot be used with other tools in Gemini 1.x.',
        );
      }

      final VertexAiSearchConfig config = buildVertexAiSearchConfig(
        toolContext,
      );
      llmRequest.config.tools!.add(
        ToolDeclaration(
          retrieval: <String, Object?>{'vertexAiSearch': config.toJson()},
        ),
      );
      llmRequest.config.labels['adk_vertex_ai_search_tool'] =
          'vertex_ai_search';
      llmRequest.config.labels['adk_vertex_ai_search_config'] = jsonEncode(
        config.toJson(),
      );
      return;
    }

    throw ArgumentError(
      'Vertex AI search tool is not supported for model ${llmRequest.model}',
    );
  }
}
