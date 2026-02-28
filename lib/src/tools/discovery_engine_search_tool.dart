import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/llm_request.dart';
import '_google_access_token.dart';
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

class DiscoveryEngineSearchHttpRequest {
  DiscoveryEngineSearchHttpRequest({
    required this.method,
    required this.uri,
    Map<String, String>? headers,
    List<int>? bodyBytes,
  }) : headers = headers == null
           ? <String, String>{}
           : Map<String, String>.from(headers),
       bodyBytes = bodyBytes == null
           ? const <int>[]
           : List<int>.from(bodyBytes);

  final String method;
  final Uri uri;
  final Map<String, String> headers;
  final List<int> bodyBytes;
}

class DiscoveryEngineSearchHttpResponse {
  DiscoveryEngineSearchHttpResponse({
    required this.statusCode,
    Map<String, String>? headers,
    List<int>? bodyBytes,
  }) : headers = headers == null
           ? <String, String>{}
           : Map<String, String>.from(headers),
       bodyBytes = bodyBytes == null
           ? const <int>[]
           : List<int>.from(bodyBytes);

  final int statusCode;
  final Map<String, String> headers;
  final List<int> bodyBytes;
}

class DiscoveryEngineSearchApiException implements Exception {
  DiscoveryEngineSearchApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

typedef DiscoveryEngineSearchHandler =
    FutureOr<List<DiscoveryEngineSearchResult>> Function(
      DiscoveryEngineSearchRequest request,
    );
typedef DiscoveryEngineSearchHttpRequestProvider =
    Future<DiscoveryEngineSearchHttpResponse> Function(
      DiscoveryEngineSearchHttpRequest request,
    );
typedef DiscoveryEngineSearchAccessTokenProvider = Future<String> Function();

class DiscoveryEngineSearchTool extends FunctionTool {
  DiscoveryEngineSearchTool({
    this.dataStoreId,
    this.dataStoreSpecs,
    this.searchEngineId,
    this.filter,
    this.maxResults,
    this.searchHandler,
    DiscoveryEngineSearchHttpRequestProvider? httpRequestProvider,
    DiscoveryEngineSearchAccessTokenProvider? accessTokenProvider,
    String apiBaseUrl = _defaultDiscoveryEngineApiBaseUrl,
  }) : _servingConfig =
           '${dataStoreId ?? searchEngineId}/servingConfigs/default_config',
       _httpRequestProvider =
           httpRequestProvider ?? _defaultDiscoveryEngineHttpRequestProvider,
       _accessTokenProvider =
           accessTokenProvider ?? _defaultDiscoveryEngineAccessTokenProvider,
       _apiBaseUrl = apiBaseUrl,
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
  final DiscoveryEngineSearchHttpRequestProvider _httpRequestProvider;
  final DiscoveryEngineSearchAccessTokenProvider _accessTokenProvider;
  final String _apiBaseUrl;

  static const String _defaultDiscoveryEngineApiBaseUrl =
      'https://discoveryengine.googleapis.com/v1beta';

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
    if (rawQuery is! String) {
      throw ArgumentError('query is required for discovery_engine_search.');
    }
    return discoveryEngineSearch(query: rawQuery);
  }

  Future<Map<String, Object?>> discoveryEngineSearch({
    required String query,
  }) async {
    final DiscoveryEngineSearchRequest request = DiscoveryEngineSearchRequest(
      servingConfig: _servingConfig,
      query: query,
      dataStoreSpecs: dataStoreSpecs,
      filter: filter,
      maxResults: maxResults,
    );

    final DiscoveryEngineSearchHandler? handler = searchHandler;
    if (handler != null) {
      try {
        final List<DiscoveryEngineSearchResult> results = await handler(
          request,
        );
        return <String, Object?>{
          'status': 'success',
          'results': results.map((e) => e.toJson()).toList(),
        };
      } catch (error) {
        return <String, Object?>{
          'status': 'error',
          'error_message': '$error',
        };
      }
    }

    try {
      final List<DiscoveryEngineSearchResult> results = await _searchWithApi(
        request,
      );
      return <String, Object?>{
        'status': 'success',
        'results': results.map((DiscoveryEngineSearchResult e) => e.toJson())
            .toList(growable: false),
      };
    } on DiscoveryEngineSearchApiException catch (error) {
      return <String, Object?>{'status': 'error', 'error_message': '$error'};
    }
  }

