import 'dart:convert';

import '../models/llm_request.dart';
import '../utils/model_name_utils.dart';
import 'base_tool.dart';
import 'tool_context.dart';

class VertexAiSearchDataStoreSpec {
  VertexAiSearchDataStoreSpec({required this.dataStore});

  final String dataStore;

  Map<String, Object?> toJson() {
    return <String, Object?>{'data_store': dataStore};
  }
}

class VertexAiSearchConfig {
  VertexAiSearchConfig({
    this.datastore,
    this.dataStoreSpecs,
    this.engine,
    this.filter,
    this.maxResults,
  });

  final String? datastore;
  final List<VertexAiSearchDataStoreSpec>? dataStoreSpecs;
  final String? engine;
  final String? filter;
  final int? maxResults;

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

class VertexAiSearchTool extends BaseTool {
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

  final String? dataStoreId;
  final List<VertexAiSearchDataStoreSpec>? dataStoreSpecs;
  final String? searchEngineId;
  final String? filter;
  final int? maxResults;
  final bool bypassMultiToolsLimit;
  final bool Function() _modelIdCheckDisabledResolver;

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
  Future<Object?> run({
    required Map<String, dynamic> args,
    required ToolContext toolContext,
  }) async {
    return null;
  }

  @override
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
