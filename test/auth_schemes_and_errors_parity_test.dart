import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

void main() {
  group('auth schemes parity', () {
    test('oauthGrantTypeFromFlow resolves each grant type', () {
      expect(
        oauthGrantTypeFromFlow(
          OAuthFlows(clientCredentials: OAuthFlow(tokenUrl: 'https://token')),
        ),
        OAuthGrantType.clientCredentials,
      );
      expect(
        oauthGrantTypeFromFlow(
          OAuthFlows(
            authorizationCode: OAuthFlow(
              authorizationUrl: 'https://auth',
              tokenUrl: 'https://token',
            ),
          ),
        ),
        OAuthGrantType.authorizationCode,
      );
      expect(
        oauthGrantTypeFromFlow(
          OAuthFlows(implicit: OAuthFlow(authorizationUrl: 'https://auth')),
        ),
        OAuthGrantType.implicit,
      );
      expect(
        oauthGrantTypeFromFlow(
          OAuthFlows(password: OAuthFlow(tokenUrl: 'https://token')),
        ),
        OAuthGrantType.password,
      );
      expect(oauthGrantTypeFromFlow(OAuthFlows()), isNull);
    });

    test('OpenIdConnectWithConfig serializes endpoints and scopes', () {
      final OpenIdConnectWithConfig scheme = OpenIdConnectWithConfig(
        authorizationEndpoint: 'https://issuer/auth',
        tokenEndpoint: 'https://issuer/token',
        scopes: <String>['scope.a', 'scope.b'],
      );

      final Map<String, Object?> json = scheme.toJson();
      expect(json['type'], AuthSchemeType.openIdConnect.name);
      expect(json['authorization_endpoint'], 'https://issuer/auth');
      expect(json['token_endpoint'], 'https://issuer/token');
      expect(json['scopes'], <String>['scope.a', 'scope.b']);
    });

    test('ExtendedOAuth2 serializes flows and issuer url', () {
      final ExtendedOAuth2 scheme = ExtendedOAuth2(
        flows: OAuthFlows(
          authorizationCode: OAuthFlow(
            authorizationUrl: 'https://issuer/auth',
            tokenUrl: 'https://issuer/token',
            scopes: <String, String>{'scope.a': 'Scope A'},
          ),
        ),
        issuerUrl: 'https://issuer',
      );

      final Map<String, Object?> json = scheme.toJson();
      expect(json['type'], AuthSchemeType.oauth2.name);
      expect(json['issuer_url'], 'https://issuer');
      final Map<String, Object?> flows = Map<String, Object?>.from(
        json['flows']! as Map,
      );
      expect(flows.containsKey('authorization_code'), isTrue);
    });
  });

  group('error parity', () {
    test('InputValidationError default and custom messages', () {
      expect(
        InputValidationError().toString(),
        'InputValidationError: Invalid input.',
      );
      expect(
        InputValidationError('bad format').toString(),
        'InputValidationError: bad format',
      );
    });
  });
}
