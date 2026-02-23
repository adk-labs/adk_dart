import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

Context _newToolContext() {
  final InvocationContext invocationContext = InvocationContext(
    sessionService: InMemorySessionService(),
    invocationId: 'inv_google_api',
    agent: LlmAgent(name: 'root', instruction: 'root'),
    session: Session(id: 's_google_api', appName: 'app', userId: 'u1'),
  );
  return Context(invocationContext);
}

Map<String, Object?> _sampleDiscoverySpec() {
  return <String, Object?>{
    'title': 'Sample API',
    'version': 'v1',
    'rootUrl': 'https://example.googleapis.com/',
    'servicePath': 'sample/v1/',
    'documentationLink': 'https://example.com/docs',
    'auth': <String, Object?>{
      'oauth2': <String, Object?>{
        'scopes': <String, Object?>{
          'https://www.googleapis.com/auth/sample': <String, Object?>{
            'description': 'Sample scope',
          },
        },
      },
    },
    'schemas': <String, Object?>{
      'Sample': <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'name': <String, Object?>{'type': 'string', 'required': true},
        },
      },
    },
    'resources': <String, Object?>{
      'items': <String, Object?>{
        'methods': <String, Object?>{
          'get': <String, Object?>{
            'id': 'items.get',
            'httpMethod': 'GET',
            'path': 'items/{itemId}',
            'parameters': <String, Object?>{
              'itemId': <String, Object?>{
                'location': 'path',
                'required': true,
                'type': 'string',
              },
              'view': <String, Object?>{'location': 'query', 'type': 'string'},
            },
            'response': <String, Object?>{'\$ref': 'Sample'},
            'scopes': <Object?>['https://www.googleapis.com/auth/sample'],
          },
        },
      },
    },
  };
}

