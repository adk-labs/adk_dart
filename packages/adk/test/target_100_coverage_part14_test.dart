import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:adk/adk.dart' hide Invocation;
import 'package:adk/src/dev/cli.dart';
import 'package:test/test.dart';

class _BufferSink implements IOSink {
  _BufferSink(this.buffer);
  final StringBuffer buffer;

  @override
  void write(Object? obj) => buffer.write(obj);

  @override
  void writeln([Object? obj = '']) => buffer.writeln(obj);

  @override
  void writeAll(Iterable<dynamic> objects, [String separator = '']) =>
      buffer.writeAll(objects, separator);

  @override
  void writeCharCode(int charCode) => buffer.writeCharCode(charCode);

  @override
  void add(List<int> data) => buffer.write(utf8.decode(data));

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final List<int> chunk in stream) {
      buffer.write(utf8.decode(chunk));
    }
  }

  @override
  Future<void> close() async {}

  @override
  Future<void> get done => Future<void>.value();

  @override
  Encoding encoding = utf8;

  @override
  Future<void> flush() async {}
}

class _Part14StubModel extends BaseLlm {
  _Part14StubModel() : super(model: 'part14-stub-model');

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    yield LlmResponse(
      content: Content(
        role: 'model',
        parts: <Part>[Part.text('part14 response')],
      ),
    );
  }
}

class _Part14StubComputer implements BaseComputer {
  @override
  Future<void> initialize() async {}

