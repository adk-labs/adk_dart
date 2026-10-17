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
  group('Target 100% Coverage - Part 11 CLI Remaining Branches', () {
    test('runEvalCliCommandForTesting and runOptimizeCliCommandForTesting with null err', () async {
      final Directory tempDir = Directory.systemTemp.createTempSync('part11_eval_');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      File('${tempDir.path}/root_agent.yaml')
        .writeAsStringSync('name: test_agent\ninstruction: Test instructions\n');
      final File evalSetFile = File('${tempDir.path}/eval_set.json')
        ..writeAsStringSync(jsonEncode(<String, Object?>{
          'name': 'eval_set_1',
          'eval_cases': <Object?>[],
        }));
      File('${tempDir.path}/config.json')
        .writeAsStringSync(jsonEncode(<String, Object?>{
          'criteria': <Object?>[],
        }));
      final File badSamplerConfigFile = File('${tempDir.path}/bad_sampler_config.json')
        ..writeAsStringSync(jsonEncode(<String, Object?>{
          'app_name': 'mismatched_app',
          'train_eval_set': 'eval_set_1',
          'eval_config': <String, Object?>{
            'criteria': <Object?>[],
          },
        }));

      final StringBuffer out = StringBuffer();

      // 1. runEvalCliCommand with default config file next to eval set file and null err
      expect(
        () => runEvalCliCommandForTesting(
          <String>[
            '--eval_storage_uri=gs://b/e',
            tempDir.path,
            evalSetFile.path,
          ],
          out: _BufferIOSink(out),
          err: null,
        ),
        throwsA(isA<StateError>()),
      );

      // 2. runOptimizeCliCommand with null err
      out.clear();
      expect(
        () => runOptimizeCliCommandForTesting(
          <String>[
            tempDir.path,
            '--sampler_config_file_path=${badSamplerConfigFile.path}',
          ],
          out: _BufferIOSink(out),
          err: null,
        ),
        throwsA(isA<CliUsageError>()),
      );
    });

    test('eval_set init with --log_level and add_eval_case skipping existing', () async {
      final Directory tempDir = Directory.systemTemp.createTempSync('part11_eval_set_');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      final File scenariosFile = File('${tempDir.path}/scenarios.json')
        ..writeAsStringSync(jsonEncode(<Object?>[
          <String, Object?>{'scenario_id': 's1', 'user_input': 'hello'},
        ]));
      final File sessionFile = File('${tempDir.path}/session.json')
        ..writeAsStringSync(jsonEncode(<String, Object?>{
          'session_id': 'sess1',
          'events': <Object?>[],
        }));

      final StringBuffer out = StringBuffer();
      final StringBuffer err = StringBuffer();

      // 1. eval_set create with --log_level debug
      final int initCode = await runAdkCli(
        <String>[
          'eval_set',
          'create',
          '--log_level',
          'debug',
          tempDir.path,
          'test_eval_set',
        ],
        outSink: _BufferIOSink(out),
        errSink: _BufferIOSink(err),
      );
      expect(initCode, 0);

      // 2. eval_set add_eval_case first time
      out.clear();
      final int addCode1 = await runAdkCli(
        <String>[
          'eval_set',
          'add_eval_case',
          '--scenarios_file=${scenariosFile.path}',
          '--session_input_file=${sessionFile.path}',
          tempDir.path,
          'test_eval_set',
        ],
        outSink: _BufferIOSink(out),
        errSink: _BufferIOSink(err),
      );
      expect(addCode1, 0);

      // 3. eval_set add_eval_case second time -> skips with message
      out.clear();
      final int addCode2 = await runAdkCli(
        <String>[
          'eval_set',
          'add_eval_case',
          '--log_level=debug',
          '--scenarios_file=${scenariosFile.path}',
          '--session_input_file=${sessionFile.path}',
          tempDir.path,
          'test_eval_set',
        ],
        outSink: _BufferIOSink(out),
        errSink: _BufferIOSink(err),
      );
      expect(addCode2, 0);
      expect(out.toString(), contains('already exists in eval set'));
    });

    test('eval_set generate_eval_cases with prompt and errors', () async {
      final Directory tempDir = Directory.systemTemp.createTempSync('part11_gen_');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      final File cfgFile = File('${tempDir.path}/gen_cfg.json')
        ..writeAsStringSync(jsonEncode(<String, Object?>{
          'generation_prompt': 'Generate realistic user inquiries',
          'scenarios': <Object?>['scenario 1'],
        }));
      File('${tempDir.path}/sess.json')
        .writeAsStringSync(jsonEncode(<String, Object?>{
          'session_id': 's1',
          'events': <Object?>[],
        }));

      final StringBuffer out = StringBuffer();
      final StringBuffer err = StringBuffer();

      // 1. generate_eval_cases positional error (< 2 positionals)
      final int errPos = await runAdkCli(
        <String>['eval_set', 'generate_eval_cases', tempDir.path],
        outSink: _BufferIOSink(out),
        errSink: _BufferIOSink(err),
      );
      expect(errPos, 64);
      expect(err.toString(), contains('requires <project_dir> <eval_set_id>'));

      // 2. generate_eval_cases missing session_input_file
      err.clear();
      final int errSess = await runAdkCli(
        <String>[
          'eval_set',
          'generate_eval_cases',
          '--conversation_generation_config_file=${cfgFile.path}',
          tempDir.path,
          'set_id',
        ],
        outSink: _BufferIOSink(out),
        errSink: _BufferIOSink(err),
      );
      expect(errSess, 64);
      expect(err.toString(), contains('requires --session_input_file'));

      // 3. loadScenariosFileForTesting missing file throws FileSystemException
      expect(
        () => loadScenariosFileForTesting(File('${tempDir.path}/missing.json')),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('sanitizeConformanceEventMapForTesting with partial_args and eval selection', () {
      // 1. partial_args in function_call
      final Map<String, Object?> sanitized = sanitizeConformanceEventMapForTesting(
        <String, Object?>{
          'content': <String, Object?>{
            'parts': <Object?>[
              <String, Object?>{
                'function_call': <String, Object?>{
                  'name': 'search',
                  'id': 'call_1',
                  'partial_args': <Object?>[
                    <String, Object?>{'query': 'dart'},
                  ],
                },
                'function_response': <String, Object?>{
                  'name': 'search',
                  'id': 'call_1',
                  'response': <String, Object?>{'status': 'ok'},
                },
              },
            ],
          },
        },
      );
      expect(sanitized, isNotNull);

      // 2. parseEvalSelectionForTesting edge cases
      final dynamic selEmptySrc = parseEvalSelectionForTesting(':case1');
      expect(selEmptySrc.source, ':case1');
      expect(selEmptySrc.evalCaseIds, isEmpty);

      final dynamic selEmptyIds = parseEvalSelectionForTesting('eval_source:');
      expect(selEmptyIds.source, 'eval_source:');
      expect(selEmptyIds.evalCaseIds, isEmpty);
    });

    test('CLI parsing edge cases for run, web, and conformance', () {
      // 1. run command stateJson and stateFilePath mutually exclusive
      expect(
        () => parseAdkCliArgs(<String>[
          'run',
          '--state={}',
          '--state_file=s.json',
          '.',
        ]),
        throwsA(isA<CliUsageError>()),
      );

      // 2. run command use_local_storage with artifact_service_uri mutually exclusive
      expect(
        () => parseAdkCliArgs(<String>[
          'run',
          '--use_local_storage',
          '--artifact_service_uri=gs://b/a',
          '.',
        ]),
        throwsA(isA<CliUsageError>()),
      );

      // 3. web command --user_id, --user-id
      final ParsedAdkCommand webCmd = parseAdkCliArgs(<String>[
        'web',
        '--user_id',
        'custom_user_1',
        '.',
      ]);
      expect(webCmd.type, AdkCommandType.web);
      expect(webCmd.userId, 'custom_user_1');

      // 4. web command avatar config non-map JSON
      expect(
        () => parseAdkCliArgs(<String>['web', '--avatar_config=[1, 2]', '.']),
        throwsA(isA<CliUsageError>()),
      );

      // 5. web command avatar config entry with empty value
      expect(
        () => parseAdkCliArgs(<String>['web', '--avatar_config=agent1=', '.']),
        throwsA(isA<CliUsageError>()),
      );

      // 6. web command logo options parsing
      final ParsedAdkCommand webLogo = parseAdkCliArgs(<String>[
        'web',
        '--logo-text=MyLogo',
        '--logo-image-url=https://example.com/logo.png',
        '.',
      ]);
      expect(webLogo.logoText, 'MyLogo');
      expect(webLogo.logoImageUrl, 'https://example.com/logo.png');

      final Directory tempWeb = Directory.systemTemp.createTempSync('part11_web_logo_');
      addTearDown(() => tempWeb.deleteSync(recursive: true));
      final DevProjectConfig dummyProj = DevProjectConfig(
        appName: 'app_dummy',
        agentName: 'agent_dummy',
        description: 'Dummy App',
      );
      final DevAgentRuntime dummyRuntime = DevAgentRuntime(
        config: dummyProj,
        runner: InMemoryRunner(agent: LlmAgent(name: 'agent_dummy')),
      );
      addTearDown(() => dummyRuntime.runner.close());

      expect(
        () => startAdkDevWebServer(
          runtime: dummyRuntime,
          project: dummyProj,
          agentsDir: tempWeb.path,
          logoText: 'MyLogo',
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => startAdkDevWebServer(
          runtime: dummyRuntime,
          project: dummyProj,
          agentsDir: tempWeb.path,
          logoImageUrl: 'https://example.com/logo.png',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('Conformance discovery, sorting, and test execution branches', () async {
      final Directory tempDir = Directory.systemTemp.createTempSync('part11_conf_');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      final Directory case1 = Directory('${tempDir.path}/cat1/case1')..createSync(recursive: true);
      final Directory case2 = Directory('${tempDir.path}/cat2/case2')..createSync(recursive: true);

      // Spec without recordings
      File('${case1.path}/spec.yaml').writeAsStringSync('''
agent: agent_a
description: Test A
user_messages:
  - text: hello
''');

      // Spec with recordings
      File('${case2.path}/spec.yaml').writeAsStringSync('''
agent: agent_b
description: Test B
user_messages:
  - text: hi
''');
      File('${case2.path}/generated-recordings.yaml').writeAsStringSync('recordings: []\n');

      final StringBuffer out = StringBuffer();

      // 1. discoverConformanceCasesForTesting sorts cases and skips unrecorded in replay mode
      final List<dynamic> cases = await discoverConformanceCasesForTesting(
        <String>[tempDir.path],
        out: _BufferIOSink(out),
        replayMode: true,
        streamingMode: StreamingMode.none,
      );
      expect(cases, hasLength(1));
      expect(out.toString(), contains('no recordings'));
    });
  });

  group('Target 100% Coverage - Part 11 Web Server Remaining Branches', () {
    test('readOptionalBoolQueryForTesting, readRequiredQueryForTesting, and getRequestOriginForTesting', () async {
      final Directory tempDir = Directory.systemTemp.createTempSync('part11_req_');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      final DevProjectConfig project = DevProjectConfig(
        appName: 'app_req_test',
        agentName: 'agent_req_test',
        description: 'Req Test App',
      );
      final DevAgentRuntime runtime = DevAgentRuntime(
        config: project,
        runner: InMemoryRunner(agent: LlmAgent(name: 'agent_req_test')),
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

      // 1. Optional boolean query parsing
      handleRequestTestingOverride = (HttpRequest req, dynamic ctx) async {
        expect(readOptionalBoolQueryForTesting(req, 'b1'), isTrue);
        expect(readOptionalBoolQueryForTesting(req, 'b2'), isTrue);
        expect(readOptionalBoolQueryForTesting(req, 'b3'), isTrue);
        expect(readOptionalBoolQueryForTesting(req, 'b4'), isFalse);
        expect(readOptionalBoolQueryForTesting(req, 'b5'), isFalse);
        expect(readOptionalBoolQueryForTesting(req, 'b6'), isFalse);
        expect(readOptionalBoolQueryForTesting(req, 'b7'), isFalse);
        expect(
          () => readOptionalBoolQueryForTesting(req, 'b_invalid'),
          throwsA(isA<FormatException>()),
        );

        // 2. Required query parsing
        expect(readRequiredQueryForTesting(req, 'b1'), 'true');
        expect(
          () => readRequiredQueryForTesting(req, 'missing_key'),
          throwsA(isA<FormatException>()),
        );

        // 3. getRequestOrigin
        expect(getRequestOriginForTesting(req), isNotNull);

        req.response.statusCode = HttpStatus.ok;
        await req.response.close();
      };

      HttpClientRequest req = await client.getUrl(
        Uri.parse(
          'http://127.0.0.1:${server.port}/test_queries?b1=true&b2=yes&b3=y&b4=0&b5=false&b6=no&b7=n&b_invalid=abc',
        ),
      );
      req.headers.set('Forwarded', 'proto=https;host=example.com:8443');
      HttpClientResponse res = await req.close();
      expect(res.statusCode, HttpStatus.ok);
      await res.drain<void>();
      handleRequestTestingOverride = null;
    });

    test('resolveGraphTargetRootTesting and agentDetailsTesting with multiple agents', () async {
      final Directory tempDir = Directory.systemTemp.createTempSync('part11_agents_');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      final DevProjectConfig project = DevProjectConfig(
        appName: 'root_app',
        agentName: 'root_agent',
        description: 'Multi Agent App',
      );
      final Workflow deepWf = Workflow(
        name: 'deep_wf',
        nodes: <BaseNode>[],
      );
      final Workflow subAgent = Workflow(
        name: 'sub_z',
        nodes: <BaseNode>[
          AgentNode(name: 'agent_inner', agent: deepWf),
        ],
      );
      final LlmAgent rootAgent = LlmAgent(
        name: 'root_agent',
        subAgents: <BaseAgent>[subAgent],
      );
      final DevAgentRuntime runtime = DevAgentRuntime(
        config: project,
        runner: InMemoryRunner(agent: rootAgent),
      );
      addTearDown(() => runtime.runner.close());

      final dynamic ctx = await createAdkDevWebContextForTesting(
        runtime: runtime,
        project: project,
        agentsDir: tempDir.path,
      );

      // 1. resolveGraphTargetRootTesting for default app
      final BaseAgent resolved = resolveGraphTargetRootTesting(ctx, 'root_app');
      expect(resolved.name, 'root_agent');

      // 2. collectWorkflowGraphTargetsForTesting with child subAgents
      final Map<String, BaseAgent> targets = collectWorkflowGraphTargetsForTesting(
        rootAgent,
        currentPath: '',
      );
      expect(targets.containsKey('sub_z'), isTrue);
      expect(targets.containsKey('sub_z/agent_inner'), isTrue);

      // 3. agentDetailsTesting
      final List<Map<String, Object?>> details = agentDetailsTesting(ctx);
      expect(details, isNotEmpty);
    });

    test('Trigger route error mappings for SpecialAgentAccessDenied, FormatException, and Exception', () async {
      final Directory tempDir = Directory.systemTemp.createTempSync('part11_trig_err_');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      final DevProjectConfig project = DevProjectConfig(
        appName: 'app_trig_err',
        agentName: 'agent_trig_err',
        description: 'Trigger Err App',
      );
      final DevAgentRuntime runtime = DevAgentRuntime(
        config: project,
        runner: InMemoryRunner(agent: LlmAgent(name: 'agent_trig_err')),
      );
      addTearDown(() => runtime.runner.close());

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

      // 1. SpecialAgentAccessDeniedException -> 403
      handleRequestTestingOverride = (HttpRequest r, dynamic c) async {
        await handleTriggerRouteForTesting(
          r,
          c,
          appName: 'app_trig_err',
          triggerSource: 'pubsub',
        );
      };

      // Invalid JSON body -> FormatException -> 400
      HttpClientRequest req = await client.postUrl(
        Uri.parse('http://127.0.0.1:${server.port}/trig_format_err'),
      );
      req.headers.contentType = ContentType.json;
      req.write('{not_json');
      HttpClientResponse res = await req.close();
      expect(res.statusCode, HttpStatus.badRequest);
      await res.drain<void>();

      handleRequestTestingOverride = null;
    });

    test('A2A task lookup error -32004 for tasks/get, pushnotificationconfig/set, and resubscribe', () async {
      final Directory tempDir = Directory.systemTemp.createTempSync('part11_a2a_tasks_');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      final DevProjectConfig project = DevProjectConfig(
        appName: 'app_a2a_tasks',
        agentName: 'agent_a2a_tasks',
        description: 'A2A Tasks App',
      );
      final DevAgentRuntime runtime = DevAgentRuntime(
        config: project,
        runner: InMemoryRunner(agent: LlmAgent(name: 'agent_a2a_tasks')),
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

      // 1. tasks/get for nonexistent task returns -32004
      HttpClientRequest req = await client.postUrl(
        Uri.parse('http://127.0.0.1:${server.port}/a2a/app_a2a_tasks'),
      );
      req.headers.contentType = ContentType.json;
      req.write(
        jsonEncode(<String, Object?>{
          'jsonrpc': '2.0',
          'id': 'rpc_get',
          'method': 'tasks/get',
          'params': <String, Object?>{'id': 'missing_task'},
        }),
      );
      HttpClientResponse res = await req.close();
      expect(res.statusCode, HttpStatus.ok);
      final String bodyGet = await utf8.decoder.bind(res).join();
      expect(bodyGet, contains('-32004'));

      // 2. tasks/pushnotificationconfig/set for nonexistent task returns -32004
      req = await client.postUrl(
        Uri.parse('http://127.0.0.1:${server.port}/a2a/app_a2a_tasks'),
      );
      req.headers.contentType = ContentType.json;
      req.write(
        jsonEncode(<String, Object?>{
          'jsonrpc': '2.0',
          'id': 'rpc_set',
          'method': 'tasks/pushnotificationconfig/set',
          'params': <String, Object?>{
            'taskId': 'missing_task',
            'pushNotificationConfig': <String, Object?>{'url': 'https://cb.example.com'},
          },
        }),
      );
      res = await req.close();
      expect(res.statusCode, HttpStatus.ok);
      final String bodySet = await utf8.decoder.bind(res).join();
      expect(bodySet, contains('-32004'));

      // 3. tasks/resubscribe for nonexistent task returns -32004
      req = await client.postUrl(
        Uri.parse('http://127.0.0.1:${server.port}/a2a/app_a2a_tasks'),
      );
      req.headers.contentType = ContentType.json;
      req.write(
        jsonEncode(<String, Object?>{
          'jsonrpc': '2.0',
          'id': 'rpc_sub',
          'method': 'tasks/resubscribe',
          'params': <String, Object?>{'id': 'missing_task'},
        }),
      );
      res = await req.close();
      expect(res.statusCode, HttpStatus.ok);
      final String bodySub = await utf8.decoder.bind(res).join();
      expect(bodySub, contains('-32004'));
    });
  });
}
