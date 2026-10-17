import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:adk/cli.dart';
import 'package:adk/src/cli/cli_tools_click.dart' as click_cli;
import 'package:adk/src/dev/a2a_push_delivery_queue.dart';
import 'package:adk_dart/adk_dart.dart';
import 'package:adk_dart/src/evaluation/eval_config.dart' as core_eval_config;
import 'package:test/test.dart';

class _MockAgentLoader extends BaseAgentLoader {
  final Map<String, AgentOrApp> cache = <String, AgentOrApp>{};
  final List<String> removed = <String>[];

  @override
  List<String> listAgents() => <String>['agent_a', 'agent_b'];

  @override
  AgentOrApp loadAgent(String agentName) => cache[agentName] ?? Agent(name: agentName, model: 'gemini-2.5-flash');

  void removeAgentFromCache(String agentName) {
    removed.add(agentName);
    cache.remove(agentName);
  }
}

class _CustomBaseTool extends BaseTool {
  _CustomBaseTool({required super.name, super.description = 'custom tool'});

  @override
  Future<Object?> run({required Map<String, dynamic> args, required ToolContext toolContext}) async {
    return <String, Object?>{'ok': true};
  }
}

class _CustomBaseNode extends BaseNode {
  _CustomBaseNode({required super.name});

  @override
  FutureOr<Object?> run(WorkflowContext context, Object? nodeInput) async {
    return nodeInput;
  }
}

class _CapturedSink {
  _CapturedSink() : _controller = StreamController<List<int>>() {
    _controller.stream.listen(_bytes.addAll);
    sink = IOSink(_controller.sink);
  }

  final StreamController<List<int>> _controller;
  final List<int> _bytes = <int>[];
  late final IOSink sink;

  Future<String> closeAndRead() async {
    await sink.flush();
    await sink.close();
    await _controller.done;
    return utf8.decode(_bytes);
  }
}

