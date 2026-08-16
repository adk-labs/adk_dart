import 'dart:convert';
import 'dart:io';

import 'package:adk_dart/src/dev/project.dart';
import 'package:adk_dart/src/dev/runtime.dart';
import 'package:adk_dart/src/dev/web_server.dart';
import 'package:adk_dart/src/utils/telemetry_config.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

void main() {
  group('Telemetry config and dev server endpoint', () {
    late Directory tempDir;
    late File configFile;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('adk_telemetry_test_');
      configFile = File('${tempDir.path}/config.json');
    });

    tearDown(() {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('readTelemetryConsent and writeTelemetryConsent persist boolean preference', () {
      expect(readTelemetryConsent(configFile: configFile), isNull);

      writeTelemetryConsent(true, configFile: configFile);
      expect(readTelemetryConsent(configFile: configFile), isTrue);

      writeTelemetryConsent(false, configFile: configFile);
      expect(readTelemetryConsent(configFile: configFile), isFalse);
    });

    test('startAdkDevWebServer handles GET and POST /config/telemetry with CSRF header check', () async {
      const config = DevProjectConfig(
        appName: 'test_app',
        agentName: 'root_agent',
        description: 'test',
      );
      final runtime = DevAgentRuntime(config: config);
      final server = await startAdkDevWebServer(
        runtime: runtime,
        project: config,
        port: 0,
      );

      try {
        final client = http.Client();
        final baseUrl = 'http://127.0.0.1:${server.port}';

        // 1. GET /config/telemetry
        final getResp = await client.get(Uri.parse('$baseUrl/config/telemetry'));
        expect(getResp.statusCode, equals(200));
        final Map<String, Object?> getBody = jsonDecode(getResp.body) as Map<String, Object?>;
        expect(getBody.containsKey('telemetry'), isTrue);

        // 2. POST /config/telemetry without header should be 403 Forbidden
        final postNoHeaderResp = await client.post(
          Uri.parse('$baseUrl/config/telemetry'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({'telemetry': true}),
        );
        expect(postNoHeaderResp.statusCode, equals(403));

        // 3. POST /config/telemetry with header
        final postWithHeaderResp = await client.post(
          Uri.parse('$baseUrl/config/telemetry'),
          headers: {
            'content-type': 'application/json',
            'x-adk-telemetry-request': 'true',
          },
          body: jsonEncode({'telemetry': true}),
        );
        expect(postWithHeaderResp.statusCode, equals(200));
        final Map<String, Object?> postBody = jsonDecode(postWithHeaderResp.body) as Map<String, Object?>;
        expect(postBody['telemetry'], isTrue);
      } finally {
        await server.close(force: true);
        await runtime.runner.close();
      }
    });
  });
}
