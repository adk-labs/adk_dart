import 'dart:async';

import '../models/llm_request.dart';
import 'function_tool.dart';
import 'tool_context.dart';
import 'vertex_ai_search_tool.dart';

Object? _discoveryEngineSearchPlaceholder({required String query}) {
  return null;
}

class DiscoveryEngineSearchRequest {
  DiscoveryEngineSearchRequest({
    required this.servingConfig,
    required this.query,
    this.dataStoreSpecs,
    this.filter,
    this.maxResults,
  });

  final String servingConfig;
  final String query;
  final List<VertexAiSearchDataStoreSpec>? dataStoreSpecs;
  final String? filter;
  final int? maxResults;
}

class DiscoveryEngineSearchResult {
  DiscoveryEngineSearchResult({
    required this.title,
    required this.url,
    required this.content,
  });

  final String title;
  final String url;
  final String content;

  Map<String, Object?> toJson() {
    return <String, Object?>{'title': title, 'url': url, 'content': content};
  }
}

typedef DiscoveryEngineSearchHandler =
    FutureOr<List<DiscoveryEngineSearchResult>> Function(
      DiscoveryEngineSearchRequest request,
    );

class DiscoveryEngineSearchTool extends FunctionTool {
  DiscoveryEngineSearchTool({
    this.dataStoreId,
    this.dataStoreSpecs,
    this.searchEngineId,
    this.filter,
    this.maxResults,
    this.searchHandler,
  }) : _servingConfig =
           '${dataStoreId ?? searchEngineId}/servingConfigs/default_config',
       super(
         func: _discoveryEngineSearchPlaceholder,
         name: 'discovery_engine_search',
         description: 'discovery_engine_search',
       ) {
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
  final DiscoveryEngineSearchHandler? searchHandler;
  final String _servingConfig;

  @override
  FunctionDeclaration? getDeclaration() {
    final FunctionDeclaration? declaration = super.getDeclaration();
    if (declaration == null) {
      return null;
    }
    return declaration.copyWith(
      parameters: <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'query': <String, Object?>{'type': 'string'},
        },
        'required': <String>['query'],
      },
    );
  }

  @override
  Future<Object?> run({
    required Map<String, dynamic> args,
    required ToolContext toolContext,
  }) async {
    final Object? rawQuery = args['query'];
    if (rawQuery is! String || rawQuery.trim().isEmpty) {
      throw ArgumentError('query is required for discovery_engine_search.');
    }
    return discoveryEngineSearch(query: rawQuery.trim());
  }

  Future<Map<String, Object?>> discoveryEngineSearch({
    required String query,
  }) async {
    final DiscoveryEngineSearchHandler? handler = searchHandler;
    if (handler == null) {
      return <String, Object?>{
        'status': 'error',
        'error_message': 'Discovery Engine search handler is not configured.',
      };
    }

    final DiscoveryEngineSearchRequest request = DiscoveryEngineSearchRequest(
      servingConfig: _servingConfig,
      query: query,
      dataStoreSpecs: dataStoreSpecs,
      filter: filter,
      maxResults: maxResults,
    );

    try {
      final List<DiscoveryEngineSearchResult> results = await handler(request);
      return <String, Object?>{
        'status': 'success',
        'results': results.map((e) => e.toJson()).toList(),
      };
    } catch (error) {
      return <String, Object?>{'status': 'error', 'error_message': '$error'};
    }
  }
}
