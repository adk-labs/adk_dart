import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:adk/src/dev/cli.dart';
import 'package:adk/src/dev/project.dart';
import 'package:adk/src/dev/runtime.dart';
import 'package:adk/src/dev/web_server.dart';
import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

class _WaitingLiveAgent extends BaseAgent {
  _WaitingLiveAgent({required super.name});

  AdkAbortSignal? seenAbortSignal;
  final Completer<void> started = Completer<void>();

  @override
  Stream<Event> runAsyncImpl(InvocationContext context) async* {}

  @override
  Stream<Event> runLiveImpl(InvocationContext context) async* {
    seenAbortSignal = context.abortSignal;
    if (!started.isCompleted) {
      started.complete();
    }
    yield Event(
      invocationId: context.invocationId,
      author: name,
      content: Content.modelText('live ready'),
    );
    // Keep stream alive until abort signal fires.
    while (!(context.abortSignal?.aborted ?? false)) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }
}

class _ThrowingLiveAgent extends BaseAgent {
  _ThrowingLiveAgent({required super.name});

  @override
  Stream<Event> runAsyncImpl(InvocationContext context) async* {}

  @override
  Stream<Event> runLiveImpl(InvocationContext context) async* {
    throw const FormatException('Runner validation failed');
  }
}

void main() {
  group('27dda3e11 - avatar_config FileSystemException handling', () {
    test('wraps non-UTF-8 avatar_config read errors in CliUsageError', () {
      final Directory tempDir = Directory.systemTemp.createTempSync(
        'adk_avatar_non_utf8_',
      );
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });

      final File badFile = File('${tempDir.path}/bad_avatar.yaml');
      badFile.writeAsBytesSync(<int>[0xFF, 0xFE, 0x80, 0x81]);

      expect(
        () => parseAdkCliArgs(<String>[
          'web',
          tempDir.path,
          '--avatar_config=${badFile.path}',
        ]),
        throwsA(
          isA<CliUsageError>().having(
            (CliUsageError e) => e.message,
            'message',
            contains("could not read avatar configuration file '${badFile.path}'"),
          ),
        ),
      );
    });

    test('wraps directory avatar_config read errors in CliUsageError', () {
      final Directory tempDir = Directory.systemTemp.createTempSync(
        'adk_avatar_dir_',
      );
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });

      expect(
        () => parseAdkCliArgs(<String>[
          'web',
          tempDir.path,
          '--avatar_config=${tempDir.path}',
        ]),
        throwsA(
          isA<CliUsageError>().having(
            (CliUsageError e) => e.message,
            'message',
            contains("could not read avatar configuration file '${tempDir.path}'"),
          ),
        ),
      );
    });
  });

  group('ff66b1f17 - file:// eval_storage_uri and ADK_EVAL_STORAGE_URI', () {
    test('createEvalManagersForTesting supports file:// and ADK_EVAL_STORAGE_URI', () {
      final Directory tempDir = Directory.systemTemp.createTempSync(
        'adk_eval_uri_',
      );
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });

      final String explicitSubdir = '${tempDir.path}/explicit_eval';
      final Object explicitBundle = createEvalManagersForTesting(
        agentsDir: tempDir.path,
        useInMemory: false,
        evalStorageUri: Uri.file(explicitSubdir).toString(),
      );
      expect(explicitBundle, isNotNull);
      expect(Directory(explicitSubdir).existsSync(), isTrue);

      final String envSubdir = '${tempDir.path}/env_eval';
      final Object envBundle = createEvalManagersForTesting(
        agentsDir: tempDir.path,
        useInMemory: false,
        evalStorageUri: null,
        environment: <String, String>{
          'ADK_EVAL_STORAGE_URI': Uri.file(envSubdir).toString(),
        },
      );
      expect(envBundle, isNotNull);
      expect(Directory(envSubdir).existsSync(), isTrue);
    });

    test('rejects invalid file:// and unsupported eval storage URIs', () {
      final Directory tempDir = Directory.systemTemp.createTempSync(
        'adk_eval_uri_invalid_',
      );
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });

      expect(
        () => createEvalManagersForTesting(
          agentsDir: tempDir.path,
          useInMemory: false,
          evalStorageUri: 'file://remotehost/tmp/evals',
        ),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError e) => e.message.toString(),
            'message',
            contains('file:// URIs must target the local host'),
          ),
        ),
      );

      expect(
        () => createEvalManagersForTesting(
          agentsDir: tempDir.path,
          useInMemory: false,
          evalStorageUri: 'file:relative/path',
        ),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError e) => e.message.toString(),
            'message',
            contains('file:// URIs must use an absolute path'),
          ),
        ),
      );

      expect(
        () => createEvalManagersForTesting(
          agentsDir: tempDir.path,
          useInMemory: false,
          evalStorageUri: 'http://example.com/evals',
        ),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError e) => e.message.toString(),
            'message',
            contains('Supported URIs: gs://<bucket name>, file://<path>'),
          ),
        ),
      );
    });

    test('resolveEvalLocalBaseDirForTesting validates file:// URIs', () {
      expect(
        resolveEvalLocalBaseDirForTesting(
          baseDir: '/base',
          evalStorageUri: 'file:///tmp/my%20evals',
        ),
        '/tmp/my evals',
      );
      expect(
        () => resolveEvalLocalBaseDirForTesting(
          baseDir: '/base',
          evalStorageUri: 'file://remotehost/tmp/evals',
        ),
        throwsArgumentError,
      );
    });
  });

  group('b7ac5ef75 - protect special agents and /dev routes from wildcard/regex CORS', () {
    test('blocks foreign browser origins under wildcard CORS for special agents and /dev', () async {
      const DevProjectConfig config = DevProjectConfig(
        appName: '__special_agent',
        agentName: 'root_agent',
        description: 'special test agent',
      );
      final DevAgentRuntime runtime = DevAgentRuntime(config: config);
      final HttpServer server = await startAdkDevWebServer(
        runtime: runtime,
        project: config,
        port: 0,
        allowOrigins: <String>[
          '*',
          'regex:https://.*\\.evil\\.example',
          'https://trusted-ide.example',
        ],
      );
      final HttpClient client = HttpClient();
      addTearDown(() async {
        client.close(force: true);
        await server.close(force: true);
        await runtime.runner.close();
      });

      // 1. Foreign browser origin accessing special agent is blocked with 403.
      final HttpClientRequest badSpecialReq = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/apps/__special_agent/app-info'),
      );
      badSpecialReq.headers.set('origin', 'https://attacker.evil.example');
      final HttpClientResponse badSpecialRes = await badSpecialReq.close();
      final String badSpecialBody = await utf8.decoder.bind(badSpecialRes).join();
      expect(badSpecialRes.statusCode, HttpStatus.forbidden);
      expect(badSpecialBody, contains('own origin'));

      // 2. Spoofed X-Forwarded-Host / Forwarded does not bypass origin check.
      final HttpClientRequest spoofedReq = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/apps/__special_agent/app-info'),
      );
      spoofedReq.headers.set('origin', 'https://spoofed.example');
      spoofedReq.headers.set('x-forwarded-host', 'spoofed.example');
      spoofedReq.headers.set('x-forwarded-proto', 'https');
      spoofedReq.headers.set('forwarded', 'proto=https;host=spoofed.example');
      final HttpClientResponse spoofedRes = await spoofedReq.close();
      await utf8.decoder.bind(spoofedRes).join();
      expect(spoofedRes.statusCode, HttpStatus.forbidden);

      // 3. Server's own origin is allowed.
      final HttpClientRequest ownOriginReq = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/apps/__special_agent/app-info'),
      );
      ownOriginReq.headers.set('origin', 'http://127.0.0.1:${server.port}');
      final HttpClientResponse ownOriginRes = await ownOriginReq.close();
      await utf8.decoder.bind(ownOriginRes).join();
      expect(ownOriginRes.statusCode, HttpStatus.ok);

      // 4. Explicitly listed literal origin in allowOrigins is allowed.
      final HttpClientRequest trustedOriginReq = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/apps/__special_agent/app-info'),
      );
      trustedOriginReq.headers.set('origin', 'https://trusted-ide.example');
      final HttpClientResponse trustedOriginRes = await trustedOriginReq.close();
      await utf8.decoder.bind(trustedOriginRes).join();
      expect(trustedOriginRes.statusCode, HttpStatus.ok);

      // 5. Mutating /dev/ route is blocked for foreign browser origin even under wildcard CORS.
      final HttpClientRequest devPostReq = await client.postUrl(
        Uri.parse('http://127.0.0.1:${server.port}/dev/apps/__special_agent/Reload'),
      );
      devPostReq.headers.set('origin', 'https://attacker.evil.example');
      final HttpClientResponse devPostRes = await devPostReq.close();
      final String devPostBody = await utf8.decoder.bind(devPostRes).join();
      expect(devPostRes.statusCode, HttpStatus.forbidden);
      expect(
        devPostBody,
        contains('This endpoint writes agent files or starts runs'),
      );
    });
  });

  group('3b227d6ec - /run_live closes WebSocket cleanly on malformed frames and runner exit', () {
    test('closes WebSocket with 1007 and aborts runner on malformed live request frame', () async {
      const DevProjectConfig config = DevProjectConfig(
        appName: 'test_app',
        agentName: 'root_agent',
        description: 'test',
      );
      final _WaitingLiveAgent waitingAgent = _WaitingLiveAgent(
        name: 'root_agent',
      );
      final InMemoryRunner liveRunner = InMemoryRunner(
        appName: 'test_app',
        agent: waitingAgent,
      );
      final DevAgentRuntime liveRuntime = DevAgentRuntime(
        config: config,
        runner: liveRunner,
      );
      final Directory agentsDir = await Directory.systemTemp.createTemp(
        'adk_live_invalid_frame_',
      );
      addTearDown(() async {
        if (await agentsDir.exists()) {
          await agentsDir.delete(recursive: true);
        }
      });
      final HttpServer server = await startAdkDevWebServer(
        runtime: liveRuntime,
        project: config,
        agentsDir: agentsDir.path,
        port: 0,
      );
      final HttpClient client = HttpClient();
      addTearDown(() async {
        client.close(force: true);
        await server.close(force: true);
        await liveRunner.close();
      });

      const String sessionId = 's_live_invalid_frame';
      final HttpClientRequest createRequest = await client.postUrl(
        Uri.parse(
          'http://127.0.0.1:${server.port}/apps/test_app/users/u1/sessions',
        ),
      );
      createRequest.headers.contentType = ContentType.json;
      createRequest.write(jsonEncode(<String, Object>{'session_id': sessionId}));
      final HttpClientResponse createResponse = await createRequest.close();
      await utf8.decoder.bind(createResponse).join();
      expect(createResponse.statusCode, HttpStatus.ok);

      final WebSocket socket = await WebSocket.connect(
        'ws://127.0.0.1:${server.port}/run_live?app_name=test_app&user_id=u1&session_id=$sessionId&modalities=TEXT',
      );
      addTearDown(() async {
        await socket.close();
      });

      await waitingAgent.started.future.timeout(const Duration(seconds: 5));

      // Send a malformed LiveRequest payload ('content' must be a Map, not a String).
      socket.add(jsonEncode(<String, Object>{'content': 'not_a_content_object'}));

      // Drain remaining socket events until the server closes the connection.
      await socket.drain<void>().timeout(const Duration(seconds: 5));

      expect(socket.closeCode, WebSocketStatus.invalidFramePayloadData);
      expect(socket.closeReason, 'Invalid live request');

      for (int i = 0; i < 20; i += 1) {
        if (waitingAgent.seenAbortSignal?.aborted ?? false) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(waitingAgent.seenAbortSignal?.aborted, isTrue);
    });

    test('closes WebSocket with 1011 when runner throws FormatException', () async {
      const DevProjectConfig config = DevProjectConfig(
        appName: 'test_app',
        agentName: 'root_agent',
        description: 'test',
      );
      final _ThrowingLiveAgent throwingAgent = _ThrowingLiveAgent(
        name: 'root_agent',
      );
      final InMemoryRunner liveRunner = InMemoryRunner(
        appName: 'test_app',
        agent: throwingAgent,
      );
      final DevAgentRuntime liveRuntime = DevAgentRuntime(
        config: config,
        runner: liveRunner,
      );
      final Directory agentsDir = await Directory.systemTemp.createTemp(
        'adk_live_invalid_frame_',
      );
      addTearDown(() async {
        if (await agentsDir.exists()) {
          await agentsDir.delete(recursive: true);
        }
      });
      final HttpServer server = await startAdkDevWebServer(
        runtime: liveRuntime,
        project: config,
        agentsDir: agentsDir.path,
        port: 0,
      );
      final HttpClient client = HttpClient();
      addTearDown(() async {
        client.close(force: true);
        await server.close(force: true);
        await liveRunner.close();
      });

      const String sessionId = 's_live_runner_throws';
      final HttpClientRequest createRequest = await client.postUrl(
        Uri.parse(
          'http://127.0.0.1:${server.port}/apps/test_app/users/u1/sessions',
        ),
      );
      createRequest.headers.contentType = ContentType.json;
      createRequest.write(jsonEncode(<String, Object>{'session_id': sessionId}));
      final HttpClientResponse createResponse = await createRequest.close();
      await utf8.decoder.bind(createResponse).join();
      expect(createResponse.statusCode, HttpStatus.ok);

      final WebSocket socket = await WebSocket.connect(
        'ws://127.0.0.1:${server.port}/run_live?app_name=test_app&user_id=u1&session_id=$sessionId&modalities=TEXT',
      );
      addTearDown(() async {
        await socket.close();
      });

      await socket.drain<void>().timeout(const Duration(seconds: 5));
      expect(socket.closeCode, WebSocketStatus.internalServerError);
    });
  });
}
