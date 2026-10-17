import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:adk/adk.dart';
import 'package:adk/src/cli/cli_tools_click.dart' as click_cli;
import 'package:adk/src/cli/plugins/conformance_recordings_plugin.dart';
import 'package:adk/src/cli/plugins/conformance_recordings_schema.dart';
import 'package:adk/src/cli/plugins/conformance_replay_plugin.dart';
import 'package:adk/src/dev/a2a_push_delivery_queue.dart';
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

class _DummySerializable {
  _DummySerializable(this.data);
  final Map<String, Object?> data;
  Map<String, Object?> toJson() => data;
}

void main() {
  group('conformance_recordings_schema.dart', () {
    test('serializes and deserializes all Part types and fields', () {
      final Part fullPart = Part(
        text: 'hello',
        thought: true,
        thoughtSignature: <int>[1, 2, 3],
        functionCall: FunctionCall(
          name: 'get_weather',
          args: <String, dynamic>{'location': 'Seoul'},
          id: 'call_1',
          partialArgs: <Map<String, Object?>>[
            <String, Object?>{'city': 'Seoul'},
          ],
          willContinue: false,
        ),
        functionResponse: FunctionResponse(
          name: 'get_weather',
          response: <String, dynamic>{'temp': 20},
          id: 'resp_1',
        ),
        inlineData: InlineData(
          mimeType: 'image/png',
          data: Uint8List.fromList(<int>[0, 1, 2, 3]),
          displayName: 'sample.png',
        ),
        fileData: FileData(
          fileUri: 'gs://bucket/sample.png',
          mimeType: 'image/png',
          displayName: 'sample.png',
        ),
        executableCode: <String, Object?>{'code': 'print("hello")'},
        codeExecutionResult: <String, Object?>{'outcome': 'ok'},
      );

      final Content content = Content(role: 'user', parts: <Part>[fullPart]);
      final ConformanceJson serializedContent = serializeContent(content);
      final Content deserializedContent = deserializeContent(serializedContent);

      expect(deserializedContent.role, 'user');
      expect(deserializedContent.parts, hasLength(1));
      final Part deserializedPart = deserializedContent.parts.first;
      expect(deserializedPart.text, 'hello');
      expect(deserializedPart.thought, isTrue);
      expect(deserializedPart.thoughtSignature, <int>[1, 2, 3]);
      expect(deserializedPart.functionCall?.name, 'get_weather');
      expect(deserializedPart.functionCall?.id, 'call_1');
      expect(deserializedPart.functionCall?.willContinue, isFalse);
      expect(deserializedPart.functionResponse?.name, 'get_weather');
      expect(deserializedPart.functionResponse?.id, 'resp_1');
      expect(deserializedPart.inlineData?.mimeType, 'image/png');
      expect(deserializedPart.inlineData?.displayName, 'sample.png');
      expect(deserializedPart.fileData?.fileUri, 'gs://bucket/sample.png');
      expect(deserializedPart.executableCode, isNotNull);
      expect(deserializedPart.codeExecutionResult, isNotNull);
    });

    test('serializes and deserializes LlmRequest and LlmResponse completely', () {
      final LlmRequest request = LlmRequest(
        model: 'gemini-2.5-flash',
        contents: <Content>[
          Content(
            role: 'user',
            parts: <Part>[
              Part(
                functionCall: FunctionCall(
                  name: 'lookup',
                  args: <String, dynamic>{'q': 'test'},
                  partialArgs: <Map<String, Object?>>[],
                ),
              ),
            ],
          ),
        ],
        config: GenerateContentConfig(
          maxOutputTokens: 1024,
          stopSequences: <String>['STOP'],
          frequencyPenalty: 0.5,
          presencePenalty: 0.5,
          responseLogprobs: true,
          thinkingConfig: <String, Object?>{'mode': 'fast'},
          responseSchema: <String, Object?>{'type': 'string'},
          responseJsonSchema: <String, Object?>{'schema': 'v1'},
          responseMimeType: 'application/json',
          toolConfig: LlmToolConfig(
            functionCallingConfig: FunctionCallingConfig(
              mode: FunctionCallingConfigMode.any,
              allowedFunctionNames: <String>['lookup'],
            ),
          ),
          cachedContent: 'cached/123',
          httpOptions: HttpOptions(
            retryOptions: HttpRetryOptions(
              attempts: 3,
              initialDelay: 1.0,
              maxDelay: 10.0,
              expBase: 2.0,
              httpStatusCodes: <int>[503],
            ),
            headers: <String, String>{'X-Custom': 'val'},
            apiVersion: 'v1beta',
          ),
          labels: <String, String>{'env': 'test'},
        ),
        liveConnectConfig: LiveConnectConfig(
          responseModalities: <String>['AUDIO'],
          speechConfig: <String, Object?>{'voice': 'Puck'},
          outputAudioTranscription: <String, Object?>{'enabled': true},
          inputAudioTranscription: <String, Object?>{'enabled': true},
          systemInstruction: 'Be helpful.',
          tools: <ToolDeclaration>[
            ToolDeclaration(
              functionDeclarations: <FunctionDeclaration>[
                FunctionDeclaration(
                  name: 'fn1',
                  description: 'desc1',
                  parameters: <String, Object?>{'type': 'object'},
                ),
              ],
              googleSearch: <String, Object?>{'mode': 'auto'},
              googleSearchRetrieval: <String, Object?>{'dynamic_threshold': 0.3},
              urlContext: <String, Object?>{'urls': <String>['https://example.com']},
              codeExecution: <String, Object?>{'sandbox': 'default'},
              googleMaps: <String, Object?>{'enabled': true},
              enterpriseWebSearch: <String, Object?>{'engine': 'ent'},
              retrieval: <String, Object?>{'corpus': 'c1'},
              computerUse: <String, Object?>{'env': 'browser'},
            ),
          ],
          httpOptions: HttpOptions(apiVersion: 'v1'),
          realtimeInputConfig: <String, Object?>{'sample_rate': 16000},
          enableAffectiveDialog: true,
          proactivity: <String, Object?>{'enabled': false},
          sessionResumption: <String, Object?>{'resume': true},
          historyConfig: <String, Object?>{'max_turns': 5},
          contextWindowCompression: <String, Object?>{'enabled': true},
        ),
        cacheConfig: <String, Object?>{'ttl': 300},
        cacheMetadata: <String, Object?>{'cache_id': 'c_1'},
        cacheableContentsTokenCount: 150,
        previousInteractionId: 'prev_int_1',
      );

      final ConformanceJson serializedReq = serializeLlmRequest(request);
      final ConformanceJson canonicalReq = canonicalizeSerializedLlmRequest(serializedReq);
      expect(canonicalReq['contents'], isNotEmpty);
      expect(canonicalReq['config'], isNotEmpty);
      expect(canonicalReq.containsKey('live_connect_config'), isFalse);

      final LlmResponse response = LlmResponse(
        modelVersion: 'gemini-2.5-flash-001',
        content: Content.modelText('response text'),
        partial: false,
        turnComplete: true,
        finishReason: 'STOP',
        errorCode: '0',
        errorMessage: 'none',
        interrupted: false,
        customMetadata: <String, dynamic>{'meta': 'val'},
        usageMetadata: <String, Object?>{'total_tokens': 100},
        inputTranscription: 'hi',
        outputTranscription: 'response text',
        avgLogprobs: -0.123,
        logprobsResult: <String, Object?>{'probs': <double>[0.9]},
        cacheMetadata: <String, Object?>{'cached': true},
        citationMetadata: <String, Object?>{'sources': <String>[]},
        groundingMetadata: <String, Object?>{'web': true},
        interactionId: 'int_123',
      );

      final ConformanceJson serializedResp = serializeLlmResponse(response);
      final LlmResponse deserializedResp = deserializeLlmResponse(serializedResp);
      expect(deserializedResp.modelVersion, 'gemini-2.5-flash-001');
      expect(deserializedResp.content?.parts.first.text, 'response text');
      expect(deserializedResp.partial, isFalse);
      expect(deserializedResp.turnComplete, isTrue);
      expect(deserializedResp.finishReason, 'STOP');
      expect(deserializedResp.avgLogprobs, closeTo(-0.123, 0.001));
      expect(deserializedResp.interactionId, 'int_123');
    });

    test('normalizes complex types and JSON sorting helper', () {
      final Uint8List bytes = Uint8List.fromList(<int>[1, 2, 3]);
      expect(normalizeConformanceJsonValue(bytes), <int>[1, 2, 3]);
      expect(normalizeConformanceJsonValue(<Object>[1, 'two', false]), <Object>[1, 'two', false]);
      expect(normalizeConformanceJsonValue(_DummySerializable(<String, Object?>{'key': 'val'})), <String, Object?>{'key': 'val'});

      expect(asConformanceObjectMap(null), isEmpty);
      expect(asConformanceObjectList(null), isEmpty);
      expect(asConformanceDynamicMap(null), isNull);
      expect(asConformanceIntList('not-a-list'), isNull);
      expect(asConformanceIntList(<Object>['1', 2, 3.5]), <int>[2, 3]);
      expect(asConformanceInt('123'), 123);
      expect(asConformanceInt('not-int'), 0);
      expect(asConformanceNullableDouble('12.34'), 12.34);
      expect(asConformanceNullableDouble(55), 55.0);
      expect(asConformanceNullableDouble('invalid'), isNull);

      final String sig = stableJsonSignature(<String, Object?>{
        'z': 1,
        'a': <Object>[
          <String, Object?>{'y': 2, 'b': 3},
        ],
      });
      expect(sig, contains('"a":'));
      expect(sig, contains('"z":'));
    });
  });

  group('conformance_replay_plugin.dart', () {
    test('error classes toString and verification checks', () {
      final ReplayConfigError cfgErr = ReplayConfigError('cfg error');
      expect(cfgErr.toString(), 'ReplayConfigError: cfg error');

      final ReplayVerificationError verErr = ReplayVerificationError('ver error');
      expect(verErr.toString(), 'ReplayVerificationError: ver error');
    });
  });

  group('cli_deploy.dart', () {
    test('validates service account emails and extra packages', () {
      validateServiceAccountEmail(null);
      validateServiceAccountEmail('user@example.com');
      validateServiceAccountEmail('sa-name@project.iam.gserviceaccount.com');
      expect(() => validateServiceAccountEmail('not-an-email'), throwsArgumentError);

      validateExtraPackages(const <String>[]);
      validateExtraPackages(<String>['my_pkg', 'another_pkg']);

      expect(() => validateExtraPackages(<String>['']), throwsArgumentError);
      expect(() => validateExtraPackages(<String>['../traversal']), throwsArgumentError);
      expect(() => validateExtraPackages(<String>['foo/..']), throwsArgumentError);
      expect(() => validateExtraPackages(<String>['bin']), throwsArgumentError);
      expect(() => validateExtraPackages(<String>['lib']), throwsArgumentError);
      expect(() => validateExtraPackages(<String>['pkg1', 'sub/pkg1']), throwsArgumentError);
    });

    test('parses options and builds commands for all targets', () {
      final DeployCommand cloudRunCmd = DeployCommand(
        service: 'test-service',
        project: 'test-project',
        region: 'us-central1',
        image: 'gcr.io/test-project/test-service:latest',
        serviceAccount: 'sa@test-project.iam.gserviceaccount.com',
        withCloudRunSandbox: true,
        extraArgs: <String>['--cpu=2'],
      );
      final List<String> crArgs = toCloudRun(cloudRunCmd);
      expect(crArgs, contains('beta'));
      expect(crArgs, contains('--execution-environment=gen2'));
      expect(crArgs, contains('--service-account'));
      expect(crArgs, contains('--cpu=2'));

      final DeployCommand dockerCmd = DeployCommand(
        service: 'test-docker',
        project: 'test-project',
        region: 'us-central1',
        image: 'gcr.io/test-project/test-docker:latest',
        port: 9000,
        envVars: <String>['ENV1=val1'],
      );
      final List<String> docArgs = toDocker(dockerCmd);
      expect(docArgs, contains('docker'));
      expect(docArgs, contains('-p'));
      expect(docArgs, contains('9000:9000'));
      expect(docArgs, contains('-e'));
      expect(docArgs, contains('ENV1=val1'));

      final DeployCommand agentEngineCmd = DeployCommand(
        service: 'ae-service',
        project: 'test-project',
        region: 'us-central1',
        image: 'gcr.io/test-project/ae:latest',
        serviceAccount: 'sa@test-project.iam.gserviceaccount.com',
        workerPool: 'projects/p/locations/l/workerPools/wp',
      );
      final List<String> aeArgs = toAgentEngine(agentEngineCmd);
      expect(aeArgs, contains('alpha'));
      expect(aeArgs, contains('reasoning-engines'));
      expect(aeArgs, contains('--worker-pool'));

      final DeployCommand gkeCmd = DeployCommand(
        service: 'gke-service',
        clusterName: 'my-cluster',
        project: 'test-project',
        region: 'us-central1',
        image: 'gcr.io/test-project/gke:latest',
      );
      final List<String> gkeArgs = toGke(gkeCmd);
      expect(gkeArgs, contains('container'));
      expect(gkeArgs, contains('clusters'));
      expect(gkeArgs, contains('my-cluster'));

      final DeployCommand gkeCmdFallback = DeployCommand(
        service: 'gke-service',
        project: 'test-project',
        region: 'us-central1',
        image: 'gcr.io/test-project/gke:latest',
      );
      expect(toGke(gkeCmdFallback), contains('gke-service'));
    });

    test('handles parse errors and flags in parseDeployCliOptions', () {
      expect(
        () => parseDeployCliOptions(
          <String>['--target=unknown'],
          env: <String, String>{'GOOGLE_CLOUD_PROJECT': 'p'},
        ),
        throwsArgumentError,
      );

      expect(
        () => parseDeployCliOptions(
          <String>['--log_level=VERBOSE'],
          env: <String, String>{'GOOGLE_CLOUD_PROJECT': 'p'},
        ),
        throwsArgumentError,
      );

      expect(
        () => parseDeployCliOptions(
          <String>['--service_type=InvalidType'],
          env: <String, String>{'GOOGLE_CLOUD_PROJECT': 'p'},
        ),
        throwsArgumentError,
      );

      expect(
        () => parseDeployCliOptions(
          <String>['--env=NO_EQUALS'],
          env: <String, String>{'GOOGLE_CLOUD_PROJECT': 'p'},
        ),
        throwsArgumentError,
      );

      expect(
        () => parseDeployCliOptions(
          <String>['--env==VALUE_ONLY'],
          env: <String, String>{'GOOGLE_CLOUD_PROJECT': 'p'},
        ),
        throwsArgumentError,
      );

      expect(
        () => parseDeployCliOptions(
          <String>['--port=invalid'],
          env: <String, String>{'GOOGLE_CLOUD_PROJECT': 'p'},
        ),
        throwsArgumentError,
      );

      expect(
        () => parseDeployCliOptions(
          <String>['--port', '70000'],
          env: <String, String>{'GOOGLE_CLOUD_PROJECT': 'p'},
        ),
        throwsArgumentError,
      );

      expect(
        () => parseDeployCliOptions(
          <String>['--service'],
          env: <String, String>{'GOOGLE_CLOUD_PROJECT': 'p'},
        ),
        throwsArgumentError,
      );

      expect(
        () => parseDeployCliOptions(
          <String>['cloud_run'],
          env: <String, String>{},
        ),
        throwsStateError,
      );

      expect(
        () => validateGcloudExtraArgs(<String>['arg\nwith\nnewline']),
        throwsArgumentError,
      );

      expect(
        () => parseDeployCliOptions(
          <String>[
            '--use_local_storage',
            '--session_service_uri=memory://',
          ],
          env: <String, String>{'GOOGLE_CLOUD_PROJECT': 'p'},
        ),
        throwsArgumentError,
      );

      final DeployCliOptions opts = parseDeployCliOptions(
        <String>[
          '--service_name=my_svc',
          '--app-name=my_app',
          '--temp-folder=/tmp/temp',
          '--port=8080',
          '--region=us-west1',
          '--image=my_img',
          '--service_account=sa@p.iam.gserviceaccount.com',
          '--trace_to_cloud',
          '--otel_to_cloud',
          '--with_ui',
          '--adk_version=1.0.0',
          '--log_level=DEBUG',
          '--allow_origins=http://localhost:3000',
          '--a2a',
          '--session_service_uri=memory://',
          '--artifact_service_uri=memory://',
          '--memory_service_uri=memory://',
          '--trigger_sources=pubsub',
          '--trigger_oidc_audience=aud',
          '--trigger_oidc_service_accounts=sa@p.iam.gserviceaccount.com',
          '--with_cloud_run_sandbox',
          '--extra_packages=pkg_a',
          '-a', 'k1=v1',
          '-e', 'ENV_A=1',
          '--api_key=key',
          '--agent_engine_id=ae_id',
          '--display_name=Disp',
          '--description=Desc',
          '--agent_engine_config_file=cfg.json',
          '--worker_pool=wp',
          '--cluster_name=cl',
          '--service_type=LoadBalancer',
          '--dry-run',
        ],
        env: <String, String>{'GOOGLE_CLOUD_PROJECT': 'my-p'},
      );
      expect(opts.service, 'my_svc');
      expect(opts.appName, 'my_app');
      expect(opts.port, 8080);
      expect(opts.region, 'us-west1');
      expect(opts.dryRun, isTrue);
      expect(opts.serviceType, 'LoadBalancer');
    });

    test('runDeployCommand handles help, argument errors, and runner execution', () async {
      final _CapturedSink outHelp = _CapturedSink();
      final _CapturedSink errHelp = _CapturedSink();
      final int cHelp = await runDeployCommand(
        <String>['--help'],
        outSink: outHelp.sink,
        errSink: errHelp.sink,
      );
      expect(cHelp, 0);
      expect(await outHelp.closeAndRead(), contains('Usage: adk deploy'));

      final _CapturedSink outArgErr = _CapturedSink();
      final _CapturedSink errArgErr = _CapturedSink();
      final int cArgErr = await runDeployCommand(
        <String>['--target=unknown'],
        outSink: outArgErr.sink,
        errSink: errArgErr.sink,
        environment: <String, String>{'GOOGLE_CLOUD_PROJECT': 'p'},
      );
      expect(cArgErr, 64);
      expect(await errArgErr.closeAndRead(), contains('Unknown deploy target'));

      final _CapturedSink outStateErr = _CapturedSink();
      final _CapturedSink errStateErr = _CapturedSink();
      final int cStateErr = await runDeployCommand(
        <String>['cloud_run'],
        outSink: outStateErr.sink,
        errSink: errStateErr.sink,
        environment: <String, String>{},
      );
      expect(cStateErr, 1);
      expect(await errStateErr.closeAndRead(), contains('GOOGLE_CLOUD_PROJECT'));
    });
  });

  group('trigger_routes.dart', () {
    test('TransientError and TriggerAuthException toString and constructors', () {
      const TransientError trans = TransientError('network timeout');
      expect(trans.toString(), contains('network timeout'));

      const TriggerAuthException authEx = TriggerAuthException(
        statusCode: HttpStatus.forbidden,
        message: 'access denied',
      );
      expect(authEx.toString(), contains('403'));
      expect(authEx.toString(), contains('access denied'));
    });

    test('PubSubTriggerRequest and PubSubMessage JSON handling and error paths', () {
      final PubSubMessage msg = PubSubMessage(
        data: base64Encode(utf8.encode('test message')),
        attributes: <String, String>{'key': 'val'},
        messageId: 'msg-1',
        publishTime: '2026-01-01T00:00:00Z',
      );
      final Map<String, Object?> json = msg.toJson();
      expect(json['messageId'], 'msg-1');

      final PubSubTriggerRequest req = PubSubTriggerRequest.fromJson(<String, Object?>{
        'message': json,
        'subscription': 'sub-1',
        'userId': 'custom-user',
        'sessionId': 'custom-sess',
      });
      expect(req.userId, 'custom-user');
      expect(req.sessionId, 'custom-sess');

      final PubSubTriggerRequest defaultReq = PubSubTriggerRequest.fromJson(<String, Object?>{
        'message': <String, Object?>{},
      });
      expect(defaultReq.userId, 'pubsub_trigger_user');
      expect(defaultReq.sessionId, isNull);
    });

    test('EventarcTriggerRequest JSON parsing across payload and headers', () {
      final EventarcTriggerRequest req1 = EventarcTriggerRequest.fromJson(
        <String, Object?>{
          'data': <String, Object?>{
            'message': <String, Object?>{
              'data': base64Encode(utf8.encode('inner payload')),
              'attributes': <String, Object?>{'tag': 'urgent'},
            },
          },
          'id': 'evt-1',
          'source': '//source',
          'type': 'google.cloud.event',
          'subject': 'sub',
          'time': '2026-01-01T00:00:00Z',
          'custom_field': 123,
        },
        headers: <String, String>{
          'ce-userid': 'header_user',
          'ce-sessionid': 'header_sess',
        },
      );
      expect(req1.userId, 'header_user');
      expect(req1.sessionId, 'header_sess');
      expect(req1.id, 'evt-1');
      expect(req1.extraFields, contains('custom_field'));

      final EventarcTriggerRequest req2 = EventarcTriggerRequest.fromJson(
        <String, Object?>{},
      );
      expect(req2.userId, 'eventarc_trigger_user');
      expect(req2.sessionId, isNull);
    });

    test('TriggerResponse serialization and router source verification', () {
      final TriggerResponse resp = TriggerResponse(
        sessionId: 's1',
        response: 'agent output',
      );
      final Map<String, Object?> json = resp.toJson();
      expect(json['session_id'], 's1');
      expect(json['response'], 'agent output');
      expect(json['status'], 'success');

      final TriggerRouter router = TriggerRouter(
        getRunnerAsync: (String appName) async => InMemoryRunner(
          agent: LlmAgent(name: 'a', model: 'm'),
        ),
        sessionService: InMemorySessionService(),
        triggerSources: const <String>['pubsub'],
      );
      expect(router.isSourceEnabled('pubsub'), isTrue);
      expect(router.isSourceEnabled('PUBSUB'), isTrue);
      expect(router.isSourceEnabled('eventarc'), isFalse);
    });
  });

  group('service_registry.dart remaining branches', () {
    test('agentengine memory service and short-form kwargs parsing', () {
      final ServiceRegistry registry = getServiceRegistry();
      setCliEnvironmentValue('GOOGLE_CLOUD_PROJECT', 'p-1');
      setCliEnvironmentValue('GOOGLE_CLOUD_LOCATION', 'us-central1');

      final BaseMemoryService? aeMem = registry.createMemoryService(
        'agentengine://projects/p-1/locations/us-central1/reasoningEngines/re-1',
      );
      expect(aeMem, isA<VertexAiMemoryBankService>());

      final Directory tempDir = Directory.systemTemp.createTempSync('adk_service_reg_test_');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      final BaseMemoryService? ragMem = registry.createMemoryService(
        'rag://my-corpus',
        kwargs: <String, Object?>{'agents_dir': tempDir.path},
      );
      expect(ragMem, isA<VertexAiRagMemoryService>());

      expect(
        () => registry.createMemoryService(
          'rag://',
          kwargs: <String, Object?>{'agents_dir': tempDir.path},
        ),
        throwsArgumentError,
      );

      expect(
        () => registry.createMemoryService('agentengine://'),
        throwsArgumentError,
      );

      expect(
        () => registry.createMemoryService('agentengine://invalid/structure'),
        throwsArgumentError,
      );
    });

    test('loads services module from services.yaml', () {
      final Directory tempDir = Directory.systemTemp.createTempSync('adk_services_yaml_');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      final File yamlFile = File('${tempDir.path}${Platform.pathSeparator}services.yaml');
      yamlFile.writeAsStringSync('''
services:
  - uri: "memory://"
  - uri: "file://${tempDir.path}/artifacts"
  - uri: "sqlite://${tempDir.path}/test.db"
  - uri: "invalid_item"
''');

      expect(() => loadServicesModule(tempDir.path), returnsNormally);
      expect(() => loadServicesModule('${tempDir.path}/non_existent'), returnsNormally);
    });
  });

  group('small files gap coverage', () {
    test('agent_graph.dart covers FunctionTool caption and edge highlights', () async {
      final FunctionTool fnTool = FunctionTool(
        name: 'my_fn_tool',
        description: 'desc',
        func: (Map<String, dynamic> args) => 'result',
      );
      final Workflow wf = Workflow(
        name: 'wf_highlight',
        nodes: <BaseNode>[
          ToolNode(tool: fnTool),
        ],
        edges: <Edge>[
          Edge(fromNode: START, toNode: 'my_fn_tool'),
        ],
      );

      final String mermaid = await getAgentGraph(
        wf,
        highlightPairs: <(String, String)>{
          ('wf_highlight:my_fn_tool', 'tool:my_fn_tool'),
        },
      );
      expect(mermaid, contains('🔧 my_fn_tool'));
      expect(mermaid, contains('==>'));
    });

    test('cli_create.dart fallback app name from directory', () async {
      final Directory tempDir = Directory.systemTemp.createTempSync('adk_create_test_');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      final _CapturedSink out = _CapturedSink();
      final int code = await runCreateCommand(
        projectDir: tempDir.path,
        appName: null,
        outSink: out.sink,
      );
      expect(code, 0);
      final String text = await out.closeAndRead();
      expect(text, contains('Agent created'));
    });

    test('cli_eval.dart getDefaultMetricInfo with trajectory metrics', () {
      final List<EvalMetric> defMetrics = getDefaultMetricInfo(addTrajectoryMetrics: false);
      expect(defMetrics, <EvalMetric>[EvalMetric.finalResponseExactMatch]);

      final List<EvalMetric> trajMetrics = getDefaultMetricInfo(addTrajectoryMetrics: true);
      expect(trajMetrics, contains(EvalMetric.finalResponseContains));
    });

    test('cli_tools_click.dart dispatches create subcommand to runAdkCli', () async {
      final _CapturedSink out = _CapturedSink();
      final _CapturedSink err = _CapturedSink();
      final int code = await click_cli.main(
        <String>['create', '--help'],
        outSink: out.sink,
        errSink: err.sink,
      );
      expect(code, 0);
    });

    test('adk_web_server_client.dart error decoding and methods', () async {
      final HttpServer server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((HttpRequest req) async {
        if (req.uri.path == '/run_sse') {
          req.response.headers.contentType = ContentType('text', 'event-stream');
          req.response.write('data: {"error": "sse-failure"}\n\n');
          await req.response.close();
        } else if (req.uri.path.startsWith('/apps/app/users/u/sessions') && req.method == 'POST') {
          req.response.statusCode = 200;
          req.response.write(jsonEncode(<String, Object?>{'id': 's1'}));
          await req.response.close();
        } else if (req.uri.path == '/version') {
          req.response.statusCode = 200;
          req.response.write(jsonEncode(<String, Object?>{}));
          await req.response.close();
        } else if (req.uri.path.startsWith('/apps/app/users/u/sessions/s') && req.method == 'DELETE') {
          req.response.statusCode = 200;
          await req.response.close();
        }
      });
      addTearDown(server.close);

      final AdkWebServerClient client = AdkWebServerClient(
        Uri.parse('http://${server.address.host}:${server.port}'),
      );
      addTearDown(client.close);

      await expectLater(
        client.runAgentSse(appName: 'app', userId: 'u', sessionId: 's'),
        throwsA(isA<StateError>()),
      );

      final Map<String, Object?> sess = await client.createSession(
        appName: 'app',
        userId: 'u',
      );
      expect(sess['id'], isNotNull);

      final Map<String, Object?> ver = await client.getVersionData();
      expect(ver, isEmpty);

      await client.deleteSession(appName: 'app', userId: 'u', sessionId: 's');
    });

    test('conformance_recordings_plugin.dart missing directory error', () {
      final ConformanceRecordingsPlugin plugin = ConformanceRecordingsPlugin();
      final InvocationContext ctx = InvocationContext(
        invocationId: 'inv-1',
        agent: LlmAgent(name: 'a', model: 'm'),
        sessionService: InMemorySessionService(),
        session: Session(id: 's', appName: 'app', userId: 'u'),
      );
      final CallbackContext cbCtx = CallbackContext(ctx);
      cbCtx.state['_adk_recordings_config'] = <String, Object?>{
        'dir': '   ',
        'user_message_index': 0,
      };

      expect(
        plugin.afterModelCallback(
          callbackContext: cbCtx,
          llmResponse: LlmResponse(content: Content.modelText('test')),
        ),
        throwsStateError,
      );
    });

    test('recordings_schema.dart RecordingTurn fromJson with metadata', () {
      final RecordingTurn turn = RecordingTurn.fromJson(<String, Object?>{
        'user_text': 'hello',
        'reply_text': 'world',
        'metadata': <String, Object?>{'turn': 1},
      });
      expect(turn.userText, 'hello');
      expect(turn.metadata['turn'], 1);
    });

    test('agent_loader.dart computer use agent and determine agent language', () {
      final Directory tempDir = Directory.systemTemp.createTempSync('adk_agent_load_');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      final File adkJson = File('${tempDir.path}${Platform.pathSeparator}adk.json');
      adkJson.writeAsStringSync('{"appName": "my_app"}');

      final AgentLoader loader = AgentLoader(
        tempDir.path,
        agentFactories: <String, AgentFactory>{
          'custom_agent': (String name, String dir) => LlmAgent(name: name, model: 'm'),
        },
      );
      expect(loader.loadAgent('custom_agent'), isA<LlmAgent>());

      expect(
        () => loader.loadAgent('unknown_agent'),
        throwsArgumentError,
      );

      final Directory emptyDir = Directory('${tempDir.path}/non_existent');
      final AgentLoader emptyLoader = AgentLoader(emptyDir.path);
      expect(emptyLoader.listAgents(), isEmpty);
    });

    test('dot_adk_folder.dart invalid type argument error', () {
      expect(
        () => dotAdkFolderForAgent(agentsRoot: 12345, appName: 'test'),
        throwsArgumentError,
      );
    });

    test('envs.dart setCliEnvironmentValues and dotenv logging callbacks', () {
      setCliEnvironmentValues(<String, String>{'CUSTOM_A': '1', 'CUSTOM_B': '2'});
      expect(getCliEnvironmentValue('CUSTOM_A'), '1');
      expect(getCliEnvironmentValue('CUSTOM_B'), '2');

      final List<String> logs = <String>[];
      setCliEnvironmentValue(adkDisableLoadDotenvEnvVar, 'true');
      loadDotenvForAgent('agent', '/tmp', log: logs.add);
      expect(logs, isNotEmpty);

      clearCliEnvironmentOverrides();
      final List<String> missingLogs = <String>[];
      loadDotenvForAgent('agent', '/tmp/no_such_agent_parent', log: missingLogs.add);
      expect(missingLogs, isNotEmpty);
    });

    test('graph_serialization.dart serializes agent properties and json safety', () {
      final LlmAgent agent = LlmAgent(
        name: 'test_agent',
        model: 'gemini-2.5-flash',
        includeContents: 'latest',
        outputKey: 'my_output',
      );
      final GraphJson json = serializeAgent(agent);
      expect(json['include_contents'], 'latest');
      expect(json['output_key'], 'my_output');

      final Workflow wf = Workflow(
        name: 'wf_subagent',
        nodes: <BaseNode>[
          node((WorkflowContext _, Object? input) => input, name: 'subnode'),
        ],
      );
      final GraphJson wfJson = serializeAgent(wf);
      expect(wfJson['nodes'], isNotEmpty);
    });

    test('local_storage.dart listSessions on per-app local storage', () async {
      final Directory tempDir = Directory.systemTemp.createTempSync('adk_local_sess_');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      final BaseSessionService service = createLocalSessionService(
        baseDir: tempDir.path,
        perAgent: true,
      );
      final Session sess = await service.createSession(
        appName: 'app1',
        userId: 'u1',
        sessionId: 's1',
      );
      expect(sess.id, 's1');

      final ListSessionsResponse list = await service.listSessions(appName: 'app1');
      expect(list.sessions, hasLength(1));
    });

    test('logs.dart fallback when symlink creation fails and logToTmpFolder default timestamp', () {
      final List<String> logMessages = <String>[];
      tryCreateLatestLogSymlink(
        '/dev/null/cannot_exist',
        'agent',
        '/tmp/file.log',
        echo: logMessages.add,
      );
      expect(logMessages, isNotEmpty);
      expect(logMessages.first, contains('To access latest log'));

      final String path = logToTmpFolder();
      expect(File(path).existsSync(), isTrue);
    });

    test('service_factory.dart error branches and FormatException handling', () {
      expect(redactUriForLog('https://[invalid-ipv6/path'), '<unparseable>');
      expect(isCloudRun(), isA<bool>());
      expect(isKubernetes(), isA<bool>());

      final Directory tempDir = Directory.systemTemp.createTempSync('adk_svc_fact_');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      final BaseSessionService sess = createSessionServiceFromOptions(
        baseDir: tempDir,
        sessionDbKwargs: <String, Object?>{'db_timeout': 30},
      );
      expect(sess, isNotNull);
    });

    test('a2a_push_delivery_queue.dart decoding edge cases', () {
      final Directory tempDir = Directory.systemTemp.createTempSync('adk_a2a_q_');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      final String dbPath = '${tempDir.path}${Platform.pathSeparator}queue.db';
      final A2aPushDeliveryQueue queue = A2aPushDeliveryQueue.open(dbPath: dbPath);
      queue.enqueue(
        appName: 'app',
        taskId: 't',
        targetUrl: 'http://localhost:8080/callback',
        headers: <String, String>{' ': 'val', 'k': ''},
        authHeader: 'Bearer abc',
        task: <String, Object?>{},
        update: <String, Object?>{},
        policy: const A2aPushDeliveryPolicy(),
      );
      final List<A2aPushDeliveryEntry> pending = queue.readDue();
      expect(pending, hasLength(1));
      queue.markFailed(pending.first, error: 'err');
      queue.markDelivered(pending.first.id);
      queue.close();
    });

    test('project.dart copyWith and joinPath with trailing slash', () async {
      const DevProjectConfig cfg = DevProjectConfig(
        appName: 'app',
        agentName: 'agent',
        description: 'desc',
      );
      final DevProjectConfig updated = cfg.copyWith(appName: 'new_app');
      expect(updated.appName, 'new_app');
      expect(updated.agentName, 'agent');

      final Directory tempDir = Directory.systemTemp.createTempSync('adk_join_test_');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      final String pathWithSlash = '${tempDir.path}${Platform.pathSeparator}';
      await createDevProject(projectDirPath: pathWithSlash);
      expect(File('${tempDir.path}${Platform.pathSeparator}adk.json').existsSync(), isTrue);
    });

    test('runtime.dart fallback city and empty prompt handling', () async {
      final DemoTimeModel model = DemoTimeModel();
      final Stream<LlmResponse> emptyStream = model.generateContent(
        LlmRequest(
          contents: <Content>[
            Content(role: 'user', parts: <Part>[Part.text('')]),
          ],
        ),
      );
      final LlmResponse emptyResp = await emptyStream.first;
      expect(emptyResp.content?.parts.first.text, contains('Ask me about time'));

      final Stream<LlmResponse> fallbackStream = model.generateContent(
        LlmRequest(
          contents: <Content>[
            Content(role: 'user', parts: <Part>[Part.text('tell me the current time please')]),
          ],
        ),
      );
      final LlmResponse fallbackResp = await fallbackStream.first;
      expect(fallbackResp.content?.parts.first.functionCall?.name, getCurrentTimeToolName);
    });
  });
}
