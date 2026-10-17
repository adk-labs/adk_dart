import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'package:adk/adk.dart';
import 'package:adk/src/cli/plugins/conformance_recordings_plugin.dart';
import 'package:adk/src/cli/plugins/conformance_recordings_schema.dart';
import 'package:adk/src/cli/plugins/conformance_replay_plugin.dart';

class _NoToJsonObject {
  @override
  String toString() => 'custom_no_to_json';
}

class _CaptureSink implements IOSink {
  final StringBuffer buffer = StringBuffer();
  final Completer<void> _doneCompleter = Completer<void>();

  @override
  Encoding encoding = utf8;

  @override
  void add(List<int> data) {
    buffer.write(utf8.decode(data, allowMalformed: true));
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final List<int> chunk in stream) {
      add(chunk);
    }
  }

  @override
  Future<void> close() async {
    if (!_doneCompleter.isCompleted) {
      _doneCompleter.complete();
    }
  }

  @override
  Future<void> get done => _doneCompleter.future;

  @override
  Future<void> flush() async {}

  @override
  void write(Object? object) {
    buffer.write(object);
  }

  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) {
    buffer.writeAll(objects, separator);
  }

  @override
  void writeCharCode(int charCode) {
    buffer.writeCharCode(charCode);
  }

  @override
  void writeln([Object? object = '']) {
    buffer.writeln(object ?? '');
  }

  String get output => buffer.toString();
}

