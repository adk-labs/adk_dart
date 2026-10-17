import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:adk/adk.dart';
import 'package:adk/src/cli/plugins/conformance_replay_plugin.dart';
import 'package:adk/src/dev/a2a_push_delivery_queue.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:test/test.dart';

class _Part4EchoLlm extends BaseLlm {
  _Part4EchoLlm() : super(model: 'part4_echo_model');

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    yield LlmResponse(content: Content.modelText('echo response'));
  }
}

class _Part4RateLimitLlm extends BaseLlm {
  _Part4RateLimitLlm() : super(model: 'part4_rate_limit_model');

  int calls = 0;

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    calls += 1;
    if (calls == 1) {
      yield LlmResponse(
        errorCode: '429',
        errorMessage: 'Resource exhausted',
      );
      return;
    }
    yield LlmResponse(content: Content.modelText('recovered response'));
  }
}

class _Part4Plugin extends BasePlugin {
  _Part4Plugin() : super(name: 'part4_plugin');
}

class _Part4ErrorLlm extends BaseLlm {
  _Part4ErrorLlm() : super(model: 'part4_error_model');

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    throw Exception('429 Resource exhausted');
  }
}

class _CustomJsonSerializable {
  Map<String, Object?> toJson() => <String, Object?>{'key': 'custom_val'};
}

class _CaptureSink implements IOSink {
  final StringBuffer buffer = StringBuffer();

  String get output => buffer.toString();

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
  void add(List<int> data) => buffer.write(utf8.decode(data, allowMalformed: true));

  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      buffer.write('ERROR: $error');

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final List<int> chunk in stream) {
      add(chunk);
    }
  }

  @override
  Future<void> flush() async {}

  @override
  Future<void> close() async {}

  @override
  Future<void> get done => Future<void>.value();

  @override
  Encoding encoding = utf8;
}

