import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

class _NoopAgent extends BaseAgent {
  _NoopAgent({required super.name});

  @override
  Stream<Event> runAsyncImpl(InvocationContext context) async* {}
}

Context _newContext({String? functionCallId}) {
  final InvocationContext invocationContext = InvocationContext(
    sessionService: InMemorySessionService(),
    invocationId: 'inv_1',
    agent: _NoopAgent(name: 'root'),
    session: Session(id: 's1', appName: 'app', userId: 'u1'),
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
  });
}
