import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

Context _newToolContext({String? functionCallId, Map<String, Object?>? state}) {
  final InvocationContext invocationContext = InvocationContext(
    sessionService: InMemorySessionService(),
    invocationId: 'inv_google',
    agent: LlmAgent(name: 'root', instruction: 'root'),
    session: Session(
      id: 's_google',
      appName: 'app',
      userId: 'u1',
      state: state ?? <String, Object?>{},
    ),
  );
  return Context(invocationContext, functionCallId: functionCallId);
}

void main() {
  group('google tools parity', () {
    test('GoogleSearchTool configures Gemini 2 requests', () async {
      final GoogleSearchTool tool = GoogleSearchTool();
      final LlmRequest request = LlmRequest(model: 'gemini-2.5-flash');
      await tool.processLlmRequest(
        toolContext: _newToolContext(),
        llmRequest: request,
      );
      expect(request.config.labels['adk_google_search_tool'], 'google_search');
      expect(request.config.tools, isNotNull);
      expect(
        request.config.tools!.last.googleSearch,
        isA<Map<String, Object?>>(),
      );
    });

    test('GoogleSearchTool configures Gemini 1 retrieval payload', () async {
      final GoogleSearchTool tool = GoogleSearchTool();
      final LlmRequest request = LlmRequest(model: 'gemini-1.5-flash');

      await tool.processLlmRequest(
        toolContext: _newToolContext(),
        llmRequest: request,
      );

      expect(
        request.config.labels['adk_google_search_tool'],
        'google_search_retrieval',
      );
      expect(request.config.tools, isNotNull);
      expect(
        request.config.tools!.last.googleSearchRetrieval,
        isA<Map<String, Object?>>(),
      );
    });

    test('GoogleSearchTool enforces Gemini 1 multi-tool limitation', () async {
      final GoogleSearchTool tool = GoogleSearchTool();
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
    });

    test('GoogleSearchTool supports model override and check bypass', () async {
      final GoogleSearchTool tool = GoogleSearchTool(
        model: 'not-gemini',
        modelIdCheckDisabledResolver: () => true,
      );
      final LlmRequest request = LlmRequest(model: 'gemini-2.0-flash');
      await tool.processLlmRequest(
        toolContext: _newToolContext(),
        llmRequest: request,
      );
      expect(request.model, 'not-gemini');
      expect(request.config.labels['adk_google_search_tool'], 'google_search');
      expect(request.config.tools, isNotNull);
      expect(
        request.config.tools!.last.googleSearch,
        isA<Map<String, Object?>>(),
      );
    });

    test(
      'LlmAgent wraps GoogleSearchTool into GoogleSearchAgentTool for multi-tool bypass',
      () async {
        final LlmAgent agent = LlmAgent(
          name: 'multi_search',
          model: 'gemini-2.5-flash',
          instruction: 'search',
          tools: <Object>[
            GoogleSearchTool(bypassMultiToolsLimit: true),
            FunctionTool(name: 'echo', func: ({required String text}) => text),
          ],
        );

        final List<BaseTool> tools = await agent.canonicalTools();
        expect(
          tools.any((BaseTool tool) => tool is GoogleSearchAgentTool),
          isTrue,
        );
      },
    );

    test('createGoogleSearchAgent returns search-only agent tooling', () {
      final LlmAgent agent = createGoogleSearchAgent('gemini-2.5-flash');
      expect(agent.name, 'google_search_agent');
      expect(agent.tools.whereType<GoogleSearchTool>().isNotEmpty, isTrue);
      final GoogleSearchAgentTool tool = GoogleSearchAgentTool(agent: agent);
      expect(tool.name, 'google_search_agent');
    });

    test('BaseGoogleCredentialsConfig validates mutually exclusive fields', () {
      expect(
        () => BaseGoogleCredentialsConfig(
          credentials: GoogleOAuthCredential(accessToken: 'token'),
          clientId: 'client-id',
        ),
        throwsArgumentError,
      );
      expect(() => BaseGoogleCredentialsConfig(), throwsArgumentError);
      expect(
        () => BaseGoogleCredentialsConfig(
          externalAccessTokenKey: 'token_key',
          clientSecret: 'client-secret',
        ),
        throwsArgumentError,
      );
    });

    test(
      'GoogleCredentialsManager reads external access token from state',
      () async {
        final Context context = _newToolContext(
          state: <String, Object?>{'external_token': 'abc123'},
        );
        final GoogleCredentialsManager manager = GoogleCredentialsManager(
          BaseGoogleCredentialsConfig(externalAccessTokenKey: 'external_token'),
        );
        final Object? result = await manager.getValidCredentials(context);
        expect(result, isA<GoogleOAuthCredential>());
        expect((result! as GoogleOAuthCredential).accessToken, 'abc123');
      },
    );

    test(
      'GoogleCredentialsManager requests OAuth credential when absent',
      () async {
        final Context context = _newToolContext(functionCallId: 'fc_google_1');
        final GoogleCredentialsManager manager = GoogleCredentialsManager(
          BaseGoogleCredentialsConfig(
            clientId: 'cid',
            clientSecret: 'csec',
            tokenCacheKey: 'oauth_cache_key',
          ),
        );
        final Object? result = await manager.getValidCredentials(context);
        expect(result, isNull);
        expect(
          context.actions.requestedAuthConfigs.containsKey('fc_google_1'),
          isTrue,
        );
      },
    );

    test(
      'GoogleCredentialsManager loads OAuth credential from auth response',
      () async {
        final Map<String, Object?> state = <String, Object?>{
          authResponseStateKey('oauth_cache_key'): AuthCredential(
            authType: AuthCredentialType.oauth2,
            oauth2: OAuth2Auth(accessToken: 'oauth_access_token'),
          ),
        };
        final Context context = _newToolContext(
          functionCallId: 'fc_google_2',
          state: state,
        );
        final GoogleCredentialsManager manager = GoogleCredentialsManager(
          BaseGoogleCredentialsConfig(
            clientId: 'cid',
            clientSecret: 'csec',
            tokenCacheKey: 'oauth_cache_key',
          ),
        );
        final Object? result = await manager.getValidCredentials(context);
        expect(result, isA<GoogleOAuthCredential>());
        expect(
          (result! as GoogleOAuthCredential).accessToken,
          'oauth_access_token',
        );
        expect(context.state['oauth_cache_key'], isA<String>());
      },
    );

    test('GoogleTool executes function without credentials config', () async {
      String hello({required String name}) => 'hello $name';

      final GoogleTool tool = GoogleTool(func: hello, name: 'hello_tool');
      final Object? result = await tool.run(
        args: <String, dynamic>{'name': 'dart'},
        toolContext: _newToolContext(),
      );
      expect(result, 'hello dart');
    });

    test('GoogleTool requests auth when OAuth credential is missing', () async {
      String fn({Object? credentials}) => '$credentials';

      final Context context = _newToolContext(functionCallId: 'fc_google_3');
      final GoogleTool tool = GoogleTool(
        func: fn,
        name: 'auth_tool',
        credentialsConfig: BaseGoogleCredentialsConfig(
          clientId: 'cid',
          clientSecret: 'csec',
          tokenCacheKey: 'oauth_google_tool',
        ),
      );

      final Object? result = await tool.run(
        args: <String, dynamic>{},
        toolContext: context,
      );
      expect(result, isA<String>());
      expect('$result', contains('User authorization is required'));
      expect(
        context.actions.requestedAuthConfigs.containsKey('fc_google_3'),
        isTrue,
      );
    });

    test('GoogleTool injects credential when available', () async {
      String fn({Object? credentials}) {
        final GoogleOAuthCredential value =
            credentials! as GoogleOAuthCredential;
        return value.accessToken;
      }

      final Map<String, Object?> state = <String, Object?>{
        authResponseStateKey('oauth_google_tool'): AuthCredential(
          authType: AuthCredentialType.oauth2,
          oauth2: OAuth2Auth(accessToken: 'token_from_state'),
        ),
      };
      final GoogleTool tool = GoogleTool(
        func: fn,
        name: 'auth_tool',
        credentialsConfig: BaseGoogleCredentialsConfig(
          clientId: 'cid',
          clientSecret: 'csec',
          tokenCacheKey: 'oauth_google_tool',
        ),
      );

      final Object? result = await tool.run(
        args: <String, dynamic>{},
        toolContext: _newToolContext(state: state),
      );
      expect(result, 'token_from_state');
    });

    test(
      'GoogleTool falls back to original args when callable does not accept injected credential params',
      () async {
        String fn({required String city}) => 'city=$city';

        final GoogleTool tool = GoogleTool(
          func: fn,
          name: 'city_tool',
          credentialsConfig: BaseGoogleCredentialsConfig(
            externalAccessTokenKey: 'external_token',
          ),
        );

        final Object? result = await tool.run(
          args: <String, dynamic>{'city': 'seoul'},
          toolContext: _newToolContext(
            state: <String, Object?>{'external_token': 'token-x'},
          ),
        );
        expect(result, 'city=seoul');
      },
    );

    test(
      'GoogleTool preserves callable StateError instead of retrying on matching text',
      () async {
        int callCount = 0;

        String fn({Object? credentials}) {
          callCount += 1;
          throw StateError('Failed to invoke function tool from upstream api');
        }

        final GoogleTool tool = GoogleTool(
          func: fn,
          name: 'error_tool',
          credentialsConfig: BaseGoogleCredentialsConfig(
            externalAccessTokenKey: 'external_token',
          ),
        );

        final Object? result = await tool.run(
          args: <String, dynamic>{},
          toolContext: _newToolContext(
            state: <String, Object?>{'external_token': 'token-x'},
          ),
        );
        expect(result, isA<Map<String, Object?>>());
        final Map<String, Object?> payload = result! as Map<String, Object?>;
        expect(payload['status'], 'ERROR');
        expect('${payload['error_details']}', contains('from upstream api'));
        expect(callCount, 1);
      },
    );
  });
}
