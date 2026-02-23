import 'package:adk_dart/adk_dart.dart'
    hide OAuth2CredentialExchanger, ServiceAccountCredentialExchanger;
import 'package:adk_dart/src/tools/openapi_tool/auth/auth_helpers.dart';
import 'package:adk_dart/src/tools/openapi_tool/auth/credential_exchangers/auto_auth_credential_exchanger.dart';
import 'package:adk_dart/src/tools/openapi_tool/auth/credential_exchangers/base_credential_exchanger.dart';
import 'package:adk_dart/src/tools/openapi_tool/auth/credential_exchangers/oauth2_exchanger.dart';
import 'package:adk_dart/src/tools/openapi_tool/auth/credential_exchangers/service_account_exchanger.dart';
import 'package:adk_dart/src/tools/openapi_tool/common/common.dart';
import 'package:test/test.dart';

class _MockExchanger extends BaseAuthCredentialExchanger {
  _MockExchanger(this.result);

  final AuthCredential? result;

  @override
  Future<AuthCredential?> exchangeCredential(
    Object authScheme, [
    AuthCredential? authCredential,
  ]) async {
    return result;
  }
}

void main() {
  group('openapi common parity', () {
    test('renames keyword and builds api parameter metadata', () {
      expect(renamePythonKeywords('if'), 'param_if');
      expect(renamePythonKeywords('normal_name'), 'normal_name');

      final ApiParameter parameter = ApiParameter(
        originalName: 'X-Request-Id',
        paramLocation: 'header',
        paramSchema: <String, Object?>{'type': 'string'},
        description: 'request id',
      );
      expect(parameter.pyName, 'x_request_id');
      expect(parameter.typeHint, 'String');
      expect(parameter.toArgString(), 'x_request_id: x_request_id');
      expect(parameter.toPydocString(), contains('request id'));
    });
  });

  group('openapi auth helpers parity', () {
    test('creates api-key and bearer token schemes', () {
      final ({SecurityScheme authScheme, AuthCredential? authCredential})
      apiKey = tokenToSchemeCredential(
        'apikey',
        location: 'header',
        name: 'X-API-Key',
        credentialValue: 'k1',
      );
      expect(apiKey.authScheme.type, AuthSchemeType.apiKey);
      expect(apiKey.authCredential?.apiKey, 'k1');

      final ({SecurityScheme authScheme, AuthCredential? authCredential})
      bearer = tokenToSchemeCredential('oauth2Token', credentialValue: 't1');
      expect(bearer.authScheme.type, AuthSchemeType.http);
      expect(bearer.authCredential?.http?.credentials.token, 't1');
    });

    test('builds openid scheme from config dict and fetched url', () async {
      final ({
        OpenIdConnectWithConfig authScheme,
        AuthCredential authCredential,
      })
      direct = openidDictToSchemeCredential(
        <String, Object?>{
          'authorization_endpoint': 'https://issuer/auth',
          'token_endpoint': 'https://issuer/token',
          'userinfo_endpoint': 'https://issuer/userinfo',
        },
        <String>['scope-1'],
        <String, Object?>{'client_id': 'cid', 'client_secret': 'sec'},
      );
      expect(direct.authScheme.authorizationEndpoint, 'https://issuer/auth');
      expect(direct.authCredential.oauth2?.clientId, 'cid');

      final ({
        OpenIdConnectWithConfig authScheme,
        AuthCredential authCredential,
      })
      fetched = await openidUrlToSchemeCredential(
        'https://issuer/.well-known/openid-configuration',
        <String>['scope-2'],
        <String, Object?>{'client_id': 'cid2', 'client_secret': 'sec2'},
        configFetcher: (String url) async {
          expect(url, contains('.well-known'));
          return <String, Object?>{
            'authorization_endpoint': 'https://issuer2/auth',
            'token_endpoint': 'https://issuer2/token',
          };
        },
      );
      expect(fetched.authScheme.tokenEndpoint, 'https://issuer2/token');
      expect(fetched.authCredential.oauth2?.clientId, 'cid2');
    });

    test('maps credentials into synthetic auth parameters', () {
      final SecurityScheme apiKeyScheme = SecurityScheme(
        type: AuthSchemeType.apiKey,
        inLocation: 'query',
        name: 'key',
      );
      final AuthCredential apiKeyCredential = AuthCredential(
        authType: AuthCredentialType.apiKey,
        apiKey: 'k2',
      );
      final AuthParameterBinding apiKeyBinding = credentialToParam(
        apiKeyScheme,
        apiKeyCredential,
      );
      expect(apiKeyBinding.parameter?.paramLocation, 'query');
      expect(apiKeyBinding.args?['${internalAuthPrefix}key'], 'k2');

      final SecurityScheme oauthScheme = SecurityScheme(
        type: AuthSchemeType.oauth2,
      );
      final AuthCredential bearerCredential = AuthCredential(
        authType: AuthCredentialType.http,
        http: HttpAuth(
          scheme: 'bearer',
          credentials: HttpCredentials(token: 'tok'),
        ),
      );
      final AuthParameterBinding bearerBinding = credentialToParam(
        oauthScheme,
        bearerCredential,
      );
      expect(
        bearerBinding.args?['${internalAuthPrefix}Authorization'],
        'Bearer tok',
      );
    });

    test('converts raw map into typed auth scheme objects', () {
      final Object apiKey = dictToAuthScheme(<String, Object?>{
        'type': 'apiKey',
        'name': 'X-API-Key',
        'in': 'header',
      });
      expect(apiKey, isA<SecurityScheme>());

      final Object oauth2 = dictToAuthScheme(<String, Object?>{
        'type': 'oauth2',
        'flows': <String, Object?>{
          'authorizationCode': <String, Object?>{
            'authorizationUrl': 'https://issuer/auth',
            'tokenUrl': 'https://issuer/token',
            'scopes': <String, Object?>{'s1': 'scope'},
          },
        },
      });
      expect(oauth2, isA<ExtendedOAuth2>());
    });
  });

  group('openapi auth exchanger parity', () {
    test(
      'oauth2 exchanger turns access token into bearer credential',
      () async {
        final OAuth2CredentialExchanger exchanger = OAuth2CredentialExchanger();
        final AuthCredential? exchanged = await exchanger.exchangeCredential(
          SecurityScheme(type: AuthSchemeType.oauth2),
          AuthCredential(
            authType: AuthCredentialType.oauth2,
            oauth2: OAuth2Auth(accessToken: 'oauth-token'),
          ),
        );
        expect(exchanged?.authType, AuthCredentialType.http);
        expect(exchanged?.http?.credentials.token, 'oauth-token');
      },
    );

    test('service-account exchanger uses injected token resolver', () async {
      final ServiceAccountCredentialExchanger exchanger =
          ServiceAccountCredentialExchanger(
            tokenResolver: (ServiceAccountAuth _) async => 'sa-token',
          );
      final AuthCredential? exchanged = await exchanger.exchangeCredential(
        SecurityScheme(type: AuthSchemeType.http),
        AuthCredential(
          authType: AuthCredentialType.serviceAccount,
          serviceAccount: ServiceAccountAuth(
            serviceAccountCredential: ServiceAccountCredential(
              projectId: 'p',
              privateKeyId: 'k',
              privateKey: 'pk',
              clientEmail: 'svc@example.com',
              clientId: '123',
              authUri: 'https://accounts.google.com/o/oauth2/auth',
              tokenUri: 'https://oauth2.googleapis.com/token',
            ),
          ),
        ),
      );
      expect(exchanged?.authType, AuthCredentialType.http);
      expect(exchanged?.http?.credentials.token, 'sa-token');
    });

    test('auto exchanger dispatches by credential type', () async {
      final AutoAuthCredentialExchanger exchanger = AutoAuthCredentialExchanger(
        customExchangers: <AuthCredentialType, BaseAuthCredentialExchanger>{
          AuthCredentialType.apiKey: _MockExchanger(
            AuthCredential(authType: AuthCredentialType.apiKey, apiKey: 'done'),
          ),
        },
      );

      final AuthCredential? exchanged = await exchanger.exchangeCredential(
        SecurityScheme(type: AuthSchemeType.apiKey),
        AuthCredential(authType: AuthCredentialType.apiKey, apiKey: 'src'),
      );
      expect(exchanged?.apiKey, 'done');
    });
  });
}