  @override
  Future<ComputerState> currentState() async => ComputerState(
    screenshot: <int>[1, 2, 3],
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUpAll(() {
    LLMRegistry.clear();
    LLMRegistry.register(
      supportedModels: <RegExp>[
        RegExp(r'^part14-stub-model$'),
        RegExp(r'^gemini-.*$'),
      ],
      factory: (String model) => _Part14StubModel(),
    );
  });

  tearDownAll(LLMRegistry.clear);

  group('Target 100% Coverage Part 14 - Remaining Lines in CLI and Web Server', () {
    late Directory tempDir;
    late StringBuffer outBuffer;
    late StringBuffer errBuffer;
    late _BufferSink outSink;
    late _BufferSink errSink;
    late DevProjectConfig project;
    late DevAgentRuntime runtime;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('adk_part14_test_');
      File('${tempDir.path}/root_agent.yaml').writeAsStringSync('''
name: my_app
model: gemini-2.5-flash
instruction: Web server app
''');
      project = DevProjectConfig(
        appName: 'my_app',
        agentName: 'my_app',
        description: 'Web server app',
      );
      runtime = DevAgentRuntime(
        config: project,
        runner: InMemoryRunner(agent: LlmAgent(name: 'my_app', model: 'gemini-2.5-flash')),
      );

      outBuffer = StringBuffer();
      errBuffer = StringBuffer();
      outSink = _BufferSink(outBuffer);
      errSink = _BufferSink(errBuffer);
      simulateSignalUnsupportedForTesting = false;
      simulateScreencastInitErrorForTesting = false;
      simulateSseFlushErrorForTesting = false;
      signalWatchTestingOverride = null;
      cliReadLineTestingOverride = null;
      webStdinTestingOverride = null;
      agentLoaderTestingOverride = null;
      webServerAgentLoaderTestingOverride = null;
      webServerSessionServiceTestingOverride = null;
      webServerArtifactServiceTestingOverride = null;
    });

    tearDown(() async {
      simulateSignalUnsupportedForTesting = false;
      simulateScreencastInitErrorForTesting = false;
      simulateSseFlushErrorForTesting = false;
      signalWatchTestingOverride = null;
      cliReadLineTestingOverride = null;
      webStdinTestingOverride = null;
      agentLoaderTestingOverride = null;
      webServerAgentLoaderTestingOverride = null;
      webServerSessionServiceTestingOverride = null;
      webServerArtifactServiceTestingOverride = null;
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    });

    test('1. CLI line 4633: parseAdkCliArgs throws CliUsageError on trailing separator avatar_config', () {
      expect(
        () => parseAdkCliArgs(<String>['web', tempDir.path, '--avatar_config=key=']),
        throwsA(isA<CliUsageError>()),
      );
      expect(
        () => parseAdkCliArgs(<String>['web', tempDir.path, '--avatar_config=key:']),
        throwsA(isA<CliUsageError>()),
      );
    });

    test('2. CLI line 4934: runRunCommandForTesting with err: null evaluates stderr', () async {
      final AgentLoader loader = AgentLoader(tempDir.path);
      final File agentFile = File('${tempDir.path}${Platform.pathSeparator}agent.dart');
      await agentFile.writeAsString('''
import 'package:adk_dart/adk_dart.dart';
final rootAgent = LlmAgent(name: 'part14_agent', model: 'gemini-2.5-flash');
''');
      agentLoaderTestingOverride = (_) => loader;

      final dynamic parsed = parseAdkCliArgs(<String>[
        'run',
        tempDir.path,
      ]);

      cliReadLineTestingOverride = () => 'exit';
      final int exitCode = await runRunCommandForTesting(
        parsed,
        outSink,
        err: null,
      );
      expect(exitCode, equals(0));
    });

    test('3. CLI line 5060: resolveCliReadLineForTesting returns stdin.readLineSync when null', () {
      cliReadLineTestingOverride = null;
      final String? Function() func = resolveCliReadLineForTesting(null);
      expect(func, isNotNull);
    });

    test('4. CLI line 5244: resume_file_path with events and initial_state executes Map.from(initialState)', () async {
      final File snapshotFile = File('${tempDir.path}${Platform.pathSeparator}snap.session.json');
      final StorageSessionV0 storage = StorageSessionV0(
        appName: 'snap_app',
        userId: 'snap_user',
        id: 'snap_sess_1',
        state: <String, Object?>{'old': 'value'},
        storageEvents: <StorageEventV0>[
          StorageEventV0(
            id: 'evt_1',
            appName: 'snap_app',
            userId: 'snap_user',
            sessionId: 'snap_sess_1',
            invocationId: 'inv_1',
            author: 'user',
            content: Content(
              role: 'user',
              parts: <Part>[Part.text('hello')],
            ),
          ),
        ],
      );
      await snapshotFile.writeAsString(jsonEncode(storage.toJson()));

      final AgentLoader loader = AgentLoader(tempDir.path);
      final File agentFile = File('${tempDir.path}${Platform.pathSeparator}agent.dart');
      await agentFile.writeAsString('''
import 'package:adk_dart/adk_dart.dart';
final rootAgent = LlmAgent(name: 'snap_app', model: 'gemini-2.5-flash');
''');
      agentLoaderTestingOverride = (_) => loader;

      final dynamic parsed = parseAdkCliArgs(<String>[
        'run',
        tempDir.path,
        '--resume=${snapshotFile.path}',
        '--state={"new_key":"new_val"}',
      ]);

      cliReadLineTestingOverride = () => 'exit';
      final int exitCode = await runRunCommandForTesting(
        parsed,
        outSink,
        err: errSink,
      );
      expect(exitCode, equals(0));
    });

    test('5. CLI line 5323: resolveCliReadLineForTesting returns testing override when set', () {
      cliReadLineTestingOverride = () => 'custom_id';
      final String? Function() func = resolveCliReadLineForTesting(null);
      expect(func(), equals('custom_id'));
    });

    test('6. CLI lines 5490, 5491: signalWatchTestingOverride triggers stopRequested.complete()', () async {
      final StreamController<ProcessSignal> controller = StreamController<ProcessSignal>.broadcast();
      signalWatchTestingOverride = (_) => controller.stream;

      final File agentFile = File('${tempDir.path}${Platform.pathSeparator}agent.dart');
      await agentFile.writeAsString('''
import 'package:adk_dart/adk_dart.dart';
final rootAgent = LlmAgent(name: 'web_agent', model: 'gemini-2.5-flash');
''');
      final AgentLoader loader = AgentLoader(tempDir.path);
      agentLoaderTestingOverride = (_) => loader;

      final Future<int> cliFuture = runAdkCli(
        <String>['web', tempDir.path, '--port=0'],
        outSink: outSink,
        errSink: errSink,
      );

      await Future<void>.delayed(const Duration(milliseconds: 300));
      controller.add(ProcessSignal.sigint);

      final int code = await cliFuture;
      expect(code, equals(0));
      await controller.close();
    });

    test('7. CLI line 5503: resolveWebStdinForTesting returns stdin when override is null', () {
      webStdinTestingOverride = null;
      final Stream<List<int>> stream = resolveWebStdinForTesting();
      expect(stream, equals(stdin));
    });

    test('8. CLI line 5580: applyFeatureOverridesFromCliForTesting writes warning on unknown feature in disableFeatures', () {
      applyFeatureOverridesFromCliForTesting(
        enableFeatures: <String>[],
        disableFeatures: <String>['unknown_feature_xyz_part14'],
        err: errSink,
      );
      expect(errBuffer.toString(), contains('unknown_feature_xyz_part14'));
    });

    test('9. Web server line 1065: readTraceByEventId returns in-memory trace when spanExporter has null', () async {
      final dynamic context = await createAdkDevWebContextForTesting(
        runtime: runtime,
        project: project,
        agentsDir: tempDir.path,
        a2a: false,
      );

      inMemoryTracesByEventIdForTesting(context)['mock_evt_14'] = <String, Object?>{
        'event_id': 'mock_evt_14',
        'name': 'part14_span',
      };

      final Map<String, Object?>? trace = (context as dynamic).readTraceByEventId('mock_evt_14');
      expect(trace, isNotNull);
      expect(trace!['name'], equals('part14_span'));
    });

    test('10. Web server lines 2057, 2058, 2062: _handleGetAppInfo catches ArgumentError from context.getRunner', () async {
      webServerAgentLoaderTestingOverride = (path) => AgentLoader(
        path,
        agentFactories: <String, AgentFactory>{
          'bad_arg_app': (name, dir) => throw ArgumentError('Invalid app arguments 14'),
        },
        enableDevProjectFallback: false,
      );

      final dynamic context = await createAdkDevWebContextForTesting(
        runtime: runtime,
        project: project,
        agentsDir: tempDir.path,
        a2a: false,
      );

      final HttpServer server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((HttpRequest req) async {
        await handleDevWebServerRequestForTesting(req, context);
      });

      try {
        final HttpClient client = HttpClient();
        final HttpClientRequest req = await client.getUrl(
          Uri.parse('http://127.0.0.1:${server.port}/apps/bad_arg_app/app-info'),
        );
        final HttpClientResponse resp = await req.close();
        final String body = await utf8.decodeStream(resp);
        expect(resp.statusCode, equals(HttpStatus.notFound));
        expect(body, contains('Invalid app arguments 14'));
      } finally {
        await server.close(force: true);
      }
    });

    test('11. Web server lines 2065, 2066, 2070: _handleGetAppInfo catches StateError from context.getRunner', () async {
      webServerAgentLoaderTestingOverride = (path) => AgentLoader(
        path,
        agentFactories: <String, AgentFactory>{
          'bad_state_app': (name, dir) => throw StateError('State error in app loader 14'),
        },
        enableDevProjectFallback: false,
      );

      final dynamic context = await createAdkDevWebContextForTesting(
        runtime: runtime,
        project: project,
        agentsDir: tempDir.path,
        a2a: false,
      );

      final HttpServer server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((HttpRequest req) async {
        await handleDevWebServerRequestForTesting(req, context);
      });

      try {
        final HttpClient client = HttpClient();
        final HttpClientRequest req = await client.getUrl(
          Uri.parse('http://127.0.0.1:${server.port}/apps/bad_state_app/app-info'),
        );
        final HttpClientResponse resp = await req.close();
        final String body = await utf8.decodeStream(resp);
        expect(resp.statusCode, equals(HttpStatus.notFound));
        expect(body, contains('State error in app loader 14'));
      } finally {
        await server.close(force: true);
      }
    });

    test('12. Web server lines 2297, 2298, 2302: _handleScreencast catches StateError from context.getRunner', () async {
      webServerAgentLoaderTestingOverride = (path) => AgentLoader(
        path,
        agentFactories: <String, AgentFactory>{
          'screencast_err_app': (name, dir) => throw StateError('Screencast runner state error 14'),
        },
        enableDevProjectFallback: false,
      );

      final dynamic context = await createAdkDevWebContextForTesting(
        runtime: runtime,
        project: project,
        agentsDir: tempDir.path,
        a2a: false,
      );

      final HttpServer server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((HttpRequest req) async {
        await handleDevWebServerRequestForTesting(req, context);
      });

      try {
        final HttpClient client = HttpClient();
        final HttpClientRequest req = await client.getUrl(
          Uri.parse('http://127.0.0.1:${server.port}/apps/screencast_err_app/screencast'),
        );
        final HttpClientResponse resp = await req.close();
        final String body = await utf8.decodeStream(resp);
        expect(resp.statusCode, equals(HttpStatus.notFound));
        expect(body, contains('Screencast runner state error 14'));
      } finally {
        await server.close(force: true);
      }
    });

    test('13. Web server lines 2352, 2353: _handleScreencast finally block closes open socket on initialize failure', () async {
      final BaseAgent agentWithComputer = LlmAgent(
        name: 'computer_app',
        model: _Part14StubModel(),
        tools: <Object>[
          ComputerUseToolset(computer: _Part14StubComputer()),
        ],
      );

      webServerAgentLoaderTestingOverride = (path) => AgentLoader(
        path,
        agentFactories: <String, AgentFactory>{
          'computer_app': (name, dir) => agentWithComputer,
        },
        enableDevProjectFallback: false,
      );

      final dynamic context = await createAdkDevWebContextForTesting(
        runtime: runtime,
        project: project,
        agentsDir: tempDir.path,
        a2a: false,
      );

      final HttpServer server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((HttpRequest req) async {
        await handleDevWebServerRequestForTesting(req, context);
      });

      try {
        simulateScreencastInitErrorForTesting = true;

        final WebSocket socket = await WebSocket.connect(
          'ws://127.0.0.1:${server.port}/apps/computer_app/screencast',
        );

        final Completer<void> closedCompleter = Completer<void>();
        socket.listen(
          (_) {},
          onDone: () {
            if (!closedCompleter.isCompleted) {
              closedCompleter.complete();
            }
          },
          onError: (_) {
            if (!closedCompleter.isCompleted) {
              closedCompleter.complete();
            }
          },
        );
        await closedCompleter.future.timeout(const Duration(seconds: 3));
        expect(socket.readyState, equals(WebSocket.closed));
      } finally {
        await server.close(force: true);
      }
    });

    test('14. Web server line 4029: _handleRunSse catches error on flush and aborts controller', () async {
      final BaseAgent agent = LlmAgent(
        name: 'sse_app',
        model: _Part14StubModel(),
      );

      webServerAgentLoaderTestingOverride = (path) => AgentLoader(
        path,
        agentFactories: <String, AgentFactory>{
          'sse_app': (name, dir) => agent,
        },
        enableDevProjectFallback: false,
      );

      final dynamic context = await createAdkDevWebContextForTesting(
        runtime: runtime,
        project: project,
        agentsDir: tempDir.path,
        a2a: false,
      );

      final HttpServer server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((HttpRequest req) async {
        await handleDevWebServerRequestForTesting(req, context);
      });

      try {
        simulateSseFlushErrorForTesting = true;

        final HttpClient client = HttpClient();
        final HttpClientRequest req = await client.postUrl(
          Uri.parse('http://127.0.0.1:${server.port}/run_sse'),
        );
        req.headers.contentType = ContentType.json;
        req.write(jsonEncode(<String, Object?>{
          'appName': 'sse_app',
          'userId': 'user1',
          'sessionId': 's1',
          'newMessage': <String, Object?>{
            'role': 'user',
            'parts': <Map<String, Object?>>[
              <String, Object?>{'text': 'test sse'},
            ],
          },
        }));

        final HttpClientResponse resp = await req.close();
        expect(resp.statusCode, equals(HttpStatus.ok));
        client.close(force: true);
      } finally {
        simulateSseFlushErrorForTesting = false;
        await server.close(force: true);
      }
    });

    test('15. Web server line 4570: HTTP/1.0 request without Host header evaluates requestedUri.authority', () async {
      final dynamic context = await createAdkDevWebContextForTesting(
        runtime: runtime,
        project: project,
        agentsDir: tempDir.path,
        a2a: false,
      );

      final HttpServer server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final Completer<String?> originCompleter = Completer<String?>();
      server.listen((HttpRequest req) async {
        if (!originCompleter.isCompleted) {
          originCompleter.complete(getRequestOriginForTesting(req));
        }
        await handleDevWebServerRequestForTesting(req, context);
      });

      try {
        final Socket socket = await Socket.connect('127.0.0.1', server.port);
        socket.write('GET /apps/my_app/app-info HTTP/1.0\r\n\r\n');
        await socket.flush();

        final String? origin = await originCompleter.future;
        expect(origin, equals('http://127.0.0.1:${server.port}'));
        await socket.close();
      } finally {
        await server.close(force: true);
      }
    });

    test('16. Web server line 5538: FileSystemException caught when agent.json is a directory', () async {
      final Directory agentJsonDir = Directory(
        '${tempDir.path}${Platform.pathSeparator}my_app${Platform.pathSeparator}agent.json',
      );
      await agentJsonDir.create(recursive: true);

      final dynamic context = await createAdkDevWebContextForTesting(
        runtime: runtime,
        project: project,
        agentsDir: tempDir.path,
        a2a: true,
      );

      final HttpServer server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((HttpRequest req) async {
        await handleDevWebServerRequestForTesting(req, context);
      });

      try {
        final HttpClient client = HttpClient();
        final HttpClientRequest req = await client.getUrl(
          Uri.parse('http://127.0.0.1:${server.port}/a2a/my_app/.well-known/agent.json'),
        );
        final HttpClientResponse resp = await req.close();
        final String body = await utf8.decodeStream(resp);
        expect(resp.statusCode, equals(HttpStatus.ok));
        expect(body, contains('my_app'));
      } finally {
        await server.close(force: true);
      }
    });

    test('17. Web server line 6127: writeA2aSseTaskReplayForTesting with jsonRpcEnvelope: false streams raw items', () async {
      final dynamic context = await createAdkDevWebContextForTesting(
        runtime: runtime,
        project: project,
        agentsDir: tempDir.path,
        a2a: false,
      );

      final HttpServer server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((HttpRequest req) async {
        await writeA2aSseTaskReplayForTesting(
          req,
          context,
          id: 'test_id',
          jsonRpcEnvelope: false,
          task: <String, Object?>{'id': 'task_1', 'state': 'running'},
          updates: <Map<String, Object?>>[
            <String, Object?>{'id': 'task_1', 'state': 'completed'},
          ],
        );
      });

      try {
        final HttpClient client = HttpClient();
        final HttpClientRequest req = await client.getUrl(
          Uri.parse('http://127.0.0.1:${server.port}/'),
        );
        final HttpClientResponse resp = await req.close();
        final String body = await utf8.decodeStream(resp);
        expect(resp.statusCode, equals(HttpStatus.ok));
        expect(body, contains('running'));
        expect(body, contains('completed'));
      } finally {
        await server.close(force: true);
      }
    });
  });
}
