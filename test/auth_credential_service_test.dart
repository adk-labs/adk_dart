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

Context _newContext() {
  final Agent agent = Agent(name: 'root_agent', model: _NoopModel());
  final Session session = Session(id: 's1', appName: 'app', userId: 'u1');
  final InvocationContext invocationContext = InvocationContext(
    sessionService: InMemorySessionService(),
    invocationId: 'inv_1',
    agent: agent,
    session: session,
  );
  return Context(invocationContext);
}

void main() {
  group('Credential services', () {
    test('in-memory credential service loads what it saves', () async {
      final InMemoryCredentialService service = InMemoryCredentialService();
      final Context context = _newContext();
      final AuthConfig config = AuthConfig(
        authScheme: 'http',
        exchangedAuthCredential: AuthCredential(
          authType: AuthCredentialType.http,
          http: HttpAuth(
            scheme: 'bearer',
            credentials: HttpCredentials(token: 'token-123'),
          ),
        ),
      );

      await service.saveCredential(config, context);
      final AuthCredential? loaded = await service.loadCredential(
        config,
        context,
      );

      expect(loaded, isNotNull);
      expect(loaded!.authType, AuthCredentialType.http);
      expect(loaded.http?.credentials.token, 'token-123');
    });

    test(
      'session-state credential service persists in callback context state',
      () async {
        final SessionStateCredentialService service =
            SessionStateCredentialService();
        final Context context = _newContext();
        final AuthConfig config = AuthConfig(
          authScheme: 'apiKey',
          exchangedAuthCredential: AuthCredential(
            authType: AuthCredentialType.apiKey,
            apiKey: 'my-api-key',
          ),
        );

        await service.saveCredential(config, context);
        final AuthCredential? loaded = await service.loadCredential(
          config,
          context,
        );

        expect(loaded, isNotNull);
        expect(loaded!.apiKey, 'my-api-key');
      },
    );
  });
}
