import 'dart:convert';
import 'dart:io';

import 'package:adk_dart/src/dev/project.dart';
import 'package:adk_dart/src/dev/runtime.dart';
import 'package:adk_dart/src/dev/web_server.dart';
import 'package:test/test.dart';

void main() {
  group('startAdkDevWebServer', () {
    late HttpServer server;
    late HttpClient client;
    late DevAgentRuntime runtime;
    late DevProjectConfig config;

    setUp(() async {
      config = const DevProjectConfig(
        appName: 'test_app',
        agentName: 'root_agent',
        description: 'test',
      );
      runtime = DevAgentRuntime(config: config);
      server = await startAdkDevWebServer(
        runtime: runtime,
        project: config,
        port: 0,
      );
      client = HttpClient();
    });

    tearDown(() async {
      client.close(force: true);
      await server.close(force: true);
      await runtime.runner.close();
    });

    test('serves health endpoint', () async {
      final HttpClientRequest request = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/health'),
      );
      final HttpClientResponse response = await request.close();
      final String body = await utf8.decoder.bind(response).join();

      expect(response.statusCode, HttpStatus.ok);
      expect(jsonDecode(body), <String, Object>{
        'status': 'ok',
        'service': 'adk_dart_web',
        'appName': 'test_app',
      });
    });

    test('creates a session and sends a message', () async {
      final HttpClientRequest createSessionRequest = await client.postUrl(
        Uri.parse('http://127.0.0.1:${server.port}/api/sessions'),
      );
      createSessionRequest.headers.contentType = ContentType.json;
      createSessionRequest.write(jsonEncode(<String, Object>{'userId': 'u1'}));

      final HttpClientResponse createSessionResponse =
          await createSessionRequest.close();
      final String createBody = await utf8.decoder
          .bind(createSessionResponse)
          .join();
      final Map<String, dynamic> createPayload =
          jsonDecode(createBody) as Map<String, dynamic>;
      final String sessionId =
          (createPayload['session'] as Map<String, dynamic>)['id'] as String;

      final HttpClientRequest messageRequest = await client.postUrl(
        Uri.parse(
          'http://127.0.0.1:${server.port}/api/sessions/$sessionId/messages',
        ),
      );
      messageRequest.headers.contentType = ContentType.json;
      messageRequest.write(
        jsonEncode(<String, Object>{
          'userId': 'u1',
          'text': 'What time in Seoul?',
        }),
      );
      final HttpClientResponse messageResponse = await messageRequest.close();
      final String messageBody = await utf8.decoder
          .bind(messageResponse)
          .join();
      final Map<String, dynamic> payload =
          jsonDecode(messageBody) as Map<String, dynamic>;

      expect(messageResponse.statusCode, HttpStatus.ok);
      expect(payload['reply'], contains('The current time in'));
    });

    test('serves list-apps endpoint', () async {
      final HttpClientRequest request = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/list-apps?detailed=true'),
      );
      final HttpClientResponse response = await request.close();
      final String body = await utf8.decoder.bind(response).join();
      final Map<String, dynamic> payload =
          jsonDecode(body) as Map<String, dynamic>;
      final List<dynamic> apps = payload['apps'] as List<dynamic>;

      expect(response.statusCode, HttpStatus.ok);
      expect(
        apps.any(
          (dynamic app) => (app as Map<String, dynamic>)['name'] == 'test_app',
        ),
        isTrue,
      );
    });

    test('runs agent via /run endpoint', () async {
      final String sessionId = 's_run_${DateTime.now().microsecondsSinceEpoch}';
      final HttpClientRequest createRequest = await client.postUrl(
        Uri.parse(
          'http://127.0.0.1:${server.port}/apps/test_app/users/u1/sessions',
        ),
      );
      createRequest.headers.contentType = ContentType.json;
      createRequest.write(
        jsonEncode(<String, Object>{'session_id': sessionId}),
      );
      final HttpClientResponse createResponse = await createRequest.close();
      await utf8.decoder.bind(createResponse).join();
      expect(createResponse.statusCode, HttpStatus.ok);

      final HttpClientRequest runRequest = await client.postUrl(
        Uri.parse('http://127.0.0.1:${server.port}/run'),
      );
      runRequest.headers.contentType = ContentType.json;
      runRequest.write(
        jsonEncode(<String, Object>{
          'app_name': 'test_app',
          'user_id': 'u1',
          'session_id': sessionId,
          'new_message': <String, Object>{
            'role': 'user',
            'parts': <Object>[
              <String, Object>{'text': 'What time in Seoul?'},
            ],
          },
        }),
      );

      final HttpClientResponse runResponse = await runRequest.close();
      final String runBody = await utf8.decoder.bind(runResponse).join();
      final List<dynamic> events = jsonDecode(runBody) as List<dynamic>;

      expect(runResponse.statusCode, HttpStatus.ok);
      expect(events, isNotEmpty);
    });

    test('streams events via /run_sse endpoint', () async {
      final String sessionId = 's_sse_${DateTime.now().microsecondsSinceEpoch}';
      final HttpClientRequest createRequest = await client.postUrl(
        Uri.parse(
          'http://127.0.0.1:${server.port}/apps/test_app/users/u1/sessions',
        ),
      );
      createRequest.headers.contentType = ContentType.json;
      createRequest.write(
        jsonEncode(<String, Object>{'session_id': sessionId}),
      );
      final HttpClientResponse createResponse = await createRequest.close();
      await utf8.decoder.bind(createResponse).join();
      expect(createResponse.statusCode, HttpStatus.ok);

      final HttpClientRequest sseRequest = await client.postUrl(
        Uri.parse('http://127.0.0.1:${server.port}/run_sse'),
      );
      sseRequest.headers.contentType = ContentType.json;
      sseRequest.write(
        jsonEncode(<String, Object>{
          'app_name': 'test_app',
          'user_id': 'u1',
          'session_id': sessionId,
          'streaming': true,
          'new_message': <String, Object>{
            'role': 'user',
            'parts': <Object>[
              <String, Object>{'text': 'What time in Tokyo?'},
            ],
          },
        }),
      );

      final HttpClientResponse sseResponse = await sseRequest.close();
      final String sseBody = await utf8.decoder.bind(sseResponse).join();

      expect(sseResponse.statusCode, HttpStatus.ok);
      expect(
        sseResponse.headers.contentType?.mimeType,
        ContentType('text', 'event-stream').mimeType,
      );
      expect(sseBody, contains('data: '));
    });

    test('lists empty artifact names', () async {
      final String sessionId = 's_art_${DateTime.now().microsecondsSinceEpoch}';
      final HttpClientRequest createRequest = await client.postUrl(
        Uri.parse(
          'http://127.0.0.1:${server.port}/apps/test_app/users/u1/sessions',
        ),
      );
      createRequest.headers.contentType = ContentType.json;
      createRequest.write(
        jsonEncode(<String, Object>{'session_id': sessionId}),
      );
      final HttpClientResponse createResponse = await createRequest.close();
      await utf8.decoder.bind(createResponse).join();
      expect(createResponse.statusCode, HttpStatus.ok);

      final HttpClientRequest listRequest = await client.getUrl(
        Uri.parse(
          'http://127.0.0.1:${server.port}/apps/test_app/users/u1/sessions/$sessionId/artifacts',
        ),
      );
      final HttpClientResponse listResponse = await listRequest.close();
      final String listBody = await utf8.decoder.bind(listResponse).join();
      final List<dynamic> artifacts = jsonDecode(listBody) as List<dynamic>;

      expect(listResponse.statusCode, HttpStatus.ok);
      expect(artifacts, isEmpty);
    });

    test('serves index page', () async {
      final HttpClientRequest request = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/'),
      );
      final HttpClientResponse response = await request.close();
      final String body = await utf8.decoder.bind(response).join();

      expect(response.statusCode, HttpStatus.ok);
      expect(body, contains('Agent Development Kit Dev UI'));
    });

    test('supports url_prefix routing', () async {
      final DevAgentRuntime prefixedRuntime = DevAgentRuntime(config: config);
      final HttpServer prefixedServer = await startAdkDevWebServer(
        runtime: prefixedRuntime,
        project: config,
        port: 0,
        urlPrefix: '/adk',
      );
      addTearDown(() async {
        await prefixedServer.close(force: true);
        await prefixedRuntime.runner.close();
      });

      final HttpClient prefixedClient = HttpClient();
      addTearDown(() => prefixedClient.close(force: true));

      final HttpClientRequest prefixedRequest = await prefixedClient.getUrl(
        Uri.parse('http://127.0.0.1:${prefixedServer.port}/adk/health'),
      );
      final HttpClientResponse prefixedResponse = await prefixedRequest.close();
      final String prefixedBody = await utf8.decoder
          .bind(prefixedResponse)
          .join();

      final HttpClientRequest bareRequest = await prefixedClient.getUrl(
        Uri.parse('http://127.0.0.1:${prefixedServer.port}/health'),
      );
      final HttpClientResponse bareResponse = await bareRequest.close();
      await utf8.decoder.bind(bareResponse).join();

      expect(prefixedResponse.statusCode, HttpStatus.ok);
      expect(prefixedBody, contains('"status":"ok"'));
      expect(bareResponse.statusCode, HttpStatus.notFound);
    });

    test('applies CORS allow list', () async {
      final DevAgentRuntime corsRuntime = DevAgentRuntime(config: config);
      final HttpServer corsServer = await startAdkDevWebServer(
        runtime: corsRuntime,
        project: config,
        port: 0,
        allowOrigins: const <String>['https://example.com'],
      );
      addTearDown(() async {
        await corsServer.close(force: true);
        await corsRuntime.runner.close();
      });

      final HttpClient corsClient = HttpClient();
      addTearDown(() => corsClient.close(force: true));

      final HttpClientRequest allowedRequest = await corsClient.getUrl(
        Uri.parse('http://127.0.0.1:${corsServer.port}/health'),
      );
      allowedRequest.headers.set('origin', 'https://example.com');
      final HttpClientResponse allowedResponse = await allowedRequest.close();
      await utf8.decoder.bind(allowedResponse).join();

      final HttpClientRequest deniedRequest = await corsClient.getUrl(
        Uri.parse('http://127.0.0.1:${corsServer.port}/health'),
      );
      deniedRequest.headers.set('origin', 'https://denied.example.com');
      final HttpClientResponse deniedResponse = await deniedRequest.close();
      await utf8.decoder.bind(deniedResponse).join();

      expect(
        allowedResponse.headers.value('access-control-allow-origin'),
        'https://example.com',
      );
      expect(
        deniedResponse.headers.value('access-control-allow-origin'),
        isNull,
      );
    });

    test('supports run_live websocket stream', () async {
      final String sessionId =
          's_live_${DateTime.now().microsecondsSinceEpoch}';
      final HttpClientRequest createRequest = await client.postUrl(
        Uri.parse(
          'http://127.0.0.1:${server.port}/apps/test_app/users/u1/sessions',
        ),
      );
      createRequest.headers.contentType = ContentType.json;
      createRequest.write(
        jsonEncode(<String, Object>{'session_id': sessionId}),
      );
      final HttpClientResponse createResponse = await createRequest.close();
      await utf8.decoder.bind(createResponse).join();
      expect(createResponse.statusCode, HttpStatus.ok);

      final WebSocket socket = await WebSocket.connect(
        'ws://127.0.0.1:${server.port}/run_live?app_name=test_app&user_id=u1&session_id=$sessionId',
      );
      addTearDown(() async {
        await socket.close();
      });

      socket.add(
        jsonEncode(<String, Object>{
          'content': <String, Object>{
            'role': 'user',
            'parts': <Object>[
              <String, Object>{'text': 'What time in Seoul?'},
            ],
          },
        }),
      );

      final dynamic firstMessage = await socket.first.timeout(
        const Duration(seconds: 5),
      );
      expect(firstMessage, isA<String>());
      final Map<String, dynamic> payload =
          jsonDecode(firstMessage as String) as Map<String, dynamic>;
      expect(payload['author'], isNotNull);
    });
  });
}
