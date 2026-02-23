import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

void main() {
  test('AuthHandler generateAuthRequest keeps oauth request payload', () {
    final AuthConfig config = AuthConfig(
      authScheme: 'oauth2_authorization_code',
      credentialKey: 'cred_1',
      rawAuthCredential: AuthCredential(
        authType: AuthCredentialType.oauth2,
        oauth2: OAuth2Auth(
          clientId: 'client',
          clientSecret: 'secret',
          authUri: 'https://auth.example.com',
        ),
      ),
    );

    final AuthConfig request = AuthHandler(
      authConfig: config,
    ).generateAuthRequest();
    expect(request.credentialKey, 'cred_1');
    expect(request.exchangedAuthCredential, isNotNull);
    expect(
      request.exchangedAuthCredential?.oauth2?.authUri,
      'https://auth.example.com',
    );
  });

  test(
    'AuthHandler generateAuthRequest throws for oauth scheme without raw auth credential',
    () {
      final AuthConfig config = AuthConfig(
        authScheme: 'oauth2_authorization_code',
        credentialKey: 'cred_missing',
      );
      final AuthHandler handler = AuthHandler(authConfig: config);

      expect(
        handler.generateAuthRequest,
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError error) => '${error.message}',
            'message',
            contains('requires auth_credential'),
          ),
        ),
      );
    },
  );

  test(
    'AuthHandler generateAuthRequest throws when oauth2 payload is missing',
    () {
      final AuthConfig config = AuthConfig(
        authScheme: 'oauth2_authorization_code',
        credentialKey: 'cred_missing_oauth2',
        rawAuthCredential: AuthCredential(authType: AuthCredentialType.oauth2),
      );
      final AuthHandler handler = AuthHandler(authConfig: config);

      expect(
        handler.generateAuthRequest,
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError error) => '${error.message}',
            'message',
            contains('requires oauth2 in auth_credential'),
          ),
        ),
      );
    },
  );

  test(
    'AuthHandler generateAuthRequest throws when auth URI and client credentials are both missing',
    () {
      final AuthConfig config = AuthConfig(
        authScheme: 'oauth2_authorization_code',
        credentialKey: 'cred_missing_client',
        rawAuthCredential: AuthCredential(
          authType: AuthCredentialType.oauth2,
          oauth2: OAuth2Auth(),
        ),
      );
      final AuthHandler handler = AuthHandler(authConfig: config);

      expect(
        handler.generateAuthRequest,
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError error) => '${error.message}',
            'message',
            contains('requires both client_id and client_secret'),
          ),
        ),
      );
    },
  );

  test(
    'AuthHandler parseAndStoreAuthResponse stores temp and auth keys',
    () async {
      final Session session = Session(id: 's1', appName: 'app', userId: 'u1');
      final State state = State(
        value: session.state,
        delta: <String, Object?>{},
      );

      final AuthConfig config = AuthConfig(
        authScheme: 'api_key',
        credentialKey: 'cred_2',
        exchangedAuthCredential: AuthCredential(
          authType: AuthCredentialType.apiKey,
          apiKey: 'abc123',
        ),
      );

      final AuthHandler handler = AuthHandler(authConfig: config);
      await handler.parseAndStoreAuthResponse(state);

      final Object? temp = state[authTemporaryStateKey('cred_2')];
      final Object? auth = state[authResponseStateKey('cred_2')];
      expect(temp, isA<AuthCredential>());
      expect(auth, isA<AuthCredential>());
      expect((temp as AuthCredential).apiKey, 'abc123');
      expect((auth as AuthCredential).apiKey, 'abc123');
    },
  );
}