void main() {
  setUpAll(() {
    LLMRegistry.register(
      supportedModels: <RegExp>[
        RegExp(r'^part4_echo_model$'),
        RegExp(r'^part4_rate_limit_model$'),
      ],
      factory: (String model) {
        if (model == 'part4_rate_limit_model') {
          return _Part4RateLimitLlm();
        }
        return _Part4EchoLlm();
      },
    );
  });

  group('Target 100 coverage part 4 - small files & cli_deploy completion', () {
    test('project.dart DevProjectConfig.copyWith', () {
      final DevProjectConfig cfg = DevProjectConfig(
        appName: 'app1',
        agentName: 'ag1',
        description: 'desc1',
        userId: 'u1',
      );
      final DevProjectConfig copy = cfg.copyWith(
        appName: 'app2',
        agentName: 'ag2',
        description: 'desc2',
        userId: 'u2',
      );
      expect(copy.appName, 'app2');
      expect(copy.agentName, 'ag2');
      expect(copy.description, 'desc2');
      expect(copy.userId, 'u2');

      final DevProjectConfig defaultCopy = cfg.copyWith();
      expect(defaultCopy.appName, 'app1');
      expect(defaultCopy.agentName, 'ag1');
      expect(defaultCopy.description, 'desc1');
      expect(defaultCopy.userId, 'u1');
    });

    test('conformance_replay_plugin.dart empty or null tool response payload', () async {
      final Directory tempDir = Directory.systemTemp.createTempSync('adk_replay_empty_res_');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      final File recFile = File('${tempDir.path}${Platform.pathSeparator}generated-recordings.yaml');
      recFile.writeAsStringSync('''
recordings:
  - user_message_index: 0
    agent_name: test_agent
    tool_recording:
      tool_call:
        name: tool_empty
        args:
          x: 1
      tool_response:
        response: null
''');
      final ConformanceReplayPlugin plugin = ConformanceReplayPlugin();
      final InvocationContext ctx = InvocationContext(
        invocationId: 'inv-rep-empty-res',
        agent: LlmAgent(name: 'test_agent', model: 'part4_echo_model'),
        sessionService: InMemorySessionService(),
        session: Session(id: 's', appName: 'app', userId: 'u'),
      );
      final CallbackContext cbCtx = CallbackContext(ctx);
      cbCtx.state['_adk_replay_config'] = <dynamic, dynamic>{
        'dir': tempDir.path,
        'user_message_index': 0,
      };
      final ToolContext toolCtx = Context(ctx, functionCallId: 'call_empty');

      final FunctionTool tool = FunctionTool(
        name: 'tool_empty',
        description: 'd',
        func: (Map<String, dynamic> args) => 1,
      );

      final Map<String, dynamic>? res = await plugin.beforeToolCallback(
        tool: tool,
        toolArgs: <String, dynamic>{'x': 1},
        toolContext: toolCtx,
      );
      expect(res, isEmpty);
    });

    test('envs.dart skips overriding explicit environment variables', () {
      final Directory tempDir = Directory.systemTemp.createTempSync('adk_envs_explicit_');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      final File envFile = File('${tempDir.path}${Platform.pathSeparator}.env');
      envFile.writeAsStringSync('PATH=/should/not/override/system/path\nCUSTOM_VAR_XYZ=123\n');

      loadDotenvForAgent('test_agent', tempDir.path);
      expect(getCliEnvironmentValue('CUSTOM_VAR_XYZ'), '123');
    });

    test('local_storage.dart builtin app key coverage', () async {
      final Directory tempDir = Directory.systemTemp.createTempSync('adk_local_storage_builtin_');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      final PerAgentDatabaseSessionService service = PerAgentDatabaseSessionService(agentsRoot: tempDir);
      final Session session = await service.createSession(
        appName: '__builtin_test__',
        userId: 'u1',
      );
      expect(session.appName, '__builtin_test__');
      final Session? fetched = await service.getSession(
        appName: '__builtin_test__',
        userId: 'u1',
        sessionId: session.id,
      );
      expect(fetched, isNotNull);
    });

    test('service_registry.dart short-form and GCS auth header token fallbacks', () async {
      final ServiceRegistry registry = getServiceRegistry();
      final Directory tempDir = Directory.systemTemp.createTempSync('adk_svc_reg_gcp_');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      // 1. Long-form agent engine URI with agents_dir
      final BaseMemoryService? memServiceLong = registry.createMemoryService(
        'agentengine://projects/test-proj/locations/us-central1/reasoningEngines/12345',
        kwargs: <String, Object?>{'agents_dir': tempDir.path},
      );
      expect(memServiceLong, isNotNull);

      // 2. Short-form agent engine URI with missing GCP env vars throws StateError
      setCliEnvironmentValue('GOOGLE_CLOUD_PROJECT', '');
      setCliEnvironmentValue('GOOGLE_CLOUD_LOCATION', '');
      expect(
        () => registry.createMemoryService(
          'agentengine://my_short_engine_id',
          kwargs: <String, Object?>{'agents_dir': tempDir.path},
        ),
        throwsStateError,
      );

      // 3. Short-form agent engine URI with configured GCP env vars succeeds
      setCliEnvironmentValue('GOOGLE_CLOUD_PROJECT', 'p1');
      setCliEnvironmentValue('GOOGLE_CLOUD_LOCATION', 'l1');
      final BaseMemoryService? memServiceShort = registry.createMemoryService(
        'agentengine://my_short_engine_id',
        kwargs: <String, Object?>{'agents_dir': tempDir.path},
      );
      expect(memServiceShort, isNotNull);

      // 4. GCS Auth headers with ACCESS_TOKEN
      setCliEnvironmentValue('GOOGLE_OAUTH_ACCESS_TOKEN', '');
      setCliEnvironmentValue('GOOGLE_ACCESS_TOKEN', '');
      setCliEnvironmentValue('ACCESS_TOKEN', 'access_tok_xyz');
      final Map<String, String> gcsHeaders = await resolveGcsArtifactAuthHeaders();
      expect(gcsHeaders[HttpHeaders.authorizationHeader], 'Bearer access_tok_xyz');

      // 5. GCS Auth headers with fallback to resolveDefaultGoogleAccessToken
      setCliEnvironmentValue('ACCESS_TOKEN', '');
      expect(
        resolveGcsArtifactAuthHeaders(),
        throwsStateError,
      );
    });

    test('graph_serialization.dart BaseAgent, BaseLlm, Iterable, and toJson serialization', () {
      final LlmAgent childAgent = LlmAgent(name: 'child_agent', model: 'part4_echo_model');
      final LlmAgent parentAgent = LlmAgent(
        name: 'parent_agent',
        model: 'part4_echo_model',
        subAgents: <BaseAgent>[childAgent],
      );

      final Map<String, Object?> serialized = serializeAgent(parentAgent);
      expect(serialized['name'], 'parent_agent');
      expect(serialized['type'], 'agent');

      final Map<String, Object?> nodeJson = serializeNode(
        FunctionNode(
          name: 'fn_node',
          function: (WorkflowContext ctx, Object? input) => 1,
        ),
      );
      expect(nodeJson['name'], 'fn_node');
      expect(nodeJson['type'], 'function');

      final App app = App(
        name: 'my_app',
        rootAgent: parentAgent,
        plugins: <BasePlugin>[_Part4Plugin()],
        contextCacheConfig: <Object>[
          _Part4EchoLlm(),
          _CustomJsonSerializable(),
        ],
      );
      final Map<String, Object?> appJson = serializeAppInfo(
        app,
        readme: 'readme text',
      );
      expect(appJson['readme'], 'readme text');
      expect(appJson['name'], 'my_app');
      expect((appJson['plugins'] as List<Object?>).length, 1);
      expect(appJson['context_cache_config'], isA<List<Object?>>());
    });

    test('a2a_push_delivery_queue.dart raw row parsing variants', () async {
      final Directory tempDir = Directory.systemTemp.createTempSync('adk_a2a_queue_rows_');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      final File dbFile = File('${tempDir.path}${Platform.pathSeparator}a2a_queue.db');
      final A2aPushDeliveryQueue queue = A2aPushDeliveryQueue.open(dbPath: dbFile.path);
      addTearDown(() => queue.close());

      // Open sqlite directly and insert raw rows with diverse payload formats
      final sqlite.Database db = sqlite.sqlite3.open(dbFile.path);
      addTearDown(() => db.close());

      // Row 1: Valid JSON headers, non-map JSON string for task, invalid JSON string for update
      db.execute('''
        INSERT INTO a2a_push_delivery_queue (
          app_name, task_id, target_url, headers_json, auth_header,
          task_json, update_json, attempt_count, max_attempts,
          base_delay_ms, max_delay_ms, request_timeout_ms, next_attempt_at_ms, created_at_ms
        ) VALUES (
          'app1', 't1', 'https://example.com/hook', '{"X-Custom": "val1", "": "emptyKey", "k2": ""}', 'Bearer tok',
          '"just a string"', '{malformed-json', 0, 5,
          1000, 60000, 10000, 0, 0
        )
      ''');

      // Row 2: Empty headers, empty string task_json, whitespace update_json
      db.execute('''
        INSERT INTO a2a_push_delivery_queue (
          app_name, task_id, target_url, headers_json, auth_header,
          task_json, update_json, attempt_count, max_attempts,
          base_delay_ms, max_delay_ms, request_timeout_ms, next_attempt_at_ms, created_at_ms
        ) VALUES (
          'app1', 't2', 'https://example.com/hook', '', NULL,
          '   ', '   ', 0, 5,
          1000, 60000, 10000, 0, 0
        )
      ''');

      final List<A2aPushDeliveryEntry> pending = queue.readDue(limit: 10);
      expect(pending.length, 2);
      expect(pending[0].headers['X-Custom'], 'val1');
      expect(pending[0].task, isEmpty);
      expect(pending[0].update, isEmpty);
      expect(pending[1].headers, isEmpty);
      expect(pending[1].task, isEmpty);
    });

    test('service_factory.dart folder writable error and local storage error fallback', () {
      // 1. isDirWritable on nonexistent/forbidden path returns false
      expect(isDirWritable(Directory('/dev/null/forbidden_path')), isFalse);

      // Read-only directory on macOS/Linux for line 92
      final Directory roDir = Directory.systemTemp.createTempSync('adk_ro_dir_');
      addTearDown(() {
        Process.runSync('chmod', <String>['755', roDir.path]);
        roDir.deleteSync(recursive: true);
      });
      Process.runSync('chmod', <String>['555', roDir.path]);
      expect(isDirWritable(roDir), isFalse);

      // 2. createSessionServiceFromOptions fallback to DatabaseSessionService
      final BaseSessionService sess = createSessionServiceFromOptions(
        baseDir: '.',
        sessionServiceUri: 'memory:',
      );
      expect(sess, isA<InMemorySessionService>());

      final BaseSessionService sessDb = createSessionServiceFromOptions(
        baseDir: '.',
        sessionServiceUri: 'postgres://localhost/test',
      );
      expect(sessDb, isA<DatabaseSessionService>());

      // 3. createArtifactServiceFromOptions with read-only dir and useLocalStorage: true
      final BaseArtifactService artRo = createArtifactServiceFromOptions(
        baseDir: roDir.path,
        useLocalStorage: true,
      );
      expect(artRo, isA<InMemoryArtifactService>());
    });

    test('agent_loader.dart dev project fallback, agentType, and computer use detection', () {
      final Directory tempDir = Directory.systemTemp.createTempSync('adk_loader_gaps_');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      final Directory appDir = Directory('${tempDir.path}${Platform.pathSeparator}my_app');
      appDir.createSync(recursive: true);

      final AgentLoader loader = AgentLoader(tempDir.path);

      // 1. loadAgent throws StateError when neither yaml nor dart exists
      expect(() => loader.loadAgent('my_app'), throwsStateError);

      // 2. listAgentsDetailed returns 'dart' when agent.dart exists
      final File agentDart = File('${appDir.path}${Platform.pathSeparator}agent.dart');
      agentDart.writeAsStringSync('// dart agent');
      final List<Map<String, Object?>> detailed = loader.listAgentsDetailed();
      expect(detailed.any((Map<String, Object?> m) => m['language'] == 'dart'), isTrue);

      // 3. adk.json only without agent.dart
      final Directory adkJsonAppDir = Directory('${tempDir.path}${Platform.pathSeparator}adk_json_app');
      adkJsonAppDir.createSync(recursive: true);
      final File adkJson = File('${adkJsonAppDir.path}${Platform.pathSeparator}adk.json');
      adkJson.writeAsStringSync('{"appName": "adk_json_app"}');
      final List<Map<String, Object?>> detailedAdk = loader.listAgentsDetailed();
      expect(detailedAdk.any((Map<String, Object?> m) => m['name'] == 'adk_json_app' && m['language'] == 'dart'), isTrue);

      // 4. Custom factory with missing files skips entry gracefully
      final AgentLoader missingFilesLoader = AgentLoader(
        tempDir.path,
        agentFactories: <String, AgentFactory>{
          'missing_files_agent': (String name, String dir) => LlmAgent(name: 'm', model: 'part4_echo_model'),
        },
      );
      expect(missingFilesLoader.listAgentsDetailed().any((Map<String, Object?> m) => m['name'] == 'missing_files_agent'), isFalse);

      // 5. Computer use agent check with BaseToolset and FunctionTool
      final LlmAgent agentWithTools = LlmAgent(
        name: 'agent_tools',
        model: 'part4_echo_model',
        tools: <Object>[
          FunctionTool(name: 'f1', description: 'd', func: (_) => 1),
        ],
      );
      final AgentLoader customLoader = AgentLoader(
        tempDir.path,
        agentFactories: <String, AgentFactory>{
          'custom': (String name, String dir) => agentWithTools,
        },
      );
      final List<Map<String, Object?>> customDetailed = customLoader.listAgentsDetailed();
      expect(customDetailed.any((Map<String, Object?> m) => m['is_computer_use'] == false), isTrue);
    });

    test('trigger_routes.dart semaphore queuing, unsupported sources, and transient retry', () async {
      // 1. Unsupported trigger source throws ArgumentError
      expect(
        () => TriggerRouter(
          getRunnerAsync: (String _) async => throw UnimplementedError(),
          sessionService: InMemorySessionService(),
          triggerSources: const <String>['unsupported_trigger_type'],
        ),
        throwsArgumentError,
      );

      final InMemorySessionService sessService = InMemorySessionService();
      final _Part4RateLimitLlm rateLimitLlm = _Part4RateLimitLlm();
      final Runner retryRunner = Runner(
        appName: 'trig_app_retry',
        agent: LlmAgent(name: 'retry_agent', model: rateLimitLlm),
        sessionService: sessService,
      );

      final TriggerRouter router = TriggerRouter(
        getRunnerAsync: (String _) async => retryRunner,
        sessionService: sessService,
        triggerSources: const <String>['pubsub', 'eventarc'],
        maxConcurrent: 1,
        maxRetries: 2,
        baseDelaySeconds: 0.01,
        maxDelaySeconds: 0.02,
      );

      // 2. Semaphore queuing: launch two concurrent PubSub requests with maxConcurrent = 1
      final Future<TriggerResponse> f1 = router.handlePubSubRequest(
        appName: 'trig_app_retry',
        triggerRequest: PubSubTriggerRequest(
          message: PubSubMessage(
            data: base64Encode(utf8.encode('msg 1')),
          ),
        ),
      );
      final Future<TriggerResponse> f2 = router.handlePubSubRequest(
        appName: 'trig_app_retry',
        triggerRequest: PubSubTriggerRequest(
          message: PubSubMessage(
            data: base64Encode(utf8.encode('msg 2')),
          ),
        ),
      );
      final List<TriggerResponse> responses = await Future.wait(<Future<TriggerResponse>>[f1, f2]);
      expect(responses[0].response, isNotEmpty);
      expect(responses[1].response, isNotEmpty);

      // 3. Exception with 429 testing _isRateLimitError
      final Runner excRunner = Runner(
        appName: 'trig_app_exc',
        agent: LlmAgent(name: 'exc_agent', model: _Part4ErrorLlm()),
        sessionService: sessService,
      );
      final TriggerRouter excRouter = TriggerRouter(
        getRunnerAsync: (String _) async => excRunner,
        sessionService: sessService,
        triggerSources: const <String>['pubsub'],
        maxRetries: 0,
      );
      expect(
        () => excRouter.handlePubSubRequest(
          appName: 'trig_app_exc',
          triggerRequest: PubSubTriggerRequest(
            message: PubSubMessage(data: base64Encode(utf8.encode('test'))),
          ),
        ),
        throwsA(isA<Exception>()),
      );

      // 3. PubSub request with empty data and no attributes
      final TriggerResponse emptyPubSub = await router.handlePubSubRequest(
        appName: 'trig_app_retry',
        triggerRequest: PubSubTriggerRequest(
          message: PubSubMessage(),
        ),
      );
      expect(emptyPubSub.response, isNotEmpty);

      // 4. PubSub request with invalid base64 throws FormatException
      expect(
        () => router.handlePubSubRequest(
          appName: 'trig_app_retry',
          triggerRequest: PubSubTriggerRequest(
            message: PubSubMessage(data: 'invalid-b64-!@#\$%'),
          ),
        ),
        throwsFormatException,
      );

      // 5. Eventarc request with null data but extraFields present
      final TriggerResponse extraEventarc = await router.handleEventarcRequest(
        appName: 'trig_app_retry',
        triggerRequest: EventarcTriggerRequest(
          extraFields: <String, Object?>{'key_1': 'val_1'},
        ),
      );
      expect(extraEventarc.response, isNotEmpty);

      // 6. Eventarc request with inner message and valid base64 data
      final TriggerResponse innerB64Eventarc = await router.handleEventarcRequest(
        appName: 'trig_app_retry',
        triggerRequest: EventarcTriggerRequest(
          data: <String, Object?>{
            'message': <String, Object?>{
              'data': base64Encode(utf8.encode('inner b64 message')),
            },
          },
        ),
      );
      expect(innerB64Eventarc.response, isNotEmpty);

      // 7. Eventarc request with non-map scalar data (integer)
      final TriggerResponse intDataEventarc = await router.handleEventarcRequest(
        appName: 'trig_app_retry',
        triggerRequest: EventarcTriggerRequest(
          data: 12345,
        ),
      );
      expect(intDataEventarc.response, isNotEmpty);

      // 8. Session creation when sessionId is specified but does not exist
      final TriggerResponse newNamedSessionResp = await router.handlePubSubRequest(
        appName: 'trig_app_retry',
        triggerRequest: PubSubTriggerRequest(
          sessionId: 'brand_new_session_id',
          message: PubSubMessage(
            data: base64Encode(utf8.encode('new session message')),
          ),
        ),
      );
      expect(newNamedSessionResp.sessionId, 'brand_new_session_id');
    });

    test('cli_deploy.dart full flag permutations and error validation', () async {
      final _CaptureSink out = _CaptureSink();
      final _CaptureSink err = _CaptureSink();

      // 1. Extra packages parent traversal and dot errors
      expect(
        await runDeployCommand(
          <String>['--extra_packages', '../forbidden'],
          outSink: out,
          errSink: err,
        ),
        64,
      );
      expect(
        await runDeployCommand(
          <String>['--extra_packages', '.'],
          outSink: out,
          errSink: err,
        ),
        64,
      );

      // 2. All deploy flag permutations in dry-run mode
      out.buffer.clear();
      err.buffer.clear();
      final int code = await runDeployCommand(
        <String>[
          'cloud_run',
          '--dry-run',
          '--service', 'my-svc',
          '--service-name', 'my-svc-name',
          '--app-name', 'my-app',
          '--temp-folder', '/tmp/my-temp',
          '--port', '8080',
          '--project', 'test-project',
          '--region', 'us-central1',
          '--image', 'gcr.io/test-project/my-image',
          '--service-account', 'sa@test-project.iam.gserviceaccount.com',
          '--trace_to_cloud',
          '--otel_to_cloud',
          '--with-ui',
          '--adk-version', '2026.10.15',
          '--verbosity', 'DEBUG',
          '--command-timeout', '120',
          '--cluster', 'my-cluster',
          '--location', 'us-central1-a',
          '--subnetwork', 'my-subnet',
          '--staging_bucket', 'gs://my-bucket',
          '--min_instances', '1',
          '--max_instances', '10',
          '--concurrency', '80',
          '--cpu', '2',
          '--memory', '4Gi',
          '--allow-unauthenticated',
          '--vpc_connector', 'my-vpc',
          '--ingress', 'all',
          '--env_vars', 'KEY1=VAL1,KEY2=VAL2',
          '--source', '.',
          '--dockerfile', 'Dockerfile',
        ],
        outSink: out,
        errSink: err,
        environment: <String, String>{
          'GOOGLE_CLOUD_PROJECT': 'test-project',
          'GOOGLE_CLOUD_LOCATION': 'us-central1',
        },
      );
      expect(code, 0);
      expect(out.output, contains('gcloud run deploy'));

      // 3. Verbosity warning in err
      expect(err.output, contains('WARNING: Deprecated option --verbosity is used'));

      // 4. DeployCommandRunner invocation
      final List<List<String>> executedCommands = <List<String>>[];
      final int runnerExitCode = await runDeployCommand(
        <String>[
          'cloud_run',
          '--project', 'test-project',
          '--service', 'exec-svc',
        ],
        outSink: out,
        commandRunner: (
          List<String> command, {
          required IOSink out,
          required IOSink err,
          required Map<String, String> environment,
        }) async {
          executedCommands.add(command);
          return 0;
        },
      );
      expect(runnerExitCode, 0);
      expect(executedCommands, isNotEmpty);

      // 5. Default outSink check for line 492
      expect(await runDeployCommand(<String>['--help']), 0);

      // 6. Comprehensive flag parsing forms for parseDeployCliOptions
      final DeployCliOptions parsed1 = parseDeployCliOptions(
        <String>[
          'cloud_run',
          '--service=svc1',
          '--service-name=svc2',
          '--app_name=app1',
          '--temp_folder=/tmp/f',
          '--service-account=sa@g.com',
          '--adk-version=1.0.0',
          '--allow-origins', 'https://a.com',
          '--allow-origins=https://b.com',
          '--session-service-uri', 'memory:',
          '--artifact-service-uri', 'memory:',
          '--memory-service-uri', 'memory:',
          '--session_db_url', 'sqlite:////tmp/s.db',
          '--session_db_url=sqlite:////tmp/s2.db',
          '--artifact_storage_uri', 'gs://bucket1',
          '--artifact_storage_uri=gs://bucket2',
          '--trigger-sources', 'pubsub',
          '--trigger-sources=eventarc',
          '--trigger-oidc-audience', 'aud1',
          '--trigger-oidc-audience=aud2',
          '--trigger-oidc-service-accounts', 'sa1@g.com',
          '--trigger-oidc-service-accounts=sa2@g.com',
          '--extra-packages=pkg_a',
          '--provider-args=k1=v1',
          '--provider_args=k2=v2',
          '--api-key', 'secret-key-1',
          '--api-key=secret-key-2',
          '--verbosity=WARNING',
          '--absolutize_imports', 'true',
          '--agent-engine-id', 'ae1',
          '--agent-engine-id=ae2',
          '--display-name', 'd1',
          '--display-name=d2',
          '--description', 'desc1',
          '--agent-engine-config-file', 'ae.yaml',
          '--agent-engine-config-file=ae2.yaml',
          '--worker-pool=pool1',
          '--cluster-name=clust1',
          '--service-type', 'ClusterIP',
          '--service-type=LoadBalancer',
        ],
        env: <String, String>{'GOOGLE_CLOUD_PROJECT': 'my-proj'},
      );
      expect(parsed1.service, 'svc2');
      expect(parsed1.apiKey, 'secret-key-2');
      expect(parsed1.extraPackages, contains('pkg_a'));

      // 7. Conflicting import validation options throws ArgumentError
      expect(
        () => parseDeployCliOptions(
          <String>[
            'cloud_run',
            '--validate-agent-import',
            '--skip-agent-import-validation',
            '--project=p',
          ],
        ),
        throwsArgumentError,
      );

      // 8. Error when use_local_storage is passed with explicit session service
      expect(
        () => parseDeployCliOptions(
          <String>[
            'cloud_run',
            '--use_local_storage',
            '--session_service_uri=memory:',
            '--project=p',
          ],
        ),
        throwsArgumentError,
      );

      // 9. GKE default service name from cluster-name
      final DeployCliOptions gkeParsed = parseDeployCliOptions(
        <String>['gke', '--cluster-name=my-cluster', '--project=p'],
      );
      expect(gkeParsed.service, 'my-cluster');
    });
  });
}
