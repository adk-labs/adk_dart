import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

Context _newToolContext({String? functionCallId, Map<String, Object?>? state}) {
  final InvocationContext invocationContext = InvocationContext(
    sessionService: InMemorySessionService(),
    invocationId: 'inv_openapi_rest',
    agent: LlmAgent(name: 'root', instruction: 'root'),
    session: Session(
      id: 's_openapi_rest',
      appName: 'app',
      userId: 'u1',
      state: state ?? <String, Object?>{},
    ),
  );
  return Context(invocationContext, functionCallId: functionCallId);
}

void main() {
  group('rest api tool parity', () {
    test('snake_to_lower_camel conversion', () {
      expect(snakeToLowerCamel('single'), 'single');
      expect(snakeToLowerCamel('two_words'), 'twoWords');
      expect(snakeToLowerCamel('three_word_example'), 'threeWordExample');
      expect(snakeToLowerCamel('alreadyCamelCase'), 'alreadyCamelCase');
    });

    test('prepares path/query/body parameters for json request', () {
      final RestApiTool tool = RestApiTool(
        name: 'test_tool',
        description: 'desc',
        endpoint: OperationEndpoint(
          baseUrl: 'https://example.com',
          path: '/users/{userId}/messages',
          method: 'GET',
        ),
        operation: <String, Object?>{
          'operationId': 'messages.get',
          'requestBody': <String, Object?>{
            'content': <String, Object?>{
              'application/json': <String, Object?>{
                'schema': <String, Object?>{
                  'type': 'object',
                  'properties': <String, Object?>{
                    'subject': <String, Object?>{'type': 'string'},
                  },
                },
              },
            },
          },
          'responses': <String, Object?>{
            '200': <String, Object?>{'description': 'ok'},
          },
        },
      );

      final Map<String, Object?> params = tool.prepareRequestParams(
        <ApiParameter>[
          ApiParameter(
            originalName: 'userId',
            paramLocation: 'path',
            paramSchema: <String, Object?>{'type': 'string'},
          ),
          ApiParameter(
            originalName: 'q',
            paramLocation: 'query',
            paramSchema: <String, Object?>{'type': 'string'},
          ),
          ApiParameter(
            originalName: 'subject',
            paramLocation: 'body',
            paramSchema: <String, Object?>{'type': 'string'},
          ),
        ],
        <String, Object?>{'user_id': '123', 'q': 'all', 'subject': 'hello'},
      );

      expect(params['method'], 'get');
      expect(params['url'], 'https://example.com/users/123/messages');
      expect((params['params'] as Map)['q'], 'all');
      expect((params['json'] as Map)['subject'], 'hello');
      expect((params['headers'] as Map)['Content-Type'], 'application/json');
      expect((params['headers'] as Map)['User-Agent'], contains('google-adk/'));
    });

    test(
      'calls request executor and returns successful json response',
      () async {
        Map<String, Object?>? captured;
        final RestApiTool tool = RestApiTool(
          name: 'test_tool',
          description: 'desc',
          endpoint: OperationEndpoint(
            baseUrl: 'https://example.com/',
            path: '/items/{itemId}',
            method: 'GET',
          ),
          operation: <String, Object?>{
            'operationId': 'items.get',
            'parameters': <Object?>[
              <String, Object?>{
                'name': 'itemId',
                'in': 'path',
                'required': true,
                'schema': <String, Object?>{'type': 'string'},
              },
              <String, Object?>{
                'name': 'view',
                'in': 'query',
                'schema': <String, Object?>{'type': 'string'},
              },
            ],
            'responses': <String, Object?>{
              '200': <String, Object?>{'description': 'ok'},
            },
          },
          headerProvider: (ReadonlyContext context) {
            expect(context.userId, 'u1');
            return <String, String>{'X-Request-ID': 'r1'};
          },
          requestExecutor:
              ({required Map<String, Object?> requestParams}) async {
                captured = requestParams;
                return RestApiResponse(
                  statusCode: 200,
                  jsonData: <String, Object?>{'result': 'success'},
                );
              },
        );
        tool.setDefaultHeaders(<String, String>{'developer-token': 'token'});
        tool.configureSslVerify('/path/to/ca.pem');

        final Map<String, Object?> response = await tool.call(
          args: <String, dynamic>{'item_id': 'abc', 'view': 'full'},
          toolContext: _newToolContext(),
        );

        expect(response, <String, Object?>{'result': 'success'});
        expect(captured, isNotNull);
        expect(captured!['url'], 'https://example.com/items/abc');
        expect((captured!['params'] as Map)['view'], 'full');
        expect((captured!['headers'] as Map)['X-Request-ID'], 'r1');
        expect((captured!['headers'] as Map)['developer-token'], 'token');
        expect(captured!['verify'], '/path/to/ca.pem');
      },
    );

    test('returns error payload for failed status response', () async {
      final RestApiTool tool = RestApiTool(
        name: 'test_tool',
        description: 'desc',
        endpoint: OperationEndpoint(
          baseUrl: 'https://example.com',
          path: '/test',
          method: 'GET',
        ),
        operation: <String, Object?>{
          'operationId': 'test.get',
          'responses': <String, Object?>{
            '200': <String, Object?>{'description': 'ok'},
          },
        },
        requestExecutor: ({required Map<String, Object?> requestParams}) async {
          return RestApiResponse(
            statusCode: 500,
            text: 'Internal Server Error',
          );
        },
      );

      final Map<String, Object?> result = await tool.call(
        args: <String, dynamic>{},
        toolContext: _newToolContext(),
      );

      expect(result.containsKey('error'), isTrue);
      expect('${result['error']}', contains('Status Code: 500'));
      expect('${result['error']}', contains('Internal Server Error'));
    });

    test('returns pending when interactive auth is required', () async {
      bool requestCalled = false;
      final RestApiTool tool = RestApiTool(
        name: 'auth_tool',
        description: 'desc',
        endpoint: OperationEndpoint(
          baseUrl: 'https://example.com',
          path: '/secure',
          method: 'GET',
        ),
        operation: <String, Object?>{
          'operationId': 'secure.get',
          'responses': <String, Object?>{
            '200': <String, Object?>{'description': 'ok'},
          },
        },
        authScheme: SecurityScheme(type: AuthSchemeType.openIdConnect),
        authCredential: AuthCredential(
          authType: AuthCredentialType.openIdConnect,
          oauth2: OAuth2Auth(clientId: 'cid', clientSecret: 'secret'),
        ),
        requestExecutor: ({required Map<String, Object?> requestParams}) async {
          requestCalled = true;
          return RestApiResponse(
            statusCode: 200,
            jsonData: <String, Object?>{},
          );
        },
      );

      final Context context = _newToolContext(functionCallId: 'fc1');
      final Map<String, Object?> result = await tool.call(
        args: <String, dynamic>{},
        toolContext: context,
      );

      expect(result, <String, Object?>{
        'pending': true,
        'message': 'Needs your authorization to access your data.',
      });
      expect(requestCalled, isFalse);
      expect(context.actions.requestedAuthConfigs.containsKey('fc1'), isTrue);
    });
  });

  group('tool auth handler parity', () {
    test('uses existing stored credential from tool context', () async {
      final Context context = _newToolContext(functionCallId: 'fc-existing');
      final SecurityScheme scheme = SecurityScheme(
        type: AuthSchemeType.apiKey,
        inLocation: 'header',
        name: 'X-API-Key',
      );
      final AuthCredential sourceCredential = AuthCredential(
        authType: AuthCredentialType.apiKey,
        apiKey: 'source',
      );
      final AuthCredential storedCredential = AuthCredential(
        authType: AuthCredentialType.apiKey,
        apiKey: 'stored',
      );

      final ToolContextCredentialStore store = ToolContextCredentialStore(
        toolContext: context,
      );
      final String key = store.getCredentialKey(scheme, sourceCredential);
      store.storeCredential(key, storedCredential);

      final ToolAuthHandler handler = ToolAuthHandler.fromToolContext(
        context,
        scheme,
        sourceCredential,
      );

      final AuthPreparationResult result = await handler
          .prepareAuthCredentials();
      expect(result.state, 'done');
      expect(result.authCredential?.apiKey, 'stored');
    });

    test('honors explicit credential key when requesting auth', () async {
      final Context context = _newToolContext(functionCallId: 'fc-key');
      final ToolAuthHandler handler = ToolAuthHandler.fromToolContext(
        context,
        SecurityScheme(type: AuthSchemeType.openIdConnect),
        AuthCredential(
          authType: AuthCredentialType.openIdConnect,
          oauth2: OAuth2Auth(clientId: 'cid', clientSecret: 'secret'),
        ),
        credentialKey: 'my_tool_tokens',
      );

      final AuthPreparationResult result = await handler
          .prepareAuthCredentials();
      expect(result.state, 'pending');

      final Object? requested = context.actions.requestedAuthConfigs['fc-key'];
      expect(requested, isA<AuthConfig>());
      expect((requested as AuthConfig).credentialKey, 'my_tool_tokens');
    });
  });
}
