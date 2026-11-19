import 'dart:convert';
import 'dart:io';

import 'package:adk/adk.dart';
import 'package:test/test.dart';

class _CredentialEchoModel extends BaseLlm {
  _CredentialEchoModel() : super(model: 'fake-cred-model');

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    yield LlmResponse(
      content: Content(
        role: 'model',
        parts: <Part>[
          Part.fromFunctionCall(
            name: 'adk_request_credential',
            id: 'adk-req-cred-id',
            args: <String, dynamic>{
              'functionCallId': 'adk-original-fc-id',
              'authConfig': <String, Object?>{
                'authScheme': <String, Object?>{'type': 'oauth2'},
                'rawAuthCredential': <String, Object?>{
                  'authType': 'oauth2',
                  'oauth2': <String, Object?>{
                    'clientId': 'public-client-id',
                    'clientSecret': 'should-never-reach-the-client',
                    'codeVerifier': 'pkce-verifier-should-not-leak-either',
                  },
                },
              },
            },
          ),
        ],
      ),
    );
  }
}

class _SecretDeltaAgent extends BaseAgent {
  _SecretDeltaAgent({required super.name});

  @override
  Stream<Event> runAsyncImpl(InvocationContext context) async* {
    yield Event(
      invocationId: context.invocationId,
      author: name,
      content: Content(
        role: 'model',
        parts: <Part>[
          Part.fromFunctionCall(
            name: 'adk_request_credential',
            id: 'adk-req-cred-id',
            args: <String, dynamic>{
              'functionCallId': 'adk-original-fc-id',
              'authConfig': <String, Object?>{
                'rawAuthCredential': <String, Object?>{
                  'authType': 'oauth2',
                  'oauth2': <String, Object?>{
                    'clientId': 'public-client-id',
                    'clientSecret': 'should-never-reach-the-client',
                    'codeVerifier': 'pkce-verifier-should-not-leak-either',
                  },
                },
              },
            },
          ),
        ],
      ),
      actions: EventActions(
        stateDelta: <String, Object?>{
          'temp:my_tool:oauth2:abcd1234': <String, Object?>{
            'authType': 'oauth2',
            'oauth2': <String, Object?>{
              'clientId': 'public-client-id',
              'accessToken': 'access-token-should-not-be-logged',
              'refreshToken': 'refresh-token-should-not-be-logged',
            },
          },
        },
      ),
    );
  }
}

class _MapLoader extends BaseAgentLoader {
  _MapLoader(this._agents);

  final Map<String, AgentOrApp> _agents;

  @override
  List<String> listAgents() => _agents.keys.toList(growable: false)..sort();

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
      throw ArgumentError('Agent not found: $agentName');
    }
    return found;
  }
}

