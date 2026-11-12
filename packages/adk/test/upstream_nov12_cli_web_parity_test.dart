import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:adk/adk.dart';
import 'package:test/test.dart';

class _MapAgentLoader extends BaseAgentLoader {
  _MapAgentLoader(this._entries);

  final Map<String, AgentOrApp> _entries;

  @override
  AgentOrApp loadAgent(String agentName) {
    final AgentOrApp? found = _entries[agentName];
    if (found == null) {
      throw ArgumentError('Agent not found: $agentName');
    }
    return found;
  }

  @override
  List<String> listAgents() => _entries.keys.toList(growable: false);
}

class _CapturingCredentialsClient
    implements AuthProviderCredentialsServiceClient {
  _CapturingCredentialsClient({this.onFinalize});

  final FutureOr<void> Function(FinalizeCredentialsRequest request)? onFinalize;
  FinalizeCredentialsRequest? lastRequest;

  @override
  FutureOr<void> finalizeCredentials(FinalizeCredentialsRequest request) async {
    lastRequest = request;
    if (onFinalize != null) {
      await onFinalize!(request);
    }
  }
}

Future<({int statusCode, String body})> _sendRequest({
  required int port,
  required String method,
  required String path,
  Object? jsonBody,
  Map<String, String>? headers,
}) async {
  final HttpClient client = HttpClient();
  try {
    final Uri uri = Uri.parse('http://127.0.0.1:$port$path');
    final HttpClientRequest request = await client.openUrl(method, uri);
    headers?.forEach(request.headers.set);
    if (jsonBody != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(jsonBody));
    }
    final HttpClientResponse response = await request.close();
    final String body = await utf8.decoder.bind(response).join();
    return (statusCode: response.statusCode, body: body);
  } finally {
    client.close(force: true);
  }
}

