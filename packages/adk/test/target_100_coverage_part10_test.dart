import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:adk/adk.dart';
import 'package:adk/src/dev/cli.dart';
import 'package:test/test.dart';

class _BufferIOSink implements IOSink {
  _BufferIOSink(this.buffer);
  final StringBuffer buffer;

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
  void add(List<int> data) => buffer.write(utf8.decode(data));

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final List<int> chunk in stream) {
      buffer.write(utf8.decode(chunk));
    }
  }

  @override
  Future<void> close() async {}

  @override
  Future<void> get done => Future<void>.value();

  @override
  Encoding encoding = utf8;

  @override
  Future<void> flush() async {}
}

void main() {
  group('Target 100% Coverage - Part 10 CLI helpers and error branches', () {
    tearDown(() {
      writeTelemetryConsentTestingOverride = null;
      runSubcommandTestingOverride = null;
      handleRequestTestingOverride = null;
    });

    test('writeTelemetryConsentTestingOverride error branches in runAdkCli', () async {
      final StringBuffer out = StringBuffer();
      final StringBuffer err = StringBuffer();

      // 1. Telemetry enable error
      writeTelemetryConsentTestingOverride = (bool _) {
        throw Exception('simulated enable telemetry failure');
      };
      final int codeEnable = await runAdkCli(
        <String>['telemetry', 'enable'],
        outSink: _BufferIOSink(out),
        errSink: _BufferIOSink(err),
      );
      expect(codeEnable, 1);
      expect(err.toString(), contains('Failed to enable telemetry'));

      // 2. Telemetry disable error
      err.clear();
      writeTelemetryConsentTestingOverride = (bool _) {
        throw Exception('simulated disable telemetry failure');
      };
      final int codeDisable = await runAdkCli(
        <String>['telemetry', 'disable'],
        outSink: _BufferIOSink(out),
        errSink: _BufferIOSink(err),
      );
      expect(codeDisable, 1);
      expect(err.toString(), contains('Failed to disable telemetry'));
    });

    test('runSubcommandTestingOverride triggers SocketException catch in runAdkCli', () async {
      final StringBuffer err = StringBuffer();
      runSubcommandTestingOverride = (ParsedAdkCommand command) async {
        throw const SocketException('Connection refused');
      };

      final int code = await runAdkCli(
        <String>['run', '.'],
        errSink: _BufferIOSink(err),
      );
      expect(code, 1);
      expect(err.toString(), contains('Network error:'));
    });

    test('buildConformanceRunMessageForTesting exhaustive edge cases', () {
      final Map<String, String> callMap = <String, String>{'my_tool': 'call_123'};

      // 1. Non-Map content returns content as-is
      expect(buildConformanceRunMessageForTesting(12345, callMap), 12345);

      // 2. Content without 'parts' or non-list parts returns content
      expect(
        buildConformanceRunMessageForTesting(<String, Object?>{'role': 'user'}, callMap),
        <String, Object?>{'role': 'user'},
      );
      expect(
        buildConformanceRunMessageForTesting(<String, Object?>{'parts': 'not_a_list'}, callMap),
        <String, Object?>{'parts': 'not_a_list'},
      );

      // 3. Parts is empty or first part is not a Map returns content
      expect(
        buildConformanceRunMessageForTesting(<String, Object?>{'parts': <Object?>[]}, callMap),
        <String, Object?>{'parts': <Object?>[]},
      );
      expect(
        buildConformanceRunMessageForTesting(<String, Object?>{
          'parts': <Object?>['not_a_map']
        }, callMap),
        <String, Object?>{
          'parts': <Object?>['not_a_map']
        },
      );

      // 4. First part has function_response without name returns content
      expect(
        buildConformanceRunMessageForTesting(<String, Object?>{
          'parts': <Object?>[
            <String, Object?>{'function_response': <String, Object?>{}}
          ]
        }, callMap),
        isA<Map<String, Object?>>(),
      );

      // 5. Function response with unknown name throws StateError
      expect(
        () => buildConformanceRunMessageForTesting(<String, Object?>{
          'parts': <Object?>[
            <String, Object?>{
              'function_response': <String, Object?>{'name': 'unknown_tool'}
            }
          ]
        }, callMap),
        throwsA(isA<StateError>()),
      );

      // 6. Function response with known name sets call id
      final Object? resolved = buildConformanceRunMessageForTesting(<String, Object?>{
        'parts': <Object?>[
          <String, Object?>{
            'function_response': <String, Object?>{'name': 'my_tool'}
          }
        ]
      }, callMap);
      expect(resolved, isA<Map<String, Object?>>());
      final Map<String, Object?> resolvedMap = resolved! as Map<String, Object?>;
      final List<Object?> parts = resolvedMap['parts']! as List<Object?>;
      final Map<String, Object?> firstPart = parts[0]! as Map<String, Object?>;
      expect(
        (firstPart['function_response'] as Map<String, Object?>)['id'],
        'call_123',
      );

      // 7. Text and fallback
      expect(buildConformanceRunMessageForTesting(null, callMap, text: 'hi'), 'hi');
      expect(buildConformanceRunMessageForTesting(null, callMap), '');
    });

    test('sanitizeConformanceSessionMapForTesting and deepCopyMapForTesting', () {
      // 1. Session with non-empty state
      final Map<String, Object?> sessionWithState = <String, Object?>{
        'id': 'sess_1',
        'last_update_time': 12345,
        'state': <String, Object?>{
          'foo': 'bar',
          '_adk_recordings_config': <String, Object?>{'mode': 'all'},
        },
      };
      final Map<String, Object?> sanitized =
          sanitizeConformanceSessionMapForTesting(sessionWithState);
      expect(sanitized.containsKey('id'), isFalse);
      expect(sanitized['state'], <String, Object?>{'foo': 'bar'});

      // 2. Session with only internal state keys removes state
      final Map<String, Object?> sessionInternalState = <String, Object?>{
        'state': <String, Object?>{
          '_adk_recordings_config': <String, Object?>{'mode': 'all'},
        },
      };
      final Map<String, Object?> sanitizedInternal =
          sanitizeConformanceSessionMapForTesting(sessionInternalState);
      expect(sanitizedInternal.containsKey('state'), isFalse);

      // 3. deepCopyMapForTesting
      final Map<String, Object?> regularMap = <String, Object?>{
        'key': 'one',
        'str': 'val',
      };
      final Map<String, Object?> copied = deepCopyMapForTesting(regularMap);
      expect(copied['key'], 'one');
      expect(copied['str'], 'val');
    });

    test('parseEvalSelectionForTesting and createEvalManagersForTesting', () {
      // 1. Windows drive root
      final dynamic selWin = parseEvalSelectionForTesting('C:\\agent\\eval.json');
      expect(selWin.source, 'C:\\agent\\eval.json');
      expect(selWin.evalCaseIds, isEmpty);

      // 2. Colon with empty source or empty ids
      final dynamic selEmptySrc = parseEvalSelectionForTesting(' :case1');
      expect(selEmptySrc.source, ':case1');
      expect(selEmptySrc.evalCaseIds, isEmpty);

      final dynamic selEmptyIds = parseEvalSelectionForTesting('eval_set: ');
      expect(selEmptyIds.source, 'eval_set:');
      expect(selEmptyIds.evalCaseIds, isEmpty);

      // 3. Valid source and multiple IDs
      final dynamic selValid = parseEvalSelectionForTesting('eval_set:c1,c2');
      expect(selValid.source, 'eval_set');
      expect(selValid.evalCaseIds, <String>{'c1', 'c2'});

      // 4. createEvalManagers with GCS URI
      final dynamic gcsManagers = createEvalManagersForTesting(
        evalStorageUri: 'gs://test-bucket/evals',
        agentsDir: '.',
        useInMemory: false,
      );
      expect(gcsManagers, isNotNull);
    });

    test('mergeEvalTargetsForTesting exhaustive combinations', () {
      final List<dynamic> targets = <dynamic>[];

      // 1. Add when not present
      mergeEvalTargetsForTesting(targets, 'set_1', <String>{'c1'});
      expect(targets, hasLength(1));
      expect(targets.first.evalCaseIds, <String>{'c1'});

      // 2. Both have case IDs -> union
      mergeEvalTargetsForTesting(targets, 'set_1', <String>{'c2', 'c3'});
      expect(targets.first.evalCaseIds, <String>{'c1', 'c2', 'c3'});

      // 3. Existing has case IDs, new has empty evalCaseIds -> transitions to empty (all cases)
      mergeEvalTargetsForTesting(targets, 'set_1', <String>{});
      expect(targets.first.evalCaseIds, isEmpty);

      // 4. Existing has empty evalCaseIds, new has case IDs -> remains empty (all cases)
      mergeEvalTargetsForTesting(targets, 'set_1', <String>{'c4'});
      expect(targets.first.evalCaseIds, isEmpty);
    });

    test('bestOptimizedAgentIndexForTesting rawBestIdx and score loops', () {
      final List<BaseAgentWithScores> agents = <BaseAgentWithScores>[
        BaseAgentWithScores(optimizedAgent: LlmAgent(name: 'a1'), overallScore: 0.4),
        BaseAgentWithScores(optimizedAgent: LlmAgent(name: 'a2'), overallScore: 0.95),
        BaseAgentWithScores(optimizedAgent: LlmAgent(name: 'a3'), overallScore: 0.8),
      ];

      // 1. Valid rawBestIdx
      final GepaRootAgentPromptOptimizerResult resWithIdx =
          GepaRootAgentPromptOptimizerResult(
            optimizedAgents: agents,
            gepaResult: <String, Object?>{'best_idx': 2},
          );
      expect(bestOptimizedAgentIndexForTesting(resWithIdx), 2);

      // 2. Without best_idx, finds maximum score
      final GepaRootAgentPromptOptimizerResult resNoIdx =
          GepaRootAgentPromptOptimizerResult(optimizedAgents: agents);
      expect(bestOptimizedAgentIndexForTesting(resNoIdx), 1);

      // 3. Empty agents list returns 0
      final GepaRootAgentPromptOptimizerResult resEmpty =
          GepaRootAgentPromptOptimizerResult(
            optimizedAgents: const <BaseAgentWithScores>[],
          );
      expect(bestOptimizedAgentIndexForTesting(resEmpty), 0);
    });

    test('loadConformanceSpecForTesting spec validation format exceptions', () {
      final Directory tempDir = Directory.systemTemp.createTempSync('conf_spec_');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      // 1. user_messages has non-map item
      final File specNonMap = File('${tempDir.path}/spec_non_map.yaml')
        ..writeAsStringSync('''
agent: test_agent
user_messages:
  - "just a string"
''');
      expect(
        () => loadConformanceSpecForTesting(specNonMap.path),
        throwsA(isA<FormatException>()),
      );

      // 2. user_messages item has neither text nor content
      final File specEmptyMsg = File('${tempDir.path}/spec_empty_msg.yaml')
        ..writeAsStringSync('''
agent: test_agent
user_messages:
  - other_key: "value"
''');
      expect(
        () => loadConformanceSpecForTesting(specEmptyMsg.path),
        throwsA(isA<FormatException>()),
      );

      // 3. user_messages item with state_delta
      final File specValid = File('${tempDir.path}/spec_valid.yaml')
        ..writeAsStringSync('''
agent: test_agent
user_messages:
  - text: "hello"
    state_delta:
      session_key: "session_val"
''');
      final dynamic parsed = loadConformanceSpecForTesting(specValid.path);
      expect(parsed.agent, 'test_agent');
      expect(parsed.userMessages, hasLength(1));
      expect(parsed.userMessages[0].stateDelta, <String, Object?>{
        'session_key': 'session_val',
      });
    });

    test('writeConformanceReportMarkdownForTesting with versionData', () async {
      final Directory tempDir = Directory.systemTemp.createTempSync('conf_rep_');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      final String reportPath = await writeConformanceReportMarkdownForTesting(
        summaries: const <dynamic>[],
        reportDir: tempDir.path,
        versionData: <String, Object?>{
          'server_version': '0.9.1',
          'dart_sdk': '3.8.0',
        },
      );
      final File reportFile = File(reportPath);
      expect(reportFile.existsSync(), isTrue);
      final String content = reportFile.readAsStringSync();
      expect(content, contains('## Version'));
      expect(content, contains('- server_version: 0.9.1'));
    });

    test('loadAgentForCliForTesting throws when path is not a directory', () async {
      final Directory tempDir = Directory.systemTemp.createTempSync('cli_file_');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      final File notADir = File('${tempDir.path}/dummy.txt')..writeAsStringSync('hi');

      expect(
        () => loadAgentForCliForTesting(notADir.path),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('parseAdkCliArgs edge flags and error options', () async {
      final Directory tempDir = Directory.systemTemp.createTempSync('cli_args_');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      final File stateFile = File('${tempDir.path}/state.json')..writeAsStringSync('{}');

      final StringBuffer out = StringBuffer();
      final StringBuffer err = StringBuffer();

      // 1. eval_set add_eval_case unknown option -> 64
      final int c1 = await runAdkCli(
        <String>['eval_set', 'add_eval_case', '--unknown_flag', '.'],
        outSink: _BufferIOSink(out),
        errSink: _BufferIOSink(err),
      );
      expect(c1, 64);
      expect(err.toString(), contains('Unknown option for eval_set add_eval_case'));

      // 2. conformance record unknown option -> 64
      err.clear();
      final int c2 = await runAdkCli(
        <String>['conformance', 'record', '--unknown_flag_xyz', '.'],
        outSink: _BufferIOSink(out),
        errSink: _BufferIOSink(err),
      );
      expect(c2, 64);
      expect(err.toString(), contains('Unknown option for conformance record'));

      // 3. conformance test unknown option -> 64
      err.clear();
      final int c3 = await runAdkCli(
        <String>['conformance', 'test', '--unknown_flag_xyz', '.'],
        outSink: _BufferIOSink(out),
        errSink: _BufferIOSink(err),
      );
      expect(c3, 64);
      expect(err.toString(), contains('Unknown option for conformance test'));

      // 4. run command state-file variations
      final ParsedAdkCommand p5 = parseAdkCliArgs(<String>[
        'run',
        '--state_file=${stateFile.path}',
        '.',
      ]);
      expect(p5.type, AdkCommandType.run);

      final ParsedAdkCommand p6 = parseAdkCliArgs(<String>[
        'run',
        '--state-file=${stateFile.path}',
        '.',
      ]);
      expect(p6.type, AdkCommandType.run);

      // 5. web options logo-text, logo-image-url, and max_llm_calls
      final ParsedAdkCommand p7 = parseAdkCliArgs(<String>[
        'web',
        '--logo-text=MyLogo',
        '--logo-image-url',
        'http://example.com/logo.png',
        '--max_llm_calls',
        '25',
        '.',
      ]);
      expect(p7.type, AdkCommandType.web);
      expect(p7.logoText, 'MyLogo');
      expect(p7.logoImageUrl, 'http://example.com/logo.png');
      expect(p7.maxLlmCalls, 25);

      // 6. Invalid web max_llm_calls throws CliUsageError
      expect(
        () => parseAdkCliArgs(<String>['web', '--max_llm_calls=not_a_number', '.']),
        throwsA(isA<CliUsageError>()),
      );

      // 7. Invalid avatar config JSON throws CliUsageError
      expect(
        () => parseAdkCliArgs(<String>['web', '--avatar_config={not_json', '.']),
        throwsA(isA<CliUsageError>()),
      );

      // 8. Invalid avatar config entry throws CliUsageError
      expect(
        () => parseAdkCliArgs(<String>['web', '--avatar_config=invalid_entry', '.']),
        throwsA(isA<CliUsageError>()),
      );
    });
  });

  group('Target 100% Coverage - Part 10 Web Server helpers and error routes', () {
    tearDown(() {
      handleRequestTestingOverride = null;
    });

    test('asDoubleForTesting and buildLiveHighlightsForTesting', () async {
      final Directory tempDir = Directory.systemTemp.createTempSync('part10_helpers_');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      final DevProjectConfig project = DevProjectConfig(
        appName: 'app_hl',
        agentName: 'agent_hl',
        description: 'Helpers App',
      );
      final DevAgentRuntime runtime = DevAgentRuntime(
        config: project,
        runner: InMemoryRunner(agent: LlmAgent(name: 'agent_hl')),
      );
      addTearDown(() => runtime.runner.close());

      final dynamic ctx = await createAdkDevWebContextForTesting(
        runtime: runtime,
        project: project,
        agentsDir: tempDir.path,
      );

      // 1. asDoubleForTesting
      expect(asDoubleForTesting(ctx, '15.75'), 15.75);
      expect(asDoubleForTesting(ctx, 'invalid'), 0.0);
      expect(asDoubleForTesting(ctx, 42), 42.0);

      // 2. buildLiveHighlightsForTesting
      final Event toolCallEvt = Event(
        id: 'e1',
        invocationId: 'i1',
        author: 'model',
        content: Content(
          parts: <Part>[
            Part.fromFunctionResponse(
              name: 'calculator',
              response: <String, Object?>{'result': 4},
            ),
          ],
        ),
      );
      final Event authorEvt = Event(
        id: 'e2',
        invocationId: 'i2',
        author: 'agent_user',
        content: Content(parts: <Part>[Part.text('hello')]),
      );

      final Set<(String, String)> hl1 = buildLiveHighlightsForTesting(toolCallEvt);
      expect(hl1, contains(('tool:calculator', 'model')));

      final Set<(String, String)> hl2 = buildLiveHighlightsForTesting(authorEvt);
      expect(hl2, contains(('agent_user', '')));
    });

    test('parseRunRequestForTesting fallback to text field', () async {
      final Directory tempDir = Directory.systemTemp.createTempSync('part10_req_');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      final DevProjectConfig project = DevProjectConfig(
        appName: 'app_req',
        agentName: 'agent_req',
        description: 'Req App',
      );
      final DevAgentRuntime runtime = DevAgentRuntime(
        config: project,
        runner: InMemoryRunner(agent: LlmAgent(name: 'agent_req')),
      );
      addTearDown(() => runtime.runner.close());

      final dynamic ctx = await createAdkDevWebContextForTesting(
        runtime: runtime,
        project: project,
        agentsDir: tempDir.path,
      );

      final dynamic req = parseRunRequestForTesting(<String, dynamic>{
        'app_name': 'app_req',
        'user_id': 'u1',
        'session_id': 's1',
        'text': 'hello from form text',
      }, ctx);
      expect(req.appName, 'app_req');
      expect(req.userId, 'u1');
      expect(req.sessionId, 's1');
      expect(req.newMessage, isNotNull);
      expect(req.newMessage.parts.first.text, 'hello from form text');
    });

    test('findGraphTargetForTesting path resolution', () {
      final LlmAgent sub1 = LlmAgent(name: 'sub_agent_1');
      final LlmAgent root = LlmAgent(
        name: 'root_agent',
        subAgents: <BaseAgent>[sub1],
      );

      // 1. Empty path returns root
      expect(findGraphTargetForTesting(root, const <String>[]), same(root));

      // 2. Path matching subAgent
      final BaseAgent? found = findGraphTargetForTesting(
        root,
        <String>['root_agent', 'sub_agent_1'],
      );
      expect(found, same(sub1));

      // 3. Path not matching
      expect(
        findGraphTargetForTesting(root, <String>['nonexistent_sub']),
        isNull,
      );
    });

    test('handleRequestTestingOverride catches and converts all exception types', () async {
      final Directory tempDir = Directory.systemTemp.createTempSync('part10_serv_');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      final DevProjectConfig project = DevProjectConfig(
        appName: 'app_err',
        agentName: 'agent_err',
        description: 'Error Testing App',
      );
      final DevAgentRuntime runtime = DevAgentRuntime(
        config: project,
        runner: InMemoryRunner(agent: LlmAgent(name: 'agent_err')),
      );
      addTearDown(() => runtime.runner.close());

      final HttpServer server = await startAdkDevWebServer(
        runtime: runtime,
        project: project,
        agentsDir: tempDir.path,
        port: 0,
      );
      addTearDown(() => server.close(force: true));

      final HttpClient client = HttpClient();
      addTearDown(client.close);

      // 1. ArgumentError -> 400
      handleRequestTestingOverride = (HttpRequest req, dynamic ctx) async {
        throw ArgumentError('invalid argument test');
      };
      HttpClientRequest req = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/test_err'),
      );
      HttpClientResponse res = await req.close();
      expect(res.statusCode, HttpStatus.badRequest);
      await res.drain<void>();

      // 2. StateError -> 404
      handleRequestTestingOverride = (HttpRequest req, dynamic ctx) async {
        throw StateError('state error test');
      };
      req = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/test_err'),
      );
      res = await req.close();
      expect(res.statusCode, HttpStatus.notFound);
      await res.drain<void>();

      // 3. SessionNotFoundError -> 404
      handleRequestTestingOverride = (HttpRequest req, dynamic ctx) async {
        throw SessionNotFoundError('session not found test');
      };
      req = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/test_err'),
      );
      res = await req.close();
      expect(res.statusCode, HttpStatus.notFound);
      await res.drain<void>();

      // 4. SpecialAgentAccessDeniedException -> 403
      handleRequestTestingOverride = (HttpRequest req, dynamic ctx) async {
        throw const SpecialAgentAccessDeniedException();
      };
      req = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/test_err'),
      );
      res = await req.close();
      expect(res.statusCode, HttpStatus.forbidden);
      await res.drain<void>();

      // 5. Generic Exception -> 500
      handleRequestTestingOverride = (HttpRequest req, dynamic ctx) async {
        throw Exception('unexpected server error');
      };
      req = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/test_err'),
      );
      res = await req.close();
      expect(res.statusCode, HttpStatus.internalServerError);
      await res.drain<void>();
    });

    test('Trigger route exceptions and verification error handling', () async {
      final Directory tempDir = Directory.systemTemp.createTempSync('part10_trig_');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      final DevProjectConfig project = DevProjectConfig(
        appName: 'app_trig',
        agentName: 'agent_trig',
        description: 'Trigger Testing App',
      );
      final DevAgentRuntime runtime = DevAgentRuntime(
        config: project,
        runner: InMemoryRunner(agent: LlmAgent(name: 'agent_trig')),
      );
      addTearDown(() => runtime.runner.close());

      // Enable trigger sources
      final HttpServer server = await startAdkDevWebServer(
        runtime: runtime,
        project: project,
        agentsDir: tempDir.path,
        port: 0,
        triggerSources: const <String>['pubsub'],
      );
      addTearDown(() => server.close(force: true));

      final HttpClient client = HttpClient();
      addTearDown(client.close);

      // 1. Trigger source that is disabled (eventarc is disabled, only pubsub enabled) writes 404
      HttpClientRequest req = await client.postUrl(
        Uri.parse('http://127.0.0.1:${server.port}/apps/app_trig/trigger/eventarc'),
      );
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(<String, Object?>{}));
      HttpClientResponse res = await req.close();
      expect(res.statusCode, HttpStatus.notFound);
      final String disabledRes = await utf8.decoder.bind(res).join();
      expect(disabledRes, contains('Unknown trigger source: eventarc'));

      // 1b. Unknown trigger source in _handleTriggerRoute writes 404
      handleRequestTestingOverride = (HttpRequest r, dynamic ctx) async {
        await handleTriggerRouteForTesting(
          r,
          ctx,
          appName: 'app_trig',
          triggerSource: 'unsupported_source',
        );
      };
      req = await client.postUrl(
        Uri.parse('http://127.0.0.1:${server.port}/test_unsupported_trigger'),
      );
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(<String, Object?>{}));
      res = await req.close();
      expect(res.statusCode, HttpStatus.notFound);
      final String unsupportedRes = await utf8.decoder.bind(res).join();
      expect(unsupportedRes, contains('Unknown trigger source: unsupported_source'));
      handleRequestTestingOverride = null;

      // 2. GET /apps/missing_agent returns 404
      req = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/apps/missing_agent'),
      );
      res = await req.close();
      expect(res.statusCode, HttpStatus.notFound);
      await res.drain<void>();

      // 3. Artifact versions endpoints error paths
      req = await client.getUrl(
        Uri.parse(
          'http://127.0.0.1:${server.port}/apps/app_trig/users/u1/sessions/s1/artifacts/doc.txt/versions/not_a_number',
        ),
      );
      res = await req.close();
      expect(res.statusCode, HttpStatus.badRequest);
      final String nanErr = await utf8.decoder.bind(res).join();
      expect(nanErr, contains('Invalid version id'));

      req = await client.getUrl(
        Uri.parse(
          'http://127.0.0.1:${server.port}/apps/app_trig/users/u1/sessions/s1/artifacts/doc.txt/versions/999',
        ),
      );
      res = await req.close();
      expect(res.statusCode, HttpStatus.notFound);
      await res.drain<void>();

      req = await client.postUrl(
        Uri.parse(
          'http://127.0.0.1:${server.port}/apps/app_trig/users/u1/sessions/s1/artifacts/doc.txt/versions/1',
        ),
      );
      res = await req.close();
      expect(res.statusCode, HttpStatus.notFound);
      await res.drain<void>();

      req = await client.putUrl(
        Uri.parse(
          'http://127.0.0.1:${server.port}/apps/app_trig/users/u1/sessions/s1/artifacts/doc.txt',
        ),
      );
      res = await req.close();
      expect(res.statusCode, HttpStatus.methodNotAllowed);
      await res.drain<void>();
    });

    test('A2A RPC tasks:push_notification_config:get and task not found errors', () async {
      final Directory tempDir = Directory.systemTemp.createTempSync('part10_a2a_');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      final DevProjectConfig project = DevProjectConfig(
        appName: 'app_a2a',
        agentName: 'agent_a2a',
        description: 'A2A Testing App',
      );
      final DevAgentRuntime runtime = DevAgentRuntime(
        config: project,
        runner: InMemoryRunner(agent: LlmAgent(name: 'agent_a2a')),
      );
      addTearDown(() => runtime.runner.close());

      final HttpServer server = await startAdkDevWebServer(
        runtime: runtime,
        project: project,
        agentsDir: tempDir.path,
        port: 0,
        a2a: true,
      );
      addTearDown(() => server.close(force: true));

      final HttpClient client = HttpClient();
      addTearDown(client.close);

      // 1. tasks:push_notification_config:get for nonexistent task returns -32004
      HttpClientRequest req = await client.postUrl(
        Uri.parse('http://127.0.0.1:${server.port}/a2a/app_a2a'),
      );
      req.headers.contentType = ContentType.json;
      req.write(
        jsonEncode(<String, Object?>{
          'jsonrpc': '2.0',
          'id': 'rpc_1',
          'method': 'tasks:push_notification_config:get',
          'params': <String, Object?>{'id': 'nonexistent_task'},
        }),
      );
      HttpClientResponse res = await req.close();
      expect(res.statusCode, HttpStatus.ok);
      final String body1 = await utf8.decoder.bind(res).join();
      expect(body1, contains('-32004'));

      // 2. tasks/cancel for nonexistent task returns -32004
      req = await client.postUrl(
        Uri.parse('http://127.0.0.1:${server.port}/a2a/app_a2a'),
      );
      req.headers.contentType = ContentType.json;
      req.write(
        jsonEncode(<String, Object?>{
          'jsonrpc': '2.0',
          'id': 'rpc_2',
          'method': 'tasks/cancel',
          'params': <String, Object?>{'id': 'nonexistent_task'},
        }),
      );
      res = await req.close();
      expect(res.statusCode, HttpStatus.ok);
      final String body2 = await utf8.decoder.bind(res).join();
      expect(body2, contains('-32004'));

      // 3. Invalid A2A params (missing required fields) returns -32602
      req = await client.postUrl(
        Uri.parse('http://127.0.0.1:${server.port}/a2a/app_a2a'),
      );
      req.headers.contentType = ContentType.json;
      req.write(
        jsonEncode(<String, Object?>{
          'jsonrpc': '2.0',
          'id': 'rpc_3',
          'method': 'message/send',
          'params': <String, Object?>{},
        }),
      );
      res = await req.close();
      expect(res.statusCode, HttpStatus.ok);
      final String body3 = await utf8.decoder.bind(res).join();
      expect(body3, contains('-32602'));
    });
  });
}