void main() {
  tearDown(() {
    isLocalAgentBuilderClientTestingOverride = null;
    runDebugLogTestingOverride = null;
  });

  group('adk-web v1.0.8 bundle sync', () {
    test('browser directory contains v1.0.8 main bundle with no stale main-*.js', () async {
      final Directory browserDir = Directory('lib/src/cli/browser');
      expect(browserDir.existsSync(), isTrue);

      final File indexFile = File('${browserDir.path}/index.html');
      expect(indexFile.existsSync(), isTrue);
      final String indexHtml = indexFile.readAsStringSync();
      expect(indexHtml, contains('main-PJ4DBNMP.js'));

      final List<String> mainBundles = browserDir
          .listSync()
          .whereType<File>()
          .map((File f) => f.uri.pathSegments.last)
          .where((String name) => name.startsWith('main-') && name.endsWith('.js'))
          .toList(growable: false);
      expect(mainBundles, <String>['main-PJ4DBNMP.js']);

      final Directory tempDir = await Directory.systemTemp.createTemp(
        'adk_nov19_web_bundle_',
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

      final HttpClientRequest idxReq = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/dev-ui/'),
      );
      final HttpClientResponse idxRes = await idxReq.close();
      final String idxBody = await utf8.decoder.bind(idxRes).join();
      expect(idxRes.statusCode, HttpStatus.ok);
      expect(idxBody, contains('main-PJ4DBNMP.js'));

      final HttpClientRequest jsReq = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/dev-ui/main-PJ4DBNMP.js'),
      );
      final HttpClientResponse jsRes = await jsReq.close();
      await jsRes.drain<void>();
      expect(jsRes.statusCode, HttpStatus.ok);
    });
  });

  group('c890aa317 & e2a21ac23 - remove builder routes and built-in __ agents', () {
    test('AgentLoader, NestedAgentLoader, and local storage reject __ reserved names', () async {
      final Directory tempDir = await Directory.systemTemp.createTemp(
        'adk_nov19_reserved_',
      );
      addTearDown(() => tempDir.delete(recursive: true));

      final AgentLoader loader = AgentLoader(tempDir.path);
      expect(
        () => loader.loadAgent('__adk_agent_builder_assistant'),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError e) => '${e.message}',
            'message',
            contains('reserved'),
          ),
        ),
      );

      final NestedAgentLoader nestedLoader = NestedAgentLoader(tempDir.path);
      expect(
        () => nestedLoader.loadAgent('__adk_agent_builder_assistant'),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError e) => '${e.message}',
            'message',
            contains('reserved'),
          ),
        ),
      );

      final PerAgentDatabaseSessionService sessionService =
          PerAgentDatabaseSessionService(agentsRoot: tempDir.path);
      await expectLater(
        sessionService.createSession(
          appName: '__adk_agent_builder_assistant',
          userId: 'u1',
        ),
        throwsArgumentError,
      );
      expect(Directory('${tempDir.path}/.adk').existsSync(), isFalse);

      final PerAgentFileArtifactService artifactService =
          PerAgentFileArtifactService(agentsRoot: tempDir.path);
      await expectLater(
        artifactService.saveArtifact(
          appName: '__adk_agent_builder_assistant',
          userId: 'u1',
          filename: 'note.txt',
          artifact: Part.text('hello'),
        ),
        throwsArgumentError,
      );
      expect(Directory('${tempDir.path}/.adk').existsSync(), isFalse);
    });

    test('API/Dev server returns 404 for __ apps and removed builder routes', () async {
      final Directory tempDir = await Directory.systemTemp.createTemp(
        'adk_nov19_404_',
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

      final HttpClientRequest specialInfoReq = await client.getUrl(
        Uri.parse(
          'http://127.0.0.1:${server.port}/apps/__adk_agent_builder_assistant/app-info',
        ),
      );
      final HttpClientResponse specialInfoRes = await specialInfoReq.close();
      await specialInfoRes.drain<void>();
      expect(specialInfoRes.statusCode, HttpStatus.notFound);

      final HttpClientRequest builderReq = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/dev/apps/my_app/builder'),
      );
      final HttpClientResponse builderRes = await builderReq.close();
      await builderRes.drain<void>();
      expect(builderRes.statusCode, HttpStatus.notFound);
    });
  });

  group('3e6c5868f - require local client for POST /config/telemetry', () {
    test('rejects remote clients with 403 unless ADK_ALLOW_REMOTE_AGENT_BUILDER=1', () async {
      final Directory tempDir = await Directory.systemTemp.createTemp(
        'adk_nov19_telemetry_',
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

      // 1. Proxied remote client with X-Forwarded-For -> 403 even with CSRF header.
      final HttpClientRequest forwardedReq = await client.postUrl(
        Uri.parse('http://127.0.0.1:${server.port}/config/telemetry'),
      );
      forwardedReq.headers.contentType = ContentType.json;
      forwardedReq.headers.set('x-adk-telemetry-request', 'true');
      forwardedReq.headers.set('x-forwarded-for', '203.0.113.10');
      forwardedReq.write(jsonEncode(<String, Object?>{'telemetry': false}));
      final HttpClientResponse forwardedRes = await forwardedReq.close();
      await forwardedRes.drain<void>();
      expect(forwardedRes.statusCode, HttpStatus.forbidden);

      // 2. Non-loopback client -> 403.
      isLocalAgentBuilderClientTestingOverride = (_) => false;
      final HttpClientRequest remoteReq = await client.postUrl(
        Uri.parse('http://127.0.0.1:${server.port}/config/telemetry'),
      );
      remoteReq.headers.contentType = ContentType.json;
      remoteReq.headers.set('x-adk-telemetry-request', 'true');
      remoteReq.write(jsonEncode(<String, Object?>{'telemetry': false}));
      final HttpClientResponse remoteRes = await remoteReq.close();
      await remoteRes.drain<void>();
      expect(remoteRes.statusCode, HttpStatus.forbidden);

      // 3. Opt-in via ADK_ALLOW_REMOTE_AGENT_BUILDER=1 permits remote write.
      final AdkDevServer optInServer = AdkDevServer(
        agentsDir: tempDir.path,
        environment: const <String, String>{
          'ADK_ALLOW_REMOTE_AGENT_BUILDER': '1',
        },
        port: 0,
      );
      final HttpServer optInHttp = await optInServer.start();
      addTearDown(optInServer.stop);

      final HttpClientRequest allowedReq = await client.postUrl(
        Uri.parse('http://127.0.0.1:${optInHttp.port}/config/telemetry'),
      );
      allowedReq.headers.contentType = ContentType.json;
      allowedReq.headers.set('x-adk-telemetry-request', 'true');
      allowedReq.write(jsonEncode(<String, Object?>{'telemetry': false}));
      final HttpClientResponse allowedRes = await allowedReq.close();
      final String allowedBody = await utf8.decoder.bind(allowedRes).join();
      expect(allowedRes.statusCode, HttpStatus.ok);
      expect(jsonDecode(allowedBody), <String, Object?>{'telemetry': false});
    });
  });

  group('ba774bcc3 - /run redacts credential secrets in response and debug log', () {
    test('redacts oauth2 secrets from both /run response and debug log', () async {
      final Directory tempDir = await Directory.systemTemp.createTemp(
        'adk_nov19_redact_',
      );
      addTearDown(() => tempDir.delete(recursive: true));

      final _SecretDeltaAgent secretAgent = _SecretDeltaAgent(
        name: 'secret_agent',
      );
      final AdkDevServer devServer = AdkDevServer(
        agentsDir: tempDir.path,
        agentLoader: _MapLoader(<String, AgentOrApp>{'sec_app': secretAgent}),
        autoCreateSession: true,
        port: 0,
      );
      final HttpServer server = await devServer.start();
      addTearDown(devServer.stop);

      final List<String> capturedLogs = <String>[];
      runDebugLogTestingOverride = capturedLogs.add;

      final HttpClient client = HttpClient();
      addTearDown(() => client.close(force: true));

      final HttpClientRequest req = await client.postUrl(
        Uri.parse('http://127.0.0.1:${server.port}/run'),
      );
      req.headers.contentType = ContentType.json;
      req.write(
        jsonEncode(<String, Object?>{
          'app_name': 'sec_app',
          'user_id': 'u1',
          'session_id': 's1',
          'new_message': <String, Object?>{
            'role': 'user',
            'parts': <Object?>[
              <String, Object?>{'text': 'hello'},
            ],
          },
        }),
      );
      final HttpClientResponse res = await req.close();
      final String body = await utf8.decoder.bind(res).join();
      expect(res.statusCode, HttpStatus.ok);

      final String combinedLogs = capturedLogs.join('\n');
      expect(combinedLogs, contains('Events generated:'));

      const List<String> secrets = <String>[
        'access-token-should-not-be-logged',
        'refresh-token-should-not-be-logged',
        'should-never-reach-the-client',
        'pkce-verifier-should-not-leak-either',
      ];
      for (final String secret in secrets) {
        expect(body, isNot(contains(secret)));
        expect(combinedLogs, isNot(contains(secret)));
      }
      expect(body, contains('public-client-id'));
    });
  });

  group('ec2ac7c5e - non-LLM root nodes in /apps/{app}/app-info', () {
    test('returns AppInfo with reachable LlmAgents for SequentialAgent root', () async {
      final Directory tempDir = await Directory.systemTemp.createTemp(
        'adk_nov19_app_info_',
      );
      addTearDown(() => tempDir.delete(recursive: true));

      final LlmAgent workerA = LlmAgent(
        name: 'worker_a',
        model: _CredentialEchoModel(),
        instruction: 'Worker A instruction',
      );
      final LlmAgent workerB = LlmAgent(
        name: 'worker_b',
        model: _CredentialEchoModel(),
        instruction: 'Worker B instruction',
      );
      final SequentialAgent rootSeq = SequentialAgent(
        name: 'root_pipeline',
        description: 'Top-level sequential pipeline',
        subAgents: <BaseAgent>[workerA, workerB],
      );

      final AdkDevServer devServer = AdkDevServer(
        agentsDir: tempDir.path,
        agentLoader: _MapLoader(<String, AgentOrApp>{'seq_app': rootSeq}),
        port: 0,
      );
      final HttpServer server = await devServer.start();
      addTearDown(devServer.stop);

      final HttpClient client = HttpClient();
      addTearDown(() => client.close(force: true));

      final HttpClientRequest req = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/apps/seq_app/app-info'),
      );
      final HttpClientResponse res = await req.close();
      final Map<String, dynamic> payload =
          jsonDecode(await utf8.decoder.bind(res).join())
              as Map<String, dynamic>;

      expect(res.statusCode, HttpStatus.ok);
      expect(payload['name'], 'seq_app');
      expect(payload['rootAgentName'], 'root_pipeline');
      expect(payload['description'], 'Top-level sequential pipeline');
      final Map<String, dynamic> agents =
          payload['agents'] as Map<String, dynamic>;
      expect(agents.containsKey('root_pipeline'), isFalse);
      expect(agents.keys, containsAll(<String>['worker_a', 'worker_b']));
    });

    test('flattens subAgents through non-LLM containers under an LlmAgent root', () async {
      final Directory tempDir = await Directory.systemTemp.createTemp(
        'adk_nov19_flatten_',
      );
      addTearDown(() => tempDir.delete(recursive: true));

      final LlmAgent leaf = LlmAgent(
        name: 'leaf_llm',
        model: _CredentialEchoModel(),
        instruction: 'Leaf',
      );
      final SequentialAgent middle = SequentialAgent(
        name: 'middle_seq',
        subAgents: <BaseAgent>[leaf],
      );
      final LlmAgent root = LlmAgent(
        name: 'root_llm',
        model: _CredentialEchoModel(),
        instruction: 'Root',
        subAgents: <BaseAgent>[middle],
      );

      final AdkDevServer devServer = AdkDevServer(
        agentsDir: tempDir.path,
        agentLoader: _MapLoader(<String, AgentOrApp>{'flat_app': root}),
        port: 0,
      );
      final HttpServer server = await devServer.start();
      addTearDown(devServer.stop);

      final HttpClient client = HttpClient();
      addTearDown(() => client.close(force: true));

      final HttpClientRequest req = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/apps/flat_app/app-info'),
      );
      final HttpClientResponse res = await req.close();
      final Map<String, dynamic> payload =
          jsonDecode(await utf8.decoder.bind(res).join())
              as Map<String, dynamic>;

      expect(res.statusCode, HttpStatus.ok);
      final Map<String, dynamic> agents =
          payload['agents'] as Map<String, dynamic>;
      expect(agents.keys, containsAll(<String>['root_llm', 'leaf_llm']));
      expect(
        (agents['root_llm'] as Map<String, dynamic>)['subAgents'],
        <String>['leaf_llm'],
      );
    });
  });

  group('b64b540c1 - cross-run criterion eval set mean formatting', () {
    test('formats full, singular, partial, and n/a criterion summaries', () {
      expect(
        formatEvalSetCriterionSummary(
          const CrossRunCriterionSummary(
            name: 'pass_rate',
            mean: 0.75,
            numCasesWithValue: 2,
            numCases: 2,
          ),
        ),
        'pass_rate: 0.75 (mean over 2 cases)',
      );
      expect(
        formatEvalSetCriterionSummary(
          const CrossRunCriterionSummary(
            name: 'pass@4',
            mean: 1.0,
            numCasesWithValue: 1,
            numCases: 1,
          ),
        ),
        'pass@4: 1.00 (mean over 1 case)',
      );
      expect(
        formatEvalSetCriterionSummary(
          const CrossRunCriterionSummary(
            name: 'pass^3',
            mean: 0.41,
            numCasesWithValue: 11,
            numCases: 12,
          ),
        ),
        'pass^3: 0.41 (mean over 11 of 12 cases)',
      );
      expect(
        formatEvalSetCriterionSummary(
          const CrossRunCriterionSummary(
            name: 'pass^3',
            mean: null,
            numCasesWithValue: 0,
            numCases: 2,
          ),
        ),
        'pass^3: n/a (no case had a value)',
      );
    });
  });

  group('1ade0ba68, 5e91ab0a5, c16dac705, 7d2c7b75d - deployer & Dockerfile parity', () {
    test('1ade0ba68: emits each --allow_origins value as its own server argument', () {
      final DockerDeployer deployer = DockerDeployer();
      final List<String> fromList = deployer.getCliEnvArgs(
        allowOrigins: const <String>[
          'https://a.example',
          'https://b.example',
        ],
      );
      expect(
        fromList.where((String a) => a.startsWith('--allow_origins=')),
        <String>[
          '--allow_origins=https://a.example',
          '--allow_origins=https://b.example',
        ],
      );

      final List<String> fromCsv = deployer.getCliEnvArgs(
        origins: 'https://a.example, https://b.example',
      );
      expect(
        fromCsv.where((String a) => a.startsWith('--allow_origins=')),
        <String>[
          '--allow_origins=https://a.example',
          '--allow_origins=https://b.example',
        ],
      );
    });

    test('c16dac705: only pip-installs extra_packages folders that declare a project', () async {
      final Directory tempDir = await Directory.systemTemp.createTemp(
        'adk_nov19_extra_pkgs_',
      );
      addTearDown(() => tempDir.delete(recursive: true));

      final Directory projectDir = Directory('${tempDir.path}/real_pkg')
        ..createSync();
      File('${projectDir.path}/pyproject.toml').writeAsStringSync(
        '[project]\nname = "real_pkg"\nversion = "0.1.0"\n',
      );

      final Directory buildSystemDir = Directory('${tempDir.path}/build_pkg')
        ..createSync();
      File('${buildSystemDir.path}/pyproject.toml').writeAsStringSync(
        '[build-system]\nrequires = ["setuptools"]\n',
      );

      final Directory setupPyDir = Directory('${tempDir.path}/setup_pkg')
        ..createSync();
      File('${setupPyDir.path}/setup.py').writeAsStringSync('from setuptools import setup\n');

      final Directory toolOnlyDir = Directory('${tempDir.path}/tool_only_pkg')
        ..createSync();
      File('${toolOnlyDir.path}/pyproject.toml').writeAsStringSync(
        '[tool.ruff]\nline-length = 80\n',
      );

      final Directory malformedDir = Directory('${tempDir.path}/bad_toml_pkg')
        ..createSync();
      File('${malformedDir.path}/pyproject.toml').writeAsStringSync(
        '[project\nbroken = true\n',
      );

      final Directory initPyDir = Directory('${tempDir.path}/has_init_pkg')
        ..createSync();
      File('${initPyDir.path}/pyproject.toml').writeAsStringSync(
        '[project]\nname = "has_init_pkg"\n',
      );
      File('${initPyDir.path}/__init__.py').writeAsStringSync('');

      final File wheelFile = File('${tempDir.path}/my_lib-1.0.0-py3-none-any.whl')
        ..writeAsStringSync('fake wheel');

      expect(isInstallableExtraPackage(projectDir.path), isTrue);
      expect(isInstallableExtraPackage(buildSystemDir.path), isTrue);
      expect(isInstallableExtraPackage(setupPyDir.path), isTrue);
      expect(isInstallableExtraPackage(toolOnlyDir.path), isFalse);
      expect(isInstallableExtraPackage(malformedDir.path), isFalse);
      expect(isInstallableExtraPackage(initPyDir.path), isFalse);
      expect(isInstallableExtraPackage(wheelFile.path), isTrue);
    });

    test('5e91ab0a5: places extra_packages before requirements and force-reinstalls after', () async {
      final Directory tempDir = await Directory.systemTemp.createTemp(
        'adk_nov19_dockerfile_order_',
      );
      addTearDown(() => tempDir.delete(recursive: true));

      final Directory agentDir = Directory('${tempDir.path}/my_agent')
        ..createSync();
      File('${agentDir.path}/requirements.txt').writeAsStringSync('requests\n');
      final File wheelFile = File('${tempDir.path}/patched-1.0.0-py3-none-any.whl')
        ..writeAsStringSync('wheel');
      final Directory stagingDir = Directory('${tempDir.path}/staging')
        ..createSync();

      final DockerDeployer deployer = DockerDeployer();
      await deployer.deploy(
        agentFolder: agentDir.path,
        appName: 'my_agent',
        tempFolder: stagingDir.path,
        extraPackages: <String>[wheelFile.path],
        allowOrigins: const <String>['https://one.example', 'https://two.example'],
        validateAgentImport: true,
        buildImage: false,
      );

      final String dockerfile = File(
        '${stagingDir.path}/Dockerfile',
      ).readAsStringSync();

      final int extraInstallIdx = dockerfile.indexOf(
        'RUN pip install --no-cache-dir "/tmp/extra_packages/patched-1.0.0-py3-none-any.whl"',
      );
      final int reqsInstallIdx = dockerfile.indexOf(
        'RUN pip install --no-cache-dir -r "/app/agents/my_agent/requirements.txt"',
      );
      final int reinstallIdx = dockerfile.indexOf(
        'RUN ["pip","install","--force-reinstall","--no-deps","/tmp/extra_packages/patched-1.0.0-py3-none-any.whl"]',
      );

      expect(extraInstallIdx, greaterThan(-1));
      expect(reqsInstallIdx, greaterThan(extraInstallIdx));
      expect(reinstallIdx, greaterThan(reqsInstallIdx));

      // 1ade0ba68: separate --allow_origins entries
      expect(dockerfile, contains('"--allow_origins=https://one.example"'));
      expect(dockerfile, contains('"--allow_origins=https://two.example"'));

      // 7d2c7b75d: startup agent import validation wrapper in CMD
      expect(dockerfile, contains('CMD ["python","-c",'));
      expect(dockerfile, contains(r'loader.load_agent(\"my_agent\")'));
    });

    test('7d2c7b75d: shouldValidateAgentImportOnStartup gates on version >= 2.0.0 and skip flag', () {
      expect(
        shouldValidateAgentImportOnStartup(
          skipAgentImportValidation: false,
          adkVersion: '2.0.0',
        ),
        isTrue,
      );
      expect(
        shouldValidateAgentImportOnStartup(
          skipAgentImportValidation: false,
          adkVersion: '2.3.1',
        ),
        isTrue,
      );
      expect(
        shouldValidateAgentImportOnStartup(
          skipAgentImportValidation: false,
          adkVersion: '1.21.0',
        ),
        isFalse,
      );
      expect(
        shouldValidateAgentImportOnStartup(
          skipAgentImportValidation: true,
          adkVersion: '2.0.0',
        ),
        isFalse,
      );
    });

    test('7d2c7b75d & 5e91ab0a5: parseDeployCliOptions wires validateAgentImport default=true and dockerfile strips dev_server.py after reinstall', () {
      final DeployCliOptions defaultOpts = parseDeployCliOptions(
        const <String>['cloud_run', '--project', 'my-proj'],
      );
      expect(defaultOpts.validateAgentImport, isTrue);

      final DeployCliOptions disabledOpts = parseDeployCliOptions(
        const <String>[
          'cloud_run',
          '--project',
          'my-proj',
          '--no-validate-agent-import',
        ],
      );
      expect(disabledOpts.validateAgentImport, isFalse);

      final DeployCliOptions skippedOpts = parseDeployCliOptions(
        const <String>[
          'cloud_run',
          '--project',
          'my-proj',
          '--skip-agent-import-validation',
        ],
      );
      expect(skippedOpts.validateAgentImport, isFalse);

      expect(
        () => parseDeployCliOptions(
          const <String>[
            'cloud_run',
            '--project',
            'my-proj',
            '--validate-agent-import',
            '--skip-agent-import-validation',
          ],
        ),
        throwsArgumentError,
      );

      final int reinstallIdx = dockerfileTemplate.indexOf(
        '{reinstall_extra_packages}',
      );
      final int devServerRemoveIdx = dockerfileTemplate.indexOf('dev_server*');
      expect(reinstallIdx, greaterThanOrEqualTo(0));
      expect(devServerRemoveIdx, greaterThan(reinstallIdx));
    });
  });
}