void main() {
  group('1. Workflow Node Loaders, Test Runner & Dev Graph Parity (f0086e3f4)', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('adk_nov12_node_loader_');
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('asBaseAgent, asRootNodeOrAgent, isComputerUseAgent, replay runner, and AdkDevServer support standalone BaseNode and Workflow', () async {
      final BaseNode standaloneNode = node(
        (WorkflowContext ctx, Object? input) => 'Node reply: $input',
        name: 'echo_fn_node',
        description: 'Standalone function node',
      );
      final BaseNode stepNode = node(
        (WorkflowContext ctx, Object? input) => 'Workflow reply: $input',
        name: 'wf_step',
      );
      final Workflow workflowAgent = Workflow(
        name: 'demo_workflow',
        description: 'Multi-step workflow',
        nodes: <BaseNode>[stepNode],
        edges: <Edge>[Edge(fromNode: START, toNode: stepNode)],
      );

      expect(isStandaloneWorkflowNode(standaloneNode), isTrue);
      expect(isStandaloneWorkflowNode(workflowAgent), isFalse);
      expect(asRootNodeOrAgent(standaloneNode), same(standaloneNode));
      expect(
        AgentLoader(tempDir.path).isComputerUseAgent(standaloneNode),
        isFalse,
      );

      final BaseAgent wrapped = asBaseAgent(standaloneNode);
      expect(wrapped, isA<Workflow>());
      expect(wrapped.name, 'echo_fn_node');

      // Agent test runner: rebuildTests + runAgentReplayTest on standalone BaseNode.
      final File testFile = File('${tempDir.path}/node_case.test.json');
      testFile.writeAsStringSync(
        jsonEncode(<String, Object?>{
          'id': 's_node_replay',
          'app_name': 'node_app',
          'user_id': 'u1',
          'state': <String, Object?>{},
          'events': <Object?>[
            <String, Object?>{
              'author': 'user',
              'content': <String, Object?>{
                'role': 'user',
                'parts': <Object?>[
                  <String, Object?>{'text': 'ping'},
                ],
              },
            },
          ],
        }),
      );

      await rebuildTests(
        agentDir: tempDir.path,
        rootAgent: standaloneNode,
      );
      final List<Map<String, Object?>> replayedEvents =
          await runAgentReplayTest(
            testFile: testFile,
            rootAgent: standaloneNode,
          );
      expect(replayedEvents, isNotEmpty);

      // AdkDevServer with custom BaseAgentLoader serving both standalone BaseNode and Workflow.
      final BaseAgentLoader loader = _MapAgentLoader(<String, AgentOrApp>{
        'node_app': standaloneNode,
        'workflow_app': workflowAgent,
      });
      final AdkDevServer devServer = AdkDevServer(
        agentsDir: tempDir.path,
        agentLoader: loader,
        port: 0,
      );
      final HttpServer server = await devServer.start();
      addTearDown(devServer.stop);

      final ({int statusCode, String body}) listRes = await _sendRequest(
        port: server.port,
        method: 'GET',
        path: '/list-apps',
      );
      expect(listRes.statusCode, HttpStatus.ok);
      expect(
        jsonDecode(listRes.body),
        containsAll(<String>['node_app', 'workflow_app']),
      );

      // Create session & POST /run against standalone FunctionNode.
      final ({int statusCode, String body}) createSessionRes =
          await _sendRequest(
            port: server.port,
            method: 'POST',
            path: '/apps/node_app/users/u1/sessions/s1',
            jsonBody: const <String, Object?>{},
          );
      expect(createSessionRes.statusCode, HttpStatus.ok);

      final ({int statusCode, String body}) runRes = await _sendRequest(
        port: server.port,
        method: 'POST',
        path: '/run',
        jsonBody: <String, Object?>{
          'app_name': 'node_app',
          'user_id': 'u1',
          'session_id': 's1',
          'new_message': <String, Object?>{
            'role': 'user',
            'parts': <Object?>[
              <String, Object?>{'text': 'hello node'},
            ],
          },
        },
      );
      expect(runRes.statusCode, HttpStatus.ok);
      final List<Object?> events = jsonDecode(runRes.body) as List<Object?>;
      expect(events, isNotEmpty);
      expect(runRes.body, contains('Node reply:'));

      // GET /dev/apps/{app}/graph returns {} for both standalone BaseNode and Workflow,
      // while legacy GET /apps/{app}/graph still returns dot_src for Workflow.
      for (final String app in <String>['node_app', 'workflow_app']) {
        final ({int statusCode, String body}) devGraphRes = await _sendRequest(
          port: server.port,
          method: 'GET',
          path: '/dev/apps/$app/graph',
        );
        expect(devGraphRes.statusCode, HttpStatus.ok);
        expect(jsonDecode(devGraphRes.body), equals(const <String, Object?>{}));
      }

      final Map<String, Object?> firstEvent =
          (events.first as Map).cast<String, Object?>();
      final String eventId = '${firstEvent['id']}';
      final ({int statusCode, String body}) devEventGraphRes =
          await _sendRequest(
            port: server.port,
            method: 'GET',
            path: '/dev/apps/node_app/users/u1/sessions/s1/events/$eventId/graph',
          );
      expect(devEventGraphRes.statusCode, HttpStatus.ok);
      expect(
        jsonDecode(devEventGraphRes.body),
        equals(const <String, Object?>{}),
      );

      final ({int statusCode, String body}) legacyWorkflowGraph =
          await _sendRequest(
            port: server.port,
            method: 'GET',
            path: '/apps/workflow_app/graph',
          );
      expect(legacyWorkflowGraph.statusCode, HttpStatus.ok);
      expect(
        (jsonDecode(legacyWorkflowGraph.body) as Map)['dot_src'],
        contains('digraph'),
      );
    });
  });

  group('2. Agent Identity Finalize Endpoint Parity (f0eb6139c)', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('adk_nov12_identity_');
    });

    tearDown(() async {
      authProviderCredentialsClientFactoryTestingOverride = null;
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('POST /agent-identity/finalize rewrites connector resource, decodes unpadded URL-safe Base64, honors target host override, and maps all error statuses', () async {
      String? capturedEndpoint;
      String? capturedTransport;
      late _CapturingCredentialsClient clientImpl;

      authProviderCredentialsClientFactoryTestingOverride = ({
        String? apiEndpoint,
        String transport = 'rest',
        Map<String, String>? environment,
      }) {
        capturedEndpoint = apiEndpoint;
        capturedTransport = transport;
        return clientImpl;
      };

      final AdkApiServer apiServer = AdkApiServer(
        agentsDir: tempDir.path,
        port: 0,
        environment: <String, String>{
          agentIdentityCredentialsTargetHostEnv:
              'staging-agentidentitycredentials.sandbox.googleapis.com',
        },
      );
      final HttpServer server = await apiServer.start();
      addTearDown(apiServer.stop);

      // 1. Success with unpadded URL-safe Base64 ('-_8' -> [0xfb, 0xff]).
      clientImpl = _CapturingCredentialsClient();
      final ({int statusCode, String body}) okRes = await _sendRequest(
        port: server.port,
        method: 'POST',
        path: '/agent-identity/finalize',
        jsonBody: <String, Object?>{
          'connector_name':
              'projects/my-proj/locations/global/connectors/github-conn',
          'user_id': 'user_42',
          'user_id_validation_state': '-_8',
          'consent_nonce': 'nonce_xyz',
        },
      );
      expect(okRes.statusCode, HttpStatus.ok);
      expect(jsonDecode(okRes.body), equals(<String, Object?>{'status': 'ok'}));
      expect(
        capturedEndpoint,
        'staging-agentidentitycredentials.sandbox.googleapis.com',
      );
      expect(capturedTransport, 'rest');
      expect(
        clientImpl.lastRequest?.authProvider,
        'projects/my-proj/locations/global/authProviders/github-conn',
      );
      expect(clientImpl.lastRequest?.userId, 'user_42');
      expect(clientImpl.lastRequest?.consentNonce, 'nonce_xyz');
      expect(
        clientImpl.lastRequest?.userIdValidationState,
        equals(<int>[0xfb, 0xff]),
      );

      // 2. Invalid Base64 validation states -> 400.
      for (final String badB64 in <String>['!!!invalid_base64!!!', 'ab!cd']) {
        final ({int statusCode, String body}) badRes = await _sendRequest(
          port: server.port,
          method: 'POST',
          path: '/agent-identity/finalize',
          jsonBody: <String, Object?>{
            'connector_name': 'projects/p/locations/l/connectors/c',
            'user_id': 'u',
            'user_id_validation_state': badB64,
            'consent_nonce': 'n',
          },
        );
        expect(badRes.statusCode, HttpStatus.badRequest);
        expect(badRes.body, contains('Invalid base64 user_id_validation_state'));
      }

      // 3. Missing dependency -> 500.
      authProviderCredentialsClientFactoryTestingOverride = ({
        String? apiEndpoint,
        String transport = 'rest',
        Map<String, String>? environment,
      }) {
        throw const AgentIdentityMissingDependencyException();
      };
      final ({int statusCode, String body}) missingDepRes = await _sendRequest(
        port: server.port,
        method: 'POST',
        path: '/agent-identity/finalize',
        jsonBody: <String, Object?>{
          'connector_name': 'projects/p/locations/l/connectors/c',
          'user_id': 'u',
          'user_id_validation_state': 'YWJj',
          'consent_nonce': 'n',
        },
      );
      expect(missingDepRes.statusCode, HttpStatus.internalServerError);
      expect(missingDepRes.body, contains('google-adk[agent-identity]'));

      // 4. InvalidArgument -> 400.
      authProviderCredentialsClientFactoryTestingOverride = ({
        String? apiEndpoint,
        String transport = 'rest',
        Map<String, String>? environment,
      }) {
        return _CapturingCredentialsClient(
          onFinalize: (_) => throw const AgentIdentityInvalidArgumentException(
            'Nonce expired',
          ),
        );
      };
      final ({int statusCode, String body}) invalidArgRes = await _sendRequest(
        port: server.port,
        method: 'POST',
        path: '/agent-identity/finalize',
        jsonBody: <String, Object?>{
          'connector_name': 'projects/p/locations/l/connectors/c',
          'user_id': 'u',
          'user_id_validation_state': 'YWJj',
          'consent_nonce': 'n',
        },
      );
      expect(invalidArgRes.statusCode, HttpStatus.badRequest);
      expect(invalidArgRes.body, contains('Nonce expired'));

      // 5. 4xx GoogleAPICallError (403) -> 403; 5xx (503) -> 500.
      authProviderCredentialsClientFactoryTestingOverride = ({
        String? apiEndpoint,
        String transport = 'rest',
        Map<String, String>? environment,
      }) {
        return _CapturingCredentialsClient(
          onFinalize: (_) => throw const AgentIdentityApiException(
            'Caller lacks permission',
            code: 403,
          ),
        );
      };
      final ({int statusCode, String body}) forbiddenRes = await _sendRequest(
        port: server.port,
        method: 'POST',
        path: '/agent-identity/finalize',
        jsonBody: <String, Object?>{
          'connector_name': 'projects/p/locations/l/connectors/c',
          'user_id': 'u',
          'user_id_validation_state': 'YWJj',
          'consent_nonce': 'n',
        },
      );
      expect(forbiddenRes.statusCode, HttpStatus.forbidden);

      authProviderCredentialsClientFactoryTestingOverride = ({
        String? apiEndpoint,
        String transport = 'rest',
        Map<String, String>? environment,
      }) {
        return _CapturingCredentialsClient(
          onFinalize: (_) => throw const AgentIdentityApiException(
            'Backend unavailable',
            code: 503,
          ),
        );
      };
      final ({int statusCode, String body}) unavailableRes = await _sendRequest(
        port: server.port,
        method: 'POST',
        path: '/agent-identity/finalize',
        jsonBody: <String, Object?>{
          'connector_name': 'projects/p/locations/l/connectors/c',
          'user_id': 'u',
          'user_id_validation_state': 'YWJj',
          'consent_nonce': 'n',
        },
      );
      expect(unavailableRes.statusCode, HttpStatus.internalServerError);
    });
  });

  group('3. Disable Server Trace Continuation on Agent Engine (88b3afe70)', () {
    test('GOOGLE_CLOUD_AGENT_ENGINE_ID disables server traceparent continuation so unsampled platform header does not suppress ADK spans', () async {
      final Directory tempDir = await Directory.systemTemp.createTemp(
        'adk_nov12_ae_trace_',
      );
      addTearDown(() async {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });
      final BaseAgentLoader aeLoader = _MapAgentLoader(<String, AgentOrApp>{
        'ae_app': node(
          (WorkflowContext ctx, Object? input) => 'AE reply: $input',
          name: 'ae_node',
        ),
      });

      final Map<String, String> aeEnv = <String, String>{
        googleCloudAgentEngineIdEnv: 'reasoning-engine-12345',
      };
      expect(isServerTracingEnabled(environment: aeEnv), isFalse);
      expect(
        isServerTracingEnabled(environment: const <String, String>{}),
        isTrue,
      );

      final AdkApiServer aeServer = AdkApiServer(
        agentsDir: tempDir.path,
        agentLoader: aeLoader,
        port: 0,
        environment: aeEnv,
      );
      expect(aeServer.telemetryConfig['tracing'], isFalse);

      final AdkDevServer devOnAe = AdkDevServer(
        agentsDir: tempDir.path,
        agentLoader: aeLoader,
        port: 0,
        environment: aeEnv,
      );
      final HttpServer server = await devOnAe.start();
      addTearDown(devOnAe.stop);

      const String platformTraceId = '11111111111111111111111111111111';
      const String platformSpanId = '2222222222222222';
      const String unsampledTraceparent =
          '00-$platformTraceId-$platformSpanId-00';

      await _sendRequest(
        port: server.port,
        method: 'POST',
        path: '/apps/ae_app/users/u1/sessions/s_ae',
        jsonBody: const <String, Object?>{},
      );

      final ({int statusCode, String body}) runRes = await _sendRequest(
        port: server.port,
        method: 'POST',
        path: '/run',
        headers: <String, String>{'traceparent': unsampledTraceparent},
        jsonBody: <String, Object?>{
          'app_name': 'ae_app',
          'user_id': 'u1',
          'session_id': 's_ae',
          'new_message': <String, Object?>{
            'role': 'user',
            'parts': <Object?>[
              <String, Object?>{'text': 'hello'},
            ],
          },
        },
      );
      expect(runRes.statusCode, HttpStatus.ok);

      final ({int statusCode, String body}) traceRes = await _sendRequest(
        port: server.port,
        method: 'GET',
        path: '/debug/trace/session/s_ae',
      );
      expect(traceRes.statusCode, HttpStatus.ok);
      final List<Object?> spans = jsonDecode(traceRes.body) as List<Object?>;
      expect(spans, isNotEmpty);
      final Map<String, Object?> rootSpan =
          (spans.first as Map).cast<String, Object?>();
      expect(rootSpan['trace_id'], isNot(platformTraceId));
      expect(rootSpan['parent_span_id'], isNull);
    });
  });

  group('4. CLI Interactive HITL String Schema Preservation (9e549adf7)', () {
    test('schemaExpectsText and promptForFunctionCall preserve numeric/boolean-looking text for string schemas', () async {
      expect(schemaExpectsText(<String, Object?>{'type': 'string'}), isTrue);
      expect(
        schemaExpectsText(<String, Object?>{
          'anyOf': <Object?>[
            <String, Object?>{'type': 'string'},
            <String, Object?>{'type': 'null'},
          ],
        }),
        isTrue,
      );
      expect(schemaExpectsText(<String, Object?>{'type': 'integer'}), isFalse);
      expect(
        schemaExpectsText(<String, Object?>{
          'anyOf': <Object?>[
            <String, Object?>{'type': 'string'},
            <String, Object?>{'type': 'integer'},
          ],
        }),
        isFalse,
      );
      expect(schemaExpectsText(null), isFalse);

      // Pure string schema preserves "94103", "true", and "null" as String!
      for (final String literal in <String>['94103', 'true', 'null']) {
        final Content responseContent = await promptForFunctionCall(
          functionCallId: 'call_zip',
          functionName: requestInputFunctionCallName,
          args: <String, Object?>{
            'message': 'Enter ZIP code:',
            'response_schema': <String, Object?>{'type': 'string'},
          },
          readLine: (_) async => literal,
        );
        final Part responsePart = responseContent.parts.single;
        expect(
          responsePart.functionResponse!.response['result'],
          equals(literal),
        );
        expect(responsePart.functionResponse!.response['result'], isA<String>());
      }

      // Integer schema JSON-decodes "42" -> int 42.
      final Content intResponseContent = await promptForFunctionCall(
        functionCallId: 'call_age',
        functionName: requestInputFunctionCallName,
        args: <String, Object?>{
          'message': 'Enter age:',
          'response_schema': <String, Object?>{'type': 'integer'},
        },
        readLine: (_) async => '42',
      );
      expect(
        intResponseContent.parts.single.functionResponse!.response['result'],
        equals(42),
      );

      // Tool confirmation prompt converts "yes" / "no" into ToolConfirmation JSON.
      final Content confirmContent = await promptForFunctionCall(
        functionCallId: 'call_confirm',
        functionName: requestConfirmationFunctionCallName,
        args: <String, Object?>{
          'originalFunctionCall': <String, Object?>{'name': 'delete_db'},
          'toolConfirmation': <String, Object?>{'hint': 'Proceed?'},
        },
        readLine: (_) async => 'yes',
      );
      expect(
        confirmContent.parts.single.functionResponse!.response['confirmed'],
        isTrue,
      );
    });
  });

  group('5. Agent Engine Deploy display_name Precedence (319b5a70e)', () {
    test('resolveAgentEngineConfig and toAgentEngine respect display_name from .agent_engine_config.json unless overridden by CLI', () async {
      final Directory agentDir = await Directory.systemTemp.createTemp(
        'my_agent_folder_',
      );
      addTearDown(() async {
        if (agentDir.existsSync()) {
          await agentDir.delete(recursive: true);
        }
      });

      final File configFile = File('${agentDir.path}/.agent_engine_config.json');
      configFile.writeAsStringSync(
        jsonEncode(<String, Object?>{
          'display_name': 'Configured Agent Title',
          'description': 'Configured description',
        }),
      );

      // 1. CLI --display_name omitted -> preserves config file display_name.
      final Map<String, Object?> preserved = resolveAgentEngineConfig(
        agentFolder: agentDir.path,
      );
      expect(preserved['display_name'], 'Configured Agent Title');

      final List<String> gcloudPreserved = toAgentEngine(
        DeployCommand(
          service: 'svc',
          project: 'my-proj',
          region: 'us-central1',
          image: 'gcr.io/my-proj/svc:latest',
          agentFolder: agentDir.path,
        ),
      );
      final int displayIdx1 = gcloudPreserved.indexOf('--display-name');
      expect(displayIdx1, greaterThan(-1));
      expect(gcloudPreserved[displayIdx1 + 1], 'Configured Agent Title');

      // 2. Explicit CLI --display_name overrides config file display_name.
      final Map<String, Object?> overridden = resolveAgentEngineConfig(
        agentFolder: agentDir.path,
        displayName: 'CLI Override Title',
      );
      expect(overridden['display_name'], 'CLI Override Title');

      // 3. Config file has empty/missing display_name -> falls back to folder/app name.
      configFile.writeAsStringSync(jsonEncode(<String, Object?>{'min_instances': 1}));
      final Map<String, Object?> fallback = resolveAgentEngineConfig(
        agentFolder: agentDir.path,
        appName: 'fallback_app_name',
      );
      expect(fallback['display_name'], 'fallback_app_name');

      // 4. Explicit missing --agent_engine_config_file throws FileSystemException.
      expect(
        () => resolveAgentEngineConfig(
          agentFolder: agentDir.path,
          agentEngineConfigFile: '${agentDir.path}/does_not_exist.json',
        ),
        throwsA(isA<FileSystemException>()),
      );
    });
  });

  group('6. adk-web Static Browser Bundle Parity (6528d2f & 969cee9)', () {
    test('bundled index.html and main-TXG3WSWW.js contain app-selector tooltip/wrapping and centered OAuth/Agent-Identity popup features', () {
      final File indexFile = File('lib/src/cli/browser/index.html');
      final File mainJsFile = File('lib/src/cli/browser/main-TXG3WSWW.js');
      expect(indexFile.existsSync(), isTrue);
      expect(mainJsFile.existsSync(), isTrue);

      final String indexHtml = indexFile.readAsStringSync();
      expect(indexHtml, contains('./main-TXG3WSWW.js'));

      final String js = mainJsFile.readAsStringSync();
      // 6528d2f: unavailable app tooltip + multi-line wrapping in app selector.
      expect(js, contains('unavailableAppName()'));
      expect(js, contains('overflow-wrap:anywhere'));
      // 969cee9: centeredPopupFeatures using screenX/screenY and outerWidth/outerHeight.
      expect(js, contains('centeredPopupFeatures'));
      expect(js, contains('screenX'));
      expect(js, contains('outerWidth'));
    });
  });
}
