import 'dart:convert';
import 'dart:io';

import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

class _FakeApiHubClient implements BaseAPIHubClient {
  _FakeApiHubClient(this.spec);

  final String spec;
  int getSpecCallCount = 0;
  final List<String> requestedResourceNames = <String>[];

  @override
  Future<String> getSpecContent(String resourceName) async {
    getSpecCallCount += 1;
    requestedResourceNames.add(resourceName);
    return spec;
  }
}

void main() {
  tearDown(resetSecretManagerSecretFetcher);

  group('APIHubClient parity', () {
    test('resolves first version and first spec content from API resource', () async {
      final String spec = '''
openapi: 3.0.1
info:
  title: Calendar API
  description: Calendar endpoints
paths: {}
''';
      final String encodedSpec = base64Encode(utf8.encode(spec));

      final List<String> calledUrls = <String>[];
      final APIHubClient client = APIHubClient(
        accessToken: 'token-1',
        requestExecutor:
            ({
              required Uri uri,
              required String method,
              required Map<String, String> headers,
            }) async {
              calledUrls.add(uri.toString());
              expect(method, 'GET');
              expect(
                headers[HttpHeaders.authorizationHeader],
                'Bearer token-1',
              );

              if (uri.toString() ==
                  'https://apihub.googleapis.com/v1/projects/p1/locations/us-central1/apis/my-api') {
                return ApiHubHttpResponse(
                  statusCode: 200,
                  body:
                      '{"versions":["projects/p1/locations/us-central1/apis/my-api/versions/v1"]}',
                );
              }
              if (uri.toString() ==
                  'https://apihub.googleapis.com/v1/projects/p1/locations/us-central1/apis/my-api/versions/v1') {
                return ApiHubHttpResponse(
                  statusCode: 200,
                  body:
                      '{"specs":["projects/p1/locations/us-central1/apis/my-api/versions/v1/specs/spec1"]}',
                );
              }
              if (uri.toString() ==
                  'https://apihub.googleapis.com/v1/projects/p1/locations/us-central1/apis/my-api/versions/v1/specs/spec1:contents') {
                return ApiHubHttpResponse(
                  statusCode: 200,
                  body: '{"contents":"$encodedSpec"}',
                );
              }
              throw StateError('Unexpected URL: $uri');
            },
      );

      final String loaded = await client.getSpecContent(
        'projects/p1/locations/us-central1/apis/my-api',
      );

      expect(loaded, contains('openapi: 3.0.1'));
      expect(calledUrls, <String>[
        'https://apihub.googleapis.com/v1/projects/p1/locations/us-central1/apis/my-api',
        'https://apihub.googleapis.com/v1/projects/p1/locations/us-central1/apis/my-api/versions/v1',
        'https://apihub.googleapis.com/v1/projects/p1/locations/us-central1/apis/my-api/versions/v1/specs/spec1:contents',
      ]);
    });

    test('accepts UI URL with explicit spec path', () async {
      final String spec = '{"openapi":"3.0.1","info":{"title":"UI API"}}';
      final String encodedSpec = base64Encode(utf8.encode(spec));

      final List<String> calledUrls = <String>[];
      final APIHubClient client = APIHubClient(
        accessToken: 'token-2',
        requestExecutor:
            ({
              required Uri uri,
              required String method,
              required Map<String, String> headers,
            }) async {
              calledUrls.add(uri.toString());
              expect(method, 'GET');
              expect(
                headers[HttpHeaders.authorizationHeader],
                'Bearer token-2',
              );
              return ApiHubHttpResponse(
                statusCode: 200,
                body: '{"contents":"$encodedSpec"}',
              );
            },
      );

      final String loaded = await client.getSpecContent(
        'https://console.cloud.google.com/apigee/api-hub/projects/p1/locations/us-central1/apis/my-api/versions/v1/specs/spec1?project=p1',
      );

      expect(loaded, contains('UI API'));
      expect(calledUrls, <String>[
        'https://apihub.googleapis.com/v1/projects/p1/locations/us-central1/apis/my-api/versions/v1/specs/spec1:contents',
      ]);
    });

    test('extractResourceName validates required location and api id', () {
      final APIHubClient client = APIHubClient(accessToken: 'token');

      expect(
        () => client.extractResourceName('projects/p1/apis/my-api'),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError error) => '${error.message}',
            'message',
            contains('Location not found'),
          ),
        ),
      );

      expect(
        () => client.extractResourceName('projects/p1/locations/us-central1'),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError error) => '${error.message}',
            'message',
            contains('API id not found'),
          ),
        ),
      );
    });
  });

  group('APIHubToolset parity', () {
    const String specJson =
        '{"openapi":"3.0.1","info":{"title":"Sample API Hub","description":"sample spec"},"paths":{"/events":{"get":{"operationId":"listEvents","description":"List events","responses":{"200":{"description":"ok"}}}}}}';

    test('eager load parses spec and creates tools', () async {
      final _FakeApiHubClient fakeClient = _FakeApiHubClient(specJson);
      final APIHubToolset toolset = APIHubToolset(
        apihubResourceName: 'projects/p1/locations/us-central1/apis/my-api',
        apihubClient: fakeClient,
      );

      final List<BaseTool> tools = await toolset.getTools();

      expect(fakeClient.getSpecCallCount, 1);
      expect(
        fakeClient.requestedResourceNames.single,
        contains('/apis/my-api'),
      );
      expect(toolset.name, 'sample_api_hub');
      expect(toolset.description, 'sample spec');
      expect(tools.map((BaseTool tool) => tool.name), contains('list_events'));
    });

    test('lazy loading defers spec fetch until getTools', () async {
      final _FakeApiHubClient fakeClient = _FakeApiHubClient(specJson);
      final APIHubToolset toolset = APIHubToolset(
        apihubResourceName: 'projects/p1/locations/us-central1/apis/my-api',
        apihubClient: fakeClient,
        lazyLoadSpec: true,
      );

      expect(fakeClient.getSpecCallCount, 0);
      final List<BaseTool> tools = await toolset.getTools();
      expect(fakeClient.getSpecCallCount, 1);
      expect(tools.length, 1);
    });

    test('auth config is exposed for toolset level auth flow', () {
      final _FakeApiHubClient fakeClient = _FakeApiHubClient(specJson);
      final APIHubToolset toolset = APIHubToolset(
        apihubResourceName: 'projects/p1/locations/us-central1/apis/my-api',
        apihubClient: fakeClient,
        lazyLoadSpec: true,
        authScheme: SecurityScheme(
          type: AuthSchemeType.http,
          scheme: 'bearer',
          bearerFormat: 'JWT',
        ),
        authCredential: AuthCredential(
          authType: AuthCredentialType.http,
          http: HttpAuth(
            scheme: 'bearer',
            credentials: HttpCredentials(token: 'secret-token'),
          ),
        ),
      );

      final AuthConfig? authConfigA = toolset.getAuthConfig();
      final AuthConfig? authConfigB = toolset.getAuthConfig();

      expect(authConfigA, isNotNull);
      expect(
        authConfigA!.rawAuthCredential?.http?.credentials.token,
        'secret-token',
      );
      expect(identical(authConfigA, authConfigB), isTrue);
    });
  });

  group('SecretManagerClient parity', () {
    test('throws on invalid service account json', () {
      expect(
        () => SecretManagerClient(serviceAccountJson: '{invalid-json}'),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError error) => '${error.message}',
            'message',
            contains('Invalid service account JSON'),
          ),
        ),
      );
    });

    test('delegates secret fetch to configured fetcher', () async {
      setSecretManagerSecretFetcher(({
        required String resourceName,
        String? serviceAccountJson,
        String? authToken,
      }) async {
        expect(resourceName, 'projects/p/secrets/s/versions/latest');
        expect(authToken, 'token-3');
        expect(serviceAccountJson, isNull);
        return 'my-secret';
      });

      final SecretManagerClient client = SecretManagerClient(
        authToken: 'token-3',
      );
      final String value = await client.getSecret(
        'projects/p/secrets/s/versions/latest',
      );

      expect(value, 'my-secret');
    });

    test('resolves token from service account json before fetch', () async {
      setSecretManagerSecretFetcher(({
        required String resourceName,
        String? serviceAccountJson,
        String? authToken,
      }) async {
        expect(resourceName, 'projects/p/secrets/s/versions/latest');
        expect(authToken, 'token-from-service-account');
        expect(serviceAccountJson, contains('access_token'));
        return 'my-secret';
      });

      final SecretManagerClient client = SecretManagerClient(
        serviceAccountJson: '{"access_token":"token-from-service-account"}',
      );
      final String value = await client.getSecret(
        'projects/p/secrets/s/versions/latest',
      );

      expect(value, 'my-secret');
    });

    test('auth token takes precedence over service account embedded token', () async {
      setSecretManagerSecretFetcher(({
        required String resourceName,
        String? serviceAccountJson,
        String? authToken,
      }) async {
        expect(authToken, 'token-from-auth-arg');
        return 'my-secret';
      });

      final SecretManagerClient client = SecretManagerClient(
        serviceAccountJson: '{"access_token":"token-from-service-account"}',
        authToken: 'token-from-auth-arg',
      );
      final String value = await client.getSecret(
        'projects/p/secrets/s/versions/latest',
      );
      expect(value, 'my-secret');
    });
  });
}
