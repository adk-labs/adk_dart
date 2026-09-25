import 'dart:convert';
import 'dart:io';

import 'package:adk/src/cli/adk_web_server.dart';
import 'package:adk/src/dev/project.dart';
import 'package:test/test.dart';

void main() {
  group('AdkWebServer', () {
    test('starts from an existing directory without adk.json', () async {
      final Directory temp = Directory.systemTemp.createTempSync(
        'adk_web_no_config_',
      );
      addTearDown(() => temp.deleteSync(recursive: true));

      final AdkWebServer server = AdkWebServer(
        agentsDir: temp.path,
        port: 0,
        host: '127.0.0.1',
      );
      final HttpServer httpServer = await server.start();
      addTearDown(server.stop);

      final HttpClient client = HttpClient();
      final Uri uri = Uri.parse(
        'http://${httpServer.address.address}:${httpServer.port}/health',
      );
      final HttpClientRequest request = await client.getUrl(uri);
      final HttpClientResponse response = await request.close();
      final String body = await utf8.decoder.bind(response).join();

      expect(response.statusCode, HttpStatus.ok);
      expect(body, contains('"status":"ok"'));
      client.close(force: true);
    });

    test('throws when agents directory does not exist', () async {
      final String missingPath =
          '${Directory.systemTemp.path}${Platform.pathSeparator}'
          'adk_web_missing_${DateTime.now().microsecondsSinceEpoch}';
      final AdkWebServer server = AdkWebServer(
        agentsDir: missingPath,
        port: 0,
        host: '127.0.0.1',
      );

      await expectLater(
        server.start(),
        throwsA(
          isA<FileSystemException>().having(
            (FileSystemException error) => error.message,
            'message',
            contains('Project directory does not exist.'),
          ),
        ),
      );
    });

    test('starts and responds to health endpoint', () async {
      final Directory temp = Directory.systemTemp.createTempSync('adk_web_');
      addTearDown(() => temp.deleteSync(recursive: true));

      await createDevProject(projectDirPath: temp.path, appName: 'my_agent');

      final AdkWebServer server = AdkWebServer(
        agentsDir: temp.path,
        port: 0,
        host: '127.0.0.1',
      );
      final HttpServer httpServer = await server.start();
      addTearDown(server.stop);

      final HttpClient client = HttpClient();
      final Uri uri = Uri.parse(
        'http://${httpServer.address.address}:${httpServer.port}/health',
      );
      final HttpClientRequest request = await client.getUrl(uri);
      final HttpClientResponse response = await request.close();
      final String body = await utf8.decoder.bind(response).join();

      expect(response.statusCode, HttpStatus.ok);
      expect(body, contains('"status":"ok"'));

      final HttpClientRequest configRequest = await client.getUrl(
        Uri.parse(
          'http://${httpServer.address.address}:${httpServer.port}/dev-ui/config',
        ),
      );
      final HttpClientResponse configResponse = await configRequest.close();
      final String configBody = await utf8.decoder.bind(configResponse).join();

      expect(configResponse.statusCode, HttpStatus.ok);
      expect(configBody, contains('logo_text'));
      client.close(force: true);
    });

    test('rejects half-specified logo with ArgumentError', () async {
      final Directory temp = Directory.systemTemp.createTempSync(
        'adk_web_logo_err_',
      );
      addTearDown(() => temp.deleteSync(recursive: true));
      await createDevProject(projectDirPath: temp.path, appName: 'logo_agent');

      final AdkWebServer server = AdkWebServer(
        agentsDir: temp.path,
        port: 0,
        host: '127.0.0.1',
        logoText: 'ACME',
      );
      await expectLater(
        server.start(),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError e) => e.message,
            'message',
            contains('Both --logo-text and --logo-image-url must be defined'),
          ),
        ),
      );
    });

    test(
      'serves dynamic runtime-config.json with Cache-Control no-store and logo',
      () async {
        final Directory temp = Directory.systemTemp.createTempSync(
          'adk_web_config_',
        );
        addTearDown(() => temp.deleteSync(recursive: true));
        await createDevProject(
          projectDirPath: temp.path,
          appName: 'config_agent',
        );

        final AdkWebServer server = AdkWebServer(
          agentsDir: temp.path,
          port: 0,
          host: '127.0.0.1',
          urlPrefix: '/custom',
          logoText: 'ACME Corp',
          logoImageUrl: 'https://example.com/logo.png',
        );
        final HttpServer httpServer = await server.start();
        addTearDown(server.stop);

        final HttpClient client = HttpClient();
        final HttpClientRequest request = await client.getUrl(
          Uri.parse(
            'http://${httpServer.address.address}:${httpServer.port}/custom/dev-ui/assets/config/runtime-config.json',
          ),
        );
        final HttpClientResponse response = await request.close();
        final String body = await utf8.decoder.bind(response).join();
        client.close(force: true);

        expect(response.statusCode, HttpStatus.ok);
        expect(response.headers.value('cache-control'), 'no-store');
        final Map<String, dynamic> json =
            jsonDecode(body) as Map<String, dynamic>;
        expect(json['backendUrl'], '/custom');
        expect(json.containsKey('telemetry'), isTrue);
        expect(json['logo'], <String, dynamic>{
          'text': 'ACME Corp',
          'imageUrl': 'https://example.com/logo.png',
        });
      },
    );
  });
}
