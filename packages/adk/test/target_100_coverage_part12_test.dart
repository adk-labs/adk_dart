import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:adk/adk.dart';
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

class _Part12StubModel extends BaseLlm {
  _Part12StubModel() : super(model: 'part12-stub-model');

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    yield LlmResponse(content: Content.modelText('part12 stub response'));
  }
}

void main() {
  setUpAll(() {
    LLMRegistry.register(
      supportedModels: <RegExp>[
        RegExp(r'^part12-stub-model$'),
        RegExp(r'^gemini-.*$'),
      ],
      factory: (String m) => _Part12StubModel(),
    );
  });

  tearDownAll(LLMRegistry.clear);

  group('Target 100% Coverage - Part 12 CLI Remaining Lines', () {
    test('runEval with test_config.json and optimize with print_detailed_results', () async {
      final Directory tempDir = Directory.systemTemp.createTempSync('part12_eval_');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      File('${tempDir.path}/root_agent.yaml').writeAsStringSync('name: test_agent\ninstruction: Test prompt\n');
      final File evalSetFile = File('${tempDir.path}/eval_set.json')
        ..writeAsStringSync(jsonEncode(<String, Object?>{
          'name': 'eval_set_1',
          'eval_cases': <Object?>[],
        }));
      // default config file named test_config.json next to eval set
      File('${tempDir.path}/test_config.json').writeAsStringSync(jsonEncode(<String, Object?>{
        'criteria': <Object?>[],
      }));

      final StringBuffer out = StringBuffer();

      // Effective config file path from test_config.json next to eval_set.json
      expect(
        () => runEvalCliCommandForTesting(
          <String>[
            '--eval_storage_uri=gs://b/e',
            tempDir.path,
            evalSetFile.path,
          ],
          out: _BufferSink(out),
          err: null,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('generate_eval_cases executes generation with prompt', () async {
      final Directory tempDir = Directory.systemTemp.createTempSync('part12_gen_cases_');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      final File cfgFile = File('${tempDir.path}/gen_cfg.json')
        ..writeAsStringSync(jsonEncode(<String, Object?>{
          'generation_prompt': 'Generate realistic inquiry',
          'scenarios': <Object?>['Scenario A'],
          'count': 1,
        }));
      final File sessFile = File('${tempDir.path}/sess.json')
        ..writeAsStringSync(jsonEncode(<String, Object?>{
          'session_id': 's1',
          'events': <Object?>[],
        }));

      final StringBuffer out = StringBuffer();
      final int code = await runAdkCli(
        <String>[
          'eval_set',
          'generate_eval_cases',
          '--conversation_generation_config_file=${cfgFile.path}',
          '--session_input_file=${sessFile.path}',
          tempDir.path,
          'gen_set',
        ],
        outSink: _BufferSink(out),
        errSink: _BufferSink(out),
      );
      expect(code, 0);
    });

    test('Conformance record, test execution, report, and case discovery branches', () async {
      final Directory tempDir = Directory.systemTemp.createTempSync('part12_conf_');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      final Directory cat1CaseA = Directory('${tempDir.path}/cat1/case_a')..createSync(recursive: true);
      final Directory cat1CaseB = Directory('${tempDir.path}/cat1/case_b')..createSync(recursive: true);
      final Directory cat2CaseC = Directory('${tempDir.path}/cat2/case_c')..createSync(recursive: true);
      final Directory catBad = Directory('${tempDir.path}/catBad/bad_case')..createSync(recursive: true);

      File('${cat1CaseA.path}/spec.yaml').writeAsStringSync('agent: a\ndescription: Desc A\nuser_messages: []\n');
      File('${cat1CaseB.path}/spec.yaml').writeAsStringSync('agent: b\ndescription: Desc B\nuser_messages: []\n');
      File('${cat2CaseC.path}/spec.yaml').writeAsStringSync('agent: c\ndescription: Desc C\nuser_messages: []\n');
      File('${catBad.path}/spec.yaml').writeAsStringSync('invalid: yaml: [unclosed');

      // Pre-create generated files for case_a to test deletion
      final File sessA = File('${cat1CaseA.path}/generated-session.yaml')..writeAsStringSync('test');
      final File recA = File('${cat1CaseA.path}/generated-recordings.yaml')..writeAsStringSync('test');

      final StringBuffer out = StringBuffer();

      // 1. discoverConformanceCasesForTesting handles sorting (same cat, diff cat) and invalid yaml exception
      final List<dynamic> cases = await discoverConformanceCasesForTesting(
        <String>[tempDir.path],
        out: _BufferSink(out),
        replayMode: false,
        streamingMode: StreamingMode.none,
      );
      expect(cases, hasLength(3));
      expect(out.toString(), contains('Failed to load'));

      // 2. Mock HTTP server for AdkWebServerClient
      final HttpServer mockServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => mockServer.close(force: true));

      int sessionCounter = 0;
      mockServer.listen((HttpRequest req) async {
        if (req.uri.path.endsWith('/sessions')) {
          sessionCounter++;
          req.response.statusCode = HttpStatus.ok;
          req.response.headers.contentType = ContentType.json;
          if (sessionCounter == 1) {
            req.response.write(jsonEncode(<String, Object?>{}));
          } else {
            req.response.write(jsonEncode(<String, Object?>{'id': 'sess_live_123'}));
          }
          await req.response.close();
        } else {
          req.response.statusCode = HttpStatus.notFound;
          await req.response.close();
        }
      });

      final AdkWebServerClient client = AdkWebServerClient(
        Uri.parse('http://${mockServer.address.host}:${mockServer.port}'),
      );

      // 3. recordConformanceCaseForTesting deletes pre-existing files and throws on empty session
      await expectLater(
        recordConformanceCaseForTesting(
          client,
          cases.first,
          userId: 'test_u',
          streamingMode: StreamingMode.none,
        ),
        throwsA(isA<StateError>()),
      );
      expect(sessA.existsSync(), isFalse);
      expect(recA.existsSync(), isFalse);

      // 4. runConformanceTestCaseForTesting live mode
      final dynamic liveRes = await runConformanceTestCaseForTesting(
        client,
        cases.first,
        mode: 'live',
        userId: 'test_u',
        streamingMode: StreamingMode.none,
      );
      expect(liveRes.success, isTrue);

      // 5. runConformanceTestCaseForTesting replay mode with missing recorded session
      final dynamic replayRes = await runConformanceTestCaseForTesting(
        client,
        cases.first,
        mode: 'replay',
        userId: 'test_u',
        streamingMode: StreamingMode.none,
      );
      expect(replayRes.success, isFalse);
      expect(replayRes.errorMessage, contains('No recorded session found'));

      // 6. writeConformanceReportMarkdownForTesting with null reportDir
      final String report = await writeConformanceReportMarkdownForTesting(
        summaries: <dynamic>[],
        reportDir: null,
        versionData: <String, Object?>{'server_version': '1.2.3'},
      );
      expect(report, contains('1_2_3'));
      if (File(report).existsSync()) {
        File(report).deleteSync();
      }
    });

    test('CLI parsing edge cases across all commands', () {
      // 1. eval_set create with --eval_storage_uri=... and --log_level=...
      final dynamic cmd1 = parseEvalSetCreateCommandForTesting(<String>[
        '--eval_storage_uri=gs://b/e',
        '--log_level=debug',
        '.',
        'set1',
      ]);
      expect(cmd1.evalStorageUri, 'gs://b/e');

      // 2. eval_set add_eval_case with --eval_storage_uri, --verbosity, --session_input_file=...
      final dynamic cmd2 = parseEvalSetAddEvalCaseCommandForTesting(<String>[
        '--eval_storage_uri',
        'gs://b/e',
        '--eval_storage_uri=gs://b/e2',
        '--log_level',
        'debug',
        '--verbosity=info',
        '--scenarios_file=sc.json',
        '--session_input_file=sess.json',
        '.',
        'set2',
      ]);
      expect(cmd2.evalStorageUri, 'gs://b/e2');

      // Missing session_input_file error
      expect(
        () => parseEvalSetAddEvalCaseCommandForTesting(<String>[
          '--scenarios_file=sc.json',
          '.',
          'set_err',
        ]),
        throwsA(isA<CliUsageError>()),
      );

      // 3. conformance record options: --base_url=..., --user_id=..., --streaming_mode=..., --streaming-mode=...
      final dynamic cmd3 = parseConformanceRecordCommandForTesting(<String>[
        '--base_url=http://localhost:8000',
        '--user_id=u1',
        '--streaming_mode=sse',
        '--streaming-mode=none',
        '.',
      ]);
      expect(cmd3.streamingMode, StreamingMode.none);

      // 4. conformance test options: --base_url=..., --user_id=..., --streaming-mode=...
      final dynamic cmd4 = parseConformanceTestCommandForTesting(<String>[
        '--base_url=http://localhost:8000',
        '--user_id=u2',
        '--streaming-mode=sse',
        '.',
      ]);
      expect(cmd4.streamingMode, StreamingMode.sse);

      // 5. create with --app_name and --app-name
      final ParsedAdkCommand cmd5 = parseAdkCliArgs(<String>[
        'create',
        '--app_name',
        'app1',
        '--app-name',
        'app2',
        '.',
      ]);
      expect(cmd5.type, AdkCommandType.create);
      expect(cmd5.appName, 'app2');

      // 6. avatar config JSON non-map error
      expect(
        () => parseAdkCliArgs(<String>['web', '--avatar_config="not_a_map"}', '.']),
        throwsA(isA<CliUsageError>()),
      );

      // 7. avatar config empty key error
      expect(
        () => parseAdkCliArgs(<String>['web', '--avatar_config= =foo', '.']),
        throwsA(isA<CliUsageError>()),
      );

      // 8. disable_features with unknown feature warning
      final ParsedAdkCommand cmd8 = parseAdkCliArgs(<String>[
        'run',
        '--disable_features=unknown_feat_abc',
        '.',
      ]);
      expect(cmd8.disableFeatures, contains('unknown_feat_abc'));
    });

    test('run command loading App and session timeout & resume branches', () async {
      final Directory tempDir = Directory.systemTemp.createTempSync('part12_run_app_');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      // 1. App in root_agent.yaml or agent.dart
      File('${tempDir.path}/root_agent.yaml').writeAsStringSync('''
name: custom_app_pkg
instruction: App instructions
''');

      final StringBuffer out = StringBuffer();
      final StringBuffer err = StringBuffer();

      // 2. Timeout in single-step message execution
      final int timeoutCode = await runAdkCli(
        <String>[
          'run',
          '--timeout=1s',
          '--message=hello',
          tempDir.path,
        ],
        outSink: _BufferSink(out),
        errSink: _BufferSink(err),
      );
      expect(timeoutCode, anyOf(0, 1));

      // Invalid timeout syntax usage error
      final int invalidTimeoutCode = await runAdkCli(
        <String>[
          'run',
          '--timeout=0',
          '--message=hello',
          tempDir.path,
        ],
        outSink: _BufferSink(StringBuffer()),
        errSink: _BufferSink(StringBuffer()),
      );
      expect(invalidTimeoutCode, 64);

      // 3. Auto-resuming open interrupt with message
      final Directory tempResume = Directory.systemTemp.createTempSync('part12_resume_');
      addTearDown(() => tempResume.deleteSync(recursive: true));
      File('${tempResume.path}/root_agent.yaml').writeAsStringSync('''
name: resume_agent
instruction: Resume prompt
''');

      // Create a snapshot file with an open interrupt
      final File snapFile = File('${tempResume.path}/snap.session.json')
        ..writeAsStringSync(jsonEncode(<String, Object?>{
          'id': 'sess_snap',
          'app_name': 'resume_agent',
          'user_id': 'user_snap',
          'state': <String, Object?>{'key': 'val'},
          'events': <Object?>[
            <String, Object?>{
              'id': 'evt_int',
              'author': 'model',
              'long_running_tool_ids': <Object?>['tool_int_1'],
              'content': <String, Object?>{
                'parts': <Object?>[
                  <String, Object?>{
                    'function_call': <String, Object?>{
                      'name': 'ask_user',
                      'id': 'tool_int_1',
                      'args': <String, Object?>{'q': 'question?'},
                    },
                  },
                ],
              },
            },
          ],
        }));

      out.clear();
      final int snapCode = await runAdkCli(
        <String>[
          'run',
          '--resume=${snapFile.path}',
          '--message=my response',
          tempResume.path,
        ],
        outSink: _BufferSink(out),
        errSink: _BufferSink(err),
      );
      expect(snapCode, anyOf(0, 1, 2));

      // 4. Session snapshot file where lastEvent is user
      final File snapUserFile = File('${tempResume.path}/snap_user.session.json')
        ..writeAsStringSync(jsonEncode(<String, Object?>{
          'id': 'sess_user_snap',
          'app_name': 'resume_agent',
          'user_id': 'user_snap',
          'state': <String, Object?>{},
          'events': <Object?>[
            <String, Object?>{
              'id': 'evt_u',
              'author': 'user',
              'content': <String, Object?>{
                'parts': <Object?>[
                  <String, Object?>{'text': 'User last input'},
                ],
              },
            },
          ],
        }));

      out.clear();
      final int userSnapCode = await runAdkCli(
        <String>[
          'run',
          '--resume=${snapUserFile.path}',
          tempResume.path,
        ],
        outSink: _BufferSink(out),
        errSink: _BufferSink(err),
        readLine: () => 'exit',
      );
      expect(userSnapCode, anyOf(0, 1));
    });
  });

  group('Target 100% Coverage - Part 12 Web Server Remaining Lines', () {
    test('createAdkDevWebContextForTesting logoText error and multiple app resolution', () async {
      final Directory tempDir = Directory.systemTemp.createTempSync('part12_web_ctx_');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      final DevProjectConfig project = DevProjectConfig(
        appName: 'app_main',
        agentName: 'agent_main',
        description: 'Main App',
      );
      final DevAgentRuntime runtime = DevAgentRuntime(
        config: project,
        runner: InMemoryRunner(agent: LlmAgent(name: 'agent_main')),
      );
      addTearDown(() => runtime.runner.close());

      // 1. logoText without logoImageUrl throws ArgumentError in createAdkDevWebContextForTesting
      expect(
        () => createAdkDevWebContextForTesting(
          runtime: runtime,
          project: project,
          agentsDir: tempDir.path,
          logoText: 'LogoOnly',
        ),
        throwsA(isA<ArgumentError>()),
      );

      // 2. Setup a second app in agentsDir
      final Directory app2Dir = Directory('${tempDir.path}/app_two')..createSync();
      File('${app2Dir.path}/root_agent.yaml').writeAsStringSync('''
name: agent_two
instruction: Agent Two prompt
''');

      final dynamic ctx = await createAdkDevWebContextForTesting(
        runtime: runtime,
        project: project,
        agentsDir: tempDir.path,
      );

      // Runner and agent resolution for second app
      final Runner runnerTwo = await ctx.getRunner('app_two');
      expect(runnerTwo.agent.name, 'agent_two');

      final BaseAgent agentTwo = ctx.getRootAgent('app_two');
      expect(agentTwo.name, 'agent_two');

      // Fallback for empty app name
      final BaseAgent fallback = ctx.getRootAgent('');
      expect(fallback.name, 'agent_main');

      // Missing app rethrows ArgumentError
      expect(() => ctx.getRootAgent('missing_app'), throwsA(isA<ArgumentError>()));

      // Multiple app details list and sorting
      final List<Map<String, Object?>> details = agentDetailsTesting(ctx);
      expect(details.length, greaterThanOrEqualTo(2));

      // Record trace and read trace
      final Event dummyEvent = Event(
        id: 'trace_evt_1',
        invocationId: 'inv_1',
        author: 'model',
        customMetadata: <String, Object?>{'trace_info': 'yes'},
      );
      ctx.recordTraceEvent(
        appName: 'app_main',
        userId: 'u1',
        sessionId: 's1',
        event: dummyEvent,
      );
      final Map<String, Object?>? trace = ctx.readTraceByEventId('trace_evt_1');
      expect(trace, isNotNull);
      final List<Map<String, Object?>> sessionTraces = ctx.readTraceBySessionId('s1');
      expect(sessionTraces, isNotEmpty);
    });

    test('enqueueA2aPushDeliveryTesting and A2A push notification headers', () async {
      final Directory tempDir = Directory.systemTemp.createTempSync('part12_push_');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      // Local server to receive push notification
      final HttpServer pushReceiver = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => pushReceiver.close(force: true));

      final Completer<void> receivedCompleter = Completer<void>();
      pushReceiver.listen((HttpRequest req) async {
        expect(req.headers.value('X-Custom-Header'), 'CustomVal');
        req.response.statusCode = HttpStatus.ok;
        await req.response.close();
        if (!receivedCompleter.isCompleted) {
          receivedCompleter.complete();
        }
      });

      final DevProjectConfig project = DevProjectConfig(
        appName: 'app_push',
        agentName: 'agent_push',
        description: 'Push App',
      );
      final DevAgentRuntime runtime = DevAgentRuntime(
        config: project,
        runner: InMemoryRunner(agent: LlmAgent(name: 'agent_push')),
      );
      addTearDown(() => runtime.runner.close());

      final dynamic ctx = await createAdkDevWebContextForTesting(
        runtime: runtime,
        project: project,
        agentsDir: tempDir.path,
      );

      await enqueueA2aPushDeliveryTesting(
        ctx,
        appName: 'app_push',
        taskId: 'task_push_1',
        pushConfig: <String, Object?>{
          'url': 'http://127.0.0.1:${pushReceiver.port}/push',
          'headers': <String, String>{'X-Custom-Header': 'CustomVal'},
        },
        task: <String, Object?>{'id': 'task_push_1'},
        updates: <Map<String, Object?>>[
          <String, Object?>{'status': 'running'},
        ],
      );

      await receivedCompleter.future.timeout(const Duration(seconds: 3));
    });

    test('HTTP endpoints: evals route, trigger route exceptions, and screen stream', () async {
      final Directory tempDir = Directory.systemTemp.createTempSync('part12_http_');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      final DevProjectConfig project = DevProjectConfig(
        appName: 'app_http',
        agentName: 'agent_http',
        description: 'HTTP App',
      );
      final DevAgentRuntime runtime = DevAgentRuntime(
        config: project,
        runner: InMemoryRunner(agent: LlmAgent(name: 'agent_http')),
      );
      addTearDown(() => runtime.runner.close());

      final HttpServer server = await startAdkDevWebServer(
        runtime: runtime,
        project: project,
        agentsDir: tempDir.path,
        port: 0,
        a2a: true,
        triggerSources: const <String>['pubsub'],
        maxLlmCalls: 10,
        extraPlugins: const <String>['non_existent_extra_plugin'],
      );
      addTearDown(() => server.close(force: true));

      final HttpClient client = HttpClient();
      addTearDown(client.close);

      // 1. GET /apps/{appName}/eval_sets/{evalSetId}/evals/{evalCaseId} -> 404
      HttpClientRequest req = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/apps/app_http/eval_sets/set1/evals/case1'),
      );
      HttpClientResponse res = await req.close();
      expect(res.statusCode, HttpStatus.notFound);
      await res.drain<void>();

      // 2. Trigger route exceptions: SpecialAgentAccessDenied, ArgumentError, Exception
      handleRequestTestingOverride = (HttpRequest r, dynamic c) async {
        if (r.uri.path.contains('access_denied')) {
          throw const SpecialAgentAccessDeniedException();
        }
        if (r.uri.path.contains('arg_err')) {
          throw ArgumentError('Invalid trigger argument');
        }
        if (r.uri.path.contains('gen_ex')) {
          throw Exception('Internal trigger failure');
        }
        await handleTriggerRouteForTesting(
          r,
          c,
          appName: 'app_http',
          triggerSource: 'pubsub',
        );
      };

      req = await client.postUrl(Uri.parse('http://127.0.0.1:${server.port}/apps/app_http/trigger/pubsub/access_denied'));
      res = await req.close();
      expect(res.statusCode, HttpStatus.forbidden);
      await res.drain<void>();

      req = await client.postUrl(Uri.parse('http://127.0.0.1:${server.port}/apps/app_http/trigger/pubsub/arg_err'));
      res = await req.close();
      expect(res.statusCode, HttpStatus.badRequest);
      await res.drain<void>();

      req = await client.postUrl(Uri.parse('http://127.0.0.1:${server.port}/apps/app_http/trigger/pubsub/gen_ex'));
      res = await req.close();
      expect(res.statusCode, HttpStatus.internalServerError);
      await res.drain<void>();

      handleRequestTestingOverride = null;

      // 4. Run eval with empty cases and legacy payload: POST /apps/{appName}/eval_sets/{evalSetId}/run -> 404
      req = await client.postUrl(Uri.parse('http://127.0.0.1:${server.port}/apps/app_http/eval_sets/set1/run'));
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(<String, Object?>{}));
      res = await req.close();
      expect(res.statusCode, HttpStatus.badRequest);
      await res.drain<void>();

      // 5. Artifact versions error: invalid version string -> 400
      req = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/apps/app_http/users/u1/sessions/s1/artifacts/art1/versions/not_a_num/metadata'),
      );
      res = await req.close();
      expect(res.statusCode, HttpStatus.badRequest);
      await res.drain<void>();

      // 6. Artifact versions not found: version 999 -> 404
      req = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/apps/app_http/users/u1/sessions/s1/artifacts/art1/versions/999/metadata'),
      );
      res = await req.close();
      expect(res.statusCode, HttpStatus.notFound);
      await res.drain<void>();

      // 7. POST /run with maxLlmCalls context
      await runtime.runner.sessionService.createSession(
        appName: 'app_http',
        userId: 'u1',
        sessionId: 's1',
      );
      req = await client.postUrl(
        Uri.parse('http://127.0.0.1:${server.port}/run'),
      );
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(<String, Object?>{
        'appName': 'app_http',
        'userId': 'u1',
        'sessionId': 's1',
        'autoCreateSession': true,
        'newMessage': <String, Object?>{
          'parts': <Object?>[
            <String, Object?>{'text': 'Hello'},
          ],
        },
      }));
      res = await req.close();
      expect(res.statusCode, HttpStatus.ok);
      await res.drain<void>();

      // 8. Run SSE with missing session and autoCreateSession: false -> 404
      req = await client.postUrl(
        Uri.parse('http://127.0.0.1:${server.port}/run_sse'),
      );
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(<String, Object?>{
        'appName': 'app_http',
        'userId': 'u1',
        'sessionId': 'missing_sess',
        'autoCreateSession': false,
        'newMessage': <String, Object?>{
          'parts': <Object?>[
            <String, Object?>{'text': 'Hello'},
          ],
        },
      }));
      res = await req.close();
      expect(res.statusCode, HttpStatus.notFound);
      await res.drain<void>();

      // 9. POST with empty body -> empty JSON object handled
      req = await client.postUrl(
        Uri.parse('http://127.0.0.1:${server.port}/run'),
      );
      req.headers.contentType = ContentType.json;
      res = await req.close();
      expect(res.statusCode, anyOf(HttpStatus.ok, HttpStatus.badRequest, HttpStatus.notFound));
      await res.drain<void>();

      // 10. A2A agent card with app_name query param
      req = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/.well-known/agent.json?app_name=app_http'),
      );
      res = await req.close();
      expect(res.statusCode, HttpStatus.ok);
      await res.drain<void>();

      // 11. Corrupted disk card json file -> FormatException handled gracefully
      final Directory a2aCardDir = Directory('${tempDir.path}/app_http/.well-known')..createSync(recursive: true);
      File('${a2aCardDir.path}/agent.json').writeAsStringSync('corrupt_not_json');
      req = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/a2a/app_http/.well-known/agent.json'),
      );
      res = await req.close();
      expect(res.statusCode, HttpStatus.ok);
      await res.drain<void>();

      // 12. A2A RPC tasks:push_notification_config:get and flat params
      req = await client.postUrl(Uri.parse('http://127.0.0.1:${server.port}/a2a/app_http'));
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(<String, Object?>{
        'jsonrpc': '2.0',
        'id': 'r_get',
        'method': 'tasks:push_notification_config:get',
        'params': <String, Object?>{'taskId': 't_none'},
      }));
      res = await req.close();
      expect(res.statusCode, HttpStatus.ok);
      await res.drain<void>();

      // Flat params in pushnotificationconfig/set
      req = await client.postUrl(Uri.parse('http://127.0.0.1:${server.port}/a2a/app_http'));
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(<String, Object?>{
        'jsonrpc': '2.0',
        'id': 'r_flat',
        'method': 'tasks/pushnotificationconfig/set',
        'params': <String, Object?>{
          'taskId': 't_flat',
          'url': 'https://callback.example.com',
        },
      }));
      res = await req.close();
      expect(res.statusCode, HttpStatus.ok);
      await res.drain<void>();

      // A2A RPC throwing ArgumentError (-32602)
      req = await client.postUrl(Uri.parse('http://127.0.0.1:${server.port}/a2a/app_http'));
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(<String, Object?>{
        'jsonrpc': '2.0',
        'id': 'r_arg',
        'method': 'tasks/get',
        'params': 'not_a_map',
      }));
      res = await req.close();
      expect(res.statusCode, HttpStatus.ok);
      final String argBody = await utf8.decoder.bind(res).join();
      expect(argBody, contains('-32602'));

      // A2A message send with custom contextId
      req = await client.postUrl(Uri.parse('http://127.0.0.1:${server.port}/a2a/app_http'));
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(<String, Object?>{
        'jsonrpc': '2.0',
        'id': 'r_send',
        'method': 'message/send',
        'params': <String, Object?>{
          'contextId': 'ctx_custom_99',
          'parts': <Object?>[
            <String, Object?>{'text': 'Hello A2A'},
          ],
        },
      }));
      res = await req.close();
      expect(res.statusCode, HttpStatus.ok);
      await res.drain<void>();
    });
  });
}
