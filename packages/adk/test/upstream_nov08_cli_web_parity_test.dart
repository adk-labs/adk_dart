import 'dart:convert';
import 'dart:io';

import 'package:adk/adk.dart';
import 'package:test/test.dart';

Future<({int statusCode, String body})> _sendRequest({
  required int port,
  required String method,
  required String path,
  Object? jsonBody,
}) async {
  final HttpClient client = HttpClient();
  try {
    final Uri uri = Uri.parse('http://127.0.0.1:$port$path');
    final HttpClientRequest request = await client.openUrl(method, uri);
    if (jsonBody != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(jsonBody));
    }
    final HttpClientResponse response = await request.close();
    final String body = await utf8.decoder.bind(response).join();
    return (statusCode: response.statusCode, body: body);
  } finally {
    client.close(force: true);
  }
}

void main() {
  group('DevServer / ApiServer unconfigured eval managers (bd4389766)', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('adk_cli_eval_mgr_test_');
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('returns 500 when eval_sets_manager is not configured across all eval-set routes', () async {
      final DevProjectConfig project = DevProjectConfig(
        appName: 'test_app',
        agentName: 'root_agent',
        description: 'Test app',
      );
      final DevAgentRuntime runtime = DevAgentRuntime(config: project);
      final HttpServer server = await startAdkDevWebServer(
        runtime: runtime,
        project: project,
        agentsDir: tempDir.path,
        port: 0,
        enableWebUi: false,
        evalSetsManager: null,
      );
      addTearDown(() async {
        await server.close(force: true);
        await runtime.runner.close();
      });

      final List<(String, String, Object?)> cases = <(String, String, Object?)>[
        ('POST', '/dev/apps/test_app/eval-sets', <String, Object?>{'eval_set': <String, Object?>{'eval_set_id': 's'}}),
        ('POST', '/apps/test_app/eval_sets/s', null),
        ('GET', '/dev/apps/test_app/eval-sets', null),
        ('POST', '/dev/apps/test_app/eval-sets/s/add-session', <String, Object?>{'eval_id': 'e', 'session_id': 'sess', 'user_id': 'u'}),
        ('GET', '/apps/test_app/eval_sets/s/evals', null),
        ('GET', '/dev/apps/test_app/eval-sets/s/eval-cases/e', null),
        ('PUT', '/dev/apps/test_app/eval-sets/s/eval-cases/e', <String, Object?>{'eval_id': 'e', 'conversation': <Object?>[]}),
        ('DELETE', '/dev/apps/test_app/eval-sets/s/eval-cases/e', null),
        ('POST', '/dev/apps/test_app/eval-sets/s/run', <String, Object?>{'eval_ids': <Object?>[], 'eval_metrics': <Object?>[]}),
      ];

      for (final (String method, String path, Object? body) in cases) {
        final ({int statusCode, String body}) res = await _sendRequest(
          port: server.port,
          method: method,
          path: path,
          jsonBody: body,
        );
        expect(
          res.statusCode,
          HttpStatus.internalServerError,
          reason: 'Expected 500 for $method $path, got ${res.statusCode}: ${res.body}',
        );
        final Map<String, Object?> decoded =
            (jsonDecode(res.body) as Map).cast<String, Object?>();
        expect(decoded['detail'], 'Eval sets manager is not configured');
      }
    });

    test('returns 500 when eval_set_results_manager is not configured across eval-result routes', () async {
      final DevProjectConfig project = DevProjectConfig(
        appName: 'test_app',
        agentName: 'root_agent',
        description: 'Test app',
      );
      final DevAgentRuntime runtime = DevAgentRuntime(config: project);
      final HttpServer server = await startAdkDevWebServer(
        runtime: runtime,
        project: project,
        agentsDir: tempDir.path,
        port: 0,
        enableWebUi: false,
        evalSetResultsManager: null,
      );
      addTearDown(() async {
        await server.close(force: true);
        await runtime.runner.close();
      });

      const List<String> paths = <String>[
        '/dev/apps/test_app/eval-results/r',
        '/apps/test_app/eval_results/r',
        '/dev/apps/test_app/eval-results',
        '/apps/test_app/eval_results',
      ];

      for (final String path in paths) {
        final ({int statusCode, String body}) res = await _sendRequest(
          port: server.port,
          method: 'GET',
          path: path,
        );
        expect(
          res.statusCode,
          HttpStatus.internalServerError,
          reason: 'Expected 500 for GET $path, got ${res.statusCode}: ${res.body}',
        );
        final Map<String, Object?> decoded =
            (jsonDecode(res.body) as Map).cast<String, Object?>();
        expect(decoded['detail'], 'Eval set results manager is not configured');
      }
    });

    test('run_eval succeeds when eval_set_results_manager is null', () async {
      final InMemoryEvalSetsManager evalSetsManager = InMemoryEvalSetsManager();
      await evalSetsManager.createEvalSet('test_app', 's');

      final DevProjectConfig project = DevProjectConfig(
        appName: 'test_app',
        agentName: 'root_agent',
        description: 'Test app',
      );
      final DevAgentRuntime runtime = DevAgentRuntime(config: project);
      final HttpServer server = await startAdkDevWebServer(
        runtime: runtime,
        project: project,
        agentsDir: tempDir.path,
        port: 0,
        enableWebUi: false,
        evalSetsManager: evalSetsManager,
        evalSetResultsManager: null,
      );
      addTearDown(() async {
        await server.close(force: true);
        await runtime.runner.close();
      });

      final ({int statusCode, String body}) res = await _sendRequest(
        port: server.port,
        method: 'POST',
        path: '/dev/apps/test_app/eval-sets/s/run',
        jsonBody: <String, Object?>{
          'eval_ids': <Object?>[],
          'eval_metrics': <Object?>[],
        },
      );
      expect(res.statusCode, HttpStatus.ok);
      final Map<String, Object?> decoded =
          (jsonDecode(res.body) as Map).cast<String, Object?>();
      expect(decoded['run_eval_results'], isEmpty);
    });
  });

  group('ADK Web ContentBubbleComponent.getTextContent UTF-8 decoding (26c1a9e)', () {
    test('decodeDataUrlTextContentUtf8 decodes multibyte UTF-8 text without garbling', () {
      const String text = 'こんにちは 🌙 报告';
      final String encoded = base64Encode(utf8.encode(text));
      final String dataUrl = 'data:text/plain;base64,$encoded';

      expect(decodeDataUrlTextContentUtf8(dataUrl), text);
    });

    test('decodeDataUrlTextContentUtf8 handles empty input, missing comma, and invalid base64', () {
      expect(decodeDataUrlTextContentUtf8(''), '');
      expect(decodeDataUrlTextContentUtf8(null), '');
      expect(decodeDataUrlTextContentUtf8('data:text/plain;base64'), '');
      expect(
        decodeDataUrlTextContentUtf8('data:text/plain;base64,!!!not-base64!!!'),
        'Failed to decode text content',
      );
    });

    test('bundled browser main-TXG3WSWW.js uses TextDecoder("utf-8") in getTextContent', () {
      final File bundleFile = File('lib/src/cli/browser/main-TXG3WSWW.js');
      expect(bundleFile.existsSync(), isTrue);
      final String content = bundleFile.readAsStringSync();
      expect(
        content,
        contains(
          'getTextContent(t){if(!t)return"";let e=t.indexOf(",");if(e===-1)return"";let i=t.substring(e+1);try{let r=Uint8Array.from(atob(i),o=>o.charCodeAt(0));return new TextDecoder("utf-8").decode(r)}catch(r){return"Failed to decode text content"}}',
        ),
      );
    });
  });
}
