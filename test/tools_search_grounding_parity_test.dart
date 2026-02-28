import 'dart:convert';

import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

Context _newToolContext() {
  final InvocationContext invocationContext = InvocationContext(
    sessionService: InMemorySessionService(),
    invocationId: 'inv_search_grounding',
    agent: LlmAgent(name: 'root', instruction: 'root'),
    session: Session(
      id: 's_search_grounding',
      appName: 'app',
      userId: 'u1',
      state: <String, Object?>{},
    ),
  );
  return Context(invocationContext);
}

void main() {
  group('search/grounding tools parity', () {
    test(
      'EnterpriseWebSearchTool appends enterprise grounding label',
      () async {
        final EnterpriseWebSearchTool tool = EnterpriseWebSearchTool();
        final LlmRequest request = LlmRequest(model: 'gemini-2.5-flash');

        await tool.processLlmRequest(
          toolContext: _newToolContext(),
          llmRequest: request,
        );

        expect(
          request.config.labels['adk_enterprise_web_search_tool'],
          'enterprise_web_search',
        );
        expect(request.config.tools, isNotNull);
        expect(
          request.config.tools!.last.enterpriseWebSearch,
          isA<Map<String, Object?>>(),
        );
      },
    );

    test('EnterpriseWebSearchTool rejects non-Gemini model', () async {
      final EnterpriseWebSearchTool tool = EnterpriseWebSearchTool();
      final LlmRequest request = LlmRequest(model: 'gpt-4.1');

      await expectLater(
        () => tool.processLlmRequest(
          toolContext: _newToolContext(),
          llmRequest: request,
        ),
        throwsArgumentError,
      );
    });

    test(
      'EnterpriseWebSearchTool rejects Gemini 1.x multi-tool combination',
      () async {
        final EnterpriseWebSearchTool tool = EnterpriseWebSearchTool();
        final LlmRequest request = LlmRequest(
          model: 'gemini-1.5-pro',
          config: GenerateContentConfig(
            tools: <ToolDeclaration>[
              ToolDeclaration(
                functionDeclarations: <FunctionDeclaration>[
                  FunctionDeclaration(name: 'another_tool'),
                ],
              ),
            ],
          ),
        );

        await expectLater(
          () => tool.processLlmRequest(
            toolContext: _newToolContext(),
            llmRequest: request,
          ),
          throwsArgumentError,
        );
      },
    );

    test('GoogleMapsGroundingTool blocks Gemini 1.x', () async {
      final GoogleMapsGroundingTool tool = GoogleMapsGroundingTool();
      final LlmRequest request = LlmRequest(model: 'gemini-1.5-flash');

      await expectLater(
        () => tool.processLlmRequest(
          toolContext: _newToolContext(),
          llmRequest: request,
        ),
        throwsArgumentError,
      );
    });

    test('GoogleMapsGroundingTool appends maps grounding label', () async {
      final GoogleMapsGroundingTool tool = GoogleMapsGroundingTool();
      final LlmRequest request = LlmRequest(model: 'gemini-2.0-flash');

      await tool.processLlmRequest(
        toolContext: _newToolContext(),
        llmRequest: request,
      );

      expect(
        request.config.labels['adk_google_maps_grounding_tool'],
        'google_maps',
      );
      expect(request.config.tools, isNotNull);
      expect(
        request.config.tools!.last.googleMaps,
        isA<Map<String, Object?>>(),
      );
    });

    test('VertexAiSearchTool validates data store / engine exclusivity', () {
      expect(() => VertexAiSearchTool(), throwsArgumentError);
      expect(
        () => VertexAiSearchTool(
          dataStoreId: 'projects/p/locations/l/collections/c/dataStores/d',
          searchEngineId: 'projects/p/locations/l/collections/c/engines/e',
        ),
        throwsArgumentError,
      );
      expect(
        () => VertexAiSearchTool(
          dataStoreId: 'projects/p/locations/l/collections/c/dataStores/d',
          dataStoreSpecs: <VertexAiSearchDataStoreSpec>[
            VertexAiSearchDataStoreSpec(
              dataStore: 'projects/p/.../dataStores/x',
            ),
          ],
        ),
        throwsArgumentError,
      );
    });

    test('VertexAiSearchTool appends labels and serialized config', () async {
      final VertexAiSearchTool tool = VertexAiSearchTool(
        searchEngineId: 'projects/p/locations/l/collections/c/engines/e',
        dataStoreSpecs: <VertexAiSearchDataStoreSpec>[
          VertexAiSearchDataStoreSpec(
            dataStore: 'projects/p/.../dataStores/d1',
          ),
        ],
        filter: 'category = "docs"',
        maxResults: 5,
      );
      final LlmRequest request = LlmRequest(model: 'gemini-2.5-pro');

      await tool.processLlmRequest(
        toolContext: _newToolContext(),
        llmRequest: request,
      );

      expect(
        request.config.labels['adk_vertex_ai_search_tool'],
        'vertex_ai_search',
      );
      final String? encoded =
          request.config.labels['adk_vertex_ai_search_config'];
      expect(encoded, isNotNull);
      final Map<String, Object?> json = Map<String, Object?>.from(
        jsonDecode(encoded!) as Map,
      );
      expect(json['engine'], 'projects/p/locations/l/collections/c/engines/e');
      expect(json['filter'], 'category = "docs"');
      expect(json['max_results'], 5);

      expect(request.config.tools, isNotNull);
      final ToolDeclaration retrievalTool = request.config.tools!.last;
      final Map<String, Object?> retrieval = Map<String, Object?>.from(
        retrievalTool.retrieval! as Map,
      );
      final Map<String, Object?> vertexAiSearch = Map<String, Object?>.from(
        retrieval['vertexAiSearch'] as Map,
      );
      expect(
        vertexAiSearch['engine'],
        'projects/p/locations/l/collections/c/engines/e',
      );
      expect(vertexAiSearch['filter'], 'category = "docs"');
      expect(vertexAiSearch['max_results'], 5);
    });

    test(
      'VertexAiSearchTool enforces Gemini 1.x multi-tool limit by default',
      () async {
        final VertexAiSearchTool tool = VertexAiSearchTool(
          dataStoreId: 'projects/p/locations/l/collections/c/dataStores/d',
        );
        final LlmRequest request = LlmRequest(
          model: 'gemini-1.5-pro',
          config: GenerateContentConfig(
            tools: <ToolDeclaration>[
              ToolDeclaration(
                functionDeclarations: <FunctionDeclaration>[
                  FunctionDeclaration(name: 'another_tool'),
                ],
              ),
            ],
          ),
        );

        await expectLater(
          () => tool.processLlmRequest(
            toolContext: _newToolContext(),
            llmRequest: request,
          ),
          throwsArgumentError,
        );
      },
    );

    test(
      'VertexAiSearchTool bypasses Gemini 1.x multi-tool limit when enabled',
      () async {
        final VertexAiSearchTool tool = VertexAiSearchTool(
          dataStoreId: 'projects/p/locations/l/collections/c/dataStores/d',
          bypassMultiToolsLimit: true,
        );
        final LlmRequest request = LlmRequest(
          model: 'gemini-1.5-pro',
          config: GenerateContentConfig(
            tools: <ToolDeclaration>[
              ToolDeclaration(
                functionDeclarations: <FunctionDeclaration>[
                  FunctionDeclaration(name: 'another_tool'),
                ],
              ),
            ],
          ),
        );

        await tool.processLlmRequest(
          toolContext: _newToolContext(),
          llmRequest: request,
        );

        expect(
          request.config.labels['adk_vertex_ai_search_tool'],
          'vertex_ai_search',
        );
      },
    );

    test(
      'LlmAgent wraps VertexAiSearchTool into DiscoveryEngineSearchTool for multi-tool bypass',
      () async {
        final LlmAgent agent = LlmAgent(
          name: 'multi_vertex_search',
          model: 'gemini-2.5-flash',
          instruction: 'search',
          tools: <Object>[
            VertexAiSearchTool(
              dataStoreId: 'projects/p/locations/l/collections/c/dataStores/d',
              bypassMultiToolsLimit: true,
            ),
            FunctionTool(name: 'echo', func: ({required String text}) => text),
          ],
        );

        final List<BaseTool> tools = await agent.canonicalTools();
        expect(
          tools.any((BaseTool tool) => tool is DiscoveryEngineSearchTool),
          isTrue,
        );
        expect(
          tools.any((BaseTool tool) => tool is VertexAiSearchTool),
          isFalse,
        );
      },
    );

    test('DiscoveryEngineSearchTool validates configuration invariants', () {
      expect(() => DiscoveryEngineSearchTool(), throwsArgumentError);
      expect(
        () => DiscoveryEngineSearchTool(
          dataStoreId: 'projects/p/locations/l/collections/c/dataStores/d',
          searchEngineId: 'projects/p/locations/l/collections/c/engines/e',
        ),
        throwsArgumentError,
      );
      expect(
        () => DiscoveryEngineSearchTool(
          dataStoreId: 'projects/p/locations/l/collections/c/dataStores/d',
          dataStoreSpecs: <VertexAiSearchDataStoreSpec>[
            VertexAiSearchDataStoreSpec(
              dataStore: 'projects/p/.../dataStores/x',
            ),
          ],
        ),
        throwsArgumentError,
      );
    });

    test(
      'DiscoveryEngineSearchTool executes injected handler and formats output',
      () async {
        late DiscoveryEngineSearchRequest capturedRequest;
        final DiscoveryEngineSearchTool tool = DiscoveryEngineSearchTool(
          dataStoreId: 'projects/p/locations/l/collections/c/dataStores/d',
          filter: 'lang = "en"',
          maxResults: 3,
          searchHandler: (DiscoveryEngineSearchRequest request) async {
            capturedRequest = request;
            return <DiscoveryEngineSearchResult>[
              DiscoveryEngineSearchResult(
                title: 'Doc 1',
                url: 'https://example.com/doc1',
                content: 'first',
              ),
            ];
          },
        );

        final Object? result = await tool.run(
          args: <String, dynamic>{'query': 'dart'},
          toolContext: _newToolContext(),
        );

        expect(capturedRequest.query, 'dart');
        expect(
          capturedRequest.servingConfig,
          'projects/p/locations/l/collections/c/dataStores/d/servingConfigs/default_config',
        );
        expect(capturedRequest.filter, 'lang = "en"');
        expect(capturedRequest.maxResults, 3);

        final Map<String, Object?> payload = Map<String, Object?>.from(
          result! as Map,
        );
        expect(payload['status'], 'success');
        final List<Object?> rows = List<Object?>.from(
          payload['results'] as List,
        );
        expect(rows, hasLength(1));
        final Map<String, Object?> first = Map<String, Object?>.from(
          rows.first! as Map,
        );
        expect(first['title'], 'Doc 1');
        expect(first['url'], 'https://example.com/doc1');
        expect(first['content'], 'first');
      },
    );

    test('DiscoveryEngineSearchTool reports handler errors', () async {
      final DiscoveryEngineSearchTool tool = DiscoveryEngineSearchTool(
        dataStoreId: 'projects/p/locations/l/collections/c/dataStores/d',
        searchHandler: (DiscoveryEngineSearchRequest _) {
          throw StateError('upstream unavailable');
        },
      );

      final Object? result = await tool.run(
        args: <String, dynamic>{'query': 'dart'},
        toolContext: _newToolContext(),
      );
      final Map<String, Object?> payload = Map<String, Object?>.from(
        result! as Map,
      );
      expect(payload['status'], 'error');
      expect(payload['error_message'], contains('upstream unavailable'));
    });

    test('DiscoveryEngineSearchTool returns error without handler', () async {
      final DiscoveryEngineSearchTool tool = DiscoveryEngineSearchTool(
        dataStoreId: 'projects/p/locations/l/collections/c/dataStores/d',
        accessTokenProvider: () async =>
            throw StateError('token resolution failed'),
      );

      final Object? result = await tool.run(
        args: <String, dynamic>{'query': 'dart'},
        toolContext: _newToolContext(),
      );
      final Map<String, Object?> payload = Map<String, Object?>.from(
        result! as Map,
      );
      expect(payload['status'], 'error');
      expect(
        payload['error_message'],
        contains('token resolution failed'),
      );
    });

    test(
      'DiscoveryEngineSearchTool default API path sends chunk search request and normalizes response',
      () async {
        late DiscoveryEngineSearchHttpRequest capturedRequest;
        final DiscoveryEngineSearchTool tool = DiscoveryEngineSearchTool(
          dataStoreId: 'projects/p/locations/l/collections/c/dataStores/d',
          filter: 'lang = "en"',
          maxResults: 2,
          accessTokenProvider: () async => 'token-1',
          httpRequestProvider: (
            DiscoveryEngineSearchHttpRequest request,
          ) async {
            capturedRequest = request;
            final Map<String, Object?> response = <String, Object?>{
              'results': <Object?>[
                <String, Object?>{
                  'chunk': <String, Object?>{
                    'content': 'chunk-content-1',
                    'documentMetadata': <String, Object?>{
                      'title': 'Doc 1',
                      'uri': 'https://fallback.example/doc1',
                      'structData': <String, Object?>{
                        'uri': 'https://preferred.example/doc1',
                      },
                    },
                  },
                },
                <String, Object?>{
                  'chunk': <String, Object?>{
                    'content': 'chunk-content-2',
                    'documentMetadata': <String, Object?>{
                      'title': 'Doc 2',
                      'uri': 'https://example/doc2',
                    },
                  },
                },
              ],
            };
            return DiscoveryEngineSearchHttpResponse(
              statusCode: 200,
              bodyBytes: utf8.encode(jsonEncode(response)),
            );
          },
        );

        final Object? result = await tool.run(
          args: <String, dynamic>{'query': 'raw query'},
          toolContext: _newToolContext(),
        );

        expect(capturedRequest.method, 'POST');
        expect(capturedRequest.uri.toString(), contains(':search'));
        expect(capturedRequest.headers['Authorization'], 'Bearer token-1');
        final Map<String, Object?> requestBody = (jsonDecode(
          utf8.decode(capturedRequest.bodyBytes),
        ) as Map).cast<String, Object?>();
        expect(requestBody['query'], 'raw query');
        expect(
          ((requestBody['contentSearchSpec'] as Map)['searchResultMode']),
          'CHUNKS',
        );
        expect(requestBody['filter'], 'lang = "en"');
        expect(requestBody['pageSize'], 2);

        final Map<String, Object?> payload = Map<String, Object?>.from(
          result! as Map,
        );
        expect(payload['status'], 'success');
        final List<Object?> rows = List<Object?>.from(payload['results'] as List);
        expect(rows, hasLength(2));
        final Map<String, Object?> first = Map<String, Object?>.from(
          rows.first! as Map,
        );
        expect(first['title'], 'Doc 1');
        expect(first['url'], 'https://preferred.example/doc1');
        expect(first['content'], 'chunk-content-1');
      },
    );
  });
}
