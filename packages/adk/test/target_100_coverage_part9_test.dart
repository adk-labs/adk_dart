import 'dart:convert';
import 'dart:core';
import 'dart:core' as core;
import 'dart:io';

import 'package:adk/adk.dart';
import 'package:adk/src/dev/cli.dart';
import 'package:test/test.dart';


void topLevelTestFunc() {}

class _DummyA2aEvent extends A2aEvent {}

class _DummyA2aPartRoot extends A2aPartRoot {}

class _FakeComputer implements BaseComputer {
  @override
  dynamic noSuchMethod(core.Invocation invocation) => null;
}

void main() {
  group('Target 100% Coverage - Part 9', () {
    test('cli helpers and conformance unit tests', () {
      // 1. emptyToNullTesting
      expect(emptyToNullTesting(''), isNull);
      expect(emptyToNullTesting('   '), isNull);
      expect(emptyToNullTesting(null), isNull);
      expect(emptyToNullTesting('hello'), 'hello');

      // 2. deepCloneJsonValueForTesting
      expect(deepCloneJsonValueForTesting(null), isNull);
      expect(deepCloneJsonValueForTesting(42), 42);
      expect(deepCloneJsonValueForTesting('abc'), 'abc');
      expect(
        deepCloneJsonValueForTesting(<String, Object?>{
          'a': 1,
          'b': <Object?>[2, 3],
        }),
        <String, Object?>{
          'a': 1,
          'b': <Object?>[2, 3],
        },
      );

      // 3. sanitizeConformanceEventMapForTesting
      final Map<String, Object?> rawEvent = <String, Object?>{
        'actions': <String, Object?>{
          'state_delta': <String, Object?>{
            'k': 'v',
            '_adk_replay_config': 'secret',
          },
        },
        'state': <String, Object?>{'user': 'name'},
        'content': <String, Object?>{
          'parts': <Object?>[
            <String, Object?>{
              'function_call': <String, Object?>{
                'name': 'tool1',
                'partial_args': <String, Object?>{'arg': 1},
              },
            },
          ],
        },
      };
      final Map<String, Object?> sanitized = sanitizeConformanceEventMapForTesting(rawEvent);
      expect(sanitized['actions'], isNotNull);
      expect((sanitized['actions'] as Map)['state_delta'], containsPair('k', 'v'));
      expect((sanitized['actions'] as Map)['state_delta'], isNot(contains('_adk_replay_config')));

      // Test actions without stateDelta
      final Map<String, Object?> emptyActionsEvent = <String, Object?>{
        'actions': <String, Object?>{},
      };
      final Map<String, Object?> sanitizedEmpty = sanitizeConformanceEventMapForTesting(emptyActionsEvent);
      expect(sanitizedEmpty.containsKey('actions'), isFalse);

      // 4. asObjectMapForTesting
      expect(asObjectMapForTesting(null), isEmpty);
      expect(asObjectMapForTesting('not a map'), isEmpty);
      expect(asObjectMapForTesting(<String, int>{'x': 10}), <String, Object?>{'x': 10});

      // 5. parseHostForTesting
      expect(parseHostForTesting('localhost'), InternetAddress.loopbackIPv4);
      expect(parseHostForTesting('127.0.0.1'), InternetAddress('127.0.0.1'));

      // 6. displayHostForTesting
      expect(displayHostForTesting(InternetAddress.loopbackIPv6), '[::1]');
      expect(displayHostForTesting(InternetAddress.loopbackIPv4), '127.0.0.1');
    });

    test('web_server unit testing helpers', () async {
      // 1. toDynamicMapForTesting
      expect(toDynamicMapForTesting(null), isEmpty);
      expect(toDynamicMapForTesting(123), isEmpty);
      expect(toDynamicMapForTesting(<Object, Object>{'key': 'value'}), <String, dynamic>{'key': 'value'});

      // 2. validatePathIdentifierForTesting
      expect(validatePathIdentifierForTesting('my_agent', 'agent'), 'my_agent');
      expect(() => validatePathIdentifierForTesting('.', 'folder'), throwsFormatException);
      expect(() => validatePathIdentifierForTesting('..', 'folder'), throwsFormatException);
      expect(() => validatePathIdentifierForTesting('foo/bar', 'folder'), throwsFormatException);
      expect(() => validatePathIdentifierForTesting(r'foo\bar', 'folder'), throwsFormatException);

      // 3. resolveEvalLocalBaseDirForTesting
      expect(
        resolveEvalLocalBaseDirForTesting(baseDir: '/base', evalStorageUri: '   '),
        '/base',
      );
      expect(
        resolveEvalLocalBaseDirForTesting(baseDir: '/base', evalStorageUri: 'file:///local/path'),
        '/local/path',
      );
      expect(
        () => resolveEvalLocalBaseDirForTesting(baseDir: '/base', evalStorageUri: 'http://example.com'),
        throwsArgumentError,
      );

      // 4. a2aPartToJsonForTesting
      expect(
        a2aPartToJsonForTesting(
          A2aPart.fileUri('https://example.com/f.pdf', mimeType: 'application/pdf'),
        ),
        <String, Object?>{
          'kind': 'file',
          'file': <String, Object?>{
            'uri': 'https://example.com/f.pdf',
            'mimeType': 'application/pdf',
            'mime_type': 'application/pdf',
          },
        },
      );
      expect(
        a2aPartToJsonForTesting(
          A2aPart.fileBytes('AQID', mimeType: 'image/png'),
        ),
        <String, Object?>{
          'kind': 'file',
          'file': <String, Object?>{
            'bytes': 'AQID',
            'mimeType': 'image/png',
            'mime_type': 'image/png',
          },
        },
      );
      expect(
        a2aPartToJsonForTesting(A2aPart(root: _DummyA2aPartRoot())),
        <String, Object?>{'kind': 'text', 'text': ''},
      );

      // 5. a2aEventToJsonForTesting
      expect(
        a2aEventToJsonForTesting(_DummyA2aEvent()),
        <String, Object?>{'kind': 'unknown'},
      );

      // 6. inferFunctionToolNameForTesting
      expect(inferFunctionToolNameForTesting(topLevelTestFunc), 'topLevelTestFunc');
      expect(inferFunctionToolNameForTesting(() {}), startsWith('tool_'));

      // 7. findComputerUseToolsetForTesting
      final LlmAgent simpleAgent = LlmAgent(name: 'simple');
      expect(findComputerUseToolsetForTesting(simpleAgent), isNull);

      final ComputerUseToolset cuToolset = ComputerUseToolset(computer: _FakeComputer());
      final LlmAgent cuAgent = LlmAgent(name: 'cu', tools: <BaseToolset>[cuToolset]);
      final Workflow wf = Workflow(
        name: 'wf',
        nodes: <BaseNode>[
          AgentNode(name: 'agent_node', agent: cuAgent),
        ],
      );
      expect(findComputerUseToolsetForTesting(wf), same(cuToolset));

      // 8. collectWorkflowGraphTargetsForTesting and findGraphTargetFromForTesting
      final Workflow subWf = Workflow(name: 'sub1', nodes: const <BaseNode>[]);
      final Workflow rootWf = Workflow(
        name: 'root',
        nodes: <BaseNode>[
          AgentNode(name: 'sub1', agent: subWf),
        ],
      );
      final Map<String, BaseAgent> targets = collectWorkflowGraphTargetsForTesting(rootWf, currentPath: 'root');
      expect(targets.keys, contains('root/sub1'));
      expect(findGraphTargetFromForTesting(rootWf, <String>['sub1']), same(subWf));
      expect(findGraphTargetFromForTesting(rootWf, <String>[]), same(rootWf));
      expect(findGraphTargetFromForTesting(rootWf, <String>['nonexistent']), isNull);

      // 9. parseRunEvalCaseIdsForTesting
      expect(
        parseRunEvalCaseIdsForTesting(<String, dynamic>{
          'eval_ids': <Object?>['case1', 'case2'],
        }),
        <String>['case1', 'case2'],
      );
      expect(
        parseRunEvalCaseIdsForTesting(<String, dynamic>{
          'eval_case_ids': <Object?>['caseA'],
        }),
        <String>['caseA'],
      );
      expect(parseRunEvalCaseIdsForTesting(<String, dynamic>{}), isEmpty);

      // 10. parseRunEvalMetricsForTesting
      expect(
        parseRunEvalMetricsForTesting(<String, dynamic>{}),
        <EvalMetric>[EvalMetric.finalResponseExactMatch],
      );
      expect(
        parseRunEvalMetricsForTesting(<String, dynamic>{
          'eval_metrics': <String>['final_response_exact_match'],
        }),
        <EvalMetric>[EvalMetric.finalResponseExactMatch],
      );

      // 11. hasValueForTesting
      expect(hasValueForTesting(<String, String>{'K': 'V'}, 'K'), isTrue);
      expect(hasValueForTesting(<String, String>{'K': ''}, 'K'), isFalse);
      expect(hasValueForTesting(<String, String>{}, 'K'), isFalse);

      // 12. instantiatePluginUsingMirrorsForTesting
      expect(
        await instantiatePluginUsingMirrorsForTesting('non.existent.PluginClass', baseDir: Directory.current.path),
        isNull,
      );
    });

    test('web_server startup configuration validations', () async {
      final DevProjectConfig project = DevProjectConfig(
        appName: 'app_val',
        agentName: 'agent_val',
        description: 'desc',
      );
      final DevAgentRuntime runtime = DevAgentRuntime(
        config: project,
        runner: InMemoryRunner(agent: LlmAgent(name: 'agent_val')),
      );
      addTearDown(() => runtime.runner.close());

      // 1. expressMode without geminiEnterpriseAppName throws ArgumentError
      expect(
        () => startAdkDevWebServer(
          runtime: runtime,
          project: project,
          expressMode: true,
          geminiEnterpriseAppName: '',
        ),
        throwsArgumentError,
      );

      // 2. Non-loopback host without auth verifier / audience throws ArgumentError
      expect(
        () => startAdkDevWebServer(
          runtime: runtime,
          project: project,
          host: InternetAddress('192.168.1.100'),
          triggerSources: <String>['cron'],
          triggerAuthVerifier: null,
          triggerOidcAudience: '',
        ),
        throwsArgumentError,
      );

      // 3. Logo text without logo image url throws ArgumentError
      expect(
        () => startAdkDevWebServer(
          runtime: runtime,
          project: project,
          logoText: 'MyLogo',
          logoImageUrl: null,
        ),
        throwsArgumentError,
      );
    });

    test('web_server HTTP request routes and query parsing edge cases', () async {
      final Directory tempDir = Directory.systemTemp.createTempSync('part9_web_');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      final DevProjectConfig project = DevProjectConfig(
        appName: 'test_app',
        agentName: 'test_agent',
        description: 'Test Web App',
      );
      final LlmAgent rootAgent = LlmAgent(name: 'test_agent');
      final DevAgentRuntime runtime = DevAgentRuntime(
        config: project,
        runner: InMemoryRunner(agent: rootAgent),
      );
      addTearDown(() => runtime.runner.close());

      final HttpServer server = await startAdkDevWebServer(
        runtime: runtime,
        project: project,
        agentsDir: tempDir.path,
        port: 0,
        a2a: true,
        triggerSources: <String>['pubsub'],
      );
      addTearDown(() => server.close(force: true));

      final HttpClient client = HttpClient();
      addTearDown(client.close);

      // 1. OPTIONS request
      final HttpClientRequest optReq = await client.openUrl(
        'OPTIONS',
        Uri.parse('http://127.0.0.1:${server.port}/apps/test_app'),
      );
      final HttpClientResponse optRes = await optReq.close();
      expect(optRes.statusCode, HttpStatus.ok);
      final String optBody = await utf8.decodeStream(optRes);
      expect(optBody, contains('{}'));

      // 2. Query param boolean variations & missing required query
      final Uri boolUri = Uri.parse(
        'http://127.0.0.1:${server.port}/apps/test_app/users/u1/sessions?verbose=yes',
      );
      final HttpClientRequest getSessionsReq = await client.getUrl(boolUri);
      final HttpClientResponse getSessionsRes = await getSessionsReq.close();
      expect(getSessionsRes.statusCode, HttpStatus.ok);
      await getSessionsRes.drain<void>();

      // 3. Trigger route unknown source -> 404
      final HttpClientRequest trigReq = await client.postUrl(
        Uri.parse('http://127.0.0.1:${server.port}/apps/test_app/trigger/unknown_source'),
      );
      trigReq.headers.contentType = ContentType.json;
      trigReq.write('{}');
      final HttpClientResponse trigRes = await trigReq.close();
      expect(trigRes.statusCode, HttpStatus.notFound);
      final String trigBody = await utf8.decodeStream(trigRes);
      expect(trigBody, contains('Unknown trigger source'));

      // 4. Artifact version not an integer -> 400
      final HttpClientRequest artReq = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/apps/test_app/users/u1/sessions/s1/artifacts/art1/versions/invalid_ver'),
      );
      final HttpClientResponse artRes = await artReq.close();
      expect(artRes.statusCode, HttpStatus.badRequest);
      final String artBody = await utf8.decodeStream(artRes);
      expect(artBody, contains('Invalid version id'));

      // 5. A2A tasks/pushnotificationconfig/get with missing task -> -32004 not found
      final HttpClientRequest a2aReq = await client.postUrl(
        Uri.parse('http://127.0.0.1:${server.port}/a2a/test_app'),
      );
      a2aReq.headers.contentType = ContentType.json;
      a2aReq.write(jsonEncode(<String, Object?>{
        'jsonrpc': '2.0',
        'id': 'rpc-1',
        'method': 'tasks/pushnotificationconfig/get',
        'params': <String, Object?>{
          'taskId': 'nonexistent-task',
        },
      }));
      final HttpClientResponse a2aRes = await a2aReq.close();
      expect(a2aRes.statusCode, HttpStatus.ok);
      final String a2aBody = await utf8.decodeStream(a2aRes);
      expect(a2aBody, contains('-32004'));
      expect(a2aBody, contains('A2A task not found'));
    });

    test('AdkDevWebContext methods and trace caching', () async {
      final Directory tempDir = Directory.systemTemp.createTempSync('part9_ctx_');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      final DevProjectConfig project = DevProjectConfig(
        appName: 'app_ctx',
        agentName: 'agent_ctx',
        description: 'Context Testing App',
      );
      final LlmAgent rootAgent = LlmAgent(name: 'agent_ctx');
      final DevAgentRuntime runtime = DevAgentRuntime(
        config: project,
        runner: InMemoryRunner(agent: rootAgent),
      );
      addTearDown(() => runtime.runner.close());

      // 1. Web context with enableWebUi = true
      final dynamic ctx = await createAdkDevWebContextForTesting(
        runtime: runtime,
        project: project,
        agentsDir: tempDir.path,
        enableWebUi: true,
      );
      expect(ctx.allowSpecialAgents, isTrue);

      // 2. Web context with enableWebUi = false
      final dynamic ctxNoUi = await createAdkDevWebContextForTesting(
        runtime: runtime,
        project: project,
        agentsDir: tempDir.path,
        enableWebUi: false,
      );
      expect(ctxNoUi.allowSpecialAgents, isFalse);

      // 3. getRunner with null (uses defaultAppName) and caching
      final Runner r1 = await ctx.getRunner(null) as Runner;
      expect(r1, isNotNull);
      final Runner r2 = await ctx.getRunner('   ') as Runner;
      expect(identical(r1, r2), isTrue);

      // 4. asBaseAgent
      expect(ctx.asBaseAgent(rootAgent), same(rootAgent));
      expect(ctx.asBaseAgent(123), isNull);

      // 5. recordTraceEvent and readTraceByEventId and readTraceBySessionId
      final Event event1 = Event(
        id: 'evt_1',
        invocationId: 'inv_1',
        author: 'agent_ctx',
        content: Content(parts: <Part>[Part.text('hello')]),
        customMetadata: <String, Object?>{'parent_span_id': '0a'},
      );
      ctx.recordTraceEvent(
        appName: 'app_ctx',
        userId: 'u1',
        sessionId: 'sess_1',
        event: event1,
      );

      // Record again with same event ID to test update branch
      ctx.recordTraceEvent(
        appName: 'app_ctx',
        userId: 'u1',
        sessionId: 'sess_1',
        event: event1,
      );

      final Map<String, Object?>? trace = ctx.readTraceByEventId('evt_1') as Map<String, Object?>?;
      expect(trace, isNotNull);
      expect(trace!['event_id'], 'evt_1');
      expect(ctx.readTraceByEventId('nonexistent'), isNull);

      final List<Map<String, Object?>> sessTraces =
          (ctx.readTraceBySessionId('sess_1') as List).cast<Map<String, Object?>>();
      expect(sessTraces, hasLength(1));

      // 6. getRootAgent
      final BaseAgent agentRoot = ctx.getRootAgent('') as BaseAgent;
      expect(agentRoot.name, 'agent_ctx');
      expect(() => ctx.getRootAgent('nonexistent_app'), throwsA(isA<ArgumentError>()));

      // 7. enqueueA2aPushNotifications fallback when queue is null
      await ctxNoUi.enqueueA2aPushNotifications(
        appName: 'app_ctx',
        taskId: 'task_abc',
        pushConfig: <String, Object?>{
          'url': 'http://127.0.0.1:9/push',
        },
        task: <String, Object?>{'id': 'task_abc'},
        updates: <Map<String, Object?>>[
          <String, Object?>{'status': 'running'},
        ],
      );
    });
  });
}
