import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:adk/adk.dart';
import 'package:test/test.dart';

class _DynamicEchoModel extends BaseLlm {
  _DynamicEchoModel({required this.prefix, super.model = 'fake-echo-model'});

  String prefix;

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    String lastUserText = '';
    for (final Content c in request.contents) {
      if (c.role == 'user') {
        for (final Part p in c.parts) {
          if (p.text != null && p.text!.isNotEmpty) {
            lastUserText = p.text!;
          }
        }
      }
    }
    if (stream) {
      yield LlmResponse(
        content: Content.modelText('$prefix: '),
        partial: true,
        turnComplete: false,
      );
      yield LlmResponse(
        content: Content.modelText('$prefix: $lastUserText'),
        partial: false,
        turnComplete: true,
      );
      return;
    }
    yield LlmResponse(
      content: Content.modelText('$prefix: $lastUserText'),
      turnComplete: true,
    );
  }
}

class _MapAgentLoader extends BaseAgentLoader {
  _MapAgentLoader(this._entries);

  final Map<String, AgentOrApp> _entries;

  @override
  AgentOrApp loadAgent(String agentName) {
    final AgentOrApp? found = _entries[agentName];
    if (found == null) {
      throw ArgumentError('Agent not found: $agentName');
    }
    return found;
  }

  @override
  List<String> listAgents() => _entries.keys.toList(growable: false);
}

class _HttpTestResponse {
  const _HttpTestResponse({
    required this.statusCode,
    required this.body,
    required this.headers,
    required this.chunks,
  });

  final int statusCode;
  final String body;
  final Map<String, String> headers;
  final List<String> chunks;
}

Future<_HttpTestResponse> _sendHttp({
  required int port,
  required String method,
  required String rawPathAndQuery,
  Object? jsonBody,
  List<int>? rawBytes,
  String? contentType,
  Map<String, String>? headers,
}) async {
  final HttpClient client = HttpClient();
  try {
    final Uri uri = Uri.parse('http://127.0.0.1:$port$rawPathAndQuery');
    final HttpClientRequest request = await client.openUrl(method, uri);
    headers?.forEach(request.headers.set);
    if (contentType != null) {
      request.headers.set(HttpHeaders.contentTypeHeader, contentType);
    }
    if (rawBytes != null) {
      request.add(rawBytes);
    } else if (jsonBody != null) {
      if (contentType == null) {
        request.headers.contentType = ContentType.json;
      }
      request.add(utf8.encode(jsonEncode(jsonBody)));
    }
    final HttpClientResponse response = await request.close();
    final Map<String, String> respHeaders = <String, String>{};
    response.headers.forEach((String name, List<String> values) {
      if (values.isNotEmpty) {
        respHeaders[name.toLowerCase()] = values.join(', ');
      }
    });
    final List<String> chunks = <String>[];
    await for (final String chunk in response.transform(utf8.decoder)) {
      chunks.add(chunk);
    }
    return _HttpTestResponse(
      statusCode: response.statusCode,
      body: chunks.join(),
      headers: respHeaders,
      chunks: chunks,
    );
  } finally {
    client.close(force: true);
  }
}