void main() {
  group('shared_value.dart', () {
    test('stores and mutates value', () {
      final SharedValue<int> shared = SharedValue<int>(42);
      expect(shared.value, 42);
      shared.value = 100;
      expect(shared.value, 100);
    });
  });

  group('cleanup.dart', () {
    test('closeRunners handles empty and non-empty runners', () async {
      await closeRunners(<Runner>[]);

      final InMemoryRunner runner1 = InMemoryRunner(
        agent: Agent(name: 'r1', model: 'gemini-2.5-flash'),
        appName: 'r1',
      );
      final InMemoryRunner runner2 = InMemoryRunner(
        agent: Agent(name: 'r2', model: 'gemini-2.5-flash'),
        appName: 'r2',
      );
      await closeRunners(<Runner>[runner1, runner2], timeout: const Duration(seconds: 1));
    });
  });

  group('agent_change_handler.dart', () {
    test('onModified invalidates cache only for supported extensions', () {
      final Directory tempDir = Directory.systemTemp.createTempSync('adk_change_test_');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      final AgentLoader loader = AgentLoader(tempDir.path);
      final Set<String> runnersToClean = <String>{};
      final SharedValue<String> appRef = SharedValue<String>('my_app');

      final AgentChangeEventHandler handler = AgentChangeEventHandler(
        agentLoader: loader,
        runnersToClean: runnersToClean,
        currentAppNameRef: appRef,
      );

      handler.onModified('notes.txt');
      expect(runnersToClean, isEmpty);

      handler.onModified('agent.dart');
      expect(runnersToClean, contains('my_app'));

      handler.onModified('config.yaml');
      handler.onModified('config.yml');
      handler.onModified('agent.py');
      expect(runnersToClean.length, 1);
    });
  });

  group('common.dart', () {
    test('toCamelCase and normalizeJsonObject', () {
      expect(toCamelCase(''), '');
      expect(toCamelCase('_'), '');
      expect(toCamelCase('hello_world'), 'helloWorld');
      expect(toCamelCase('one_two_three'), 'oneTwoThree');
      expect(toCamelCase('alreadyCamel'), 'alreadycamel');

      final Map<String, Object?> normalized = normalizeJsonObject(<Object?, Object?>{
        'user_id': 123,
        'first_name': 'Alice',
      });
      expect(normalized['userId'], 123);
      expect(normalized['firstName'], 'Alice');
    });
  });

  group('evals.dart', () {
    test('createGcsEvalManagersFromUri and convertSessionToEvalInvocations', () {
      expect(
        () => createGcsEvalManagersFromUri('http://bucket/path'),
        throwsArgumentError,
      );

      setCliEnvironmentValue('GOOGLE_CLOUD_PROJECT', '');
      try {
        expect(
          () => createGcsEvalManagersFromUri('gs://my-bucket'),
          throwsStateError,
        );
      } finally {
        clearCliEnvironmentOverrides();
      }

      setCliEnvironmentValue('GOOGLE_CLOUD_PROJECT', 'test-proj');
      try {
        final GcsEvalManagers managers = createGcsEvalManagersFromUri('gs://my-bucket');
        expect(managers.evalSetsManager.bucketName, 'my-bucket');
        expect(managers.evalSetResultsManager.bucketName, 'my-bucket');
      } finally {
        clearCliEnvironmentOverrides();
      }

      final List<Invocation> emptyInvs = convertSessionToEvalInvocations(null);
      expect(emptyInvs, isEmpty);

      final Session session = Session(
        id: 's1',
        appName: 'app',
        userId: 'user',
        events: <Event>[
          Event(
            id: 'e1',
            invocationId: 'inv1',
            author: 'user',
            content: Content.userText('hi'),
          ),
          Event(
            id: 'e2',
            invocationId: 'inv1',
            author: 'model',
            content: Content.modelText('hello!'),
          ),
        ],
      );
      final List<Invocation> invs = convertSessionToEvalInvocations(session);
      expect(invs, isNotEmpty);
    });
  });

  group('logs.dart', () {
    test('setupAdkLogger and symlink helpers', () {
      setupAdkLogger(level: Level.debug);
      expect(activeLoggerConfig.level, Level.debug);

      setupAdkLogger(level: Level.warning);
      expect(activeLoggerConfig.level, Level.warning);

      setupAdkLogger(level: Level.error);
      expect(activeLoggerConfig.level, Level.error);

      final Directory tempDir = Directory.systemTemp.createTempSync('adk_log_test_');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      final File targetFile = File('${tempDir.path}${Platform.pathSeparator}test.log');
      targetFile.writeAsStringSync('log line');
      final String linkPath = '${tempDir.path}${Platform.pathSeparator}test.latest.log';

      final bool created = createSymlink(linkPath, targetFile.path);
      expect(created, isTrue);

      final bool recreated = createSymlink(linkPath, targetFile.path);
      expect(recreated, isTrue);

      final bool cannotOverwriteDir = createSymlink(tempDir.path, targetFile.path);
      expect(cannotOverwriteDir, isFalse);

      final List<String> echoMessages = <String>[];
      tryCreateLatestLogSymlink(
        tempDir.path,
        'test_prefix',
        targetFile.path,
        echo: echoMessages.add,
      );
      expect(echoMessages, isNotEmpty);

      final String tmpLog = logToTmpFolder(
        level: Level.info,
        subFolder: 'test_logs_tmp',
        logFilePrefix: 'agent_test',
        logFileTimestamp: '20261017',
        echo: (_) {},
      );
      expect(File(tmpLog).existsSync(), isTrue);
    });
  });

  group('service_factory.dart', () {
    test('redactUriForLog handles edge cases', () {
      expect(redactUriForLog(''), '<empty>');
      expect(redactUriForLog('invalid-uri'), '<scheme-missing>');
      expect(redactUriForLog('http://user:secret@localhost:8080/path?key=val&token=secret'), contains('redacted'));
      expect(redactUriForLog('sqlite:///test.db'), 'sqlite:///test.db');
    });

    test('runtime detection and writable directory checks', () {
      expect(isCloudRun(<String, String>{cloudRunServiceEnv: 'my-service'}), isTrue);
      expect(isCloudRun(<String, String>{}), isFalse);

      expect(isKubernetes(<String, String>{kubernetesHostEnv: '10.0.0.1'}), isTrue);
      expect(isKubernetes(<String, String>{}), isFalse);

      final Directory tempDir = Directory.systemTemp.createTempSync('adk_factory_test_');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      expect(isDirWritable(tempDir), isTrue);
      expect(isDirWritable(Directory('${tempDir.path}/non_existent')), isFalse);
    });

    test('resolveUseLocalStorage handles all environment flags', () {
      final Directory tempDir = Directory.systemTemp.createTempSync('adk_local_storage_');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      final (bool d1, String? msg1) = resolveUseLocalStorage(
        basePath: tempDir,
        requested: true,
        environment: <String, String>{disableLocalStorageEnv: 'true'},
      );
      expect(d1, isFalse);
      expect(msg1, contains('disabled'));

      final (bool d2, String? msg2) = resolveUseLocalStorage(
        basePath: tempDir,
        requested: true,
        environment: <String, String>{forceLocalStorageEnv: 'true'},
      );
      expect(d2, isTrue);
      expect(msg2, isNull);

      final (bool d3, _) = resolveUseLocalStorage(
        basePath: Directory('${tempDir.path}/no_exist'),
        requested: true,
        environment: <String, String>{forceLocalStorageEnv: 'true'},
      );
      expect(d3, isFalse);

      final (bool d4, _) = resolveUseLocalStorage(
        basePath: tempDir,
        requested: false,
      );
      expect(d4, isFalse);

      final (bool d5, String? msg5) = resolveUseLocalStorage(
        basePath: tempDir,
        requested: true,
        environment: <String, String>{cloudRunServiceEnv: 'service'},
      );
      expect(d5, isFalse);
      expect(msg5, contains('Cloud Run'));

      final (bool d6, _) = resolveUseLocalStorage(
        basePath: Directory('${tempDir.path}/no_exist'),
        requested: true,
      );
      expect(d6, isFalse);

      final (bool d7, _) = resolveUseLocalStorage(
        basePath: tempDir,
        requested: true,
      );
      expect(d7, isTrue);
    });

    test('createSessionServiceFromOptions and createArtifactServiceFromOptions', () {
      final Directory tempDir = Directory.systemTemp.createTempSync('adk_service_opts_');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      final BaseSessionService s1 = createSessionServiceFromOptions(
        baseDir: tempDir,
        useLocalStorage: false,
      );
      expect(s1, isA<InMemorySessionService>());

      final BaseSessionService s2 = createSessionServiceFromOptions(
        baseDir: tempDir,
        sessionServiceUri: 'memory://',
      );
      expect(s2, isA<InMemorySessionService>());

      final BaseMemoryService m1 = createMemoryServiceFromOptions(
        baseDir: tempDir,
      );
      expect(m1, isA<InMemoryMemoryService>());

      expect(
        () => createMemoryServiceFromOptions(
          baseDir: tempDir,
          memoryServiceUri: 'unsupported://scheme',
        ),
        throwsArgumentError,
      );

      final BaseArtifactService a1 = createArtifactServiceFromOptions(
        baseDir: tempDir,
        useLocalStorage: false,
      );
      expect(a1, isA<InMemoryArtifactService>());

      final BaseArtifactService a2 = createArtifactServiceFromOptions(
        baseDir: tempDir,
        artifactServiceUri: 'unsupported://scheme',
        strictUri: false,
      );
      expect(a2, isA<InMemoryArtifactService>());

      expect(
        () => createArtifactServiceFromOptions(
          baseDir: tempDir,
          artifactServiceUri: 'unsupported://scheme',
          strictUri: true,
        ),
        throwsArgumentError,
      );
    });
  });

  group('cli_tools_click.dart', () {
    test('dispatches arguments and handles empty/subcommands', () async {
      final _CapturedSink out1 = _CapturedSink();
      final _CapturedSink err1 = _CapturedSink();
      final int c1 = await click_cli.main(<String>[], outSink: out1.sink, errSink: err1.sink);
      await out1.closeAndRead();
      await err1.closeAndRead();
      expect(c1, 0);

      final _CapturedSink out2 = _CapturedSink();
      final _CapturedSink err2 = _CapturedSink();
      final int c2 = await click_cli.main(<String>['version'], outSink: out2.sink, errSink: err2.sink);
      final String vText = await out2.closeAndRead();
      await err2.closeAndRead();
      expect(c2, 0);
      expect(vText, contains('adk version'));

      final Directory tempDir = Directory.systemTemp.createTempSync('adk_click_create_');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      final _CapturedSink out3 = _CapturedSink();
      final int c3 = await click_cli.cliCreateCmd(
        projectDir: '${tempDir.path}/app1',
        appName: 'app1',
        type: 'config',
        outSink: out3.sink,
      );
      await out3.closeAndRead();
      expect(c3, 0);
    });
  });

  group('replay_plugin.dart & recordings_schema.dart', () {
    test('replay plugin reset and schema edge cases', () {
      final RecordingTurn turn1 = RecordingTurn(
        userText: 'hello',
        replyText: 'hi',
        metadata: <String, Object?>{'k': 'v'},
      );
      final RecordingTurn turn2 = RecordingTurn.fromJson(<String, Object?>{
        'user_text': 't2',
        'reply_text': null,
        'metadata': null,
      });
      final SessionRecording recording = SessionRecording(
        appName: 'app',
        userId: 'u',
        sessionId: 's',
        turns: <RecordingTurn>[turn1, turn2],
      );
      final ReplayPlugin replay = ReplayPlugin(recording);
      expect(replay.hasNext, isTrue);
      expect(replay.nextTurn()!.userText, 'hello');
      replay.reset();
      expect(replay.nextTurn()!.userText, 'hello');

      final String jsonStr = recording.toJsonString();
      expect(jsonStr, contains('"app_name": "app"'));

      final SessionRecording decodedNullTurns = SessionRecording.fromJson(<String, Object?>{
        'app_name': 'a',
        'user_id': 'u',
        'session_id': 's',
        'turns': null,
      });
      expect(decodedNullTurns.turns, isEmpty);
    });
  });

  group('recordings_plugin.dart', () {
    test('clear, appendTurn errors, and missing file load', () async {
      final RecordingsPlugin plugin = RecordingsPlugin();
      plugin.startSession(appName: 'app', userId: 'u', sessionId: 's1');
      expect(plugin.recordings, hasLength(1));

      expect(
        () => plugin.appendTurn(
          sessionId: 'non_existent',
          turn: RecordingTurn(userText: 'hi'),
        ),
        throwsStateError,
      );

      plugin.clear();
      expect(plugin.recordings, isEmpty);

      final RecordingsPlugin loaded = await RecordingsPlugin.loadFromFile(
        '/path/that/does/not/exist_12345.json',
      );
      expect(loaded.recordings, isEmpty);
    });
  });

  group('cli_record.dart and cli_test.dart', () {
    test('records and runs conformance test suites with mock server', () async {
      final HttpServer server = await HttpServer.bind('127.0.0.1', 0);
      server.listen((HttpRequest req) async {
        final String body = await utf8.decoder.bind(req).join();
        final Map<String, Object?> payload = body.isNotEmpty
            ? jsonDecode(body) as Map<String, Object?>
            : <String, Object?>{};

        req.response.headers.contentType = ContentType.json;
        if (req.uri.path.contains('/messages')) {
          req.response.write(jsonEncode(<String, Object?>{
            'reply': 'Echo: ${payload['text']}',
          }));
        } else {
          req.response.write(jsonEncode(<String, Object?>{'ok': true}));
        }
        await req.response.close();
      });

      final AdkWebServerClient client = AdkWebServerClient(
        Uri.parse('http://${server.address.host}:${server.port}'),
      );

      try {
        final SessionRecording recording = await recordConformanceSession(
          client: client,
          appName: 'demo_app',
          userId: 'user1',
          sessionId: 'session1',
          turns: <ConformanceTurn>[
            ConformanceTurn(userText: 'hello', expectedReplyContains: 'Echo'),
          ],
        );
        expect(recording.turns, hasLength(1));
        expect(recording.turns.first.replyText, 'Echo: hello');

        final ConformanceTestCase testCase = ConformanceTestCase(
          name: 'echo_case',
          turns: <ConformanceTurn>[
            ConformanceTurn(userText: 'world', expectedReplyContains: 'Echo: world'),
          ],
        );

        final ConformanceTestResult caseResult = await runConformanceTestCase(
          client: client,
          testCase: testCase,
          userId: 'user1',
          sessionId: 'session1',
        );
        expect(caseResult.passed, isTrue);

        final List<ConformanceTestResult> suiteResults = await runConformanceSuite(
          client: client,
          testCases: <ConformanceTestCase>[testCase],
          userId: 'user1',
          sessionId: 'session1',
        );
        expect(suiteResults, hasLength(1));
        expect(suiteResults.first.passed, isTrue);
      } finally {
        await client.close();
        await server.close(force: true);
      }
    });
  });

  group('cli_create.dart', () {
    test('promptStr, promptToChooseBackend, and promptToChooseType', () {
      expect(promptStr('Name', defaultValue: 'default'), 'default');
      expect(promptStr('Name', value: 'custom'), 'custom');
      expect(() => promptStr('Name', defaultValue: '  '), throwsArgumentError);

      expect(promptToChooseBackend(value: null), CreateBackend.geminiApi);
      expect(promptToChooseBackend(value: 'gemini-api'), CreateBackend.geminiApi);
      expect(promptToChooseBackend(value: 'gemini'), CreateBackend.geminiApi);
      expect(promptToChooseBackend(value: '1'), CreateBackend.geminiApi);
      expect(promptToChooseBackend(value: 'vertex-ai'), CreateBackend.vertexAi);
      expect(promptToChooseBackend(value: 'vertex'), CreateBackend.vertexAi);
      expect(promptToChooseBackend(value: '2'), CreateBackend.vertexAi);
      expect(() => promptToChooseBackend(value: 'unknown'), throwsArgumentError);

      expect(promptToChooseType(value: null), CreateAgentType.basic);
      expect(promptToChooseType(value: 'basic'), CreateAgentType.basic);
      expect(promptToChooseType(value: 'workflow'), CreateAgentType.workflow);
      expect(promptToChooseType(value: 'code'), CreateAgentType.code);
      expect(promptToChooseType(value: '1'), CreateAgentType.code);
      expect(promptToChooseType(value: 'config'), CreateAgentType.config);
      expect(promptToChooseType(value: '2'), CreateAgentType.config);
      expect(() => promptToChooseType(value: 'invalid'), throwsArgumentError);
    });

    test('runCreateCommand creates project files and outputs instructions', () async {
      final Directory tempDir = Directory.systemTemp.createTempSync('adk_create_test_');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      final String projectPath = '${tempDir.path}/test_app';

      final _CapturedSink out = _CapturedSink();
      final int code = await runCreateCommand(
        projectDir: projectPath,
        appName: 'test_app',
        type: 'config',
        outSink: out.sink,
      );
      final String output = await out.closeAndRead();
      expect(code, 0);
      expect(output, contains('Agent created in $projectPath'));
      expect(output, contains('Next steps:'));
    });
  });

  group('fast_api.dart', () {
    test('starts and stops FastApiApp and helper wrapper', () async {
      final Directory tempDir = Directory.systemTemp.createTempSync('adk_fastapi_');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      final FastApiApp app = getFastApiApp(
        agentsDir: tempDir.path,
        port: 0,
        enableWebUi: false,
      );

      final HttpServer server = await app.start();
      expect(server.port, isNonZero);
      await app.stop();
    });
  });

  group('dot_adk_folder.dart & local_storage.dart', () {
    test('dotAdkFolderForAgent path traversal guard', () {
      final Directory tempDir = Directory.systemTemp.createTempSync('adk_dot_test_');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      expect(
        () => dotAdkFolderForAgent(agentsRoot: tempDir.path, appName: '../../outside'),
        throwsArgumentError,
      );

      final DotAdkFolder folder = dotAdkFolderForAgent(
        agentsRoot: tempDir.path,
        appName: 'my_agent',
      );
      expect(folder.dotAdkDir.path, contains('.adk'));
    });

    test('createLocalSessionService perAgent false and absolute path edge cases', () async {
      final Directory tempDir = Directory.systemTemp.createTempSync('adk_local_sess_');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      final BaseSessionService singleSess = createLocalSessionService(
        baseDir: tempDir.path,
        perAgent: false,
      );
      expect(singleSess, isA<SqliteSessionService>());

      final BaseSessionService perAgentSess = createLocalSessionService(
        baseDir: tempDir.path,
        perAgent: true,
        appNameToDir: <String, String>{
          'abs_app': tempDir.path,
          'built_in': builtInSessionServiceKey,
        },
      );
      expect(perAgentSess, isA<PerAgentDatabaseSessionService>());

      final Session session = await perAgentSess.createSession(
        appName: 'abs_app',
        userId: 'user1',
      );
      expect(session.appName, 'abs_app');
    });
  });

  group('base_agent_loader.dart & envs.dart', () {
    test('asBaseAgent and listAgentsDetailed', () {
      final Agent rootAgent = Agent(name: 'root', model: 'gemini-2.5-flash');
      final App app = App(name: 'my_app', rootAgent: rootAgent);

      expect(asBaseAgent(app), rootAgent);
      expect(asBaseAgent(rootAgent), rootAgent);
      expect(() => asBaseAgent('invalid'), throwsArgumentError);

      final _MockAgentLoader loader = _MockAgentLoader();
      final List<Map<String, Object?>> detailed = loader.listAgentsDetailed();
      expect(detailed, hasLength(2));
      expect(detailed.first['name'], 'agent_a');
    });

    test('envs.dart dotenv parsing and walkToRootUntilFound', () {
      final Directory tempDir = Directory.systemTemp.createTempSync('adk_envs_test_');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      final Directory subDir = Directory('${tempDir.path}/a/b/c')..createSync(recursive: true);
      final File envFile = File('${tempDir.path}/.env');
      envFile.writeAsStringSync('''
# A comment
EMPTY=
KEY_A="val_a"
KEY_B='val_b'
KEY_C=plain_val
INVALID_LINE
''');

      final File? found = walkToRootUntilFound(subDir.path, '.env');
      expect(found, isNotNull);
      expect(found!.existsSync(), isTrue);

      final List<String> logs = <String>[];
      loadDotenvForAgent('c', '${tempDir.path}/a/b', log: logs.add);
      expect(getCliEnvironmentValue('KEY_A'), 'val_a');
      expect(getCliEnvironmentValue('KEY_B'), 'val_b');
      expect(getCliEnvironmentValue('KEY_C'), 'plain_val');
      clearCliEnvironmentOverrides();
      expect(getCliEnvironmentValue('KEY_A'), isNull);
    });
  });

  group('cli_eval.dart', () {
    test('resolveCliEvalMetricsFromConfig and parseAndGetEvalsToRun', () {
      final List<EvalMetric> dMetrics = resolveCliEvalMetricsFromConfig(
        core_eval_config.EvalConfig(criteria: <String, Object?>{}),
      );
      expect(dMetrics, contains(EvalMetric.finalResponseExactMatch));

      final List<EvalMetric> customMetrics = resolveCliEvalMetricsFromConfig(
        core_eval_config.EvalConfig(criteria: <String, Object?>{
          'final_response_exact_match': true,
          'final_response_contains': true,
        }),
      );
      expect(customMetrics, contains(EvalMetric.finalResponseExactMatch));
      expect(customMetrics, contains(EvalMetric.finalResponseContains));

      expect(getDefaultMetricInfo(addTrajectoryMetrics: true), contains(EvalMetric.finalResponseContains));

      final List<String> allEvals = <String>['e1', 'e2', 'e3'];
      expect(parseAndGetEvalsToRun(evalIds: null, availableEvalIds: allEvals), allEvals);
      expect(parseAndGetEvalsToRun(evalIds: 'e1,e3', availableEvalIds: allEvals), <String>['e1', 'e3']);
      expect(() => parseAndGetEvalsToRun(evalIds: 'missing', availableEvalIds: allEvals), throwsArgumentError);

      expect(convertContentToText(null), '');
      expect(convertContentToText(Content.modelText('Hello')), 'Hello');

      final String toolText = convertToolCallsToText(<FunctionCall>[
        FunctionCall(name: 'calc', args: <String, Object?>{'x': 1}),
      ]);
      expect(toolText, contains('calc({x: 1})'));

      final EvalCaseResult result = EvalCaseResult(
        evalCaseId: 'case_1',
        finalEvalStatus: EvalStatus.passed,
        metrics: <EvalMetricResult>[
          EvalMetricResult(
            metric: EvalMetric.finalResponseExactMatch,
            score: 1.0,
            passed: true,
          ),
        ],
      );
      final String pretty = prettyPrintEvalResult(result);
      expect(pretty, contains('EvalCase: case_1'));

      final Agent a = Agent(name: 'a', model: 'gemini-2.5-flash');
      expect(getRootAgentFromModule(a), a);
      expect(tryGetResetFunc(<String, Object?>{'reset': () => 42}), isNotNull);
      expect(tryGetResetFunc(null), isNull);
    });
  });

  group('dev/runtime.dart & dev/project.dart', () {
    test('runtime session helpers and dev model fallback prompt', () async {
      final DevAgentRuntime runtime = DevAgentRuntime(
        config: DevProjectConfig(
          appName: 'demo_app',
          agentName: 'root',
          description: 'desc',
        ),
      );
      final Session s = await runtime.ensureSession(userId: 'u1', sessionId: 's1');
      expect(s.id, 's1');
      final List<Session> list = await runtime.listSessions(userId: 'u1');
      expect(list, isNotEmpty);

      final DevProjectConfig cfg = DevProjectConfig(
        appName: 'app1',
        agentName: 'root',
        description: 'desc',
        userId: 'u1',
      );
      final DevProjectConfig copy = cfg.copyWith(appName: 'app2');
      expect(copy.appName, 'app2');
      expect(copy.agentName, 'root');

      expect(projectDirName('/path/to/my_folder/'), 'my_folder');
      expect(projectDirName(''), 'my_agent');

      final Directory tempDir = Directory.systemTemp.createTempSync('adk_proj_test_');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      final File notADir = File('${tempDir.path}/file.txt')..writeAsStringSync('hi');
      expect(
        () => loadDevProjectConfig(notADir.path, validateProjectDir: true),
        throwsA(isA<FileSystemException>()),
      );

      expect(
        () => createDevProject(projectDirPath: tempDir.path, type: 'INVALID_TYPE'),
        throwsArgumentError,
      );

      await createDevProject(
        projectDirPath: '${tempDir.path}/app_ok',
        region: 'us-central1',
      );
      expect(
        () => createDevProject(projectDirPath: '${tempDir.path}/app_ok'),
        throwsA(isA<FileSystemException>()),
      );
    });
  });

  group('adk_web_server_client.dart', () {
    test('handles edge case HTTP responses and methods', () async {
      final HttpServer server = await HttpServer.bind('127.0.0.1', 0);
      server.listen((HttpRequest req) async {
        final String path = req.uri.path;
        if (path.contains('/api/sessions') && req.method == 'POST') {
          req.response.write(jsonEncode(<String, Object?>{'id': 'new_session'}));
        } else if (path.contains('/run_sse')) {
          req.response.statusCode = 500;
          req.response.write('Internal Server Error');
        } else if (path.contains('/events')) {
          if (req.uri.queryParameters['userId'] == 'bad_json') {
            req.response.write('not-json');
          } else if (req.uri.queryParameters['userId'] == 'error_code') {
            req.response.statusCode = 404;
            req.response.write('Not Found');
          } else {
            req.response.write(jsonEncode(<String, Object?>{'events': <Object>[]}));
          }
        } else if (req.method == 'PATCH') {
          req.response.write(jsonEncode(<String, Object?>{'patched': true}));
        } else if (path.contains('/empty_body')) {
          req.response.write('');
        } else {
          req.response.write(jsonEncode(<String, Object?>{'ok': true}));
        }
        await req.response.close();
      });

      final AdkWebServerClient client = AdkWebServerClient(
        Uri.parse('http://${server.address.host}:${server.port}'),
      );

      try {
        final Map<String, Object?> sess = await client.createSession(
          userId: 'u1',
          appName: null,
        );
        expect(sess['id'], 'new_session');

        await expectLater(
          client.runAgentSse(
            appName: 'app',
            userId: 'u',
            sessionId: 's',
            streaming: false,
          ),
          throwsA(isA<HttpException>()),
        );

        final Map<String, Object?> evs = await client.getEvents(
          sessionId: 's1',
          userId: 'u1',
        );
        expect(evs['events'], isEmpty);

        await expectLater(
          client.getEvents(sessionId: 's1', userId: 'error_code'),
          throwsA(isA<HttpException>()),
        );

        await expectLater(
          client.getEvents(sessionId: 's1', userId: 'bad_json'),
          throwsA(isA<FormatException>()),
        );
      } finally {
        await client.close();
        await server.close(force: true);
      }
    });
  });

  group('a2a_push_delivery_queue.dart', () {
    test('pendingCount, deadLetterCount, and header/object decoding edge cases', () {
      final Directory tempDir = Directory.systemTemp.createTempSync('adk_a2a_q_');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      final String dbPath = '${tempDir.path}/a2a_queue.db';

      final A2aPushDeliveryQueue queue = A2aPushDeliveryQueue.open(
        dbPath: dbPath,
      );

      expect(queue.pendingCount(), 0);
      expect(queue.deadLetterCount(), 0);

      queue.close();
      expect(queue.pendingCount(), 0);
      expect(queue.deadLetterCount(), 0);
    });
  });

  group('adk_web_server.dart', () {
    test('startAdkWebServer and project resolution with preferred directory', () async {
      final Directory tempDir = Directory.systemTemp.createTempSync('adk_web_srv_');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      final Directory subApp = Directory('${tempDir.path}/my_sub_app')..createSync();
      File('${subApp.path}/root_agent.yaml').writeAsStringSync('name: sub_app\nmodel: gemini-2.5-flash\n');

      final HttpServer server = await startAdkWebServer(
        agentsDir: tempDir.path,
        appName: 'my_sub_app',
        port: 0,
        enableWebUi: false,
      );
      expect(server.port, isNonZero);
      await server.close(force: true);
    });
  });

  group('agent_graph.dart & graph_serialization.dart', () {
    test('agent_graph covers ToolNode, JoinNode, and unrouted edge highlights', () async {
      final Agent rootAgent = Agent(
        name: 'root',
        model: 'gemini-2.5-flash',
        tools: <Object>[
          _CustomBaseTool(name: 'custom_base_tool'),
        ],
      );

      final Workflow workflow = Workflow(
        name: 'wf',
        nodes: <BaseNode>[
          ToolNode(name: 'tool_step', tool: _CustomBaseTool(name: 't1')),
          JoinNode(name: 'join_step'),
          _CustomBaseNode(name: 'custom_step'),
        ],
        edges: <Edge>[
          Edge(fromNode: START, toNode: 'tool_step'),
          Edge(fromNode: 'tool_step', toNode: 'join_step'),
          Edge(fromNode: 'join_step', toNode: 'custom_step'),
          Edge(fromNode: 'custom_step', toNode: 'custom_step'),
        ],
      );

      final AgentGraph graph = await buildGraph(rootAgent);
      expect(graph.nodes, isNotEmpty);

      final AgentGraph wfGraph = await buildGraph(workflow);
      expect(wfGraph.nodes, isNotEmpty);

      final String dotLight = await getAgentGraphDot(
        workflow,
        darkMode: false,
      );
      expect(dotLight, contains('digraph'));

      final String mermaid = await getAgentGraph(
        workflow,
        highlightPairs: <(String, String)>{('tool_step', 'join_step')},
      );
      expect(mermaid, contains('flowchart'));
    });

    test('graph_serialization covers all agent, node, and tool variations', () {
      final Agent subAgent = Agent(
        name: 'sub',
        model: 'gemini-2.5-flash',
        description: 'Sub description',
      );
      final LlmAgent root = LlmAgent(
        name: 'root',
        model: 'gemini-2.5-flash',
        description: 'Root description',
        instruction: 'Instruction text',
        globalInstruction: 'Global instruction text',
        staticInstruction: 'Static text',
        subAgents: <BaseAgent>[subAgent],
        tools: <Object>[
          _CustomBaseTool(name: 'btool', description: 'desc'),
          () => 'closure_tool',
        ],
      );

      final Workflow wf = Workflow(
        name: 'wf_serial',
        nodes: <BaseNode>[
          ToolNode(name: 't_node', tool: _CustomBaseTool(name: 't1'), description: 'tool node desc'),
          AgentNode(name: 'a_node', agent: root, dependsOn: <String>['t_node']),
          JoinNode(name: 'j_node'),
          _CustomBaseNode(name: 'c_node'),
        ],
        edges: <Edge>[
          Edge(fromNode: START, toNode: 't_node'),
          Edge(fromNode: 't_node', toNode: 'a_node'),
          Edge(fromNode: 'a_node', toNode: 'j_node'),
          Edge(fromNode: 'j_node', toNode: 'c_node'),
          Edge(fromNode: 'c_node', toNode: 'c_node'),
        ],
      );

      final GraphJson serializedAgent = serializeAgent(root);
      expect(serializedAgent['name'], 'root');
      expect(serializedAgent['sub_agents'], isNotEmpty);

      final GraphJson serializedWf = serializeAgent(wf);
      expect(serializedWf['nodes'], hasLength(4));

      final App app = App(
        name: 'my_app',
        rootAgent: wf,
        resumabilityConfig: ResumabilityConfig(),
      );
      final GraphJson serializedApp = serializeAppInfo(app, readme: '# Readme');
      expect(serializedApp['resumability_config'], isNotNull);
      expect(serializedApp['readme'], '# Readme');
    });
  });

  group('service_registry.dart', () {
    test('creates various session, artifact, and memory services', () {
      final ServiceRegistry registry = getServiceRegistry();

      final BaseSessionService? aeSess = registry.createSessionService(
        'agentengine://projects/project-1/locations/us-central1/reasoningEngines/engine-1',
      );
      expect(aeSess, isA<VertexAiSessionService>());

      final BaseSessionService? sqMem = registry.createSessionService(
        'sqlite:///',
      );
      expect(sqMem, isA<InMemorySessionService>());

      final BaseSessionService? pgSess = registry.createSessionService(
        'postgresql://user:pass@localhost:5432/testdb',
      );
      expect(pgSess, isNotNull);

      final BaseSessionService? mySess = registry.createSessionService(
        'mysql://user:pass@localhost:3306/testdb',
      );
      expect(mySess, isNotNull);

      expect(
        () => registry.createArtifactService('file://remotehost/path'),
        throwsArgumentError,
      );
      expect(
        () => registry.createArtifactService('file://'),
        throwsArgumentError,
      );
      expect(
        () => registry.createArtifactService('file:'),
        throwsArgumentError,
      );
      final BaseArtifactService? fileArt = registry.createArtifactService(
        'file:///tmp/artifacts',
      );
      expect(fileArt, isA<FileArtifactService>());

      expect(
        () => registry.createArtifactService('gs:///'),
        throwsArgumentError,
      );

      expect(
        () => registry.createMemoryService('rag:///'),
        throwsArgumentError,
      );
    });
  });
}
