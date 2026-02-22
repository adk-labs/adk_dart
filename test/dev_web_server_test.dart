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

    test('serves index page', () async {
      final HttpClientRequest request = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/'),
      );
      final HttpClientResponse response = await request.close();
      final String body = await utf8.decoder.bind(response).join();

      expect(response.statusCode, HttpStatus.ok);
      expect(body, contains('service: adk_dart_web'));
    });
  });
}
