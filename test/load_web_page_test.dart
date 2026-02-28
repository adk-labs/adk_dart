import 'dart:io';

import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

void main() {
  group('loadWebPage', () {
    test('returns HTTP status details for non-200 responses', () async {
      final HttpServer server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(() async => server.close(force: true));
      server.listen((HttpRequest request) {
        request.response
          ..statusCode = HttpStatus.notFound
          ..write('missing');
        request.response.close();
      });

      final String text = await loadWebPage(
        'http://${server.address.host}:${server.port}/missing',
      );
      expect(text, contains('HTTP 404'));
      expect(text, contains('Failed to fetch URL'));
    });

    test('returns timeout details when request takes too long', () async {
      final HttpServer server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(() async => server.close(force: true));
      server.listen((HttpRequest request) async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.html
          ..write(
            '<html><body>slow but valid response line with many words.</body></html>',
          );
        await request.response.close();
      });

      final String text = await loadWebPage(
        'http://${server.address.host}:${server.port}/slow',
        timeout: const Duration(milliseconds: 50),
      );
      expect(text, contains('timed out after 50ms'));
    });

    test('returns failure when response exceeds maxResponseBytes', () async {
      final HttpServer server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(() async => server.close(force: true));
      server.listen((HttpRequest request) {
        final String payload =
            '<html><body>${List<String>.filled(300, 'word').join(' ')}</body></html>';
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.html
          ..write(payload);
        request.response.close();
      });

      final String text = await loadWebPage(
        'http://${server.address.host}:${server.port}/large',
        maxResponseBytes: 128,
      );
      expect(text, contains('response exceeded 128 bytes'));
    });
  });
}
