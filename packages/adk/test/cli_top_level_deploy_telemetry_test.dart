import 'dart:convert';
import 'dart:io';

import 'package:adk/src/cli/_dev_deploy.dart';
import 'package:adk/src/cli/_telemetry/__init__.dart';
import 'package:adk/src/cli/adk_web_server.dart';
import 'package:adk/src/cli/agent_test_runner.dart';
import 'package:adk/src/cli/conformance/__init__.dart';
import 'package:adk/src/cli/deployers/__init__.dart';
import 'package:adk/src/cli/plugins/conformance_recordings_schema.dart';
import 'package:adk/src/dev/project.dart';
import 'package:adk/src/dev/runtime.dart';
import 'package:adk/src/dev/web_server.dart';
import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

void main() {
  group('_dev_deploy models, builders, parsers, and HTTP routes', () {
    test('DeployDefaultsResponse serializes and deserializes camelCase keys', () {
      const DeployDefaults defaults = DeployDefaultsResponse(
        project: 'my-gcp-project',
        projectSource: 'env',
        region: 'us-west1',
        regionSource: 'gcloud',
        displayName: 'my_agent',
        description: 'Helpful agent',
        serviceName: 'my-agent',
        envFile: '.env',
      );
      final Map<String, Object?> json = defaults.toJson();
      expect(json['project'], 'my-gcp-project');
      expect(json['projectSource'], 'env');
      expect(json['region'], 'us-west1');
      expect(json['regionSource'], 'gcloud');
      expect(json['displayName'], 'my_agent');
      expect(json['serviceName'], 'my-agent');
      expect(json['envFile'], '.env');

      final DeployDefaultsResponse roundTrip = DeployDefaultsResponse.fromJson(
        json,
      );
      expect(roundTrip.project, 'my-gcp-project');
      expect(roundTrip.regionSource, 'gcloud');
    });

    test('request validation rejects leading dashes and control characters', () {
      expect(
        () => AgentEngineDeployRequest(
          project: '-bad-project',
          region: 'us-central1',
        ),
        throwsArgumentError,
      );
      expect(
        () => CloudRunDeployRequest(
          project: 'my-project-123',
          region: 'us-central1',
          serviceName: 'Invalid_Upper',
        ),
        throwsArgumentError,
      );
      expect(
        () => GkeDeployRequest(
          project: 'my-project-123',
          region: 'us-central1',
          clusterName: 'my-cluster',
          serviceType: 'InvalidType',
        ),
        throwsArgumentError,
      );
    });

    test('buildDeployArgv constructs expected command lines', () {
      final CloudRunDeployRequest req = CloudRunDeployRequest(
        project: 'my-project-123',
        region: 'us-central1',
        serviceName: 'my-service',
        port: 8080,
        withUi: true,
        extraGcloudArgs: const <String>['--concurrency=10'],
      );
      final List<String> argv = buildDeployArgv(req, '/tmp/my_agent');
      expect(
        argv,
        containsAll(<String>[
          'adk',
          'deploy',
          'cloud_run',
          '--project=my-project-123',
          '--region=us-central1',
          '--service_name=my-service',
          '--port=8080',
          '--with_ui',
          '/tmp/my_agent',
          '--',
          '--concurrency=10',
        ]),
      );
    });

    test('output parsers extract URLs and resource IDs', () {
      final Map<String, Object?> aeSuccess = parseAgentEngineOutput(
        '\x1B[32mCreated projects/my-proj/locations/us-central1/reasoningEngines/987654321\x1B[0m',
        exitCode: 0,
      );
      expect(aeSuccess['status'], 'succeeded');
      expect(aeSuccess['agentEngineId'], '987654321');
      expect(
        aeSuccess['resourceName'],
        'projects/my-proj/locations/us-central1/reasoningEngines/987654321',
      );
      expect(aeSuccess['playgroundUrl'], contains('987654321'));

      final Map<String, Object?> crSuccess = parseCloudRunOutput(
        'Deploying...\nService URL: https://my-service-xyz-uc.a.run.app\nDone.',
        exitCode: 0,
        serviceName: 'my-service',
        region: 'us-central1',
        project: 'my-proj',
      );
      expect(crSuccess['status'], 'succeeded');
      expect(crSuccess['serviceUrl'], 'https://my-service-xyz-uc.a.run.app');
      expect(crSuccess['consoleUrl'], contains('my-service'));

      final Map<String, Object?> gkeSuccess = parseGkeOutput(
        'Deployed to cluster',
        exitCode: 0,
        serviceName: 'my-gke-svc',
        serviceType: 'ClusterIP',
        port: 8000,
      );
      expect(gkeSuccess['status'], 'succeeded');
      expect(
        gkeSuccess['portForwardCommand'],
        'kubectl port-forward svc/my-gke-svc 8000:8000',
      );
    });

    test('web_server exposes /dev/apps/{app}/deploy/defaults when enableWebUi=true and blocks when enableWebUi=false', () async {
      final Directory tempDir = Directory.systemTemp.createTempSync(
        'adk_dev_deploy_test_',
      );
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
        devDeployGcloudRunnerTestingOverride = null;
      });
      final Directory appDir = Directory(
        '${tempDir.path}${Platform.pathSeparator}sample_app',
      )..createSync(recursive: true);
      File('${appDir.path}${Platform.pathSeparator}.env').writeAsStringSync(
        'GOOGLE_CLOUD_PROJECT=dotenv-project-123\nGOOGLE_CLOUD_LOCATION=europe-west1\n',
      );

      devDeployGcloudRunnerTestingOverride = (List<String> args) async => null;

      final DevProjectConfig project = const DevProjectConfig(
        appName: 'sample_app',
        agentName: 'sample_agent',
        userId: 'user',
        description: 'Sample description',
      );
      final DevAgentRuntime runtime = DevAgentRuntime(config: project);
      addTearDown(() async => runtime.runner.close());

      final HttpServer devServer = await startAdkDevWebServer(
        runtime: runtime,
        project: project,
        agentsDir: tempDir.path,
        port: 0,
        enableWebUi: true,
      );
      addTearDown(() async => devServer.close(force: true));

      final HttpClient client = HttpClient();
      addTearDown(() => client.close(force: true));

      final HttpClientRequest getReq = await client.getUrl(
        Uri.parse(
          'http://127.0.0.1:${devServer.port}/dev/apps/sample_app/deploy/defaults',
        ),
      );
      final HttpClientResponse getRes = await getReq.close();
      expect(getRes.statusCode, HttpStatus.ok);
      final Map<String, Object?> payload = Map<String, Object?>.from(
        jsonDecode(await utf8.decoder.bind(getRes).join()) as Map,
      );
      expect(payload['serviceName'], 'sample-app');
      expect(payload['envFile'], '.env');

      // Forwarded header must be rejected with 403 Forbidden (non-local client).
      final HttpClientRequest forwardedReq = await client.getUrl(
        Uri.parse(
          'http://127.0.0.1:${devServer.port}/dev/apps/sample_app/deploy/defaults',
        ),
      );
      forwardedReq.headers.set('X-Forwarded-For', '203.0.113.10');
      final HttpClientResponse forwardedRes = await forwardedReq.close();
      expect(forwardedRes.statusCode, HttpStatus.forbidden);

      // When enableWebUi is false, /dev/apps/.../deploy/* returns 404.
      final HttpServer apiOnlyServer = await startAdkDevWebServer(
        runtime: runtime,
        project: project,
        agentsDir: tempDir.path,
        port: 0,
        enableWebUi: false,
      );
      addTearDown(() async => apiOnlyServer.close(force: true));

      final HttpClientRequest apiReq = await client.getUrl(
        Uri.parse(
          'http://127.0.0.1:${apiOnlyServer.port}/dev/apps/sample_app/deploy/defaults',
        ),
      );
      final HttpClientResponse apiRes = await apiReq.close();
      expect(apiRes.statusCode, HttpStatus.notFound);
    });
  });

  group('api_server and dev_server classes and helpers', () {
    test('AdkApiServer and AdkDevServer configure expected defaults', () {
      final ApiServer apiServer = AdkApiServer(agentsDir: '.');
      expect(apiServer.enableWebUi, isFalse);
      expect(apiServer.allowSpecialAgents, isFalse);
      expect(apiServer.servesDebugTraceEndpoints, isFalse);

      final DevServer devServer = AdkDevServer(agentsDir: '.');
      expect(devServer.enableWebUi, isTrue);
      expect(devServer.allowSpecialAgents, isTrue);
      expect(devServer.servesDebugTraceEndpoints, isTrue);

      final CorsOriginsConfig cors = parseCorsOrigins(<String>[
        'https://example.com',
        r'regex:https://.*\.example\.org',
      ]);
      expect(cors.allowOrigins, <String>['https://example.com']);
      expect(cors.allowOriginRegex, r'(?:https://.*\.example\.org)');
      expect(isLoopbackAddress('127.0.0.1:8000'), isTrue);
      expect(isLoopbackAddress('[::1]:8000'), isTrue);
      expect(isLoopbackAddress('192.168.1.10'), isFalse);

      expect(
        () => checkCodeReference(<String, Object?>{
          'agent': <String, Object?>{'code': 'os.system'},
        }),
        throwsArgumentError,
      );
    });
  });

  group('deployers', () {
    test('DeployerFactory and Dockerfile template rendering', () {
      expect(DeployerFactory.getDeployer('docker'), isA<DockerDeployer>());
      expect(DeployerFactory.getDeployer('cloud_run'), isA<CloudRunDeployer>());
      expect(
        () => DeployerFactory.getDeployer('unknown'),
        throwsArgumentError,
      );

      final String dockerfile = renderDockerfile(
        appName: 'my_agent',
        port: 8080,
        cmdArgs: const <String>['adk', 'api_server', '/app/agents'],
        hasRequirementsTxt: true,
      );
      expect(dockerfile, contains('EXPOSE 8080'));
      expect(dockerfile, contains('COPY --chown=myuser:myuser "agents/my_agent/"'));
      expect(dockerfile, contains('requirements.txt'));
    });
  });

  group('_telemetry', () {
    test('MetricsCollector records events and extractNextRequestWaitMillis parses wait', () async {
      final Directory tempDir = Directory.systemTemp.createTempSync(
        'adk_telemetry_test_',
      );
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });

      final String customQueue =
          '${tempDir.path}${Platform.pathSeparator}queue.jsonl';
      final String customSessions =
          '${tempDir.path}${Platform.pathSeparator}sessions';
      final MetricsCollector collector = MetricsCollector(
        queueFilePath: customQueue,
        sessionsDirPath: customSessions,
      );
      final Map<String, Object?> event = collector.recordCliCommand(
        commandName: 'web',
        flags: const <String>['--port'],
      );
      expect(event['command_name'], 'web');
      expect(File(customQueue).existsSync(), isTrue);

      expect(
        extractNextRequestWaitMillis('{"next_request_wait_millis": 5000}'),
        5000,
      );

      final bool flushed = await collector.flush(
        transport: (String url, String body) async => const HttpReportResult(
          statusCode: 200,
          body: '{"nextRequestWaitMillis":"100"}',
        ),
      );
      expect(flushed, isTrue);
      expect(File(customQueue).readAsStringSync(), isEmpty);
    });
  });

  group('agent_test_runner and _conformance_test_google_llm', () {
    test('normalizeEvents strips volatile fields and normalizes dynamic IDs', () {
      final List<Map<String, Object?>> normalized = normalizeEvents(
        <Map<String, Object?>>[
          <String, Object?>{
            'id': 'uuid-999',
            'invocation_id': 'inv-abc',
            'author': 'user',
            'timestamp': 123456.78,
            'content': <String, Object?>{
              'role': 'user',
              'parts': <Map<String, Object?>>[
                <String, Object?>{'text': 'Hello'},
              ],
            },
          },
        ],
      );
      expect(normalized.single.containsKey('timestamp'), isFalse);
      expect(normalized.single['id'], 'event_1');
      expect(normalized.single['invocation_id'], 'inv_1');
    });

    test('ConformanceTestGemini replays recorded response on matching request', () async {
      final LlmRequest request = LlmRequest(
        model: 'gemini-2.5-flash',
        contents: <Content>[Content.userText('Hello')],
      );
      final LlmResponse expectedResponse = LlmResponse(
        content: Content.modelText('Hi there!'),
        turnComplete: true,
      );
      final ConformanceRecordings recordings = ConformanceRecordings(
        recordings: <ConformanceRecording>[
          ConformanceRecording(
            userMessageIndex: 0,
            agentName: 'root_agent',
            llmRecording: ConformanceLlmRecording(
              llmRequest: serializeLlmRequest(request),
              llmResponses: <ConformanceJson>[
                serializeLlmResponse(expectedResponse),
              ],
            ),
          ),
        ],
      );
      final ConformanceTestGemini llm = ConformanceTestGemini(
        config: <String, Object?>{
          'recordings': recordings,
          'agent_name': 'root_agent',
          'user_message_index': 0,
        },
      );
      final List<LlmResponse> replayed = await llm
          .generateContent(request)
          .toList();
      expect(replayed, hasLength(1));
      expect(replayed.first.content?.parts.first.text, 'Hi there!');
    });
  });
}
