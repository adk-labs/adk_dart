import 'dart:convert';
import 'dart:io';

import 'package:adk/adk.dart';
import 'package:test/test.dart';

class _TestTriggerModel extends BaseLlm {
  _TestTriggerModel({this.failTimes = 0}) : super(model: 'test-trigger-model');

  int failTimes;
  int attempts = 0;

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    attempts += 1;
    if (attempts <= failTimes) {
      throw const TransientError('429 RESOURCE_EXHAUSTED');
    }
    final String prompt = request.contents.last.parts
        .map((Part p) => p.text ?? '')
        .join('\n');
    yield LlmResponse(content: Content.modelText('Processed: $prompt'));
  }
}

void main() {
  group('adk CLI entrypoint & AdkCliRunner', () {
    test('AdkCliRunner returns package version', () {
      expect(AdkCliRunner.version, adkPackageVersion);
      expect(adkPackageVersion, isNotEmpty);
      expect(adkSpecVersion, '2.0');
    });

    test('AdkSystemInfo collects environment diagnostics', () {
      final Map<String, dynamic> info = AdkSystemInfo.collect();
      expect(info['adk_package_version'], adkPackageVersion);
      expect(info['dart_version'], isNotEmpty);
      expect(info['operating_system'], isNotEmpty);

      final String summary = AdkSystemInfo.formatSummary();
      expect(summary, contains('ADK Dart CLI Environment Diagnostics:'));
      expect(summary, contains(adkPackageVersion));
    });

    test('AdkCliRunner handles --version flag', () async {
      final int exitCode = await AdkCliRunner.run(<String>['--version']);
      expect(exitCode, 0);
    });

    test('AdkCliRunner handles doctor / diag command', () async {
      final int exitCode = await AdkCliRunner.run(<String>['doctor']);
      expect(exitCode, 0);
    });

    test('AdkCliRunner handles telemetry commands', () async {
      final int statusCode = await AdkCliRunner.run(<String>[
        'telemetry',
        'status',
      ]);
      expect(statusCode, 0);

      final int enableCode = await AdkCliRunner.run(<String>[
        'telemetry',
        'enable',
      ]);
      expect(enableCode, 0);

      final int disableCode = await AdkCliRunner.run(<String>[
        'telemetry',
        'disable',
      ]);
      expect(disableCode, 0);
    });

    test('AdkCliRunner returns exit code for help flag', () async {
      final int exitCode = await AdkCliRunner.run(<String>['--help']);
      expect(exitCode, 0);
    });

    test('AdkCliRunner returns non-zero exit code for unknown command', () async {
      final int exitCode = await AdkCliRunner.run(<String>[
        'unknown_subcommand_test',
      ]);
      expect(exitCode, isNot(0));
    });

    test('parseAdkCliArgs parses --trigger_sources and --state', () {
      final webCmd = parseAdkCliArgs(<String>[
        'web',
        '--trigger_sources=pubsub,eventarc',
        './my_agent',
      ]);
      expect(webCmd.triggerSources, <String>['pubsub', 'eventarc']);

      final runCmd = parseAdkCliArgs(<String>[
        'run',
        '--state={"topic":"weather"}',
        './my_agent',
      ]);
      expect(runCmd.initialState, <String, Object?>{'topic': 'weather'});
    });

    test('TriggerRouter handles Pub/Sub and Eventarc with retry and stateDelta', () async {
      final _TestTriggerModel model = _TestTriggerModel(failTimes: 1);
      final Agent agent = Agent(
        name: 'trigger_agent',
        model: model,
        instruction: 'Handle triggers',
      );
      final InMemorySessionService sessionService = InMemorySessionService();
      final Runner runner = Runner(
        appName: 'trigger_app',
        agent: agent,
        sessionService: sessionService,
      );
      final TriggerRouter router = TriggerRouter(
        getRunnerAsync: (_) async => runner,
        sessionService: sessionService,
        triggerSources: const <String>['pubsub', 'eventarc'],
        baseDelaySeconds: 0.001,
        maxDelaySeconds: 0.005,
      );

      final PubSubTriggerRequest pubsubReq = PubSubTriggerRequest.fromJson(
        <String, Object?>{
          'message': <String, Object?>{
            'data': base64Encode(utf8.encode('Hello PubSub')),
            'messageId': 'msg-123',
            'attributes': <String, String>{'env': 'test'},
          },
          'subscription': 'projects/test/subscriptions/sub-1',
        },
      );
      final TriggerResponse pubsubResp = await router.handlePubSubRequest(
        appName: 'trigger_app',
        triggerRequest: pubsubReq,
      );
      expect(pubsubResp.status, 'success');
      expect(pubsubResp.response, contains('Hello PubSub'));
      expect(model.attempts, 2);

      final Session? savedSession = await sessionService.getSession(
        appName: 'trigger_app',
        userId: 'pubsub_trigger_user',
        sessionId: pubsubResp.sessionId,
      );
      expect(
        savedSession?.state[triggerDeliveryStateKey],
        isA<Map<Object?, Object?>>(),
      );

      final EventarcTriggerRequest eventarcReq =
          EventarcTriggerRequest.fromJson(
            <String, Object?>{
              'data': <String, Object?>{'action': 'created'},
            },
            headers: const <String, String>{
              'ce-id': 'evt-99',
              'ce-type': 'google.cloud.storage.object.v1.finalized',
              'ce-source': '//storage.googleapis.com/projects/_/buckets/b',
            },
          );
      final TriggerResponse eventarcResp = await router.handleEventarcRequest(
        appName: 'trigger_app',
        triggerRequest: eventarcReq,
      );
      expect(eventarcResp.status, 'success');
      expect(eventarcResp.response, contains('created'));
      await runner.close();
    });

    test('buildGraph connects SequentialAgent chain and LoopAgent cycle', () async {
      final Agent step1 = Agent(
        name: 'step1',
        model: _TestTriggerModel(),
        instruction: 'Step 1',
      );
      final Agent step2 = Agent(
        name: 'step2',
        model: _TestTriggerModel(),
        instruction: 'Step 2',
      );
      final SequentialAgent seq = SequentialAgent(
        name: 'seq_root',
        subAgents: <BaseAgent>[step1, step2],
      );
      final AgentGraph seqGraph = await buildGraph(seq);
      expect(
        seqGraph.edges,
        containsAll(<(String, String)>[
          ('seq_root', 'step1'),
          ('step1', 'step2'),
        ]),
      );
      expect(seqGraph.edges, isNot(contains(('seq_root', 'step2'))));

      final Agent loopA = Agent(
        name: 'loop_a',
        model: _TestTriggerModel(),
        instruction: 'Loop A',
      );
      final Agent loopB = Agent(
        name: 'loop_b',
        model: _TestTriggerModel(),
        instruction: 'Loop B',
      );
      final LoopAgent loop = LoopAgent(
        name: 'loop_root',
        subAgents: <BaseAgent>[loopA, loopB],
      );
      final AgentGraph loopGraph = await buildGraph(loop);
      expect(
        loopGraph.edges,
        containsAll(<(String, String)>[
          ('loop_root', 'loop_a'),
          ('loop_a', 'loop_b'),
          ('loop_b', 'loop_a'),
        ]),
      );
    });

    test('startAdkDevWebServer serves /dev/apps and /dev/build_graph routes', () async {
      final DevProjectConfig project = const DevProjectConfig(
        appName: 'my_app',
        agentName: 'assistant',
        description: 'Test project',
        userId: 'user',
      );
      final DevAgentRuntime runtime = DevAgentRuntime(config: project);
      final server = await startAdkDevWebServer(
        runtime: runtime,
        project: project,
        port: 0,
        enableWebUi: false,
        maxLiveSessions: 2,
        maxLiveMessageBytes: 1024,
      );
      try {
        final Uri baseUri = Uri.parse('http://127.0.0.1:${server.port}');
        final HttpClient client = HttpClient();
        try {
          final HttpClientRequest req1 = await client.getUrl(
            baseUri.replace(path: '/dev/apps/my_app/build_graph'),
          );
          final HttpClientResponse res1 = await req1.close();
          expect(res1.statusCode, 200);
          final String body1 = await utf8.decoder.bind(res1).join();
          expect(body1, contains('digraph'));

          final HttpClientRequest req2 = await client.getUrl(
            baseUri.replace(path: '/dev/build_graph/my_app'),
          );
          final HttpClientResponse res2 = await req2.close();
          expect(res2.statusCode, 200);
          final String body2 = await utf8.decoder.bind(res2).join();
          expect(body2, contains('digraph'));
        } finally {
          client.close(force: true);
        }
      } finally {
        await server.close(force: true);
        await runtime.runner.close();
      }
    });
  });
}
