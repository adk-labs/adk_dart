import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:adk/cli.dart' as cli;
import 'package:adk/src/cli/api_server.dart';
import 'package:adk/src/cli/cli_deploy.dart';
import 'package:adk/src/cli/deployers/_cloud_run_deployer.dart';
import 'package:adk/src/cli/deployers/_docker_deployer.dart';
import 'package:adk/src/cli/deployers/_dockerfile_template.dart';
import 'package:adk/src/cli/dev_server.dart';
import 'package:adk/src/cli/trigger_routes.dart';
import 'package:adk/src/cli/utils/base_agent_loader.dart';
import 'package:adk/src/dev/project.dart';
import 'package:adk/src/dev/runtime.dart';
import 'package:adk/src/dev/web_server.dart';
import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

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

class _FakeRuntimesClient implements AgentEngineRuntimesClient {
  _FakeRuntimesClient({this.existing = const <AgentEngineRuntimeInfo>[]});

  final List<AgentEngineRuntimeInfo> existing;
  final List<String?> listFilters = <String?>[];
  int createCount = 0;
  final List<(String, Map<String, Object?>)> updates =
      <(String, Map<String, Object?>)>[];

  @override
  Future<List<AgentEngineRuntimeInfo>> list({String? filter}) async {
    listFilters.add(filter);
    return List<AgentEngineRuntimeInfo>.of(existing);
  }

  @override
  Future<AgentEngineRuntimeInfo> create() async {
    createCount += 1;
    return const AgentEngineRuntimeInfo(
      name: 'projects/p/locations/l/reasoningEngines/new-1',
    );
  }

  @override
  Future<void> update({
    required String name,
    required Map<String, Object?> config,
  }) async {
    updates.add((name, Map<String, Object?>.of(config)));
  }

  @override
  Future<void> delete({required String name}) async {}
}

class _EchoModel extends BaseLlm {
  _EchoModel() : super(model: 'echo-model');

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    yield LlmResponse(content: Content.modelText('ok'));
  }
}

class _RateLimitEventModel extends BaseLlm {
  _RateLimitEventModel() : super(model: 'rate-limit-event-model');

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    yield LlmResponse(
      errorCode: '429',
      errorMessage: 'secret-provider-quota-detail /internal/path',
    );
  }
}

class _RateLimitThrowModel extends BaseLlm {
  _RateLimitThrowModel() : super(model: 'rate-limit-throw-model');

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    throw StateError('RESOURCE_EXHAUSTED: secret-upstream-host');
  }
}

class _FailingArtifactService extends BaseArtifactService {
  @override
  Future<int> saveArtifact({
    required String appName,
    required String userId,
    String? sessionId,
    required String filename,
    required Part artifact,
    Map<String, Object?>? customMetadata,
  }) async {
    throw StateError('bucket leak gs://secret/path');
  }

  @override
  Future<Part?> loadArtifact({
    required String appName,
    required String userId,
    String? sessionId,
    required String filename,
    int? version,
  }) async => null;

  @override
  Future<List<String>> listArtifactKeys({
    required String appName,
    required String userId,
    String? sessionId,
  }) async => const <String>[];

  @override
  Future<void> deleteArtifact({
    required String appName,
    required String userId,
    String? sessionId,
    required String filename,
  }) async {}

  @override
  Future<List<int>> listVersions({
    required String appName,
    required String userId,
    String? sessionId,
    required String filename,
  }) async => const <int>[];

  @override
  Future<List<ArtifactVersion>> listArtifactVersions({
    required String appName,
    required String userId,
    String? sessionId,
    required String filename,
  }) async => const <ArtifactVersion>[];

  @override
  Future<ArtifactVersion?> getArtifactVersion({
    required String appName,
    required String userId,
    String? sessionId,
    required String filename,
    int? version,
  }) async => null;
}

class _MapLoader extends BaseAgentLoader {
  _MapLoader(this._agents);

  final Map<String, AgentOrApp> _agents;

  @override
  AgentOrApp loadAgent(String agentName) {
    if (agentName.startsWith('__')) {
      throw ArgumentError.value(
        agentName,
        'agentName',
        "Invalid agent name: '$agentName'. Names starting with '__' are reserved.",
      );
    }
    final AgentOrApp? found = _agents[agentName];
    if (found == null) {
      throw StateError('Agent not found: $agentName');
    }
    return found;
  }