void main() {
  group('google api discovery converter parity', () {
    test(
      'converts discovery document into openapi paths/security/schemas',
      () async {
        final GoogleApiToOpenApiConverter converter =
            GoogleApiToOpenApiConverter(
              'sample',
              'v1',
              discoverySpec: _sampleDiscoverySpec(),
            );

        final Map<String, Object?> spec = await converter.convert();
        final Map<String, Object?> components = (spec['components'] as Map)
            .cast<String, Object?>();
        final Map<String, Object?> securitySchemes =
            (components['securitySchemes'] as Map).cast<String, Object?>();
        final Map<String, Object?> paths = (spec['paths'] as Map)
            .cast<String, Object?>();

        expect(spec['openapi'], '3.0.0');
        expect((spec['servers'] as List).first, isA<Map>());
        expect(securitySchemes.containsKey('oauth2'), isTrue);
        expect(securitySchemes.containsKey('apiKey'), isTrue);
        expect(paths.containsKey('/items/{itemId}'), isTrue);
        expect(components['schemas'], isA<Map>());
      },
    );
  });

  group('google api tool parity', () {
    test(
      'builds declaration and executes with path/query/body mapping',
      () async {
        late String capturedMethod;
        late Uri capturedUri;
        late Map<String, String> capturedHeaders;
        Object? capturedBody;

        final GoogleApiTool tool = GoogleApiTool(
          operation: GoogleApiOperation(
            operationId: 'items.get',
            method: 'GET',
            path: '/items/{itemId}',
            description: 'Get item',
            parameters: <Map<String, Object?>>[
              <String, Object?>{
                'name': 'itemId',
                'in': 'path',
                'required': true,
                'schema': <String, Object?>{'type': 'string'},
              },
              <String, Object?>{
                'name': 'view',
                'in': 'query',
                'required': false,
                'schema': <String, Object?>{'type': 'string'},
              },
            ],
            requestBodySchema: <String, Object?>{
              'type': 'object',
              'properties': <String, Object?>{
                'payload': <String, Object?>{'type': 'string'},
              },
            },
          ),
          baseUrl: 'https://example.googleapis.com/sample/v1',
          requestExecutor:
              ({
                required String method,
                required Uri uri,
                required Map<String, String> headers,
                Object? body,
              }) async {
                capturedMethod = method;
                capturedUri = uri;
                capturedHeaders = headers;
                capturedBody = body;
                return <String, Object?>{'ok': true};
              },
        );

        final FunctionDeclaration? declaration = tool.getDeclaration();
        expect(declaration, isNotNull);
        expect(declaration!.parameters['properties'], isA<Map>());

        final Object? result = await tool.run(
          args: <String, dynamic>{
            'itemId': 'abc',
            'view': 'full',
            'body': <String, Object?>{'payload': 'p1'},
          },
          toolContext: _newToolContext(),
        );

        expect(capturedMethod, 'GET');
        expect(capturedUri.path, '/sample/v1/items/abc');
        expect(capturedUri.queryParameters['view'], 'full');
        expect(capturedHeaders['accept'], 'application/json');
        expect(capturedBody, <String, Object?>{'payload': 'p1'});
        expect(result, <String, Object?>{'ok': true});
      },
    );

    test(
      'auth configuration sets oauth and service-account credential modes',
      () {
        final GoogleApiTool tool = GoogleApiTool(
          operation: GoogleApiOperation(
            operationId: 'items.list',
            method: 'GET',
            path: '/items',
          ),
          baseUrl: 'https://example.googleapis.com',
        );

        tool.configureAuth('cid', 'secret');
        expect(tool.authCredential?.authType, AuthCredentialType.openIdConnect);
        expect(tool.authCredential?.oauth2?.clientId, 'cid');

        tool.configureSaAuth(
          ServiceAccountAuth(
            serviceAccountCredential: ServiceAccountCredential(
              projectId: 'p',
              privateKeyId: 'k',
              privateKey: 'pk',
              clientEmail: 'svc@example.com',
              clientId: '123',
              authUri: 'https://accounts.google.com/o/oauth2/auth',
              tokenUri: 'https://oauth2.googleapis.com/token',
            ),
            scopes: <String>['scope-1'],
          ),
        );
        expect(
          tool.authCredential?.authType,
          AuthCredentialType.serviceAccount,
        );
        expect(tool.authScheme, 'service_account');
      },
    );
  });

  group('google api toolset parity', () {
    test('loads operations from openapi and applies list filter', () async {
      final GoogleApiToolset toolset = GoogleApiToolset(
        'sample',
        'v1',
        toolFilter: <String>['items_get'],
        openApiSpec: <String, Object?>{
          'servers': <Object?>[
            <String, Object?>{
              'url': 'https://example.googleapis.com/sample/v1',
            },
          ],
          'paths': <String, Object?>{
            '/items/{itemId}': <String, Object?>{
              'get': <String, Object?>{
                'operationId': 'items.get',
                'summary': 'Get item',
                'description': 'Get item',
                'parameters': <Object?>[
                  <String, Object?>{
                    'name': 'itemId',
                    'in': 'path',
                    'required': true,
                    'schema': <String, Object?>{'type': 'string'},
                  },
                ],
              },
            },
            '/items': <String, Object?>{
              'post': <String, Object?>{
                'operationId': 'items.create',
                'summary': 'Create item',
                'description': 'Create item',
              },
            },
          },
          'components': <String, Object?>{
            'securitySchemes': <String, Object?>{
              'oauth2': <String, Object?>{
                'flows': <String, Object?>{
                  'authorizationCode': <String, Object?>{
                    'scopes': <String, Object?>{'scope-1': 'Scope 1'},
                  },
                },
              },
            },
          },
        },
      );

      final List<BaseTool> tools = await toolset.getTools();
      expect(tools, hasLength(1));
      expect(tools.single.name, 'items_get');
    });

    test(
      'prebuilt google api toolset classes set expected api names/versions',
      () {
        expect(BigQueryToolset().apiName, 'bigquery');
        expect(BigQueryToolset().apiVersion, 'v2');
        expect(CalendarToolset().apiName, 'calendar');
        expect(GmailToolset().apiVersion, 'v1');
        expect(SheetsToolset().apiVersion, 'v4');
        expect(DocsToolset().apiName, 'docs');
      },
    );
  });
}
