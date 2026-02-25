import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

class _NoopAgent extends BaseAgent {
  _NoopAgent({required super.name});

  @override
  Stream<Event> runAsyncImpl(InvocationContext context) async* {}
}

class _RecordingMemoryService extends BaseMemoryService {
  Session? lastSession;

  @override
  Future<void> addSessionToMemory(Session session) async {
    lastSession = session;
  }

  @override
  Future<SearchMemoryResponse> searchMemory({
    required String appName,
    required String userId,
    required String query,
  }) async {
    return SearchMemoryResponse();
  }
}

Context _newContext({
  String? functionCallId,
  Object? credentialService,
  Object? memoryService,
}) {
  final InvocationContext invocationContext = InvocationContext(
    sessionService: InMemorySessionService(),
    invocationId: 'inv_1',
    agent: _NoopAgent(name: 'root'),
    session: Session(id: 's1', appName: 'app', userId: 'u1'),
    credentialService: credentialService,
    memoryService: memoryService,
  );
  return Context(invocationContext, functionCallId: functionCallId);
}

void main() {
  group('Context tool request helpers', () {
    test('requestConfirmation throws when functionCallId is missing', () {
      final Context context = _newContext();
      expect(
        () => context.requestConfirmation(hint: 'approve?'),
        throwsA(
          isA<StateError>().having(
            (StateError error) => error.message,
            'message',
            contains('requires functionCallId'),
          ),
        ),
      );
    });

    test('requestConfirmation stores confirmation under function call id', () {
      final Context context = _newContext(functionCallId: 'call_1');
      context.requestConfirmation(
        hint: 'approve this action',
        payload: <String, Object?>{'scope': 'calendar'},
      );

      final Object? storedRaw =
          context.actions.requestedToolConfirmations['call_1'];
      expect(storedRaw, isA<ToolConfirmation>());
      final ToolConfirmation stored = storedRaw as ToolConfirmation;
      expect(stored.hint, 'approve this action');
      expect(stored.payload, <String, Object?>{'scope': 'calendar'});
    });

    test('requestCredential throws when functionCallId is missing', () {
      final Context context = _newContext();
      expect(
        () => context.requestCredential(AuthConfig(authScheme: 'http')),
        throwsA(
          isA<StateError>().having(
            (StateError error) => error.message,
            'message',
            contains('requires functionCallId'),
          ),
        ),
      );
    });

    test('requestCredential wraps AuthConfig using AuthHandler request', () {
      final Context context = _newContext(functionCallId: 'call_2');
      final AuthConfig authConfig = AuthConfig(
        authScheme: 'http',
        rawAuthCredential: AuthCredential(
          authType: AuthCredentialType.http,
          http: HttpAuth(
            scheme: 'bearer',
            credentials: HttpCredentials(token: 'token-1'),
          ),
        ),
      );

      context.requestCredential(authConfig);

      final Object? stored = context.actions.requestedAuthConfigs['call_2'];
      expect(stored, isA<AuthConfig>());
      final AuthConfig storedConfig = stored as AuthConfig;
      expect(storedConfig.authScheme, 'http');
      expect(storedConfig.credentialKey, authConfig.credentialKey);
      expect(
        identical(storedConfig, authConfig),
        isFalse,
        reason: 'AuthHandler should store a generated request copy.',
      );
    });

    test('requestCredential stores raw object for non-AuthConfig payload', () {
      final Context context = _newContext(functionCallId: 'call_3');
      final Map<String, Object?> authPayload = <String, Object?>{
        'provider': 'custom',
        'scope': 'read',
      };

      context.requestCredential(authPayload);

      expect(context.actions.requestedAuthConfigs['call_3'], authPayload);
    });

    test(
      'saveCredential/loadCredential roundtrip via credential service',
      () async {
        final InMemoryCredentialService service = InMemoryCredentialService();
        final Context context = _newContext(credentialService: service);
        final AuthConfig authConfig = AuthConfig(
          authScheme: 'http',
          rawAuthCredential: AuthCredential(
            authType: AuthCredentialType.http,
            http: HttpAuth(
              scheme: 'bearer',
              credentials: HttpCredentials(token: 't1'),
            ),
          ),
        );

        await context.saveCredential(authConfig);
        final AuthCredential? loaded = await context.loadCredential(authConfig);

        expect(loaded, isNotNull);
        expect(loaded!.http?.credentials.token, 't1');
      },
    );

    test('saveCredential throws when credential service is unavailable', () {
      final Context context = _newContext();
      final AuthConfig authConfig = AuthConfig(authScheme: 'http');
      expect(
        () => context.saveCredential(authConfig),
        throwsA(
          isA<StateError>().having(
            (StateError error) => error.message,
            'message',
            contains('Credential service is not initialized'),
          ),
        ),
      );
    });

    test('loadCredential throws when credential service is unavailable', () {
      final Context context = _newContext();
      final AuthConfig authConfig = AuthConfig(authScheme: 'http');
      expect(
        () => context.loadCredential(authConfig),
        throwsA(
          isA<StateError>().having(
            (StateError error) => error.message,
            'message',
            contains('Credential service is not initialized'),
          ),
        ),
      );
    });

    test('getAuthResponse reads auth credential from context state', () {
      final Context context = _newContext();
      final AuthConfig authConfig = AuthConfig(
        authScheme: 'oauth2',
        rawAuthCredential: AuthCredential(
          authType: AuthCredentialType.oauth2,
          oauth2: OAuth2Auth(clientId: 'c1', clientSecret: 's1'),
        ),
      );
      final AuthCredential expected = AuthCredential(
        authType: AuthCredentialType.oauth2,
        oauth2: OAuth2Auth(accessToken: 'token-abc'),
      );
      context.state[authTemporaryStateKey(authConfig.credentialKey)] = expected;

      final AuthCredential? loaded = context.getAuthResponse(authConfig);

      expect(loaded, isNotNull);
      expect(loaded!.oauth2?.accessToken, 'token-abc');
    });

    test(
      'addSessionToMemory forwards current session to memory service',
      () async {
        final _RecordingMemoryService memoryService = _RecordingMemoryService();
        final Context context = _newContext(memoryService: memoryService);

        await context.addSessionToMemory();

        expect(memoryService.lastSession, isNotNull);
        expect(memoryService.lastSession!.id, 's1');
        expect(memoryService.lastSession!.appName, 'app');
        expect(memoryService.lastSession!.userId, 'u1');
      },
    );

    test('addSessionToMemory throws when memory service is unavailable', () {
      final Context context = _newContext();
      expect(
        () => context.addSessionToMemory(),
        throwsA(
          isA<StateError>().having(
            (StateError error) => error.message,
            'message',
            contains('Memory service is not initialized'),
          ),
        ),
      );
    });
  });
}
