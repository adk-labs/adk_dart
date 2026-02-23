import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

class _NoopModel extends BaseLlm {
  _NoopModel() : super(model: 'noop');

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {}
}

Context _newContext({Object? credentialService, String? functionCallId}) {
  final Agent agent = Agent(name: 'root_agent', model: _NoopModel());
  final Session session = Session(id: 's1', appName: 'app', userId: 'u1');
  final InvocationContext invocationContext = InvocationContext(
    sessionService: InMemorySessionService(),
    credentialService: credentialService,
    invocationId: 'inv_1',
    agent: agent,
    session: session,
  );
  return Context(invocationContext, functionCallId: functionCallId);
}

Matcher _throwsArgumentMessage(String messageFragment) {
  return throwsA(
    isA<ArgumentError>().having(
      (ArgumentError error) => error.message.toString(),
      'message',
      contains(messageFragment),
    ),
  );
}

void main() {
  group('AuthConfig', () {
    test('credential key is stable for the same payload', () {
      final AuthCredential raw = AuthCredential(
        authType: AuthCredentialType.http,
        resourceRef: 'resource_1',
      );
      final AuthConfig a = AuthConfig(
        authScheme: 'http',
        rawAuthCredential: raw,
      );
      final AuthConfig b = AuthConfig(
        authScheme: 'http',
        rawAuthCredential: raw,
      );
      expect(a.credentialKey, b.credentialKey);
      expect(a.credentialKey, startsWith('adk_'));
    });
  });

  group('CredentialManager', () {
    test('requestCredential records auth config in event actions', () async {
      final Context context = _newContext(functionCallId: 'call_1');
      final AuthConfig authConfig = AuthConfig(
        authScheme: 'oauth2',
        rawAuthCredential: AuthCredential(
          authType: AuthCredentialType.oauth2,
          oauth2: OAuth2Auth(authUri: 'https://auth.example.com'),
        ),
      );
      final CredentialManager manager = CredentialManager(
        authConfig: authConfig,
      );

      await manager.requestCredential(context);

      final Object? stored = context.actions.requestedAuthConfigs['call_1'];
      expect(stored, isA<AuthConfig>());
      final AuthConfig storedConfig = stored as AuthConfig;
      expect(storedConfig.authScheme, authConfig.authScheme);
      expect(storedConfig.credentialKey, authConfig.credentialKey);
    });

    test('loads credential from credential service', () async {
      final InMemoryCredentialService service = InMemoryCredentialService();
      final Context context = _newContext(credentialService: service);
      final AuthConfig authConfig = AuthConfig(
        authScheme: 'http',
        exchangedAuthCredential: AuthCredential(
          authType: AuthCredentialType.http,
          http: HttpAuth(
            scheme: 'bearer',
            credentials: HttpCredentials(token: 'service-token'),
          ),
        ),
      );
      await service.saveCredential(authConfig, context);

      authConfig.exchangedAuthCredential = null;
      final CredentialManager manager = CredentialManager(
        authConfig: authConfig,
      );
      final AuthCredential? loaded = await manager.getAuthCredential(context);

      expect(loaded, isNotNull);
      expect(loaded!.http?.credentials.token, 'service-token');
    });

    test('exchanges oauth2 credential and persists it', () async {
      final InMemoryCredentialService service = InMemoryCredentialService();
      final Context context = _newContext(credentialService: service);

      final AuthConfig authConfig = AuthConfig(
        authScheme: 'oauth2:client_credentials',
        rawAuthCredential: AuthCredential(
          authType: AuthCredentialType.oauth2,
          oauth2: OAuth2Auth(
            clientId: 'client-id',
            clientSecret: 'client-secret',
          ),
        ),
      );
      final CredentialManager manager = CredentialManager(
        authConfig: authConfig,
      );
      manager.registerCredentialExchanger(
        AuthCredentialType.oauth2,
        OAuth2CredentialExchanger(
          exchangeHandler: (OAuth2Auth _, String? unusedAuthScheme) async {
            return <String, Object?>{
              'access_token': 'exchanged-token',
              'refresh_token': 'refresh-token',
              'expires_in': 3600,
            };
          },
        ),
      );

      final AuthCredential? credential = await manager.getAuthCredential(
        context,
      );
      expect(credential, isNotNull);
      expect(credential!.oauth2?.accessToken, 'exchanged-token');
      expect(credential.oauth2?.refreshToken, 'refresh-token');

      final AuthCredential? saved = await service.loadCredential(
        authConfig,
        context,
      );
      expect(saved?.oauth2?.accessToken, 'exchanged-token');
    });

    test(
      'refreshes expired oauth2 credential from credential service',
      () async {
        final InMemoryCredentialService service = InMemoryCredentialService();
        final Context context = _newContext(credentialService: service);
        final int nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;

        final AuthConfig authConfig = AuthConfig(
          authScheme: 'oauth2',
          rawAuthCredential: AuthCredential(
            authType: AuthCredentialType.oauth2,
            oauth2: OAuth2Auth(clientId: 'client', clientSecret: 'secret'),
          ),
          exchangedAuthCredential: AuthCredential(
            authType: AuthCredentialType.oauth2,
            oauth2: OAuth2Auth(
              clientId: 'client',
              clientSecret: 'secret',
              accessToken: 'old-token',
              refreshToken: 'refresh-token',
              expiresAt: nowSeconds - 100,
            ),
          ),
        );
        await service.saveCredential(authConfig, context);

        authConfig.exchangedAuthCredential = null;
        final CredentialManager manager = CredentialManager(
          authConfig: authConfig,
        );
        manager.registerCredentialRefresher(
          AuthCredentialType.oauth2,
          OAuth2CredentialRefresher(
            refreshHandler: (OAuth2Auth _, String? unusedAuthScheme) async {
              return <String, Object?>{
                'access_token': 'new-token',
                'expires_in': 1800,
              };
            },
          ),
        );

        final AuthCredential? credential = await manager.getAuthCredential(
          context,
        );
        expect(credential, isNotNull);
        expect(credential!.oauth2?.accessToken, 'new-token');
      },
    );

    test(
      'returns null for authorization-code flow without auth response',
      () async {
        final Context context = _newContext();
        final AuthConfig authConfig = AuthConfig(
          authScheme: 'oauth2:authorization_code',
          rawAuthCredential: AuthCredential(
            authType: AuthCredentialType.oauth2,
            oauth2: OAuth2Auth(
              clientId: 'client-id',
              clientSecret: 'client-secret',
            ),
          ),
        );
        final CredentialManager manager = CredentialManager(
          authConfig: authConfig,
        );

        final AuthCredential? credential = await manager.getAuthCredential(
          context,
        );
        expect(credential, isNull);
      },
    );

    test('throws when oauth2 scheme has no raw credential', () async {
      final Context context = _newContext();
      final AuthConfig authConfig = AuthConfig(authScheme: 'oauth2');
      final CredentialManager manager = CredentialManager(
        authConfig: authConfig,
      );

      await expectLater(
        manager.getAuthCredential(context),
        _throwsArgumentMessage('rawAuthCredential is required'),
      );
    });

    test('throws when oauth credential type has no oauth2 payload', () async {
      final Context context = _newContext();
      final AuthConfig authConfig = AuthConfig(
        authScheme: 'oauth2',
        rawAuthCredential: AuthCredential(authType: AuthCredentialType.oauth2),
      );
      final CredentialManager manager = CredentialManager(
        authConfig: authConfig,
      );

      await expectLater(
        manager.getAuthCredential(context),
        _throwsArgumentMessage('rawAuthCredential.oauth2 is required'),
      );
    });
  });
}
