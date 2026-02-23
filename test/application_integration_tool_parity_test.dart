import 'dart:convert';

import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

class _FakeConnectionsClient extends ConnectionsClient {
  _FakeConnectionsClient({
    this.connectionDetails = const <String, Object?>{},
    this.entitySchema = const <String, Object?>{},
    this.entityOperationsResult = const <String>['LIST'],
    this.actionSchema = const <String, Object?>{},
  }) : super(
         project: 'p1',
         location: 'us-central1',
         connection: 'conn1',
         accessTokenProvider: ({String? serviceAccountJson}) async => 'token',
         requestExecutor:
             ({
               required Uri uri,
               required String method,
               required Map<String, String> headers,
               String? body,
             }) async => ApplicationIntegrationHttpResponse(
               statusCode: 200,
               body: '{}',
             ),
       );

  final Map<String, Object?> connectionDetails;
  final Map<String, Object?> entitySchema;
  final List<String> entityOperationsResult;
  final Map<String, Object?> actionSchema;

  int connectionDetailsCalls = 0;
  int entitySchemaCalls = 0;
  int actionSchemaCalls = 0;

  @override
  Future<Map<String, Object?>> getConnectionDetails() async {
    connectionDetailsCalls += 1;
    return Map<String, Object?>.from(connectionDetails);
  }

  @override
  Future<({Map<String, Object?> schema, List<String> operations})>
  getEntitySchemaAndOperations(String entity) async {
    entitySchemaCalls += 1;
    return (
      schema: Map<String, Object?>.from(entitySchema),
      operations: List<String>.from(entityOperationsResult),
    );
  }

  @override
  Future<Map<String, Object?>> getActionSchema(String action) async {
    actionSchemaCalls += 1;
    return Map<String, Object?>.from(actionSchema);
  }
}

class _FakeIntegrationClient extends IntegrationClient {
  _FakeIntegrationClient({
    this.integrationSpec = const <String, Object?>{},
    this.connectionSpec = const <String, Object?>{},
  }) : super(project: 'p1', location: 'us-central1');

  final Map<String, Object?> integrationSpec;
  final Map<String, Object?> connectionSpec;

  int integrationSpecCalls = 0;
  int connectionSpecCalls = 0;

  @override
  Future<Map<String, Object?>> getOpenApiSpecForIntegration() async {
    integrationSpecCalls += 1;
    return Map<String, Object?>.from(integrationSpec);
  }

  @override
  Future<Map<String, Object?>> getOpenApiSpecForConnection({
    String toolName = '',
    String toolInstructions = '',
  }) async {
    connectionSpecCalls += 1;
    return Map<String, Object?>.from(connectionSpec);
  }
}

Context _newToolContext({Map<String, Object?>? state}) {
  final InvocationContext invocationContext = InvocationContext(
    sessionService: InMemorySessionService(),
    invocationId: 'inv_app_integration',
    agent: LlmAgent(name: 'root', instruction: 'root'),
    session: Session(
      id: 's_app_integration',
      appName: 'app',
      userId: 'u1',
      state: state ?? <String, Object?>{},
    ),
  );
  return Context(invocationContext);
}

