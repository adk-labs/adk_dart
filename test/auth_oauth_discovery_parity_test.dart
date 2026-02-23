import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

void main() {
  group('oauth2 credential util parity', () {
    test('createOAuth2Session builds session for OpenID Connect scheme', () {
      final AuthCredential credential = AuthCredential(
        authType: AuthCredentialType.oauth2,
        oauth2: OAuth2Auth(
          clientId: 'client-id',
          clientSecret: 'client-secret',
          redirectUri: 'https://app.example.com/callback',
          state: 'state-1',
          tokenEndpointAuthMethod: 'client_secret_post',
        ),
      );
      final OpenIdConnectWithConfig scheme = OpenIdConnectWithConfig(
        authorizationEndpoint: 'https://issuer.example.com/auth',
        tokenEndpoint: 'https://issuer.example.com/token',
        scopes: <String>['scope.a', 'scope.b'],
      );

      final OAuth2SessionResult result = createOAuth2Session(
        authScheme: scheme,
        authCredential: credential,
      );
      expect(result.tokenEndpoint, 'https://issuer.example.com/token');
      expect(result.session, isNotNull);
      expect(result.session!.clientId, 'client-id');
      expect(result.session!.scope, 'scope.a scope.b');
      expect(result.session!.tokenEndpointAuthMethod, 'client_secret_post');
    });

    test('createOAuth2Session supports authorization-code OAuth2 flow', () {
      final ExtendedOAuth2 scheme = ExtendedOAuth2(
        flows: OAuthFlows(
          authorizationCode: OAuthFlow(
            tokenUrl: 'https://issuer.example.com/token',
            scopes: <String, String>{'scope.read': 'read scope'},
          ),
        ),
      );
      final AuthCredential credential = AuthCredential(
        authType: AuthCredentialType.oauth2,
        oauth2: OAuth2Auth(
          clientId: 'client-id',
          clientSecret: 'client-secret',
        ),
      );

      final OAuth2SessionResult result = createOAuth2Session(
        authScheme: scheme,
        authCredential: credential,
      );
      expect(result.tokenEndpoint, 'https://issuer.example.com/token');
      expect(result.session!.scope, 'scope.read');
    });

    test(
      'createOAuth2Session returns empty result when credentials are missing',
      () {
        final ExtendedOAuth2 scheme = ExtendedOAuth2(
          flows: OAuthFlows(
            clientCredentials: OAuthFlow(
              tokenUrl: 'https://issuer.example.com/token',
              scopes: <String, String>{'a': 'A'},
            ),
          ),
        );
        final AuthCredential credential = AuthCredential(
          authType: AuthCredentialType.oauth2,
          oauth2: OAuth2Auth(clientId: 'client-id'),
        );

        final OAuth2SessionResult result = createOAuth2Session(
          authScheme: scheme,
          authCredential: credential,
        );
        expect(result.session, isNull);
        expect(result.tokenEndpoint, isNull);
      },
    );

    test(
      'updateCredentialWithTokens updates access/refresh/id token values',
      () {
        final AuthCredential credential = AuthCredential(
          authType: AuthCredentialType.oauth2,
          oauth2: OAuth2Auth(clientId: 'client-id', clientSecret: 'secret'),
        );

        updateCredentialWithTokens(credential, <String, Object?>{
          'access_token': 'access',
          'refresh_token': 'refresh',
          'id_token': 'id-token',
          'expires_at': '111',
          'expires_in': 55,
        });

        expect(credential.oauth2!.accessToken, 'access');
        expect(credential.oauth2!.refreshToken, 'refresh');
        expect(credential.oauth2!.idToken, 'id-token');
        expect(credential.oauth2!.expiresAt, 111);
        expect(credential.oauth2!.expiresIn, 55);
      },
    );
  });

  group('oauth2 discovery parity', () {
    test(
      'discoverAuthServerMetadata tries endpoints and validates issuer',
      () async {
        final OAuth2DiscoveryManager manager = OAuth2DiscoveryManager(
          httpGet: (Uri uri) async {
            if (uri.path.endsWith('/.well-known/oauth-authorization-server')) {
              return (
                statusCode: 200,
                body:
                    '{"issuer":"https://wrong.example.com","authorization_endpoint":"https://wrong.example.com/auth","token_endpoint":"https://wrong.example.com/token"}',
              );
            }
            if (uri.path.endsWith('/.well-known/openid-configuration')) {
              return (
                statusCode: 200,
                body:
                    '{"issuer":"https://issuer.example.com","authorization_endpoint":"https://issuer.example.com/auth","token_endpoint":"https://issuer.example.com/token","scopes_supported":["openid"]}',
              );
            }
            return (statusCode: 404, body: '{}');
          },
        );

        final AuthorizationServerMetadata? metadata = await manager
            .discoverAuthServerMetadata('https://issuer.example.com');
        expect(metadata, isNotNull);
        expect(metadata!.issuer, 'https://issuer.example.com');
        expect(metadata.tokenEndpoint, 'https://issuer.example.com/token');
        expect(metadata.scopesSupported, <String>['openid']);
      },
    );

    test('discoverResourceMetadata validates returned resource field', () async {
      final OAuth2DiscoveryManager manager = OAuth2DiscoveryManager(
        httpGet: (Uri uri) async {
          if (uri.path == '/.well-known/oauth-protected-resource/v1/resource') {
            return (
              statusCode: 200,
              body:
                  '{"resource":"https://api.example.com/v1/resource","authorization_servers":["https://issuer.example.com"]}',
            );
          }
          return (statusCode: 404, body: '{}');
        },
      );

      final ProtectedResourceMetadata? metadata = await manager
          .discoverResourceMetadata('https://api.example.com/v1/resource');
      expect(metadata, isNotNull);
      expect(metadata!.resource, 'https://api.example.com/v1/resource');
      expect(metadata.authorizationServers, <String>[
        'https://issuer.example.com',
      ]);
    });

    test('discoverResourceMetadata returns null on mismatch', () async {
      final OAuth2DiscoveryManager manager = OAuth2DiscoveryManager(
        httpGet: (Uri uri) async => (
          statusCode: 200,
          body:
              '{"resource":"https://other.example.com","authorization_servers":[]}',
        ),
      );

      final ProtectedResourceMetadata? metadata = await manager
          .discoverResourceMetadata('https://api.example.com/resource');
      expect(metadata, isNull);
    });
  });
}
