import 'dart:convert';
import 'dart:io';

import 'package:adk_dart/adk_dart.dart';
import 'package:adk_dart/src/dev/project.dart';
import 'package:test/test.dart';

void main() {
  group('AdkWebServer', () {
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
      client.close(force: true);

      expect(response.statusCode, HttpStatus.ok);
      expect(body, contains('"status":"ok"'));
    });
  });
}