  @override
  List<String> listAgents() => _agents.keys.toList()..sort();

  @override
  List<Map<String, Object?>> listAgentsDetailed() => const <Map<String, Object?>>[];
}

void main() {
  group('Unit D - bd77f3f2c python_version across deployers and cli_deploy', () {
    late Directory tempRoot;
    late Directory agentDir;

    setUp(() {
      tempRoot = Directory.systemTemp.createTempSync('adk_nov26_pyver_');
      agentDir = Directory('${tempRoot.path}${Platform.pathSeparator}my_agent')
        ..createSync(recursive: true);
    });

    tearDown(() {
      if (tempRoot.existsSync()) {
        tempRoot.deleteSync(recursive: true);
      }
      agentEngineRuntimesClientFactoryTestingOverride = null;
      defaultDeployRunnerTestingOverride = null;
    });

    test('validatePythonVersion enforces Python 3.11+ and deployUsage lists --python_version', () {
      expect(validatePythonVersion('3.11'), '3.11');
      expect(validatePythonVersion('3.12'), '3.12');
      expect(validatePythonVersion('3.12.1'), '3.12.1');
      expect(() => validatePythonVersion('3.10'), throwsArgumentError);
      expect(() => validatePythonVersion('2.7'), throwsArgumentError);
      expect(() => validatePythonVersion('3.12-slim'), throwsArgumentError);
      expect(() => validatePythonVersion('3.12\nRUN id'), throwsArgumentError);
      expect(deployUsage, contains('--python_version'));
      expect(deployUsage, contains('--python-version'));
    });

    test('parseDeployCliOptions handles --python_version defaults and validation', () async {
      final DeployCliOptions cloudRunDefault = parseDeployCliOptions(
        const <String>['cloud_run', '--project=p'],
      );
      expect(cloudRunDefault.pythonVersion, '3.11');

      final DeployCliOptions cloudRunExplicit = parseDeployCliOptions(
        const <String>['cloud_run', '--project=p', '--python_version=3.12'],
      );
      expect(cloudRunExplicit.pythonVersion, '3.12');

      final DeployCliOptions dockerKebab = parseDeployCliOptions(
        const <String>['docker', '--python-version', '3.13.1'],
      );
      expect(dockerKebab.pythonVersion, '3.13.1');

      final DeployCliOptions agentEngineOmitted = parseDeployCliOptions(
        const <String>['agent_engine', '--project=p'],
      );
      expect(agentEngineOmitted.pythonVersion, isNull);

      final DeployCliOptions agentEngineExplicit = parseDeployCliOptions(
        const <String>['agent_engine', '--project=p', '--python-version=3.12'],
      );
      expect(agentEngineExplicit.pythonVersion, '3.12');

      final _CapturedSink out = _CapturedSink();
      final _CapturedSink err = _CapturedSink();
      final int badExit = await runDeployCommand(
        const <String>['cloud_run', '--project=p', '--python_version=3.10'],
        outSink: out.sink,
        errSink: err.sink,
      );
      await out.closeAndRead();
      final String errText = await err.closeAndRead();
      expect(badExit, 64);
      expect(errText, contains('Invalid Python version'));

      expect(
        () => toCloudRun(
          DeployCommand(
            service: 'svc',
            project: 'p',
            region: 'us-central1',
            image: 'img:latest',
            pythonVersion: '3.10',
          ),
        ),
        throwsArgumentError,
      );
      expect(
        () => toDocker(
          DeployCommand(
            service: 'svc',
            project: 'p',
            region: 'us-central1',
            image: 'img:latest',
            pythonVersion: '3.10',
          ),
        ),
        throwsArgumentError,
      );
      expect(
        () => toGke(
          DeployCommand(
            service: 'svc',
            project: 'p',
            region: 'us-central1',
            image: 'img:latest',
            pythonVersion: '3.10',
          ),
        ),
        throwsArgumentError,
      );
    });

    test('DockerDeployer and CloudRunDeployer forward pythonVersion into rendered Dockerfile', () async {
      final Directory dockerStaging = Directory('${tempRoot.path}/docker_stage')
        ..createSync();
      final DockerDeployer dockerDeployer = DockerDeployer();
      await dockerDeployer.deploy(
        agentFolder: agentDir.path,
        tempFolder: dockerStaging.path,
        pythonVersion: '3.12',
        buildImage: false,
      );
      final String dockerFile = File(
        '${dockerStaging.path}/Dockerfile',
      ).readAsStringSync();
      expect(dockerFile, contains('FROM python:3.12-slim'));

      final Directory cloudRunStaging = Directory('${tempRoot.path}/cr_stage')
        ..createSync();
      final List<(String, List<String>)> recorded = <(String, List<String>)>[];
      final CloudRunDeployer cloudRunDeployer = CloudRunDeployer(
        processRunner: (
          String executable,
          List<String> arguments, {
          String? workingDirectory,
        }) async {
          recorded.add((executable, arguments));
          return ProcessResult(1, 0, '', '');
        },
      );
      await cloudRunDeployer.deploy(
        agentFolder: agentDir.path,
        project: 'my-proj',
        region: 'us-central1',
        tempFolder: cloudRunStaging.path,
        pythonVersion: '3.13',
      );
      final String crDockerfile = File(
        '${cloudRunStaging.path}/Dockerfile',
      ).readAsStringSync();
      expect(crDockerfile, contains('FROM python:3.13-slim'));
      expect(recorded.single.$1, 'gcloud');

      await expectLater(
        () => dockerDeployer.deploy(
          agentFolder: agentDir.path,
          tempFolder: dockerStaging.path,
          pythonVersion: '3.10',
        ),
        throwsArgumentError,
      );
      await expectLater(
        () => cloudRunDeployer.deploy(
          agentFolder: agentDir.path,
          project: 'my-proj',
          tempFolder: cloudRunStaging.path,
          pythonVersion: '3.10',
        ),
        throwsArgumentError,
      );
    });

    test('Agent Engine config python_version precedence and stripping before update', () async {
      File('${agentDir.path}${Platform.pathSeparator}.agent_engine_config.json')
          .writeAsStringSync(
            jsonEncode(<String, Object?>{
              'display_name': 'PyVerAgent',
              'python_version': '3.12',
            }),
          );
      final _FakeRuntimesClient client = _FakeRuntimesClient();
      final _CapturedSink out = _CapturedSink();
      final _CapturedSink err = _CapturedSink();

      // 1. CLI pythonVersion overrides config and pops python_version from config.
      await deployToAgentEngine(
        client: client,
        agentFolder: agentDir.path,
        project: 'p',
        region: 'us-central1',
        pythonVersion: '3.13',
        out: out.sink,
        err: err.sink,
      );
      final String stdoutText = await out.closeAndRead();
      await err.closeAndRead();
      expect(
        stdoutText,
        contains('Overriding python_version in agent platform config with 3.13'),
      );
      expect(client.updates.single.$2.containsKey('python_version'), isFalse);

      // 2. Invalid python_version in .agent_engine_config.json fails fast.
      File('${agentDir.path}${Platform.pathSeparator}.agent_engine_config.json')
          .writeAsStringSync(
            jsonEncode(<String, Object?>{'python_version': '3.10'}),
          );
      await expectLater(
        () => deployToAgentEngine(
          client: client,
          agentFolder: agentDir.path,
          project: 'p',
          region: 'us-central1',
        ),
        throwsArgumentError,
      );
    });
  });

  group('Unit D - 7d2c7b75d & 84cb0742b Agent Engine validation & duplicate warning', () {
    late Directory tempRoot;
    late Directory agentDir;

    setUp(() {
      tempRoot = Directory.systemTemp.createTempSync('adk_nov26_ae_');
      agentDir = Directory('${tempRoot.path}${Platform.pathSeparator}ae_agent')
        ..createSync(recursive: true);
    });

    tearDown(() {
      if (tempRoot.existsSync()) {
        tempRoot.deleteSync(recursive: true);
      }
      agentEngineRuntimesClientFactoryTestingOverride = null;
      defaultDeployRunnerTestingOverride = null;
    });

    test('toAgentEngine and deployToAgentEngine emit warning when adkVersion < 2.0.0 and validateAgentImport=true', () async {
      final _CapturedSink err = _CapturedSink();
      toAgentEngine(
        DeployCommand(
          service: 'ae',
          project: 'p',
          region: 'us-central1',
          image: 'img:latest',
          adkVersion: '1.21.0',
          validateAgentImport: true,
        ),
        err: err.sink,
      );
      final String toAeErr = await err.closeAndRead();
      expect(
        toAeErr,
        contains(
          'Omitting startup agent import validation as it requires adk_version 2.0.0 or later, and 1.21.0 was requested',
        ),
      );

      final _FakeRuntimesClient client = _FakeRuntimesClient();
      final _CapturedSink aeOut = _CapturedSink();
      final _CapturedSink aeErr = _CapturedSink();
      await deployToAgentEngine(
        client: client,
        agentFolder: agentDir.path,
        project: 'p',
        region: 'us-central1',
        adkVersion: '1.21.0',
        validateAgentImport: true,
        out: aeOut.sink,
        err: aeErr.sink,
      );
      await aeOut.closeAndRead();
      final String aeErrText = await aeErr.closeAndRead();
      expect(
        aeErrText,
        contains('Omitting startup agent import validation'),
      );

      // No warning when validateAgentImport is false.
      final _CapturedSink skippedErr = _CapturedSink();
      toAgentEngine(
        DeployCommand(
          service: 'ae',
          project: 'p',
          region: 'us-central1',
          image: 'img:latest',
          adkVersion: '1.21.0',
          validateAgentImport: false,
        ),
        err: skippedErr.sink,
      );
      expect(await skippedErr.closeAndRead(), isEmpty);
    });

    test('runDeployCommand runs best-effort duplicate warning when updateIfExists=false and commandRunner=null, but preserves custom commandRunner', () async {
      final _FakeRuntimesClient fakeClient = _FakeRuntimesClient(
        existing: const <AgentEngineRuntimeInfo>[
          AgentEngineRuntimeInfo(
            name: 'projects/p/locations/us-central1/reasoningEngines/999',
            updateTime: '2026-11-25T10:00:00Z',
          ),
        ],
      );
      agentEngineRuntimesClientFactoryTestingOverride =
          (String project, String region, Map<String, String> environment) =>
              fakeClient;
      defaultDeployRunnerTestingOverride = (
        List<String> command, {
        required IOSink out,
        required IOSink err,
        required Map<String, String> environment,
      }) async => 0;

      final _CapturedSink out = _CapturedSink();
      final _CapturedSink err = _CapturedSink();
      final int exitCode = await runDeployCommand(
        <String>[
          'agent_engine',
          '--project=p',
          '--region=us-central1',
          '--display_name=DupAgent',
          agentDir.path,
        ],
        outSink: out.sink,
        errSink: err.sink,
      );
      await out.closeAndRead();
      final String errText = await err.closeAndRead();
      expect(exitCode, 0);
      expect(fakeClient.listFilters, <String?>['display_name="DupAgent"']);
      expect(fakeClient.createCount, 0);
      expect(errText, contains('WARNING: 1 Agent Runtime(s)'));
      expect(
        errText,
        contains('projects/p/locations/us-central1/reasoningEngines/999'),
      );

      // Custom commandRunner preserves existing behavior (no HTTP list call).
      final _FakeRuntimesClient customRunnerClient = _FakeRuntimesClient();
      agentEngineRuntimesClientFactoryTestingOverride =
          (_, _, _) => customRunnerClient;
      final _CapturedSink runnerOut = _CapturedSink();
      final _CapturedSink runnerErr = _CapturedSink();
      final int runnerCode = await runDeployCommand(
        <String>[
          'agent_engine',
          '--project=p',
          '--region=us-central1',
          '--display_name=DupAgent',
          agentDir.path,
        ],
        outSink: runnerOut.sink,
        errSink: runnerErr.sink,
        commandRunner: (
          List<String> command, {
          required IOSink out,
          required IOSink err,
          required Map<String, String> environment,
        }) async => 0,
      );
      await runnerOut.closeAndRead();
      await runnerErr.closeAndRead();
      expect(runnerCode, 0);
      expect(customRunnerClient.listFilters, isEmpty);
    });
  });

  group('Unit D - f27b8f105 api_server getPropagatedContext wiring', () {
    const String aeTraceparent =
        '00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01';
    const String otherTraceparent =
        '00-11111111111111111111111111111111-2222222222222222-00';

    test('supports Google-Agent-Engine-Traceparent, Agent Engine isolation, and baggage sanitization', () {
      // 1. Agent Engine isolation ignores plain traceparent, keeps supportID.
      final W3cTraceContext isolated = extractW3cTraceContext(
        const <String, String>{
          'traceparent': otherTraceparent,
          'tracestate': 'congo=t61rcWkgMzE',
          'baggage': 'tenant=acme',
        },
        environment: const <String, String>{
          'GOOGLE_CLOUD_AGENT_ENGINE_ID': 'ae-123',
        },
      );
      expect(isolated.hasTraceContext, isFalse);
      expect(isolated.traceId, isNull);
      expect(isolated.parentSpanId, isNull);
      expect(isolated.tracestate, isNull);
      expect(isolated.supportId, otherTraceparent);
      expect(isolated.baggage, const <String, String>{'tenant': 'acme'});

      // 2. Google-Agent-Engine-Traceparent overrides plain traceparent even on AE.
      final W3cTraceContext aeOverride = extractW3cTraceContext(
        const <String, String>{
          'Google-Agent-Engine-Traceparent': aeTraceparent,
          'traceparent': otherTraceparent,
        },
        environment: const <String, String>{
          'GOOGLE_CLOUD_AGENT_ENGINE_ID': 'ae-123',
        },
      );
      expect(aeOverride.hasTraceContext, isTrue);
      expect(aeOverride.traceId, '4bf92f3577b34da6a3ce929d0e0e4736');
      expect(aeOverride.parentSpanId, '00f067aa0ba902b7');
      expect(aeOverride.supportId, otherTraceparent);

      // 3. Spoofed traceparent / google_traceparent in baggage are stripped.
      final W3cTraceContext sanitized = extractW3cTraceContext(
        const <String, String>{
          'baggage':
              'tenant_id=acme,traceparent=spoofed,google_traceparent=spoofed',
        },
        baseContext: AgentEngineTelemetryContext(
          baggage: const <String, String>{
            'traceparent': 'spoofed-base',
            'google_traceparent': 'spoofed-base',
          },
        ),
      );
      expect(sanitized.baggage, const <String, String>{'tenant_id': 'acme'});
      expect(sanitized.supportId, isNull);
      expect(sanitized.propagatedContext?.getBaggage('traceparent'), isNull);
      expect(
        sanitized.propagatedContext?.getBaggage('google_traceparent'),
        isNull,
      );
    });

    test('server /run propagates Google-Agent-Engine-Traceparent and supportID to trace spans under AE env', () async {
      final Directory tempDir = await Directory.systemTemp.createTemp(
        'adk_nov26_ae_trace_',
      );
      addTearDown(() => tempDir.delete(recursive: true));
      const DevProjectConfig project = DevProjectConfig(
        appName: 'ae_trace_app',
        agentName: 'assistant',
        description: 'AE trace test',
      );
      final Agent agent = Agent(name: 'assistant', model: _EchoModel());
      final Runner runner = Runner(
        appName: 'ae_trace_app',
        agent: agent,
        sessionService: InMemorySessionService(),
        autoCreateSession: true,
      );
      final DevAgentRuntime runtime = DevAgentRuntime(
        config: project,
        runner: runner,
      );
      final HttpServer server = await startAdkDevWebServer(
        runtime: runtime,
        project: project,
        agentsDir: tempDir.path,
        port: 0,
        enableWebUi: false,
        environment: const <String, String>{
          'GOOGLE_CLOUD_AGENT_ENGINE_ID': 'ae-999',
        },
      );
      final HttpClient client = HttpClient();
      try {
        final Uri baseUri = Uri.parse('http://127.0.0.1:${server.port}');
        final HttpClientRequest req = await client.postUrl(
          baseUri.replace(path: '/run'),
        );
        req.headers.contentType = ContentType.json;
        req.headers.set('Google-Agent-Engine-Traceparent', aeTraceparent);
        req.headers.set('traceparent', otherTraceparent);
        req.write(
          jsonEncode(<String, Object?>{
            'app_name': 'ae_trace_app',
            'user_id': 'u1',
            'session_id': 's_ae_trace',
            'autoCreateSession': true,
            'new_message': <String, Object?>{
              'role': 'user',
              'parts': <Map<String, Object?>>[
                <String, Object?>{'text': 'hi'},
              ],
            },
          }),
        );
        final HttpClientResponse res = await req.close();
        expect(res.statusCode, HttpStatus.ok);
        await res.drain<void>();

        final HttpClientRequest traceReq = await client.getUrl(
          baseUri.replace(path: '/debug/trace/session/s_ae_trace'),
        );
        final HttpClientResponse traceRes = await traceReq.close();
        expect(traceRes.statusCode, HttpStatus.ok);
        final List<dynamic> spans =
            jsonDecode(await utf8.decoder.bind(traceRes).join())
                as List<dynamic>;
        expect(spans, isNotEmpty);
        final Map<String, dynamic> span = spans.first as Map<String, dynamic>;
        expect(span['trace_id'], '4bf92f3577b34da6a3ce929d0e0e4736');
        expect(span['parent_span_id'], '00f067aa0ba902b7');
        final Map<String, dynamic> attrs =
            span['attributes'] as Map<String, dynamic>;
        expect(attrs['supportID'], otherTraceparent);
      } finally {
        client.close(force: true);
        await server.close(force: true);
        await runtime.runner.close();
      }
    });
  });

  group('Unit D - e2a21ac23, ec2ac7c5e, d61f4281d, c890aa317, 6507ad8da', () {
    test('e2a21ac23: /run and /run_sse return HTTP 404 for __-prefixed reserved app names', () async {
      final Directory tempDir = await Directory.systemTemp.createTemp(
        'adk_nov26_run404_',
      );
      addTearDown(() => tempDir.delete(recursive: true));

      final AdkDevServer devServer = AdkDevServer(
        agentsDir: tempDir.path,
        port: 0,
      );
      final HttpServer server = await devServer.start();
      addTearDown(devServer.stop);

      final HttpClient client = HttpClient();
      addTearDown(() => client.close(force: true));

      for (final String route in <String>['/run', '/run_sse']) {
        final HttpClientRequest req = await client.postUrl(
          Uri.parse('http://127.0.0.1:${server.port}$route'),
        );
        req.headers.contentType = ContentType.json;
        req.write(
          jsonEncode(<String, Object?>{
            'app_name': '__adk_agent_builder_assistant',
            'user_id': 'u1',
            'session_id': 's1',
            'new_message': <String, Object?>{
              'role': 'user',
              'parts': <Map<String, Object?>>[
                <String, Object?>{'text': 'hi'},
              ],
            },
          }),
        );
        final HttpClientResponse res = await req.close();
        await res.drain<void>();
        expect(res.statusCode, HttpStatus.notFound, reason: route);
      }
    });

    test('ec2ac7c5e: app-info traverses NodeTool, BaseNode tool entries, ParallelWorker.wrappedNode, and warns on duplicate LlmAgent names', () async {
      final Directory tempDir = await Directory.systemTemp.createTemp(
        'adk_nov26_app_info_',
      );
      addTearDown(() => tempDir.delete(recursive: true));

      final LlmAgent nodeToolAgent = LlmAgent(
        name: 'node_tool_llm',
        model: _EchoModel(),
        instruction: 'Via NodeTool',
      );
      final LlmAgent baseNodeToolAgent = LlmAgent(
        name: 'base_node_tool_llm',
        model: _EchoModel(),
        instruction: 'Via BaseNode tool entry',
      );
      final LlmAgent dupSecond = LlmAgent(
        name: 'dup_llm',
        model: _EchoModel(),
        instruction: 'Second duplicate',
      );
      final LlmAgent dupFirst = LlmAgent(
        name: 'dup_llm',
        model: _EchoModel(),
        instruction: 'First duplicate',
        subAgents: <BaseAgent>[dupSecond],
      );
      final LlmAgent rootLlm = LlmAgent(
        name: 'root_llm',
        model: _EchoModel(),
        instruction: 'Root',
        tools: <Object>[
          NodeTool(node: AgentNode(agent: nodeToolAgent, name: 'nt_node')),
          AgentNode(agent: baseNodeToolAgent, name: 'bn_node'),
        ],
        subAgents: <BaseAgent>[dupFirst],
      );
      final LlmAgent workerLlm = LlmAgent(
        name: 'worker_llm',
        model: _EchoModel(),
        instruction: 'Inside ParallelWorker',
      );
      final Workflow workflow = Workflow(
        name: 'wf_root',
        nodes: <BaseNode>[
          AgentNode(agent: rootLlm, name: 'root_node'),
          ParallelWorker(
            node: AgentNode(agent: workerLlm, name: 'worker_node'),
          ),
        ],
      );

      final List<String> warnings = <String>[];
      duplicateAgentInfoWarningTestingOverride = warnings.add;
      addTearDown(() {
        duplicateAgentInfoWarningTestingOverride = null;
      });

      final AdkDevServer devServer = AdkDevServer(
        agentsDir: tempDir.path,
        agentLoader: _MapLoader(<String, AgentOrApp>{'wf_app': workflow}),
        port: 0,
      );
      final HttpServer server = await devServer.start();
      addTearDown(devServer.stop);

      final HttpClient client = HttpClient();
      addTearDown(() => client.close(force: true));

      final HttpClientRequest req = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/apps/wf_app/app-info'),
      );
      final HttpClientResponse res = await req.close();
      expect(res.statusCode, HttpStatus.ok);
      final Map<String, dynamic> payload =
          jsonDecode(await utf8.decoder.bind(res).join())
              as Map<String, dynamic>;

      expect(payload['name'], 'wf_app');
      expect(payload['rootAgentName'], 'wf_root');
      final Map<String, dynamic> agents =
          payload['agents'] as Map<String, dynamic>;
      expect(
        agents.keys,
        containsAll(<String>[
          'root_llm',
          'node_tool_llm',
          'base_node_tool_llm',
          'dup_llm',
          'worker_llm',
        ]),
      );
      // NodeTool / BaseNode tool children are not added to subAgents.
      expect(
        (agents['root_llm'] as Map<String, dynamic>)['subAgents'],
        <String>['dup_llm'],
      );
      // First duplicate wins and warning is emitted.
      expect(
        (agents['dup_llm'] as Map<String, dynamic>)['instruction'],
        'First duplicate',
      );
      expect(warnings, hasLength(1));
      expect(warnings.single, contains("Duplicate LlmAgent name 'dup_llm'"));
    });

    test('d61f4281d: trigger routes return fixed 400 on invalid base64 and keep provider error in TransientError.cause', () async {
      // 1. handlePubSubRequest returns fixed FormatException without raw error leak.
      final InMemorySessionService sessionService = InMemorySessionService();
      final Runner okRunner = Runner(
        appName: 'trig_app',
        agent: Agent(name: 'a', model: _EchoModel()),
        sessionService: sessionService,
      );
      final TriggerRouter okRouter = TriggerRouter(
        getRunnerAsync: (_) async => okRunner,
        sessionService: sessionService,
        triggerSources: const <String>['pubsub'],
      );
      await expectLater(
        () => okRouter.handlePubSubRequest(
          appName: 'trig_app',
          triggerRequest: PubSubTriggerRequest(
            message: PubSubMessage(data: '%%%NOT_BASE64%%%'),
          ),
        ),
        throwsA(
          isA<FormatException>().having(
            (FormatException e) => e.message,
            'message',
            'Invalid base64 in message.data',
          ),
        ),
      );
      await okRunner.close();

      // 2. HTTP /apps/{app}/trigger/pubsub returns 400 with fixed detail.
      const DevProjectConfig project = DevProjectConfig(
        appName: 'trig_http_app',
        agentName: 'assistant',
        description: 'Trigger HTTP test',
      );
      final DevAgentRuntime runtime = DevAgentRuntime(config: project);
      final HttpServer server = await startAdkDevWebServer(
        runtime: runtime,
        project: project,
        port: 0,
        enableWebUi: false,
        triggerSources: const <String>['pubsub'],
      );
      final HttpClient client = HttpClient();
      try {
        final HttpClientRequest req = await client.postUrl(
          Uri.parse(
            'http://127.0.0.1:${server.port}/apps/trig_http_app/trigger/pubsub',
          ),
        );
        req.headers.contentType = ContentType.json;
        req.write(
          jsonEncode(<String, Object?>{
            'message': <String, Object?>{'data': '%%%SECRET_INVALID_B64%%%'},
          }),
        );
        final HttpClientResponse res = await req.close();
        expect(res.statusCode, HttpStatus.badRequest);
        final Map<String, dynamic> body =
            jsonDecode(await utf8.decoder.bind(res).join())
                as Map<String, dynamic>;
        expect(body['detail'], 'Invalid base64 in message.data');
        expect('${body['detail']}', isNot(contains('SECRET_INVALID_B64')));
      } finally {
        client.close(force: true);
        await server.close(force: true);
        await runtime.runner.close();
      }

      // 3. TransientError keeps provider details in .cause rather than .message.
      final Runner eventRateLimitRunner = Runner(
        appName: 'rl_event',
        agent: Agent(name: 'a', model: _RateLimitEventModel()),
        sessionService: sessionService,
      );
      final TriggerRouter eventRouter = TriggerRouter(
        getRunnerAsync: (_) async => eventRateLimitRunner,
        sessionService: sessionService,
        triggerSources: const <String>['pubsub'],
        maxRetries: 0,
        baseDelaySeconds: 0.0,
        maxDelaySeconds: 0.0,
      );
      await expectLater(
        () => eventRouter.handlePubSubRequest(
          appName: 'rl_event',
          triggerRequest: PubSubTriggerRequest(
            message: PubSubMessage(data: base64Encode(utf8.encode('hi'))),
          ),
        ),
        throwsA(
          isA<TransientError>()
              .having(
                (TransientError e) => e.message,
                'message',
                isNot(contains('secret-provider-quota-detail')),
              )
              .having(
                (TransientError e) => '${e.cause}',
                'cause',
                contains('secret-provider-quota-detail'),
              ),
        ),
      );
      await eventRateLimitRunner.close();

      final Runner throwRateLimitRunner = Runner(
        appName: 'rl_throw',
        agent: Agent(name: 'a', model: _RateLimitThrowModel()),
        sessionService: sessionService,
      );
      final TriggerRouter throwRouter = TriggerRouter(
        getRunnerAsync: (_) async => throwRateLimitRunner,
        sessionService: sessionService,
        triggerSources: const <String>['pubsub'],
        maxRetries: 0,
        baseDelaySeconds: 0.0,
        maxDelaySeconds: 0.0,
      );
      await expectLater(
        () => throwRouter.handlePubSubRequest(
          appName: 'rl_throw',
          triggerRequest: PubSubTriggerRequest(
            message: PubSubMessage(data: base64Encode(utf8.encode('hi'))),
          ),
        ),
        throwsA(
          isA<TransientError>()
              .having(
                (TransientError e) => e.message,
                'message',
                isNot(contains('secret-upstream-host')),
              )
              .having(
                (TransientError e) => '${e.cause}',
                'cause',
                contains('secret-upstream-host'),
              ),
        ),
      );
      await throwRateLimitRunner.close();
    });

    test('c890aa317: checkCodeReference rejects blocked keys without visual builder wording', () {
      expect(
        () => checkCodeReference(<String, Object?>{
          'agent': <String, Object?>{'code': 'os.system'},
        }),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError e) => '${e.message}',
            'message',
            allOf(
              contains('agent YAML'),
              isNot(contains('visual builder')),
            ),
          ),
        ),
      );
    });

    test('6507ad8da: saving artifact failure returns HTTP 500 with "Failed to save artifact"', () async {
      const DevProjectConfig project = DevProjectConfig(
        appName: 'art_app',
        agentName: 'assistant',
        description: 'Artifact failure test',
      );
      final DevAgentRuntime runtime = DevAgentRuntime(config: project);
      webServerArtifactServiceTestingOverride = _FailingArtifactService();
      addTearDown(() {
        webServerArtifactServiceTestingOverride = null;
      });
      final HttpServer server = await startAdkDevWebServer(
        runtime: runtime,
        project: project,
        port: 0,
        enableWebUi: false,
      );
      final HttpClient client = HttpClient();
      try {
        final HttpClientRequest req = await client.postUrl(
          Uri.parse(
            'http://127.0.0.1:${server.port}/apps/art_app/users/u1/sessions/s1/artifacts',
          ),
        );
        req.headers.contentType = ContentType.json;
        req.write(
          jsonEncode(<String, Object?>{
            'filename': 'test.txt',
            'artifact': <String, Object?>{'text': 'hello'},
          }),
        );
        final HttpClientResponse res = await req.close();
        expect(res.statusCode, HttpStatus.internalServerError);
        final Map<String, dynamic> body =
            jsonDecode(await utf8.decoder.bind(res).join())
                as Map<String, dynamic>;
        expect(body['detail'], 'Failed to save artifact');
        expect(body['error'], 'Failed to save artifact');
      } finally {
        client.close(force: true);
        await server.close(force: true);
        await runtime.runner.close();
      }
    });
  });

  // Reference cli.main to verify top-level export remains intact.
  test('package:adk/cli.dart exports remain usable', () {
    expect(cli.main, isNotNull);
  });
}
