import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

Context _newToolContext({String? functionCallId, Map<String, Object?>? state}) {
  final InvocationContext invocationContext = InvocationContext(
    sessionService: InMemorySessionService(),
    invocationId: 'inv_data_agent',
    agent: LlmAgent(name: 'root', instruction: 'root'),
    session: Session(
      id: 's_data_agent',
      appName: 'app',
      userId: 'u1',
      state: state ?? <String, Object?>{},
    ),
  );
  return Context(invocationContext, functionCallId: functionCallId);
}

void main() {
  group('data agent config parity', () {
    test('defaults and enforces extra-field rejection', () {
      final DataAgentToolConfig config = DataAgentToolConfig();
      expect(config.maxQueryResultRows, 50);

      expect(
        () =>
            DataAgentToolConfig.fromJson(<String, Object?>{'unexpected': true}),
        throwsArgumentError,
      );
      expect(
        () => DataAgentToolConfig.fromJson(<String, Object?>{
          'max_query_result_rows': 0,
        }),
        throwsArgumentError,
      );
    });

    test('parses snake_case and camelCase payloads', () {
      expect(
        DataAgentToolConfig.fromJson(<String, Object?>{
          'max_query_result_rows': 7,
        }).maxQueryResultRows,
        7,
      );
      expect(
        DataAgentToolConfig.fromJson(<String, Object?>{
          'maxQueryResultRows': 3,
        }).maxQueryResultRows,
        3,
      );
    });
  });

  group('data agent tool parity', () {
    test('list_accessible_data_agents returns SUCCESS payload', () async {
      final Map<String, Object?> result = await listAccessibleDataAgents(
        projectId: 'my-project',
        credentials: GoogleOAuthCredential(accessToken: 'token-1'),
        httpGet: ({required Uri uri, required Map<String, String> headers}) async {
          expect(
            uri.path,
            '/v1beta/projects/my-project/locations/global/dataAgents:listAccessible',
          );
          expect(headers['authorization'], 'Bearer token-1');
          return <String, Object?>{
            'dataAgents': <Object?>[
              <String, Object?>{
                'name': 'projects/p/locations/global/dataAgents/a1',
              },
            ],
          };
        },
      );

      expect(result['status'], 'SUCCESS');
      expect((result['response'] as List).length, 1);
    });

    test(
      'list_accessible_data_agents returns ERROR on missing token',
      () async {
        final Map<String, Object?> result = await listAccessibleDataAgents(
          projectId: 'my-project',
          credentials: <String, Object?>{},
        );
        expect(result['status'], 'ERROR');
        expect('${result['error_details']}', contains('valid access token'));
      },
    );

    test('get_data_agent_info returns SUCCESS payload', () async {
      final Map<String, Object?> result = await getDataAgentInfo(
        dataAgentName: 'projects/p/locations/global/dataAgents/a1',
        credentials: GoogleOAuthCredential(accessToken: 'token-2'),
        httpGet:
            ({required Uri uri, required Map<String, String> headers}) async {
              expect(
                uri.path,
                '/v1beta/projects/p/locations/global/dataAgents/a1',
              );
              expect(headers['authorization'], 'Bearer token-2');
              return <String, Object?>{'name': 'projects/p/.../a1'};
            },
      );
      expect(result['status'], 'SUCCESS');
      expect((result['response'] as Map)['name'], 'projects/p/.../a1');
    });

    test('ask_data_agent formats schema/data/text/error stream responses', () async {
      final Context context = _newToolContext();
      final Map<String, Object?> result = await askDataAgent(
        dataAgentName: 'projects/p/locations/global/dataAgents/a1',
        query: 'Who spent the most?',
        credentials: GoogleOAuthCredential(accessToken: 'token-3'),
        settings: DataAgentToolConfig(maxQueryResultRows: 1),
        toolContext: context,
        httpGet:
            ({required Uri uri, required Map<String, String> headers}) async {
              expect(
                uri.path,
                '/v1beta/projects/p/locations/global/dataAgents/a1',
              );
              expect(headers['x-goog-api-client'], 'GOOGLE_ADK');
              return <String, Object?>{
                'name': 'projects/p/locations/global/dataAgents/a1',
              };
            },
        streamPost:
            ({
              required Uri uri,
              required Map<String, Object?> payload,
              required Map<String, String> headers,
            }) async {
              expect(uri.path, '/v1beta/projects/p/locations/global:chat');
              expect(payload['clientIdEnum'], 'GOOGLE_ADK');
              expect(headers['authorization'], 'Bearer token-3');
              return <String>[
                '{"systemMessage":{"schema":{"query":{"question":"Who spent the most?"}}}}',
                '{"systemMessage":{"schema":{"result":{"datasources":[{"bigqueryTableReference":{"projectId":"p","datasetId":"d","tableId":"t"},"schema":{"fields":[{"name":"customer","type":"STRING","description":"Customer","mode":"NULLABLE"}]}}]}}}}',
                '{"systemMessage":{"data":{"query":{"name":"top_spender","question":"Top customer?"}}}}',
                '{"systemMessage":{"data":{"generatedSql":"SELECT 1"}}}',
                '{"systemMessage":{"data":{"result":{"schema":{"fields":[{"name":"customer"},{"name":"amount"}]},"data":[{"customer":"Jane","amount":10},{"customer":"John","amount":5}]}}}}',
                '{"systemMessage":{"text":{"parts":["The answer is ","Jane."]}}}',
                '{"error":{"code":403,"message":"denied"}}',
              ];
            },
      );

      expect(result['status'], 'SUCCESS');
      final List<Object?> messages = (result['response'] as List)
          .cast<Object?>();
      expect(messages, hasLength(7));
      expect((messages[0] as Map)['Question'], 'Who spent the most?');
      expect((messages[1] as Map).containsKey('Schema Resolved'), isTrue);
      expect(
        ((messages[4] as Map)['Data Retrieved'] as Map)['summary'],
        'Showing the first 1 of 2 total rows.',
      );
      expect((messages[5] as Map)['Answer'], 'The answer is Jane.');
      expect(((messages[6] as Map)['Error'] as Map)['Code'], 403);
    });

    test('ask_data_agent returns upstream info error unchanged', () async {
      final Map<String, Object?> result = await askDataAgent(
        dataAgentName: 'projects/p/locations/global/dataAgents/a1',
        query: 'hello',
        credentials: GoogleOAuthCredential(accessToken: 'token-4'),
        settings: DataAgentToolConfig(),
        toolContext: _newToolContext(),
        httpGet:
            ({required Uri uri, required Map<String, String> headers}) async {
              throw StateError('cannot fetch');
            },
        streamPost:
            ({
              required Uri uri,
              required Map<String, Object?> payload,
              required Map<String, String> headers,
            }) async {
              return <String>[];
            },
      );

      expect(result['status'], 'ERROR');
      expect('${result['error_details']}', contains('cannot fetch'));
    });
  });

  group('data agent toolset parity', () {
    test('toolset returns all tools and honors list filter', () async {
      final DataAgentToolset all = DataAgentToolset();
      final List<BaseTool> allTools = await all.getTools();
      expect(allTools.map((BaseTool tool) => tool.name).toSet(), <String>{
        'list_accessible_data_agents',
        'get_data_agent_info',
        'ask_data_agent',
      });

      final DataAgentToolset filtered = DataAgentToolset(
        toolFilter: <String>['ask_data_agent'],
      );
      final List<BaseTool> filteredTools = await filtered.getTools();
      expect(filteredTools, hasLength(1));
      expect(filteredTools.single.name, 'ask_data_agent');
    });

    test(
      'ask_data_agent tool runs through GoogleTool credentials/settings bridge',
      () async {
        final DataAgentToolset toolset = DataAgentToolset(
          credentialsConfig: DataAgentCredentialsConfig(
            externalAccessTokenKey: 'external_token',
          ),
          dataAgentToolConfig: DataAgentToolConfig(maxQueryResultRows: 1),
        );

        final BaseTool askTool = (await toolset.getTools()).singleWhere(
          (BaseTool tool) => tool.name == 'ask_data_agent',
        );
        final Context context = _newToolContext(
          state: <String, Object?>{'external_token': 'toolset-token'},
        );

        final Object? response = await askTool.run(
          args: <String, dynamic>{
            'dataAgentName': 'projects/p/locations/global/dataAgents/a1',
            'query': 'hello',
            'httpGet':
                ({
                  required Uri uri,
                  required Map<String, String> headers,
                }) async {
                  return <String, Object?>{
                    'name': 'projects/p/locations/global/dataAgents/a1',
                  };
                },
            'streamPost':
                ({
                  required Uri uri,
                  required Map<String, Object?> payload,
                  required Map<String, String> headers,
                }) async {
                  expect(headers['authorization'], 'Bearer toolset-token');
                  return <String>[
                    '{"systemMessage":{"text":{"parts":["ok"]}}}',
                  ];
                },
          },
          toolContext: context,
        );

        expect(response, isA<Map<String, Object?>>());
        final Map<String, Object?> payload = response! as Map<String, Object?>;
        expect(payload['status'], 'SUCCESS');
        expect(((payload['response'] as List).first as Map)['Answer'], 'ok');
      },
    );
  });
}