  Future<List<DiscoveryEngineSearchResult>> _searchWithApi(
    DiscoveryEngineSearchRequest request,
  ) async {
    final String accessToken;
    try {
      accessToken = await _accessTokenProvider();
    } catch (error) {
      throw DiscoveryEngineSearchApiException('$error');
    }
    if (accessToken.trim().isEmpty) {
      throw DiscoveryEngineSearchApiException(
        'Failed to resolve Google access token for Discovery Engine search.',
      );
    }

    final Uri uri = Uri.parse(_apiBaseUrl).resolve(
      '${request.servingConfig}:search',
    );
    final Map<String, Object?> body = <String, Object?>{
      'query': request.query,
      'contentSearchSpec': <String, Object?>{
        'searchResultMode': 'CHUNKS',
        'chunkSpec': <String, Object?>{
          'numPreviousChunks': 0,
          'numNextChunks': 0,
        },
      },
      if (request.dataStoreSpecs != null)
        'dataStoreSpecs': request.dataStoreSpecs!
            .map((VertexAiSearchDataStoreSpec item) => item.toJson())
            .toList(growable: false),
      if (request.filter != null && request.filter!.isNotEmpty)
        'filter': request.filter,
      if (request.maxResults != null && request.maxResults! > 0)
        'pageSize': request.maxResults,
    };

    final DiscoveryEngineSearchHttpResponse response;
    try {
      response = await _httpRequestProvider(
        DiscoveryEngineSearchHttpRequest(
          method: 'POST',
          uri: uri,
          headers: <String, String>{
            'Authorization': 'Bearer $accessToken',
            'Content-Type': 'application/json',
          },
          bodyBytes: utf8.encode(jsonEncode(body)),
        ),
      );
    } catch (error) {
      throw DiscoveryEngineSearchApiException(
        'Discovery Engine API request failed: $error',
      );
    }

    final String responseText = utf8.decode(response.bodyBytes);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw DiscoveryEngineSearchApiException(
        'Discovery Engine API returned ${response.statusCode}: $responseText',
      );
    }

    final Object? decoded = jsonDecode(responseText);
    if (decoded is! Map) {
      throw DiscoveryEngineSearchApiException(
        'Discovery Engine API returned malformed response.',
      );
    }
    final Map<String, Object?> map = decoded.map(
      (Object? key, Object? value) => MapEntry('$key', value),
    );

    final List<DiscoveryEngineSearchResult> results =
        <DiscoveryEngineSearchResult>[];
    final Object? rawResults = map['results'];
    if (rawResults is! List) {
      return results;
    }
    for (final Object? rawItem in rawResults) {
      if (rawItem is! Map) {
        continue;
      }
      final Map<String, Object?> item = rawItem.map(
        (Object? key, Object? value) => MapEntry('$key', value),
      );
      final Object? chunkRaw = item['chunk'];
      if (chunkRaw is! Map) {
        continue;
      }
      final Map<String, Object?> chunk = chunkRaw.map(
        (Object? key, Object? value) => MapEntry('$key', value),
      );
      final Map<String, Object?> metadata =
          chunk['documentMetadata'] is Map
          ? (chunk['documentMetadata'] as Map).map(
              (Object? key, Object? value) => MapEntry('$key', value),
            )
          : <String, Object?>{};
      String title = '${metadata['title'] ?? ''}';
      String uriValue = '${metadata['uri'] ?? ''}';
      final Object? structDataRaw = metadata['structData'];
      if (structDataRaw is Map && structDataRaw.containsKey('uri')) {
        final Object? structUri = structDataRaw['uri'];
        if (structUri != null && '$structUri'.isNotEmpty) {
          uriValue = '$structUri';
        }
      }

      results.add(
        DiscoveryEngineSearchResult(
          title: title,
          url: uriValue,
          content: '${chunk['content'] ?? ''}',
        ),
      );
    }

    return results;
  }
}

Future<DiscoveryEngineSearchHttpResponse>
_defaultDiscoveryEngineHttpRequestProvider(
  DiscoveryEngineSearchHttpRequest request,
) async {
  final HttpClient client = HttpClient();
  try {
    final HttpClientRequest httpRequest = await client.openUrl(
      request.method,
      request.uri,
    );
    request.headers.forEach(httpRequest.headers.set);
    if (request.bodyBytes.isNotEmpty) {
      httpRequest.add(request.bodyBytes);
    }
    final HttpClientResponse response = await httpRequest.close();
    final List<int> bodyBytes = await response.fold<List<int>>(
      <int>[],
      (List<int> data, List<int> chunk) {
        data.addAll(chunk);
        return data;
      },
    );
    final Map<String, String> headers = <String, String>{};
    response.headers.forEach((String name, List<String> values) {
      headers[name] = values.join(', ');
    });
    return DiscoveryEngineSearchHttpResponse(
      statusCode: response.statusCode,
      headers: headers,
      bodyBytes: bodyBytes,
    );
  } finally {
    client.close(force: true);
  }
}

Future<String> _defaultDiscoveryEngineAccessTokenProvider() {
  return resolveDefaultGoogleAccessToken(
    scopes: const <String>['https://www.googleapis.com/auth/cloud-platform'],
  );
}