void main() {
  group('connections client parity', () {
    test('connector payload conversion handles nullable object and arrays', () {
      final ConnectionsClient client = ConnectionsClient(
        project: 'p1',
        location: 'us-central1',
        connection: 'conn1',
        accessTokenProvider: ({String? serviceAccountJson}) async => 'token',
      );

      final Map<String, Object?> converted = client.connectorPayload(
        <String, Object?>{
          'type': <String>['object', 'null'],
          'description': 'entity schema',
          'properties': <String, Object?>{
            'items': <String, Object?>{
              'type': 'array',
              'items': <String, Object?>{'type': 'string'},
            },
            'nested': <String, Object?>{
              'type': 'object',
              'properties': <String, Object?>{
                'id': <String, Object?>{'type': 'integer'},
              },
            },
          },
        },
      );

      expect(converted['nullable'], isTrue);
      expect(converted['type'], 'object');
      expect((converted['properties'] as Map)['nested'], isA<Map>());
    });

    test(
      'getConnectionDetails prefers tls service name when host exists',
      () async {
        final ConnectionsClient client = ConnectionsClient(
          project: 'p1',
          location: 'us-central1',
          connection: 'conn1',
          accessTokenProvider: ({String? serviceAccountJson}) async => 'token',
          requestExecutor:
              ({
                required Uri uri,
                required String method,
                required Map<String, String> headers,
                String? body,
              }) async {
                expect(method, 'GET');
                expect(
                  uri.toString(),
                  contains('/connections/conn1?view=BASIC'),
                );
                expect(headers['authorization'], 'Bearer token');
                return ApplicationIntegrationHttpResponse(
                  statusCode: 200,
                  body: jsonEncode(<String, Object?>{
                    'name':
                        'projects/p1/locations/us-central1/connections/conn1',
                    'serviceDirectory': 'svc-dir',
                    'tlsServiceDirectory': 'svc-dir-tls',
                    'host': '10.0.0.5',
                    'authOverrideEnabled': true,
                  }),
                );
              },
        );

        final Map<String, Object?> details = await client
            .getConnectionDetails();
        expect(details['serviceName'], 'svc-dir-tls');
        expect(details['host'], '10.0.0.5');
        expect(details['authOverrideEnabled'], isTrue);
      },
    );

    test('getEntitySchemaAndOperations polls operation until done', () async {
      int operationPollCount = 0;
      final ConnectionsClient client = ConnectionsClient(
        project: 'p1',
        location: 'us-central1',
        connection: 'conn1',
        accessTokenProvider: ({String? serviceAccountJson}) async => 'token',
        pollInterval: Duration.zero,
        sleeper: (Duration _) async {},
        requestExecutor:
            ({
              required Uri uri,
              required String method,
              required Map<String, String> headers,
              String? body,
            }) async {
              if (uri.path.endsWith('connectionSchemaMetadata:getEntityType')) {
                return ApplicationIntegrationHttpResponse(
                  statusCode: 200,
                  body: jsonEncode(<String, Object?>{
                    'name': 'operations/op-1',
                  }),
                );
              }

              operationPollCount += 1;
              if (operationPollCount == 1) {
                return ApplicationIntegrationHttpResponse(
                  statusCode: 200,
                  body: jsonEncode(<String, Object?>{'done': false}),
                );
              }

              return ApplicationIntegrationHttpResponse(
                statusCode: 200,
                body: jsonEncode(<String, Object?>{
                  'done': true,
                  'response': <String, Object?>{
                    'jsonSchema': <String, Object?>{'type': 'object'},
                    'operations': <String>['LIST', 'CREATE'],
                  },
                }),
              );
            },
      );

      final ({Map<String, Object?> schema, List<String> operations}) result =
          await client.getEntitySchemaAndOperations('Issues');

      expect(result.schema['type'], 'object');
      expect(result.operations, <String>['LIST', 'CREATE']);
      expect(operationPollCount, 2);
    });
  });

  group('integration client parity', () {
    test(
      'getOpenApiSpecForIntegration posts generateOpenApiSpec request',
      () async {
        final IntegrationClient client = IntegrationClient(
          project: 'p1',
          location: 'us-central1',
          integration:
              'projects/p1/locations/us-central1/integrations/sample-integration',
          triggers: <String>['api_trigger/sample'],
          accessTokenProvider: ({String? serviceAccountJson}) async => 'token',
          requestExecutor:
              ({
                required Uri uri,
                required String method,
                required Map<String, String> headers,
                String? body,
              }) async {
                expect(method, 'POST');
                expect(uri.toString(), contains(':generateOpenApiSpec'));
                expect(headers['authorization'], 'Bearer token');
                expect(headers['x-goog-user-project'], 'p1');

                final Map<String, Object?> payload = jsonDecode(body!);
                final List<Object?> triggerResources =
                    payload['apiTriggerResources'] as List<Object?>;
                expect(triggerResources.length, 1);

                return ApplicationIntegrationHttpResponse(
                  statusCode: 200,
                  body: jsonEncode(<String, Object?>{
                    'openApiSpec': jsonEncode(<String, Object?>{
                      'openapi': '3.0.1',
                      'info': <String, String>{'title': 'integration'},
                      'paths': <String, Object?>{},
                    }),
                  }),
                );
              },
        );

        final Map<String, Object?> spec = await client
            .getOpenApiSpecForIntegration();
        expect(spec['openapi'], '3.0.1');
        expect((spec['info'] as Map)['title'], 'integration');
      },
    );

    test(
      'getOpenApiSpecForConnection builds entity and action operations',
      () async {
        final _FakeConnectionsClient fakeConnections = _FakeConnectionsClient(
          entitySchema: <String, Object?>{
            'type': 'object',
            'properties': <String, Object?>{
              'id': <String, Object?>{'type': 'string'},
            },
          },
          entityOperationsResult: <String>['CREATE'],
          actionSchema: <String, Object?>{
            'inputSchema': <String, Object?>{'type': 'object'},
            'outputSchema': <String, Object?>{'type': 'object'},
            'description': 'run custom query',
            'displayName': 'Run Action',
          },
        );

        final IntegrationClient client = IntegrationClient(
          project: 'p1',
          location: 'us-central1',
          connection: 'conn1',
          entityOperations: <String, List<String>>{
            'Issues': <String>['LIST', 'GET'],
            'Tickets': <String>[],
          },
          actions: <String>['ExecuteCustomQuery', 'RunAction'],
          connectionsClient: fakeConnections,
        );

        final Map<String, Object?> spec = await client
            .getOpenApiSpecForConnection(
              toolName: 'connector_tool',
              toolInstructions: 'follow org policy',
            );

        final Map<String, Object?> paths =
            spec['paths'] as Map<String, Object?>;
        expect(
          paths.keys.any((String key) => key.contains('#list_Issues')),
          isTrue,
        );
        expect(
          paths.keys.any((String key) => key.contains('#get_Issues')),
          isTrue,
        );
        expect(
          paths.keys.any((String key) => key.contains('#create_Tickets')),
          isTrue,
        );
        expect(
          paths.keys.any((String key) => key.contains('#ExecuteCustomQuery')),
          isTrue,
        );

        final Map<String, Object?> schemas =
            ((spec['components'] as Map)['schemas'] as Map<String, Object?>);
        expect(schemas.containsKey('RunAction_Request'), isTrue);
        expect(schemas.containsKey('connectorOutputPayload_RunAction'), isTrue);
        expect(fakeConnections.entitySchemaCalls, 2);
        expect(fakeConnections.actionSchemaCalls, 2);
      },
    );
  });

  group('integration connector tool parity', () {
    test(
      'declaration excludes connector-only fields and run injects context',
      () async {
        final Map<String, Object?> openApiSpec = <String, Object?>{
          'openapi': '3.0.1',
          'info': <String, Object?>{'title': 'connector'},
          'servers': <Map<String, String>>[
            <String, String>{'url': 'https://integrations.googleapis.com'},
          ],
          'paths': <String, Object?>{
            '/execute': <String, Object?>{
              'post': <String, Object?>{
                'operationId': 'executeConnection',
                'x-operation': 'LIST_ENTITIES',
                'x-entity': 'Issues',
                'requestBody': <String, Object?>{
                  'content': <String, Object?>{
                    'application/json': <String, Object?>{
                      'schema': <String, Object?>{
                        'type': 'object',
                        'required': <String>[
                          'connection_name',
                          'service_name',
                          'host',
                          'entity',
                          'operation',
                          'action',
                          'query',
                          'page_size',
                        ],
                        'properties': <String, Object?>{
                          'connection_name': <String, Object?>{
                            'type': 'string',
                          },
                          'service_name': <String, Object?>{'type': 'string'},
                          'host': <String, Object?>{'type': 'string'},
                          'entity': <String, Object?>{'type': 'string'},
                          'operation': <String, Object?>{'type': 'string'},
                          'action': <String, Object?>{'type': 'string'},
                          'dynamic_auth_config': <String, Object?>{
                            'type': 'object',
                          },
                          'query': <String, Object?>{'type': 'string'},
                          'page_size': <String, Object?>{'type': 'integer'},
                        },
                      },
                    },
                  },
                },
                'responses': <String, Object?>{
                  '200': <String, Object?>{
                    'description': 'ok',
                    'content': <String, Object?>{
                      'application/json': <String, Object?>{
                        'schema': <String, Object?>{'type': 'object'},
                      },
                    },
                  },
                },
              },
            },
          },
        };

        final ParsedOperation parsedOperation = OpenApiSpecParser()
            .parse(openApiSpec)
            .single;
        Map<String, Object?>? capturedJsonBody;
        final RestApiTool restApiTool = RestApiTool.fromParsedOperation(
          parsedOperation,
          requestExecutor:
              ({required Map<String, Object?> requestParams}) async {
                capturedJsonBody = (requestParams['json'] as Map?)
                    ?.cast<String, Object?>();
                return RestApiResponse(
                  statusCode: 200,
                  jsonData: <String, Object?>{'status': 'ok'},
                );
              },
        );

        final IntegrationConnectorTool tool = IntegrationConnectorTool(
          name: restApiTool.name,
          description: restApiTool.description,
          connectionName: 'projects/p1/locations/us-central1/connections/conn1',
          connectionHost: '10.0.0.1',
          connectionServiceName: 'svc-name',
          entity: 'Issues',
          operation: 'LIST_ENTITIES',
          action: 'ExecuteCustomQuery',
          restApiTool: restApiTool,
          authScheme: SecurityScheme(
            type: AuthSchemeType.http,
            scheme: 'bearer',
            bearerFormat: 'JWT',
          ),
          authCredential: AuthCredential(
            authType: AuthCredentialType.http,
            http: HttpAuth(
              scheme: 'bearer',
              credentials: HttpCredentials(token: 'dynamic-token'),
            ),
          ),
        );

        final FunctionDeclaration declaration = tool.getDeclaration()!;
        final Map<String, Object?> properties =
            declaration.parameters['properties'] as Map<String, Object?>;
        final List<Object?> required =
            declaration.parameters['required'] as List<Object?>;

        expect(properties.containsKey('connection_name'), isFalse);
        expect(properties.containsKey('service_name'), isFalse);
        expect(required.contains('connection_name'), isFalse);
        expect(required.contains('page_size'), isFalse);

        final Object? result = await tool.run(
          args: <String, dynamic>{'query': 'select * from Issues'},
          toolContext: _newToolContext(),
        );

        expect(result, isA<Map<String, Object?>>());
        expect(capturedJsonBody, isNotNull);
        expect(
          capturedJsonBody!['connection_name'],
          'projects/p1/locations/us-central1/connections/conn1',
        );
        expect(capturedJsonBody!['entity'], 'Issues');
        final Map<String, Object?> dynamicAuth =
            capturedJsonBody!['dynamic_auth_config'] as Map<String, Object?>;
        expect(
          dynamicAuth['oauth2_auth_code_flow.access_token'],
          'dynamic-token',
        );
      },
    );
  });

  group('application integration toolset parity', () {
    const Map<String, Object?> integrationSpec = <String, Object?>{
      'openapi': '3.0.1',
      'info': <String, Object?>{'title': 'Integration Spec'},
      'servers': <Map<String, String>>[
        <String, String>{'url': 'https://integrations.googleapis.com'},
      ],
      'paths': <String, Object?>{
        '/ping': <String, Object?>{
          'post': <String, Object?>{
            'operationId': 'pingConnection',
            'description': 'Ping operation',
            'responses': <String, Object?>{
              '200': <String, Object?>{
                'description': 'ok',
                'content': <String, Object?>{
                  'application/json': <String, Object?>{
                    'schema': <String, Object?>{'type': 'object'},
                  },
                },
              },
            },
          },
        },
      },
    };

    const Map<String, Object?> connectorSpec = <String, Object?>{
      'openapi': '3.0.1',
      'info': <String, Object?>{'title': 'Connector Spec'},
      'servers': <Map<String, String>>[
        <String, String>{'url': 'https://integrations.googleapis.com'},
      ],
      'paths': <String, Object?>{
        '/execute': <String, Object?>{
          'post': <String, Object?>{
            'operationId': 'listIssues',
            'x-operation': 'LIST_ENTITIES',
            'x-entity': 'Issues',
            'requestBody': <String, Object?>{
              'content': <String, Object?>{
                'application/json': <String, Object?>{
                  'schema': <String, Object?>{'type': 'object'},
                },
              },
            },
            'responses': <String, Object?>{
              '200': <String, Object?>{
                'description': 'ok',
                'content': <String, Object?>{
                  'application/json': <String, Object?>{
                    'schema': <String, Object?>{'type': 'object'},
                  },
                },
              },
            },
          },
        },
      },
    };

    test('integration mode creates OpenAPI tools', () async {
      final _FakeIntegrationClient fakeClient = _FakeIntegrationClient(
        integrationSpec: integrationSpec,
      );

      final ApplicationIntegrationToolset toolset =
          ApplicationIntegrationToolset(
            project: 'p1',
            location: 'us-central1',
            integration:
                'projects/p1/locations/us-central1/integrations/sample',
            integrationClient: fakeClient,
          );

      final List<BaseTool> tools = await toolset.getTools();
      expect(fakeClient.integrationSpecCalls, 1);
      expect(
        tools.map((BaseTool tool) => tool.name),
        contains('ping_connection'),
      );
    });

    test(
      'connection mode builds IntegrationConnectorTool and honors auth override',
      () async {
        final _FakeIntegrationClient fakeIntegrationClient =
            _FakeIntegrationClient(connectionSpec: connectorSpec);
        final _FakeConnectionsClient fakeConnectionsClient =
            _FakeConnectionsClient(
              connectionDetails: <String, Object?>{
                'name': 'projects/p1/locations/us-central1/connections/conn1',
                'serviceName': 'svc',
                'host': 'host.internal',
                'authOverrideEnabled': false,
              },
            );

        final ApplicationIntegrationToolset toolset =
            ApplicationIntegrationToolset(
              project: 'p1',
              location: 'us-central1',
              connection: 'conn1',
              entityOperations: <String, List<String>>{
                'Issues': <String>['LIST'],
              },
              authScheme: SecurityScheme(
                type: AuthSchemeType.http,
                scheme: 'bearer',
                bearerFormat: 'JWT',
              ),
              authCredential: AuthCredential(
                authType: AuthCredentialType.http,
                http: HttpAuth(
                  scheme: 'bearer',
                  credentials: HttpCredentials(),
                ),
              ),
              integrationClient: fakeIntegrationClient,
              connectionsClient: fakeConnectionsClient,
            );

        final List<BaseTool> tools = await toolset.getTools();
        expect(fakeConnectionsClient.connectionDetailsCalls, 1);
        expect(fakeIntegrationClient.connectionSpecCalls, 1);
        expect(tools.length, 1);
        expect(tools.single, isA<IntegrationConnectorTool>());

        final IntegrationConnectorTool connectorTool =
            tools.single as IntegrationConnectorTool;
        expect(connectorTool.authScheme, isNull);
        expect(connectorTool.authCredential, isNull);

        final AuthConfig? authConfig = toolset.getAuthConfig();
        expect(authConfig, isNotNull);
        expect(authConfig!.rawAuthCredential, isNotNull);
      },
    );
  });
}
