import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:adk/adk.dart';
import 'package:test/test.dart';

class _CaptureSink {
  _CaptureSink() : _controller = StreamController<List<int>>() {
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

class _HangingLiveAgent extends BaseAgent {
  _HangingLiveAgent({required super.name});
  final Completer<void> gate = Completer<void>();

  @override
  Stream<Event> runAsyncImpl(InvocationContext context) async* {}

  @override
  Stream<Event> runLiveImpl(InvocationContext context) async* {
    yield Event(
      invocationId: context.invocationId,
      author: name,
      content: Content.modelText('live ready'),
    );
    await gate.future;
  }
}

void main() {
  group('Part 5 Coverage: service_factory, agent_loader & cli_deploy gaps', () {
    test('service_factory: FileSystemException fallback in createArtifactServiceFromOptions', () {
      final Directory tempDir = Directory.systemTemp.createTempSync('svc_fac_test_');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      // Create a regular file where .adk folder would be created, causing FileSystemException on createSync
      File('${tempDir.path}${Platform.pathSeparator}.adk').writeAsStringSync('blocker');

      final BaseArtifactService service = createArtifactServiceFromOptions(
        baseDir: tempDir.path,
        useLocalStorage: true,
      );
      expect(service, isA<InMemoryArtifactService>());
    });

    test('agent_loader: _determineAgentLanguage throws StateError for unknown agent structure', () {
      final Directory tempDir = Directory.systemTemp.createTempSync('agent_loader_test_');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      // Create a subfolder with no agent.dart, adk.json, or root_agent.yaml
      final Directory emptyAgentDir = Directory('${tempDir.path}${Platform.pathSeparator}mystery_agent')
        ..createSync();
      File('${emptyAgentDir.path}${Platform.pathSeparator}some_other_file.txt').writeAsStringSync('hello');

      final AgentLoader loader = AgentLoader(
        tempDir.path,
        agentFactories: <String, AgentFactory>{
          'mystery_agent': (String name, String base) {
            return LlmAgent(name: name, model: 'test-model');
          },
        },
      );

      // listAgentsDetailed() encounters mystery_agent, loads via factory, but _determineAgentLanguage throws StateError
      // which is caught and skipped.
      final List<Map<String, Object?>> detailed = loader.listAgentsDetailed();
      expect(detailed.where((m) => m['name'] == 'mystery_agent'), isEmpty);
    });

    test('cli_deploy: remaining flag parsing & validation branches', () async {
      // 1. Separate flag args: --session_service_uri, --artifact_service_uri, --memory_service_uri
      final _CaptureSink errSink1 = _CaptureSink();
      final int code1 = await runDeployCommand(
        <String>[
          '--session_service_uri',
          'sqlite://test.db',
          '--artifact_service_uri',
          'file:///tmp/art',
          '--memory_service_uri',
          'file:///tmp/mem',
          '--staging_bucket=test-bucket',
          '--adk_app=app-obj',
          '--adk_app_object=obj',
          '--env_file=.env.test',
          '--requirements_file=req.txt',
          '--project=my-test-proj',
        ],
        errSink: errSink1.sink,
        commandRunner: (List<String> command, {required IOSink out, required IOSink err, required Map<String, String> environment}) async {
          return 0;
        },
      );
      final String errText1 = await errSink1.closeAndRead();
      expect(code1, 0);
      expect(errText1, contains('staging_bucket'));

      // 2. Positional non-target consumed before target (triggers on ArgumentError)
      final int code2 = await runDeployCommand(
        <String>[
          'my_agent_dir',
          'cloud_run',
          '--project=my-test-proj',
        ],
        commandRunner: (List<String> command, {required IOSink out, required IOSink err, required Map<String, String> environment}) async {
          return 0;
        },
      );
      expect(code2, 0);

      // 3. explicitUseLocalStorage with artifactServiceUri throws ArgumentError -> returns 64
      final _CaptureSink errSink3 = _CaptureSink();
      final int code3 = await runDeployCommand(
        <String>[
          '--use_local_storage',
          '--artifact_service_uri=file:///tmp/art',
          '--project=my-test-proj',
        ],
        errSink: errSink3.sink,
      );
      final String errText3 = await errSink3.closeAndRead();
      expect(code3, 64);
      expect(errText3, contains('Cannot specify both --use_local_storage'));

      // 4. agentEngine target with apiKey and empty project falls back to GOOGLE_CLOUD_PROJECT
      final int code4 = await runDeployCommand(
        <String>[
          'agent_engine',
          '--api_key=secret-key',
        ],
        environment: <String, String>{'GOOGLE_CLOUD_PROJECT': 'my-env-project'},
        commandRunner: (List<String> command, {required IOSink out, required IOSink err, required Map<String, String> environment}) async {
          expect(command, contains('my-env-project'));
          return 0;
        },
      );
      expect(code4, 0);
    });
  });

  group('Part 5 Coverage: DevWebServer routes & edge cases', () {
    late HttpServer server;
    late HttpClient client;
    late DevAgentRuntime runtime;
    late DevProjectConfig project;
    late Directory tempWebAssets;
    late Directory tempAgentsDir;

    setUp(() async {
      tempAgentsDir = Directory.systemTemp.createTempSync('web_agents_test_');
      tempWebAssets = Directory.systemTemp.createTempSync('web_assets_test_');
      File('${tempWebAssets.path}${Platform.pathSeparator}index.html').writeAsStringSync('<h1>Index</h1>');
      File('${tempWebAssets.path}${Platform.pathSeparator}styles.css').writeAsStringSync('body { color: red; }');
      File('${tempWebAssets.path}${Platform.pathSeparator}app.js').writeAsStringSync('console.log(1);');
      File('${tempWebAssets.path}${Platform.pathSeparator}icon.svg').writeAsStringSync('<svg></svg>');
      File('${tempWebAssets.path}${Platform.pathSeparator}data.json').writeAsStringSync('{"k":"v"}');
      File('${tempWebAssets.path}${Platform.pathSeparator}img.png').writeAsBytesSync(<int>[137, 80, 78, 71]);
      File('${tempWebAssets.path}${Platform.pathSeparator}img.jpg').writeAsBytesSync(<int>[255, 216, 255]);
      File('${tempWebAssets.path}${Platform.pathSeparator}img.webp').writeAsBytesSync(<int>[82, 73, 70, 70]);
      File('${tempWebAssets.path}${Platform.pathSeparator}font.woff2').writeAsBytesSync(<int>[119, 79, 70, 50]);
      File('${tempWebAssets.path}${Platform.pathSeparator}file.bin').writeAsBytesSync(<int>[0, 1, 2]);

      project = const DevProjectConfig(
        appName: 'test_app',
        agentName: 'root_agent',
        description: 'test project',
      );
      runtime = DevAgentRuntime(config: project);

      server = await startAdkDevWebServer(
        runtime: runtime,
        project: project,
        agentsDir: tempAgentsDir.path,
        port: 0,
        enableWebUi: true,
        logoText: 'TestLogo',
        logoImageUrl: 'https://example.com/logo.png',
        avatarConfig: <String, String>{'agent': 'agent.png'},
        maxLiveMessageBytes: 256,
        maxLiveSessions: 1,
        liveKeepaliveTimeout: const Duration(seconds: 10),
      );
      client = HttpClient();
    });

    tearDown(() async {
      client.close(force: true);
      await server.close(force: true);
      await runtime.runner.close();
      if (tempWebAssets.existsSync()) {
        tempWebAssets.deleteSync(recursive: true);
      }
      if (tempAgentsDir.existsSync()) {
        tempAgentsDir.deleteSync(recursive: true);
      }
    });

    test('validation guards in startAdkDevWebServer', () async {
      // 1. Port bounds
      expect(
        () => startAdkDevWebServer(
          runtime: runtime,
          project: project,
          port: -1,
        ),
        throwsA(isA<ArgumentError>()),
      );

      // 2. expressMode without geminiEnterpriseAppName
      expect(
        () => startAdkDevWebServer(
          runtime: runtime,
          project: project,
          port: 0,
          expressMode: true,
        ),
        throwsA(isA<ArgumentError>()),
      );

      // 3. logoText without logoImageUrl
      expect(
        () => startAdkDevWebServer(
          runtime: runtime,
          project: project,
          port: 0,
          logoText: 'OnlyText',
        ),
        throwsA(isA<ArgumentError>()),
      );

      // 4. triggerSources on non-loopback without audience or bypass env
      expect(
        () => startAdkDevWebServer(
          runtime: runtime,
          project: project,
          port: 0,
          host: InternetAddress('192.168.1.100'),
          triggerSources: const <String>['pubsub'],
          environment: const <String, String>{},
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('UI config endpoints and redirects', () async {
      // GET / -> 302 redirect
      final HttpClientRequest reqRoot = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/'),
      )..followRedirects = false;
      final HttpClientResponse resRoot = await reqRoot.close();
      expect(resRoot.statusCode, HttpStatus.movedTemporarily);
      expect(resRoot.headers.value(HttpHeaders.locationHeader), '/dev-ui/');
      await resRoot.drain<void>();

      // GET /dev-ui -> 302 redirect
      final HttpClientRequest reqDevUi = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/dev-ui'),
      )..followRedirects = false;
      final HttpClientResponse resDevUi = await reqDevUi.close();
      expect(resDevUi.statusCode, HttpStatus.movedTemporarily);
      await resDevUi.drain<void>();

      // GET /dev-ui/assets/config/runtime-config.json
      final HttpClientRequest reqRuntimeConfig = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/dev-ui/assets/config/runtime-config.json'),
      );
      final HttpClientResponse resRuntimeConfig = await reqRuntimeConfig.close();
      expect(resRuntimeConfig.statusCode, HttpStatus.ok);
      final String runtimeConfigBody = await utf8.decoder.bind(resRuntimeConfig).join();
      final Map<String, dynamic> configJson = jsonDecode(runtimeConfigBody) as Map<String, dynamic>;
      expect(configJson['logo'], isNotNull);
      expect((configJson['logo'] as Map)['text'], 'TestLogo');

      // GET /dev-ui/config
      final HttpClientRequest reqConfig = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/dev-ui/config'),
      );
      final HttpClientResponse resConfig = await reqConfig.close();
      expect(resConfig.statusCode, HttpStatus.ok);
      final String configBody = await utf8.decoder.bind(resConfig).join();
      final Map<String, dynamic> uiConfig = jsonDecode(configBody) as Map<String, dynamic>;
      expect(uiConfig['logo_text'], 'TestLogo');
      expect(uiConfig['avatar_config'], isNotNull);

      // GET /dev-ui/sub..dir -> 400 invalid path
      final HttpClientRequest reqTraversal = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/dev-ui/sub..dir'),
      );
      final HttpClientResponse resTraversal = await reqTraversal.close();
      expect(resTraversal.statusCode, HttpStatus.badRequest);
      await resTraversal.drain<void>();
    });

    test('Graph and trace endpoints across standard and /dev/ prefixes', () async {
      // 1. /apps/test_app/build_graph and /dev/build_graph/test_app
      for (final String path in <String>[
        '/apps/test_app/build_graph',
        '/dev/build_graph/test_app',
        '/dev/apps/test_app/build_graph',
      ]) {
        final HttpClientRequest req = await client.getUrl(
          Uri.parse('http://127.0.0.1:${server.port}$path'),
        );
        final HttpClientResponse res = await req.close();
        expect(res.statusCode, HttpStatus.ok, reason: 'Failed on $path');
        final String body = await utf8.decoder.bind(res).join();
        final Map<String, dynamic> json = jsonDecode(body) as Map<String, dynamic>;
        expect(json['dot_src'], isNotNull);
      }

      // 2. /apps/test_app/build_graph_image and /dev/build_graph_image/test_app
      for (final String path in <String>[
        '/apps/test_app/build_graph_image',
        '/dev/build_graph_image/test_app',
        '/dev/apps/test_app/build_graph_image',
      ]) {
        final HttpClientRequest req = await client.getUrl(
          Uri.parse('http://127.0.0.1:${server.port}$path'),
        );
        final HttpClientResponse res = await req.close();
        expect(res.statusCode, HttpStatus.ok, reason: 'Failed on $path');
        final String body = await utf8.decoder.bind(res).join();
        final Map<String, dynamic> json = jsonDecode(body) as Map<String, dynamic>;
        expect(json[''], isNotNull); // root path target
      }

      // 3. /apps/test_app/build_graph_image?node=unknown_node -> 404
      final HttpClientRequest reqUnknownNode = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/apps/test_app/build_graph_image?node=nonexistent_node'),
      );
      final HttpClientResponse resUnknownNode = await reqUnknownNode.close();
      expect(resUnknownNode.statusCode, HttpStatus.notFound);
      await resUnknownNode.drain<void>();

      // 4. /dev/apps/test_app/debug/trace/{event_id} -> 404 when missing
      final HttpClientRequest reqTrace = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/dev/apps/test_app/debug/trace/ev_123'),
      );
      final HttpClientResponse resTrace = await reqTrace.close();
      expect(resTrace.statusCode, HttpStatus.notFound);
      await resTrace.drain<void>();

      // 5. /dev/apps/test_app/debug/trace/session/{session_id} -> 200 (empty list)
      final HttpClientRequest reqSessTrace = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/dev/apps/test_app/debug/trace/session/sess_123'),
      );
      final HttpClientResponse resSessTrace = await reqSessTrace.close();
      expect(resSessTrace.statusCode, HttpStatus.ok);
      final String sessTraceBody = await utf8.decoder.bind(resSessTrace).join();
      expect(jsonDecode(sessTraceBody), isEmpty);

      // 6. /apps/test_app/users/u1/sessions/s1/events/e1/graph -> empty object when event missing
      final HttpClientRequest reqEventGraph = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/apps/test_app/users/u1/sessions/s1/events/e1/graph'),
      );
      final HttpClientResponse resEventGraph = await reqEventGraph.close();
      expect(resEventGraph.statusCode, HttpStatus.ok);
      final String eventGraphBody = await utf8.decoder.bind(resEventGraph).join();
      expect(jsonDecode(eventGraphBody), isEmpty);
    });

    test('Screencast and Trigger routes', () async {
      // 1. Screencast on non-existent app -> 404
      final HttpClientRequest reqNoAppScreencast = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/apps/unknown_app/screencast'),
      );
      final HttpClientResponse resNoAppScreencast = await reqNoAppScreencast.close();
      expect(resNoAppScreencast.statusCode, HttpStatus.notFound);
      await resNoAppScreencast.drain<void>();

      // 2. Screencast on app without computer use -> 404
      final HttpClientRequest reqNoComputer = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/apps/test_app/screencast'),
      );
      final HttpClientResponse resNoComputer = await reqNoComputer.close();
      expect(resNoComputer.statusCode, HttpStatus.notFound);
      await resNoComputer.drain<void>();

      // 3. Trigger route on unknown source -> 404
      final HttpClientRequest reqTrigger = await client.postUrl(
        Uri.parse('http://127.0.0.1:${server.port}/dev/apps/test_app/trigger/unknown_source'),
      );
      reqTrigger.headers.contentType = ContentType.json;
      reqTrigger.write('{}');
      final HttpClientResponse resTrigger = await reqTrigger.close();
      expect(resTrigger.statusCode, HttpStatus.notFound);
      await resTrigger.drain<void>();
    });

    test('Full evaluation sets and cases workflow', () async {
      // 1. List metrics info
      final HttpClientRequest reqMetrics = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/apps/test_app/metrics-info'),
      );
      final HttpClientResponse resMetrics = await reqMetrics.close();
      expect(resMetrics.statusCode, HttpStatus.ok);
      await resMetrics.drain<void>();

      // 2. List eval sets (legacy and modern)
      final HttpClientRequest reqList1 = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/apps/test_app/eval-sets'),
      );
      final HttpClientResponse resList1 = await reqList1.close();
      expect(resList1.statusCode, HttpStatus.ok);
      await resList1.drain<void>();

      final HttpClientRequest reqListLegacy = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/apps/test_app/eval_sets'),
      );
      final HttpClientResponse resListLegacy = await reqListLegacy.close();
      expect(resListLegacy.statusCode, HttpStatus.ok);
      await resListLegacy.drain<void>();

      // 3. Create eval set (modern POST /eval-sets)
      final HttpClientRequest reqCreate = await client.postUrl(
        Uri.parse('http://127.0.0.1:${server.port}/apps/test_app/eval-sets'),
      );
      reqCreate.headers.contentType = ContentType.json;
      reqCreate.write(jsonEncode(<String, Object?>{'eval_set_id': 'set_1'}));
      final HttpClientResponse resCreate = await reqCreate.close();
      expect(resCreate.statusCode, HttpStatus.ok);
      await resCreate.drain<void>();

      // 4. Create eval set (legacy POST /eval_sets/set_legacy)
      final HttpClientRequest reqCreateLegacy = await client.postUrl(
        Uri.parse('http://127.0.0.1:${server.port}/apps/test_app/eval_sets/set_legacy'),
      );
      final HttpClientResponse resCreateLegacy = await reqCreateLegacy.close();
      expect(resCreateLegacy.statusCode, HttpStatus.ok);
      await resCreateLegacy.drain<void>();

      // 5. Add session to eval set: first when session not found -> 404
      final HttpClientRequest reqAddSessionNotFound = await client.postUrl(
        Uri.parse('http://127.0.0.1:${server.port}/apps/test_app/eval-sets/set_1/add-session'),
      );
      reqAddSessionNotFound.headers.contentType = ContentType.json;
      reqAddSessionNotFound.write(jsonEncode(<String, Object?>{
        'eval_id': 'case_from_session',
        'session_id': 'missing_session',
        'user_id': 'user_1',
      }));
      final HttpClientResponse resAddSessionNotFound = await reqAddSessionNotFound.close();
      expect(resAddSessionNotFound.statusCode, HttpStatus.notFound);
      await resAddSessionNotFound.drain<void>();

      // Create a real session to add to eval set
      final HttpClientRequest reqCreateSess = await client.postUrl(
        Uri.parse('http://127.0.0.1:${server.port}/apps/test_app/users/user_1/sessions'),
      );
      reqCreateSess.headers.contentType = ContentType.json;
      reqCreateSess.write(jsonEncode(<String, Object?>{
        'session_id': 'session_for_eval',
        'state': <String, Object?>{'val': 42},
      }));
      final HttpClientResponse resCreateSess = await reqCreateSess.close();
      expect(resCreateSess.statusCode, HttpStatus.ok);
      await resCreateSess.drain<void>();

      // Now add existing session to eval set -> 200
      final HttpClientRequest reqAddSessionOk = await client.postUrl(
        Uri.parse('http://127.0.0.1:${server.port}/apps/test_app/eval-sets/set_1/add-session'),
      );
      reqAddSessionOk.headers.contentType = ContentType.json;
      reqAddSessionOk.write(jsonEncode(<String, Object?>{
        'eval_id': 'case_from_session',
        'session_id': 'session_for_eval',
        'user_id': 'user_1',
      }));
      final HttpClientResponse resAddSessionOk = await reqAddSessionOk.close();
      expect(resAddSessionOk.statusCode, HttpStatus.ok);
      await resAddSessionOk.drain<void>();

      // 6. List evals in eval set: non-existent -> 400, existent -> 200
      final HttpClientRequest reqListEvalsBad = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/apps/test_app/eval-sets/nonexistent_set/evals'),
      );
      final HttpClientResponse resListEvalsBad = await reqListEvalsBad.close();
      expect(resListEvalsBad.statusCode, HttpStatus.badRequest);
      await resListEvalsBad.drain<void>();

      final HttpClientRequest reqListEvalsOk = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/apps/test_app/eval-sets/set_1/evals'),
      );
      final HttpClientResponse resListEvalsOk = await reqListEvalsOk.close();
      expect(resListEvalsOk.statusCode, HttpStatus.ok);
      final String listEvalsBody = await utf8.decoder.bind(resListEvalsOk).join();
      final List<dynamic> evalIds = jsonDecode(listEvalsBody) as List<dynamic>;
      expect(evalIds, contains('case_from_session'));

      // 7. Get eval case: non-existent -> 404, existent -> 200
      final HttpClientRequest reqGetCase404 = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/apps/test_app/eval-sets/set_1/eval-cases/missing_case'),
      );
      final HttpClientResponse resGetCase404 = await reqGetCase404.close();
      expect(resGetCase404.statusCode, HttpStatus.notFound);
      await resGetCase404.drain<void>();

      final HttpClientRequest reqGetCaseOk = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/apps/test_app/eval-sets/set_1/eval-cases/case_from_session'),
      );
      final HttpClientResponse resGetCaseOk = await reqGetCaseOk.close();
      expect(resGetCaseOk.statusCode, HttpStatus.ok);
      await resGetCaseOk.drain<void>();

      // 8. Update eval case: mismatched id -> 400
      final HttpClientRequest reqUpdateCaseMismatch = await client.putUrl(
        Uri.parse('http://127.0.0.1:${server.port}/apps/test_app/eval-sets/set_1/eval-cases/case_from_session'),
      );
      reqUpdateCaseMismatch.headers.contentType = ContentType.json;
      reqUpdateCaseMismatch.write(jsonEncode(<String, Object?>{
        'eval_id': 'different_id',
      }));
      final HttpClientResponse resUpdateCaseMismatch = await reqUpdateCaseMismatch.close();
      expect(resUpdateCaseMismatch.statusCode, HttpStatus.badRequest);
      await resUpdateCaseMismatch.drain<void>();

      // Update eval case: valid -> 200
      final HttpClientRequest reqUpdateCaseOk = await client.putUrl(
        Uri.parse('http://127.0.0.1:${server.port}/apps/test_app/eval-sets/set_1/eval-cases/case_from_session'),
      );
      reqUpdateCaseOk.headers.contentType = ContentType.json;
      reqUpdateCaseOk.write(jsonEncode(<String, Object?>{
        'eval_id': 'case_from_session',
        'metadata': <String, Object?>{'updated': true},
      }));
      final HttpClientResponse resUpdateCaseOk = await reqUpdateCaseOk.close();
      expect(resUpdateCaseOk.statusCode, HttpStatus.ok);
      await resUpdateCaseOk.drain<void>();

      // 9. Run eval: non-existent set -> 400
      final HttpClientRequest reqRunEvalBad = await client.postUrl(
        Uri.parse('http://127.0.0.1:${server.port}/apps/test_app/eval-sets/nonexistent_set/run'),
      );
      reqRunEvalBad.headers.contentType = ContentType.json;
      reqRunEvalBad.write('{}');
      final HttpClientResponse resRunEvalBad = await reqRunEvalBad.close();
      expect(resRunEvalBad.statusCode, HttpStatus.badRequest);
      await resRunEvalBad.drain<void>();

      // Run eval: valid set -> 200
      final HttpClientRequest reqRunEvalOk = await client.postUrl(
        Uri.parse('http://127.0.0.1:${server.port}/apps/test_app/eval-sets/set_1/run'),
      );
      reqRunEvalOk.headers.contentType = ContentType.json;
      reqRunEvalOk.write(jsonEncode(<String, Object?>{
        'eval_case_ids': <String>['case_from_session'],
        'eval_metrics': <String>['final_response_exact_match'],
      }));
      final HttpClientResponse resRunEvalOk = await reqRunEvalOk.close();
      expect(resRunEvalOk.statusCode, HttpStatus.ok);
      await resRunEvalOk.drain<void>();

      // 10. List eval results (modern & legacy)
      final HttpClientRequest reqListResults = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/apps/test_app/eval-results'),
      );
      final HttpClientResponse resListResults = await reqListResults.close();
      expect(resListResults.statusCode, HttpStatus.ok);
      final String listResultsBody = await utf8.decoder.bind(resListResults).join();
      final Map<String, dynamic> resultsJson = jsonDecode(listResultsBody) as Map<String, dynamic>;
      final List<dynamic> resultIds = resultsJson['eval_result_ids'] as List<dynamic>;
      expect(resultIds, isNotEmpty);

      // Legacy eval results
      final HttpClientRequest reqListResultsLegacy = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/apps/test_app/eval_results'),
      );
      final HttpClientResponse resListResultsLegacy = await reqListResultsLegacy.close();
      expect(resListResultsLegacy.statusCode, HttpStatus.ok);
      await resListResultsLegacy.drain<void>();

      // Get single eval result
      final String evalResultId = resultIds.first as String;
      final HttpClientRequest reqGetResult = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/apps/test_app/eval-results/$evalResultId'),
      );
      final HttpClientResponse resGetResult = await reqGetResult.close();
      expect(resGetResult.statusCode, HttpStatus.ok);
      await resGetResult.drain<void>();

      // 11. Delete eval case: non-existent -> 404, existent -> 200
      final HttpClientRequest reqDelCase404 = await client.deleteUrl(
        Uri.parse('http://127.0.0.1:${server.port}/apps/test_app/eval-sets/set_1/eval-cases/missing_case'),
      );
      final HttpClientResponse resDelCase404 = await reqDelCase404.close();
      expect(resDelCase404.statusCode, HttpStatus.notFound);
      await resDelCase404.drain<void>();

      final HttpClientRequest reqDelCaseOk = await client.deleteUrl(
        Uri.parse('http://127.0.0.1:${server.port}/apps/test_app/eval-sets/set_1/eval-cases/case_from_session'),
      );
      final HttpClientResponse resDelCaseOk = await reqDelCaseOk.close();
      expect(resDelCaseOk.statusCode, HttpStatus.ok);
      await resDelCaseOk.drain<void>();
    });

    test('Session, Memory and Artifact routes', () async {
      // 1. Create session with explicit ID via POST /apps/{appName}/users/{userId}/sessions/{sessionId}
      final HttpClientRequest reqCreateWithId = await client.postUrl(
        Uri.parse('http://127.0.0.1:${server.port}/apps/test_app/users/u1/sessions/custom_s1'),
      );
      reqCreateWithId.headers.contentType = ContentType.json;
      reqCreateWithId.write(jsonEncode(<String, Object?>{
        'state': <String, Object?>{'initial': 'value'},
      }));
      final HttpClientResponse resCreateWithId = await reqCreateWithId.close();
      expect(resCreateWithId.statusCode, HttpStatus.ok);
      await resCreateWithId.drain<void>();

      // 2. Get session: missing -> 404, exists -> 200
      final HttpClientRequest reqGetMissing = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/apps/test_app/users/u1/sessions/nonexistent_sess'),
      );
      final HttpClientResponse resGetMissing = await reqGetMissing.close();
      expect(resGetMissing.statusCode, HttpStatus.notFound);
      await resGetMissing.drain<void>();

      final HttpClientRequest reqGetSess = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/apps/test_app/users/u1/sessions/custom_s1'),
      );
      final HttpClientResponse resGetSess = await reqGetSess.close();
      expect(resGetSess.statusCode, HttpStatus.ok);
      await resGetSess.drain<void>();

      // 3. List sessions: GET /apps/{appName}/users/{userId}/sessions
      final HttpClientRequest reqListSess = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/apps/test_app/users/u1/sessions'),
      );
      final HttpClientResponse resListSess = await reqListSess.close();
      expect(resListSess.statusCode, HttpStatus.ok);
      await resListSess.drain<void>();

      // 4. Update session: PATCH /apps/{appName}/users/{userId}/sessions/{sessionId}
      final HttpClientRequest reqUpdateMissing = await client.patchUrl(
        Uri.parse('http://127.0.0.1:${server.port}/apps/test_app/users/u1/sessions/nonexistent_sess'),
      );
      reqUpdateMissing.headers.contentType = ContentType.json;
      reqUpdateMissing.write('{}');
      final HttpClientResponse resUpdateMissing = await reqUpdateMissing.close();
      expect(resUpdateMissing.statusCode, HttpStatus.notFound);
      await resUpdateMissing.drain<void>();

      final HttpClientRequest reqUpdateOk = await client.patchUrl(
        Uri.parse('http://127.0.0.1:${server.port}/apps/test_app/users/u1/sessions/custom_s1'),
      );
      reqUpdateOk.headers.contentType = ContentType.json;
      reqUpdateOk.write(jsonEncode(<String, Object?>{
        'state_delta': <String, Object?>{'updated_key': 'new_val'},
      }));
      final HttpClientResponse resUpdateOk = await reqUpdateOk.close();
      expect(resUpdateOk.statusCode, HttpStatus.ok);
      await resUpdateOk.drain<void>();

      // 5. Memory patch: PATCH /apps/{appName}/users/{userId}/memory
      final HttpClientRequest reqPatchMemMissing = await client.patchUrl(
        Uri.parse('http://127.0.0.1:${server.port}/apps/test_app/users/u1/memory'),
      );
      reqPatchMemMissing.headers.contentType = ContentType.json;
      reqPatchMemMissing.write(jsonEncode(<String, Object?>{'session_id': 'nonexistent_sess'}));
      final HttpClientResponse resPatchMemMissing = await reqPatchMemMissing.close();
      expect(resPatchMemMissing.statusCode, HttpStatus.notFound);
      await resPatchMemMissing.drain<void>();

      final HttpClientRequest reqPatchMemOk = await client.patchUrl(
        Uri.parse('http://127.0.0.1:${server.port}/apps/test_app/users/u1/memory'),
      );
      reqPatchMemOk.headers.contentType = ContentType.json;
      reqPatchMemOk.write(jsonEncode(<String, Object?>{'session_id': 'custom_s1'}));
      final HttpClientResponse resPatchMemOk = await reqPatchMemOk.close();
      expect(resPatchMemOk.statusCode, HttpStatus.ok);
      await resPatchMemOk.drain<void>();

      // 6. Artifacts routes:
      // List artifacts (empty)
      final HttpClientRequest reqListArt = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/apps/test_app/users/u1/sessions/custom_s1/artifacts'),
      );
      final HttpClientResponse resListArt = await reqListArt.close();
      expect(resListArt.statusCode, HttpStatus.ok);
      await resListArt.drain<void>();

      // Save artifact: POST /apps/.../artifacts
      final HttpClientRequest reqSaveArt = await client.postUrl(
        Uri.parse('http://127.0.0.1:${server.port}/apps/test_app/users/u1/sessions/custom_s1/artifacts'),
      );
      reqSaveArt.headers.contentType = ContentType.json;
      reqSaveArt.write(jsonEncode(<String, Object?>{
        'filename': 'test_doc.txt',
        'artifact': <String, Object?>{'text': 'Hello Artifact'},
        'custom_metadata': <String, Object?>{'tag': 'v1'},
      }));
      final HttpClientResponse resSaveArt = await reqSaveArt.close();
      expect(resSaveArt.statusCode, HttpStatus.ok);
      await resSaveArt.drain<void>();

      // Get artifact
      final HttpClientRequest reqGetArt = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/apps/test_app/users/u1/sessions/custom_s1/artifacts/test_doc.txt'),
      );
      final HttpClientResponse resGetArt = await reqGetArt.close();
      expect(resGetArt.statusCode, HttpStatus.ok);
      final String artBody = await utf8.decoder.bind(resGetArt).join();
      expect(jsonDecode(artBody)['text'], 'Hello Artifact');

      // Get artifact missing -> 404
      final HttpClientRequest reqGetArt404 = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/apps/test_app/users/u1/sessions/custom_s1/artifacts/missing.txt'),
      );
      final HttpClientResponse resGetArt404 = await reqGetArt404.close();
      expect(resGetArt404.statusCode, HttpStatus.notFound);
      await resGetArt404.drain<void>();

      // List artifact versions
      final HttpClientRequest reqArtVersions = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/apps/test_app/users/u1/sessions/custom_s1/artifacts/test_doc.txt/versions'),
      );
      final HttpClientResponse resArtVersions = await reqArtVersions.close();
      expect(resArtVersions.statusCode, HttpStatus.ok);
      await resArtVersions.drain<void>();

      // List artifact version metadata
      final HttpClientRequest reqArtMeta = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/apps/test_app/users/u1/sessions/custom_s1/artifacts/test_doc.txt/versions/metadata'),
      );
      final HttpClientResponse resArtMeta = await reqArtMeta.close();
      expect(resArtMeta.statusCode, HttpStatus.ok);
      await resArtMeta.drain<void>();

      // Get version 0 artifact
      final HttpClientRequest reqGetV0 = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/apps/test_app/users/u1/sessions/custom_s1/artifacts/test_doc.txt/versions/0'),
      );
      final HttpClientResponse resGetV0 = await reqGetV0.close();
      expect(resGetV0.statusCode, HttpStatus.ok);
      await resGetV0.drain<void>();

      // Get version 0 metadata
      final HttpClientRequest reqGetV0Meta = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/apps/test_app/users/u1/sessions/custom_s1/artifacts/test_doc.txt/versions/0/metadata'),
      );
      final HttpClientResponse resGetV0Meta = await reqGetV0Meta.close();
      expect(resGetV0Meta.statusCode, HttpStatus.ok);
      await resGetV0Meta.drain<void>();

      // Delete artifact
      final HttpClientRequest reqDelArt = await client.deleteUrl(
        Uri.parse('http://127.0.0.1:${server.port}/apps/test_app/users/u1/sessions/custom_s1/artifacts/test_doc.txt'),
      );
      final HttpClientResponse resDelArt = await reqDelArt.close();
      expect(resDelArt.statusCode, HttpStatus.ok);
      await resDelArt.drain<void>();

      // Delete session: DELETE /apps/{appName}/users/{userId}/sessions/{sessionId}
      final HttpClientRequest reqDelSess = await client.deleteUrl(
        Uri.parse('http://127.0.0.1:${server.port}/apps/test_app/users/u1/sessions/custom_s1'),
      );
      final HttpClientResponse resDelSess = await reqDelSess.close();
      expect(resDelSess.statusCode, HttpStatus.ok);
      await resDelSess.drain<void>();
    });

    test('Live WebSocket message limits and concurrent session bounds', () async {
      final _HangingLiveAgent liveAgent = _HangingLiveAgent(name: 'root_agent');
      final InMemoryRunner liveRunner = InMemoryRunner(
        appName: 'test_app',
        agent: liveAgent,
      );
      final DevAgentRuntime liveRuntime = DevAgentRuntime(
        config: project,
        runner: liveRunner,
      );
      final HttpServer liveServer = await startAdkDevWebServer(
        runtime: liveRuntime,
        project: project,
        agentsDir: tempAgentsDir.path,
        port: 0,
        maxLiveSessions: 1,
        maxLiveMessageBytes: 256,
        liveKeepaliveTimeout: const Duration(seconds: 10),
      );

      try {
        // 1. Create a session for live connection
        final HttpClientRequest reqCreateSess = await client.postUrl(
          Uri.parse('http://127.0.0.1:${liveServer.port}/apps/test_app/users/u1/sessions'),
        );
        reqCreateSess.headers.contentType = ContentType.json;
        reqCreateSess.write(jsonEncode(<String, Object?>{'session_id': 'live_sess'}));
        final HttpClientResponse resCreateSess = await reqCreateSess.close();
        expect(resCreateSess.statusCode, HttpStatus.ok);
        await resCreateSess.drain<void>();

        // 2. First live WebSocket connection succeeds and receives ready event
        final WebSocket ws1 = await WebSocket.connect(
          'ws://127.0.0.1:${liveServer.port}/run_live?app_name=test_app&user_id=u1&session_id=live_sess&modalities=TEXT',
        );

        final Completer<void> ws1Ready = Completer<void>();
        final Completer<int?> closeCodeCompleter = Completer<int?>();
        ws1.listen(
          (dynamic msg) {
            if (!ws1Ready.isCompleted) {
              ws1Ready.complete();
            }
          },
          onDone: () {
            if (!closeCodeCompleter.isCompleted) {
              closeCodeCompleter.complete(ws1.closeCode);
            }
          },
        );

        await ws1Ready.future.timeout(const Duration(seconds: 3));

        // 3. Second concurrent connection exceeds maxLiveSessions: 1 -> HTTP 503
        final HttpClientRequest req503 = await client.getUrl(
          Uri.parse('http://127.0.0.1:${liveServer.port}/run_live?app_name=test_app&user_id=u1&session_id=live_sess&modalities=TEXT'),
        );
        req503.headers.set(HttpHeaders.connectionHeader, 'Upgrade');
        req503.headers.set(HttpHeaders.upgradeHeader, 'websocket');
        req503.headers.set('Sec-WebSocket-Version', '13');
        req503.headers.set('Sec-WebSocket-Key', 'dGhlIHNhbXBsZSBub25jZQ==');
        final HttpClientResponse res503 = await req503.close();
        expect(res503.statusCode, HttpStatus.serviceUnavailable);
        await res503.drain<void>();

        // 4. Send payload exceeding maxLiveMessageBytes (256) -> closed with 1009
        final String largePayload = 'A' * 300;
        ws1.add(largePayload);

        final int? code = await closeCodeCompleter.future.timeout(
          const Duration(seconds: 3),
          onTimeout: () => ws1.closeCode,
        );
        expect(code, WebSocketStatus.messageTooBig);
      } finally {
        if (!liveAgent.gate.isCompleted) {
          liveAgent.gate.complete();
        }
        await liveServer.close(force: true);
        await liveRunner.close();
      }
    });
  });
}