void main() {
  tearDown(() {
    isLocalAgentBuilderClientTestingOverride = null;
    devTestRunnerProcessStarterTestingOverride = null;
  });

  group('1. Visual Agent Builder Routes removed (c890aa317) - return 404 while YAML loading works', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('adk_nov15_builder_');
      final Directory appDir = Directory('${tempDir.path}/my_app')
        ..createSync(recursive: true);
      File('${appDir.path}/root_agent.yaml').writeAsStringSync(
        'name: my_app\n'
        'model: gemini-2.5-flash\n'
        'description: Original description\n'
        'instruction: Be helpful.\n',
      );
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('GET/POST builder routes return 404 on DevServer and ApiServer while YAML app-info remains functional', () async {
      final AdkDevServer devServer = AdkDevServer(
        agentsDir: tempDir.path,
        port: 0,
      );
      final HttpServer server = await devServer.start();
      addTearDown(devServer.stop);

      final List<(String, String)> removedRoutes = <(String, String)>[
        ('GET', '/dev/apps/my_app/builder'),
        ('GET', '/dev/apps/my_app/builder?tmp=true'),
        ('GET', '/dev/apps/my_app/builder/sub/helper.yaml'),
        ('POST', '/dev/apps/my_app/builder/save'),
        ('POST', '/dev/apps/my_app/builder/save?tmp=true'),
        ('POST', '/dev/apps/my_app/builder/cancel'),
        ('GET', '/builder/app/my_app'),
        ('POST', '/builder/app/my_app/save'),
        ('POST', '/builder/app/my_app/cancel'),
      ];
      for (final (String method, String path) in removedRoutes) {
        final _HttpTestResponse res = await _sendHttp(
          port: server.port,
          method: method,
          rawPathAndQuery: path,
        );
        expect(
          res.statusCode,
          HttpStatus.notFound,
          reason: 'Expected 404 for removed builder route $method $path',
        );
      }

      // Loading agents from root_agent.yaml is unchanged.
      final _HttpTestResponse appInfo = await _sendHttp(
        port: server.port,
        method: 'GET',
        rawPathAndQuery: '/dev/apps/my_app/app-info',
      );
      expect(appInfo.statusCode, HttpStatus.ok);
      expect(appInfo.body, contains('Original description'));
    });
  });

  group('2. Dev UI Replay Tests CRUD & Run Routes (/dev/apps/{app}/tests)', () {
    late Directory tempDir;
    late _DynamicEchoModel echoModel;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('adk_nov15_tests_');
      Directory('${tempDir.path}/echo_app').createSync(recursive: true);
      echoModel = _DynamicEchoModel(prefix: 'v1');
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('GET list, PUT /{test_name}, GET /{test_name}, POST /tests/rebuild, POST /tests/run, and DELETE /{test_name}', () async {
      final LlmAgent agent = LlmAgent(
        name: 'echo_agent',
        model: echoModel,
        instruction: 'Echo user input.',
      );
      final BaseAgentLoader loader = _MapAgentLoader(<String, AgentOrApp>{
        'echo_app': agent,
      });
      final AdkDevServer devServer = AdkDevServer(
        agentsDir: tempDir.path,
        agentLoader: loader,
        port: 0,
      );
      final HttpServer server = await devServer.start();
      addTearDown(devServer.stop);

      // 1. Initially empty test list
      final _HttpTestResponse emptyListRes = await _sendHttp(
        port: server.port,
        method: 'GET',
        rawPathAndQuery: '/dev/apps/echo_app/tests',
      );
      expect(emptyListRes.statusCode, HttpStatus.ok);
      expect(jsonDecode(emptyListRes.body), isEmpty);

      // 2. PUT /dev/apps/echo_app/tests/greeting_case (with session_data + Unicode)
      final Map<String, Object?> initialSessionData = <String, Object?>{
        'id': 'sess_1',
        'app_name': 'echo_app',
        'user_id': 'u1',
        'state': <String, Object?>{'locale': 'ja'},
        'events': <Object?>[
          <String, Object?>{
            'id': 'ev_u1',
            'invocation_id': 'inv_1',
            'author': 'user',
            'content': <String, Object?>{
              'role': 'user',
              'parts': <Object?>[
                <String, Object?>{'text': 'こんにちは'},
              ],
            },
          },
          <String, Object?>{
            'id': 'ev_m1',
            'invocation_id': 'inv_1',
            'author': 'echo_agent',
            'content': <String, Object?>{
              'role': 'model',
              'parts': <Object?>[
                <String, Object?>{'text': 'stale reply'},
              ],
            },
          },
        ],
      };
      final _HttpTestResponse putRes = await _sendHttp(
        port: server.port,
        method: 'PUT',
        rawPathAndQuery: '/dev/apps/echo_app/tests/greeting_case',
        jsonBody: <String, Object?>{'session_data': initialSessionData},
      );
      expect(putRes.statusCode, HttpStatus.ok);
      expect(jsonDecode(putRes.body), <String, Object?>{
        'status': 'success',
        'file': 'greeting_case.json',
      });

      // Verify raw file on disk preserves UTF-8 Unicode without \uXXXX escaping
      final String rawOnDisk = File(
        '${tempDir.path}/echo_app/tests/greeting_case.json',
      ).readAsStringSync();
      expect(rawOnDisk, contains('こんにちは'));

      // 3. Also test PUT from an existing server session via {session_id, user_id}
      await _sendHttp(
        port: server.port,
        method: 'POST',
        rawPathAndQuery: '/apps/echo_app/users/u1/sessions/s_from_server',
        jsonBody: const <String, Object?>{},
      );
      await _sendHttp(
        port: server.port,
        method: 'POST',
        rawPathAndQuery: '/run',
        jsonBody: <String, Object?>{
          'app_name': 'echo_app',
          'user_id': 'u1',
          'session_id': 's_from_server',
          'new_message': <String, Object?>{
            'role': 'user',
            'parts': <Object?>[
              <String, Object?>{'text': 'hello live'},
            ],
          },
        },
      );
      final _HttpTestResponse putFromSessionRes = await _sendHttp(
        port: server.port,
        method: 'PUT',
        rawPathAndQuery: '/dev/apps/echo_app/tests/live_session.json',
        jsonBody: const <String, Object?>{
          'session_id': 's_from_server',
          'user_id': 'u1',
        },
      );
      expect(putFromSessionRes.statusCode, HttpStatus.ok);

      // 4. GET /dev/apps/echo_app/tests lists both sorted .json files
      final _HttpTestResponse listRes = await _sendHttp(
        port: server.port,
        method: 'GET',
        rawPathAndQuery: '/dev/apps/echo_app/tests',
      );
      expect(listRes.statusCode, HttpStatus.ok);
      expect(jsonDecode(listRes.body), <String>[
        'greeting_case.json',
        'live_session.json',
      ]);

      // 5. GET /dev/apps/echo_app/tests/{test_name} (200 & 404)
      final _HttpTestResponse getOneRes = await _sendHttp(
        port: server.port,
        method: 'GET',
        rawPathAndQuery: '/dev/apps/echo_app/tests/greeting_case',
      );
      expect(getOneRes.statusCode, HttpStatus.ok);
      final Map<String, Object?> fetched = Map<String, Object?>.from(
        jsonDecode(getOneRes.body) as Map,
      );
      expect(fetched['id'], 'sess_1');

      final _HttpTestResponse getMissingRes = await _sendHttp(
        port: server.port,
        method: 'GET',
        rawPathAndQuery: '/dev/apps/echo_app/tests/does_not_exist',
      );
      expect(getMissingRes.statusCode, HttpStatus.notFound);

      // 6. POST /dev/apps/echo_app/tests/run?test_name=greeting_case detects mismatch before rebuild
      final _HttpTestResponse failingRunRes = await _sendHttp(
        port: server.port,
        method: 'POST',
        rawPathAndQuery: '/dev/apps/echo_app/tests/run?test_name=greeting_case',
      );
      expect(failingRunRes.statusCode, HttpStatus.ok);
      expect(failingRunRes.headers['content-type'], contains('text/plain'));
      expect(failingRunRes.body, contains('FAILED greeting_case.json'));
      expect(failingRunRes.body, contains('=== 0 passed, 1 failed ==='));

      // 7. POST /dev/apps/echo_app/tests/rebuild?test_name=greeting_case updates recorded events
      final _HttpTestResponse rebuildRes = await _sendHttp(
        port: server.port,
        method: 'POST',
        rawPathAndQuery:
            '/dev/apps/echo_app/tests/rebuild?test_name=greeting_case',
      );
      expect(rebuildRes.statusCode, HttpStatus.ok);
      expect(jsonDecode(rebuildRes.body), <String, Object?>{
        'status': 'success',
      });

      final _HttpTestResponse afterRebuildGet = await _sendHttp(
        port: server.port,
        method: 'GET',
        rawPathAndQuery: '/dev/apps/echo_app/tests/greeting_case.json',
      );
      expect(afterRebuildGet.body, contains('v1: こんにちは'));

      // 8. POST /dev/apps/echo_app/tests/run passes all tests!
      final _HttpTestResponse passingRunRes = await _sendHttp(
        port: server.port,
        method: 'POST',
        rawPathAndQuery: '/dev/apps/echo_app/tests/run',
      );
      expect(passingRunRes.statusCode, HttpStatus.ok);
      expect(passingRunRes.body, contains('PASSED greeting_case.json'));
      expect(passingRunRes.body, contains('PASSED live_session.json'));
      expect(passingRunRes.body, contains('=== 2 passed, 0 failed ==='));

      // 9. Subprocess streamTestOutput override also streams lines cleanly
      devTestRunnerProcessStarterTestingOverride = ({
        required String agentDir,
        String? testFilePath,
      }) {
        return Process.start(Platform.resolvedExecutable, <String>[
          '--version',
        ]);
      };
      final _HttpTestResponse subprocessRunRes = await _sendHttp(
        port: server.port,
        method: 'POST',
        rawPathAndQuery: '/dev/apps/echo_app/tests/run',
      );
      expect(subprocessRunRes.statusCode, HttpStatus.ok);
      expect(subprocessRunRes.body.toLowerCase(), contains('dart'));
      devTestRunnerProcessStarterTestingOverride = null;

      // 10. DELETE /dev/apps/echo_app/tests/{test_name} (200 then 404)
      final _HttpTestResponse delRes = await _sendHttp(
        port: server.port,
        method: 'DELETE',
        rawPathAndQuery: '/dev/apps/echo_app/tests/greeting_case',
      );
      expect(delRes.statusCode, HttpStatus.ok);
      expect(jsonDecode(delRes.body), <String, Object?>{'status': 'success'});

      final _HttpTestResponse delAgainRes = await _sendHttp(
        port: server.port,
        method: 'DELETE',
        rawPathAndQuery: '/dev/apps/echo_app/tests/greeting_case',
      );
      expect(delAgainRes.statusCode, HttpStatus.notFound);
    });

    test('Replay Tests routes reject path traversal, null bytes, symlinks, and remote mutations', () async {
      final AdkDevServer devServer = AdkDevServer(
        agentsDir: tempDir.path,
        port: 0,
      );
      final HttpServer server = await devServer.start();
      addTearDown(devServer.stop);

      // 1. Encoded slash, backslash, parent traversal, and null byte in {test_name} -> 400
      for (final String maliciousName in <String>[
        '..%2Foutside',
        '..%5Coutside',
        'sub%2Fnested',
        'bad%00null',
        '.json',
      ]) {
        final _HttpTestResponse getRes = await _sendHttp(
          port: server.port,
          method: 'GET',
          rawPathAndQuery: '/dev/apps/echo_app/tests/$maliciousName',
        );
        expect(
          getRes.statusCode,
          HttpStatus.badRequest,
          reason: 'Expected 400 on GET for $maliciousName',
        );

        final _HttpTestResponse putRes = await _sendHttp(
          port: server.port,
          method: 'PUT',
          rawPathAndQuery: '/dev/apps/echo_app/tests/$maliciousName',
          jsonBody: const <String, Object?>{
            'session_data': <String, Object?>{'events': <Object?>[]},
          },
        );
        expect(putRes.statusCode, HttpStatus.badRequest);

        final _HttpTestResponse delRes = await _sendHttp(
          port: server.port,
          method: 'DELETE',
          rawPathAndQuery: '/dev/apps/echo_app/tests/$maliciousName',
        );
        expect(delRes.statusCode, HttpStatus.badRequest);

        final _HttpTestResponse rebuildRes = await _sendHttp(
          port: server.port,
          method: 'POST',
          rawPathAndQuery:
              '/dev/apps/echo_app/tests/rebuild?test_name=$maliciousName',
        );
        expect(rebuildRes.statusCode, HttpStatus.badRequest);

        final _HttpTestResponse runRes = await _sendHttp(
          port: server.port,
          method: 'POST',
          rawPathAndQuery:
              '/dev/apps/echo_app/tests/run?test_name=$maliciousName',
        );
        expect(runRes.statusCode, HttpStatus.badRequest);
      }

      for (final String dotQuery in <String>['.', '..', '../secret.json']) {
        final _HttpTestResponse rebuildDotRes = await _sendHttp(
          port: server.port,
          method: 'POST',
          rawPathAndQuery:
              '/dev/apps/echo_app/tests/rebuild?test_name=${Uri.encodeQueryComponent(dotQuery)}',
        );
        expect(rebuildDotRes.statusCode, HttpStatus.badRequest);
      }

      // 2. Symlink inside tests/ pointing outside tests/ is rejected with 400
      final Directory testsDir = Directory('${tempDir.path}/echo_app/tests')
        ..createSync(recursive: true);
      final File outsideSecret = File('${tempDir.path}/secret.json')
        ..writeAsStringSync('{"secret": true}\n');
      Link('${testsDir.path}/linked.json').createSync(outsideSecret.path);

      final _HttpTestResponse symlinkGet = await _sendHttp(
        port: server.port,
        method: 'GET',
        rawPathAndQuery: '/dev/apps/echo_app/tests/linked.json',
      );
      expect(symlinkGet.statusCode, HttpStatus.badRequest);

      final _HttpTestResponse symlinkPut = await _sendHttp(
        port: server.port,
        method: 'PUT',
        rawPathAndQuery: '/dev/apps/echo_app/tests/linked.json',
        jsonBody: const <String, Object?>{
          'session_data': <String, Object?>{'overwritten': true},
        },
      );
      expect(symlinkPut.statusCode, HttpStatus.badRequest);
      expect(outsideSecret.readAsStringSync(), '{"secret": true}\n');

      // 3. Remote client receives 200 on GET /tests, 403 on PUT/DELETE/rebuild/run
      isLocalAgentBuilderClientTestingOverride = (_) => false;
      final _HttpTestResponse remoteList = await _sendHttp(
        port: server.port,
        method: 'GET',
        rawPathAndQuery: '/dev/apps/echo_app/tests',
      );
      expect(remoteList.statusCode, HttpStatus.ok);

      for (final ({String method, String path}) mut in <({
        String method,
        String path,
      })>[
        (method: 'PUT', path: '/dev/apps/echo_app/tests/t1'),
        (method: 'DELETE', path: '/dev/apps/echo_app/tests/t1'),
        (method: 'POST', path: '/dev/apps/echo_app/tests/rebuild'),
        (method: 'POST', path: '/dev/apps/echo_app/tests/run'),
      ]) {
        final _HttpTestResponse res = await _sendHttp(
          port: server.port,
          method: mut.method,
          rawPathAndQuery: mut.path,
          jsonBody: const <String, Object?>{
            'session_data': <String, Object?>{'events': <Object?>[]},
          },
        );
        expect(res.statusCode, HttpStatus.forbidden);
      }
      isLocalAgentBuilderClientTestingOverride = null;
    });
  });

  group('3. Vertex AI Reasoning Engine Adapter Routes (/api/reasoning_engine & /api/stream_reasoning_engine)', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('adk_nov15_re_');
      Directory('${tempDir.path}/enterprise_app').createSync(recursive: true);
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('POST /api/reasoning_engine supports session CRUD, query/async_query, artifacts, and rejects invalid class_method/input', () async {
      final LlmAgent enterpriseAgent = LlmAgent(
        name: 'vertex_agent',
        model: _DynamicEchoModel(prefix: 'VertexReply'),
        instruction: 'Respond as Vertex AI Reasoning Engine.',
      );
      final FastApiApp app = getFastApiApp(
        agentsDir: tempDir.path,
        geminiEnterpriseAppName: 'enterprise_app',
        enableWebUi: false,
        port: 0,
        agentLoader: _MapAgentLoader(<String, AgentOrApp>{
          'enterprise_app': enterpriseAgent,
        }),
      );
      final HttpServer server = await app.start();
      addTearDown(app.stop);

      // 1. create_session & async_create_session
      final _HttpTestResponse createRes = await _sendHttp(
        port: server.port,
        method: 'POST',
        rawPathAndQuery: '/api/reasoning_engine',
        jsonBody: <String, Object?>{
          'class_method': 'async_create_session',
          'input': <String, Object?>{
            'user_id': 'u_vertex',
            'session_id': 's_vertex_1',
            'state': <String, Object?>{'tier': 'pro'},
          },
        },
      );
      expect(createRes.statusCode, HttpStatus.ok);
      final Map<String, Object?> createdSession = Map<String, Object?>.from(
        (jsonDecode(createRes.body) as Map)['output'] as Map,
      );
      expect(createdSession['id'], 's_vertex_1');
      expect(createdSession['app_name'], 'enterprise_app');
      expect((createdSession['state'] as Map)['tier'], 'pro');

      // Sync alias create_session
      final _HttpTestResponse createSyncRes = await _sendHttp(
        port: server.port,
        method: 'POST',
        rawPathAndQuery: '/api/reasoning_engine',
        jsonBody: <String, Object?>{
          'class_method': 'create_session',
          'input': <String, Object?>{
            'user_id': 'u_vertex',
            'session_id': 's_vertex_2',
          },
        },
      );
      expect(createSyncRes.statusCode, HttpStatus.ok);

      // 2. list_sessions & async_list_sessions
      final _HttpTestResponse listRes = await _sendHttp(
        port: server.port,
        method: 'POST',
        rawPathAndQuery: '/api/reasoning_engine',
        jsonBody: <String, Object?>{
          'class_method': 'list_sessions',
          'input': <String, Object?>{'user_id': 'u_vertex'},
        },
      );
      expect(listRes.statusCode, HttpStatus.ok);
      final List<Object?> sessions =
          (((jsonDecode(listRes.body) as Map)['output'] as Map)['sessions'])
              as List<Object?>;
      expect(sessions, hasLength(2));

      // 3. get_session & async_get_session
      final _HttpTestResponse getRes = await _sendHttp(
        port: server.port,
        method: 'POST',
        rawPathAndQuery: '/api/reasoning_engine',
        jsonBody: <String, Object?>{
          'class_method': 'get_session',
          'input': <String, Object?>{
            'user_id': 'u_vertex',
            'session_id': 's_vertex_1',
          },
        },
      );
      expect(getRes.statusCode, HttpStatus.ok);
      expect(
        ((jsonDecode(getRes.body) as Map)['output'] as Map)['id'],
        's_vertex_1',
      );

      // 4. query & async_query
      final _HttpTestResponse queryRes = await _sendHttp(
        port: server.port,
        method: 'POST',
        rawPathAndQuery: '/api/reasoning_engine',
        jsonBody: <String, Object?>{
          'class_method': 'query',
          'input': <String, Object?>{
            'user_id': 'u_vertex',
            'session_id': 's_vertex_1',
            'message': 'ping engine',
          },
        },
      );
      expect(queryRes.statusCode, HttpStatus.ok);
      final List<Object?> queryEvents =
          (jsonDecode(queryRes.body) as Map)['output'] as List<Object?>;
      expect(queryEvents, isNotEmpty);
      expect(queryRes.body, contains('VertexReply: ping engine'));

      final _HttpTestResponse asyncQueryRes = await _sendHttp(
        port: server.port,
        method: 'POST',
        rawPathAndQuery: '/api/reasoning_engine',
        jsonBody: <String, Object?>{
          'class_method': 'async_query',
          'input': <String, Object?>{
            'user_id': 'u_vertex',
            'message': <String, Object?>{
              'role': 'user',
              'parts': <Object?>[
                <String, Object?>{'text': 'auto session turn'},
              ],
            },
          },
        },
      );
      expect(asyncQueryRes.statusCode, HttpStatus.ok);
      expect(asyncQueryRes.body, contains('VertexReply: auto session turn'));

      // 5. delete_session & async_delete_session
      final _HttpTestResponse deleteRes = await _sendHttp(
        port: server.port,
        method: 'POST',
        rawPathAndQuery: '/api/reasoning_engine',
        jsonBody: <String, Object?>{
          'class_method': 'delete_session',
          'input': <String, Object?>{
            'user_id': 'u_vertex',
            'session_id': 's_vertex_2',
          },
        },
      );
      expect(deleteRes.statusCode, HttpStatus.ok);
      expect((jsonDecode(deleteRes.body) as Map)['output'], isNull);

      final _HttpTestResponse getDeletedRes = await _sendHttp(
        port: server.port,
        method: 'POST',
        rawPathAndQuery: '/api/reasoning_engine',
        jsonBody: <String, Object?>{
          'class_method': 'async_get_session',
          'input': <String, Object?>{
            'user_id': 'u_vertex',
            'session_id': 's_vertex_2',
          },
        },
      );
      expect(getDeletedRes.statusCode, HttpStatus.ok);
      expect((jsonDecode(getDeletedRes.body) as Map)['output'], isNull);

      // 6. Invalid / missing / disallowed class_method & invalid inputs -> 400 / 422
      final _HttpTestResponse missingMethodRes = await _sendHttp(
        port: server.port,
        method: 'POST',
        rawPathAndQuery: '/api/reasoning_engine',
        jsonBody: const <String, Object?>{'input': <String, Object?>{}},
      );
      expect(missingMethodRes.statusCode, HttpStatus.badRequest);
      expect(missingMethodRes.body, contains('class_method cannot be None'));

      final _HttpTestResponse unknownMethodRes = await _sendHttp(
        port: server.port,
        method: 'POST',
        rawPathAndQuery: '/api/reasoning_engine',
        jsonBody: const <String, Object?>{
          'class_method': '__import__',
          'input': <String, Object?>{},
        },
      );
      expect(unknownMethodRes.statusCode, HttpStatus.badRequest);
      expect(unknownMethodRes.body, contains('not allowed'));

      // Calling streaming method on non-streaming endpoint -> 400
      final _HttpTestResponse wrongEndpointRes = await _sendHttp(
        port: server.port,
        method: 'POST',
        rawPathAndQuery: '/api/reasoning_engine',
        jsonBody: const <String, Object?>{
          'class_method': 'stream_query',
          'input': <String, Object?>{'user_id': 'u1', 'message': 'hi'},
        },
      );
      expect(wrongEndpointRes.statusCode, HttpStatus.badRequest);

      // Missing required user_id -> 422
      final _HttpTestResponse missingUserRes = await _sendHttp(
        port: server.port,
        method: 'POST',
        rawPathAndQuery: '/api/reasoning_engine',
        jsonBody: const <String, Object?>{
          'class_method': 'create_session',
          'input': <String, Object?>{},
        },
      );
      expect(missingUserRes.statusCode, HttpStatus.unprocessableEntity);
    });

    test('POST /api/stream_reasoning_engine streams NDJSON lines (and SSE on Accept: text/event-stream) for stream_query and async_stream_query', () async {
      final LlmAgent streamAgent = LlmAgent(
        name: 'stream_vertex_agent',
        model: _DynamicEchoModel(prefix: 'StreamReply'),
        instruction: 'Stream responses.',
      );
      final FastApiApp app = getFastApiApp(
        agentsDir: tempDir.path,
        geminiEnterpriseAppName: 'enterprise_app',
        enableWebUi: false,
        port: 0,
        agentLoader: _MapAgentLoader(<String, AgentOrApp>{
          'enterprise_app': streamAgent,
        }),
      );
      final HttpServer server = await app.start();
      addTearDown(app.stop);

      // 1. NDJSON streaming (default, matching fast_api.py media_type="application/json")
      final _HttpTestResponse ndjsonRes = await _sendHttp(
        port: server.port,
        method: 'POST',
        rawPathAndQuery: '/api/stream_reasoning_engine',
        jsonBody: <String, Object?>{
          'class_method': 'async_stream_query',
          'input': <String, Object?>{
            'user_id': 'u_stream',
            'message': 'hello stream',
          },
        },
      );
      expect(ndjsonRes.statusCode, HttpStatus.ok);
      expect(ndjsonRes.headers['content-type'], contains('application/json'));
      final List<String> lines = const LineSplitter()
          .convert(ndjsonRes.body)
          .where((String l) => l.trim().isNotEmpty)
          .toList();
      expect(lines.length, greaterThanOrEqualTo(2));
      final List<Map<String, Object?>> parsedChunks = lines
          .map((String l) => Map<String, Object?>.from(jsonDecode(l) as Map))
          .toList();
      expect(
        parsedChunks.any((Map<String, Object?> e) => e['partial'] == true),
        isTrue,
      );
      expect(ndjsonRes.body, contains('StreamReply: hello stream'));

      // 2. SSE streaming when Accept: text/event-stream is requested
      final _HttpTestResponse sseRes = await _sendHttp(
        port: server.port,
        method: 'POST',
        rawPathAndQuery: '/api/stream_reasoning_engine',
        headers: const <String, String>{'accept': 'text/event-stream'},
        jsonBody: <String, Object?>{
          'class_method': 'stream_query',
          'input': <String, Object?>{
            'user_id': 'u_stream',
            'message': 'hello sse',
          },
        },
      );
      expect(sseRes.statusCode, HttpStatus.ok);
      expect(sseRes.headers['content-type'], contains('text/event-stream'));
      expect(sseRes.body, contains('data: {'));
      expect(sseRes.body, contains('StreamReply: hello sse'));

      // 3. Rejects non-streaming class_method and invalid inputs
      final _HttpTestResponse nonStreamMethodRes = await _sendHttp(
        port: server.port,
        method: 'POST',
        rawPathAndQuery: '/api/stream_reasoning_engine',
        jsonBody: const <String, Object?>{
          'class_method': 'create_session',
          'input': <String, Object?>{'user_id': 'u_stream'},
        },
      );
      expect(nonStreamMethodRes.statusCode, HttpStatus.badRequest);

      final _HttpTestResponse bothSessionAndEventsRes = await _sendHttp(
        port: server.port,
        method: 'POST',
        rawPathAndQuery: '/api/stream_reasoning_engine',
        jsonBody: const <String, Object?>{
          'class_method': 'async_stream_query',
          'input': <String, Object?>{
            'user_id': 'u_stream',
            'session_id': 's1',
            'session_events': <Object?>[],
            'message': 'conflict',
          },
        },
      );
      expect(bothSessionAndEventsRes.statusCode, HttpStatus.badRequest);
    });
  });
}