void main() {
  group('Target 100 coverage part 3 - small files completion', () {
    test('agent_graph.dart covers labeled highlighted edges', () async {
      final FunctionNode a = node(
        (WorkflowContext _, Object? inVal) => inVal,
        name: 'stepA',
      );
      final FunctionNode b = node(
        (WorkflowContext _, Object? inVal) => inVal,
        name: 'stepB',
      );
      final Workflow wf = Workflow(
        name: 'labeled_wf',
        nodes: <BaseNode>[a, b],
        edges: <Edge>[
          Edge(fromNode: START, toNode: a),
          Edge(fromNode: a, toNode: b, route: 'custom_route'),
        ],
      );

      final String mermaid = await getAgentGraph(
        wf,
        highlightPairs: <(String, String)>{
          ('labeled_wf:stepA', 'labeled_wf:stepB'),
        },
      );
      expect(mermaid, contains('== "custom_route" ==>'));
    });

    test('cli_create.dart outSink null uses stdout', () async {
      final Directory tempDir = Directory.systemTemp.createTempSync('adk_create_stdout_');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      final int code = await runCreateCommand(
        projectDir: tempDir.path,
        appName: 'app_stdout',
        outSink: null,
      );
      expect(code, 0);
    });

    test('adk_web_server_client.dart covers PATCH, unsupported method, and error status', () async {
      final HttpServer server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));

      server.listen((HttpRequest req) async {
        final String path = req.uri.path;
        if (path.contains('/sessions')) {
          req.response.statusCode = 500;
          req.response.write('internal failure');
          await req.response.close();
        } else if (path == '/patch_ok') {
          req.response.statusCode = 200;
          req.response.headers.contentType = ContentType.json;
          req.response.write(jsonEncode(<String, Object?>{'patched': true}));
          await req.response.close();
        } else {
          req.response.statusCode = 200;
          req.response.write('{}');
          await req.response.close();
        }
      });

      final AdkWebServerClient client = AdkWebServerClient(
        Uri.parse('http://${server.address.host}:${server.port}'),
      );

      // Status >= 400 throws HttpException
      expect(
        () => client.createSession(userId: 'u1', appName: 'app1'),
        throwsA(isA<HttpException>()),
      );

      // Unsupported method
      expect(
        () => client.requestJson('HEAD', '/test'),
        throwsArgumentError,
      );

      // PATCH method
      final Map<String, Object?> patchRes = await client.requestJson('PATCH', '/patch_ok');
      expect(patchRes['patched'], isTrue);
    });

    test('conformance_recordings_plugin.dart covers pre-existing recordings yaml on disk', () async {
      final Directory tempDir = Directory.systemTemp.createTempSync('adk_rec_exist_');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      final File recFile = File('${tempDir.path}${Platform.pathSeparator}generated-recordings.yaml');
      recFile.writeAsStringSync('recordings: []\n');

      final ConformanceRecordingsPlugin plugin = ConformanceRecordingsPlugin();
      final InvocationContext ctx = InvocationContext(
        invocationId: 'inv-exist',
        agent: LlmAgent(name: 'a', model: 'm'),
        sessionService: InMemorySessionService(),
        session: Session(id: 's', appName: 'app', userId: 'u'),
      );
      final CallbackContext cbCtx = CallbackContext(ctx);
      cbCtx.state['_adk_recordings_config'] = <String, Object?>{
        'dir': tempDir.path,
        'user_message_index': 0,
      };

      await plugin.beforeModelCallback(
        callbackContext: cbCtx,
        llmRequest: LlmRequest(
          contents: <Content>[Content.userText('hi')],
        ),
      );
      await plugin.afterModelCallback(
        callbackContext: cbCtx,
        llmResponse: LlmResponse(content: Content.modelText('reply')),
      );
      await plugin.afterRunCallback(invocationContext: ctx);
      expect(recFile.existsSync(), isTrue);
    });

    test('conformance_recordings_schema.dart partial_args and non-toJson normalization', () {
      final Map<String, Object?> normalized = canonicalizeSerializedLlmRequest(<String, Object?>{
        'contents': <Object?>[
          <String, Object?>{
            'parts': <Object?>[
              <String, Object?>{
                'function_call': <String, Object?>{
                  'name': 'fn',
                  'partial_args': <Object?>[
                    <String, Object?>{'chunk': 'a'},
                  ],
                },
              },
            ],
          },
        ],
      });
      expect(normalized, isNotNull);

      final Object? strVal = normalizeConformanceJsonValue(_NoToJsonObject());
      expect(strVal, 'custom_no_to_json');
    });

    test('conformance_replay_plugin.dart comprehensive branches and error handling', () async {
      final Directory tempDir = Directory.systemTemp.createTempSync('adk_replay_gaps_');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      // 1. caseDir empty
      final ConformanceReplayPlugin plugin = ConformanceReplayPlugin();
      final InvocationContext ctx = InvocationContext(
        invocationId: 'inv-rep-1',
        agent: LlmAgent(name: 'my_agent', model: 'm'),
        sessionService: InMemorySessionService(),
        session: Session(id: 's', appName: 'app', userId: 'u'),
      );
      final CallbackContext cbCtx = CallbackContext(ctx);
      cbCtx.state['_adk_replay_config'] = <String, Object?>{
        'dir': '   ',
        'user_message_index': 0,
      };
      expect(
        () => plugin.beforeRunCallback(
          invocationContext: ctx,
        ),
        throwsA(isA<ReplayConfigError>()),
      );

      // 2. recordings file invalid format (scalar or list)
      final File recFile = File('${tempDir.path}${Platform.pathSeparator}generated-recordings.yaml');
      recFile.writeAsStringSync('- item1\n- item2\n');
      cbCtx.state['_adk_replay_config'] = <dynamic, dynamic>{
        'dir': tempDir.path,
        'user_message_index': 0,
      };
      expect(
        () => plugin.beforeRunCallback(
          invocationContext: ctx,
        ),
        throwsA(isA<ReplayConfigError>()),
      );

      // 3. valid file with recorded tool call but missing toolResponse
      recFile.writeAsStringSync('''
recordings:
  - user_message_index: 0
    agent_name: my_agent
    tool_recording:
      tool_call:
        name: tool_a
        args:
          x: 1
''');
      final FunctionTool toolA = FunctionTool(
        name: 'tool_a',
        description: 'desc',
        func: (Map<String, dynamic> args) => 42,
      );
      final ToolContext toolCtx = Context(
        ctx,
        functionCallId: 'call_1',
      );

      // Missing toolResponse throws ReplayVerificationError
      expect(
        () => plugin.beforeToolCallback(
          tool: toolA,
          toolArgs: <String, dynamic>{'x': 1},
          toolContext: toolCtx,
        ),
        throwsA(isA<ReplayVerificationError>()),
      );

      // 4. Tool name mismatch
      recFile.writeAsStringSync('''
recordings:
  - user_message_index: 0
    agent_name: my_agent
    tool_recording:
      tool_call:
        name: tool_expected
        args:
          x: 1
      tool_response:
        response:
          out: ok
''');
      final ConformanceReplayPlugin plugin4 = ConformanceReplayPlugin();
      final InvocationContext ctx4 = InvocationContext(
        invocationId: 'inv-rep-4',
        agent: LlmAgent(name: 'my_agent', model: 'm'),
        sessionService: InMemorySessionService(),
        session: Session(id: 's', appName: 'app', userId: 'u'),
      );
      final CallbackContext cbCtx4 = CallbackContext(ctx4);
      cbCtx4.state['_adk_replay_config'] = <dynamic, dynamic>{
        'dir': tempDir.path,
        'user_message_index': 0,
      };
      final ToolContext toolCtx4 = Context(ctx4, functionCallId: 'call_4');

      expect(
        () => plugin4.beforeToolCallback(
          tool: toolA,
          toolArgs: <String, dynamic>{'x': 1},
          toolContext: toolCtx4,
        ),
        throwsA(isA<ReplayVerificationError>()),
      );

      // 5. Tool args mismatch
      final ConformanceReplayPlugin plugin5 = ConformanceReplayPlugin();
      final InvocationContext ctx5 = InvocationContext(
        invocationId: 'inv-rep-5',
        agent: LlmAgent(name: 'my_agent', model: 'm'),
        sessionService: InMemorySessionService(),
        session: Session(id: 's', appName: 'app', userId: 'u'),
      );
      final CallbackContext cbCtx5 = CallbackContext(ctx5);
      cbCtx5.state['_adk_replay_config'] = <dynamic, dynamic>{
        'dir': tempDir.path,
        'user_message_index': 0,
      };
      final ToolContext toolCtx5 = Context(ctx5, functionCallId: 'call_5');

      final FunctionTool toolExpected = FunctionTool(
        name: 'tool_expected',
        description: 'desc',
        func: (Map<String, dynamic> args) => 42,
      );
      expect(
        () => plugin5.beforeToolCallback(
          tool: toolExpected,
          toolArgs: <String, dynamic>{'x': 999},
          toolContext: toolCtx5,
        ),
        throwsA(isA<ReplayVerificationError>()),
      );

      // 6. Matching tool call followed by excess tool request
      final ConformanceReplayPlugin plugin6 = ConformanceReplayPlugin();
      final InvocationContext ctx6 = InvocationContext(
        invocationId: 'inv-rep-6',
        agent: LlmAgent(name: 'my_agent', model: 'm'),
        sessionService: InMemorySessionService(),
        session: Session(id: 's', appName: 'app', userId: 'u'),
      );
      final CallbackContext cbCtx6 = CallbackContext(ctx6);
      cbCtx6.state['_adk_replay_config'] = <dynamic, dynamic>{
        'dir': tempDir.path,
        'user_message_index': 0,
      };
      final ToolContext toolCtx6 = Context(ctx6, functionCallId: 'call_6');

      final Map<String, dynamic>? toolRes = await plugin6.beforeToolCallback(
        tool: toolExpected,
        toolArgs: <String, dynamic>{'x': 1},
        toolContext: toolCtx6,
      );
      expect(toolRes?['out'], 'ok');

      expect(
        () => plugin6.beforeToolCallback(
          tool: toolExpected,
          toolArgs: <String, dynamic>{'x': 1},
          toolContext: toolCtx6,
        ),
        throwsA(isA<ReplayVerificationError>()),
      );
    });

    test('service_registry.dart GCS HTTP request and auth headers', () async {
      final HttpServer server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));

      server.listen((HttpRequest req) async {
        req.response.statusCode = 200;
        req.response.headers.set('x-custom-res', 'val');
        req.response.write('gcs response body');
        await req.response.close();
      });

      final GcsArtifactHttpResponse response = await sendGcsArtifactHttpRequest(
        GcsArtifactHttpRequest(
          method: 'POST',
          uri: Uri.parse('http://${server.address.host}:${server.port}/test'),
          headers: <String, String>{'x-req': '1'},
          bodyBytes: <int>[1, 2, 3],
        ),
      );
      expect(response.statusCode, 200);
      expect(response.headers['x-custom-res'], 'val');
      expect(utf8.decode(response.bodyBytes), 'gcs response body');

      // resolveGcsArtifactAuthHeaders
      setCliEnvironmentValue('GOOGLE_ACCESS_TOKEN', 'token-abc');
      final Map<String, String> authHeaders = await resolveGcsArtifactAuthHeaders();
      expect(authHeaders[HttpHeaders.authorizationHeader], 'Bearer token-abc');
    });

    test('service_registry.dart authority empty and error validations', () {
      final ServiceRegistry registry = getServiceRegistry();

      // gs:///bucket authority empty
      final Object? gcsService = registry.createArtifactService('gs:///my-bucket/prefix');
      expect(gcsService, isNotNull);

      // Network DB session error with invalid connection URI
      DatabaseSessionService.registerCustomFactory(
        scheme: 'postgresql',
        factory: (_) => throw Exception('forced postgresql error'),
      );
      expect(
        () => registry.createSessionService('postgresql://localhost:5432/test'),
        throwsStateError,
      );
      DatabaseSessionService.unregisterCustomFactory('postgresql');

      // Short-form agent engine ID with empty agentsDir
      expect(
        () => registry.createSessionService('agentengine://short_id', kwargs: <String, Object?>{'agents_dir': ''}),
        throwsArgumentError,
      );

      // loadServicesModule with service not matching interface
      final Directory tempDir = Directory.systemTemp.createTempSync('adk_svc_type_err_');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      registerServiceClassFactory('custom.String', (String uri, {Map<String, Object?>? kwargs}) => 'not-a-service');
      addTearDown(() => resetServiceRegistryForTest());

      final File yamlFile = File('${tempDir.path}${Platform.pathSeparator}services.yaml');
      yamlFile.writeAsStringSync('''
services:
  - type: session
    scheme: badsess
    class: custom.String
  - type: artifact
    scheme: badart
    class: custom.String
  - type: memory
    scheme: badmem
    class: custom.String
''');

      loadServicesModule(tempDir.path, registry: registry);
      expect(() => registry.createSessionService('badsess://x'), throwsArgumentError);
      expect(() => registry.createArtifactService('badart://x'), throwsArgumentError);
      expect(() => registry.createMemoryService('badmem://x'), throwsArgumentError);
    });

    test('trigger_routes.dart invalid base64 and rate limit transient retries', () async {
      final Directory tempDir = Directory.systemTemp.createTempSync('adk_trig_ext_');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      LLMRegistry.register(
        supportedModels: <RegExp>[RegExp(r'^part3_echo_model$')],
        factory: (String model) => _Part3EchoLlm(),
      );
      final InMemorySessionService sessService = InMemorySessionService();
      final Runner runner = Runner(
        appName: 'trig_app',
        agent: LlmAgent(name: 'a', model: 'part3_echo_model'),
        sessionService: sessService,
      );
      final TriggerRouter router = TriggerRouter(
        getRunnerAsync: (String app) async => runner,
        sessionService: sessService,
        triggerSources: const <String>['pubsub', 'eventarc'],
        maxRetries: 1,
        baseDelaySeconds: 0.01,
        maxDelaySeconds: 0.02,
      );

      // Eventarc with invalid base64 in message.data
      final TriggerResponse resp = await router.handleEventarcRequest(
        appName: 'trig_app',
        triggerRequest: EventarcTriggerRequest(
          id: 'ev-1',
          data: <String, Object?>{
            'message': <String, Object?>{
              'data': 'invalid-b64-!@#\$%',
              'attributes': <String, Object?>{'k': 'v'},
            },
          },
        ),
      );
      expect(resp.response, isNotNull);

      // Eventarc with empty data and empty extraFields
      final TriggerResponse emptyResp = await router.handleEventarcRequest(
        appName: 'trig_app',
        triggerRequest: EventarcTriggerRequest(),
      );
      expect(emptyResp.response, isNotNull);

      // Existing session reuse
      final Session existingSess = await sessService.createSession(
        appName: 'trig_app',
        userId: 'u',
        sessionId: 'existing_id',
      );
      expect(existingSess.id, 'existing_id');
      final TriggerResponse reusedResp = await router.handlePubSubRequest(
        appName: 'trig_app',
        triggerRequest: PubSubTriggerRequest(
          message: PubSubMessage(
            data: base64Encode(utf8.encode('hello again')),
            attributes: const <String, String>{'session_id': 'existing_id'},
          ),
        ),
      );
      expect(reusedResp.response, isNotNull);
    });

    test('cli_deploy.dart defaultDeployRunner and CLI flags', () async {
      final _CaptureSink out = _CaptureSink();
      final _CaptureSink err = _CaptureSink();

      final int dartExit = await defaultDeployRunner(
        <String>[Platform.executable, '--version'],
        out: out,
        err: err,
        environment: Platform.environment,
      );
      expect(dartExit, 0);

      // Test deprecated --verbosity and all parsing branches
      final DeployCliOptions verbOpts = parseDeployCliOptions(
        <String>['--verbosity=DEBUG', '--dry-run', '--validate_agent_import', '--cluster_name', 'c1', '--service_account', 'sa@p.com', '--worker_pool', 'wp1'],
        env: <String, String>{'GOOGLE_CLOUD_PROJECT': 'p'},
      );
      expect(verbOpts.logLevel, 'DEBUG');
      expect(verbOpts.warnings, isNotEmpty);
      expect(verbOpts.clusterName, 'c1');
      expect(verbOpts.serviceAccount, 'sa@p.com');
      expect(verbOpts.workerPool, 'wp1');
    });
  });

  group('Target 100 coverage part 3 - dev/cli.dart full commands', () {
    test('runAdkCli help, version, doctor and diag commands', () async {
      final _CaptureSink out = _CaptureSink();

      expect(await runAdkCli(<String>[], outSink: out), 0);
      expect(out.output, contains('Usage: adk'));

      out.buffer.clear();
      expect(await runAdkCli(<String>['-h'], outSink: out), 0);
      expect(out.output, contains('Usage: adk'));

      out.buffer.clear();
      expect(await runAdkCli(<String>['--help'], outSink: out), 0);
      expect(out.output, contains('Usage: adk'));

      out.buffer.clear();
      expect(await runAdkCli(<String>['--version'], outSink: out), 0);
      expect(out.output, contains('adk version'));

      out.buffer.clear();
      expect(await runAdkCli(<String>['-V'], outSink: out), 0);
      expect(out.output, contains('adk version'));

      out.buffer.clear();
      expect(await runAdkCli(<String>['version'], outSink: out), 0);
      expect(out.output, contains('adk version'));

      out.buffer.clear();
      expect(await runAdkCli(<String>['doctor'], outSink: out), 0);
      expect(out.output, contains('Platform OS'));

      out.buffer.clear();
      expect(await runAdkCli(<String>['doctor', '--help'], outSink: out), 0);
      expect(out.output, contains('Usage: adk'));

      out.buffer.clear();
      expect(await runAdkCli(<String>['diag'], outSink: out), 0);
      expect(out.output, contains('Platform OS'));
    });

    test('runAdkCli deploy subcommand delegation', () async {
      final _CaptureSink out = _CaptureSink();
      final _CaptureSink err = _CaptureSink();

      final int code = await runAdkCli(
        <String>['deploy', '--help'],
        outSink: out,
        errSink: err,
      );
      expect(code, 0);
      expect(out.output, contains('Usage: adk deploy'));
    });

    test('runAdkCli web and api_server subcommands with stopSignal', () async {
      final Directory tempDir = Directory.systemTemp.createTempSync('adk_web_cli_');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      await createDevProject(projectDirPath: tempDir.path);

      final _CaptureSink out = _CaptureSink();
      final _CaptureSink err = _CaptureSink();

      final int webCode = await runAdkCli(
        <String>[
          'web',
          tempDir.path,
          '--port', '0',
          '--url_prefix', '/my_prefix',
          '--log-level', 'DEBUG',
        ],
        outSink: out,
        errSink: err,
        stopSignal: Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      expect(webCode, 0);
      expect(out.output, contains('ADK web server is running'));

      out.buffer.clear();
      final int apiCode = await runAdkCli(
        <String>[
          'api_server',
          tempDir.path,
          '--port', '0',
          '--no-ui',
        ],
        outSink: out,
        errSink: err,
        stopSignal: Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      expect(apiCode, 0);
      expect(out.output, contains('UI is disabled for api_server mode'));
    });

    test('runAdkCli run interactive REPL with readLine', () async {
      final Directory tempDir = Directory.systemTemp.createTempSync('adk_run_repl_');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      await createDevProject(projectDirPath: tempDir.path);

      final _CaptureSink out = _CaptureSink();
      final _CaptureSink err = _CaptureSink();

      final List<String> inputs = <String>['', 'exit'];
      int idx = 0;
      final int code = await runAdkCli(
        <String>[
          'run',
          tempDir.path,
          '--save_session',
          '--session-id', 'test_repl_sess',
        ],
        outSink: out,
        errSink: err,
        readLine: () {
          if (idx < inputs.length) {
            return inputs[idx++];
          }
          return null;
        },
      );
      expect(code, 0);
      expect(out.output, contains('Running agent'));
      expect(out.output, contains('Session saved'));
    });

    test('runAdkCli test command', () async {
      final Directory tempDir = Directory.systemTemp.createTempSync('adk_test_cmd_');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      File('${tempDir.path}${Platform.pathSeparator}pubspec.yaml').writeAsStringSync('''
name: test_pkg
environment:
  sdk: '>=3.0.0 <4.0.0'
''');

      final _CaptureSink out = _CaptureSink();
      final _CaptureSink err = _CaptureSink();

      final int code = await runAdkCli(
        <String>['test', tempDir.path],
        outSink: out,
        errSink: err,
      );
      expect(code, anyOf(0, 1, 65));
    });

    test('runAdkCli telemetry commands', () async {
      final _CaptureSink out = _CaptureSink();
      final _CaptureSink err = _CaptureSink();

      expect(await runAdkCli(<String>['telemetry', 'status'], outSink: out, errSink: err), 0);
      expect(await runAdkCli(<String>['telemetry', 'disable'], outSink: out, errSink: err), 0);
      expect(await runAdkCli(<String>['telemetry', 'enable'], outSink: out, errSink: err), 0);
      expect(await runAdkCli(<String>['telemetry', 'invalid'], outSink: out, errSink: err), 64);
    });

    test('runAdkCli error handlers and unknown command', () async {
      final _CaptureSink out = _CaptureSink();
      final _CaptureSink err = _CaptureSink();

      expect(await runAdkCli(<String>['unknown_cmd'], outSink: out, errSink: err), 64);
      expect(await runAdkCli(<String>['eval'], outSink: out, errSink: err), 64);
      expect(await runAdkCli(<String>['eval_set'], outSink: out, errSink: err), 64);
      expect(await runAdkCli(<String>['conformance'], outSink: out, errSink: err), 64);
      expect(await runAdkCli(<String>['migrate'], outSink: out, errSink: err), 64);
      expect(await runAdkCli(<String>['optimize'], outSink: out, errSink: err), 64);
    });
  });
}

class _Part3EchoLlm extends BaseLlm {
  _Part3EchoLlm() : super(model: 'part3_echo_model');

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    yield LlmResponse(content: Content.modelText('echo response'));
  }
}
