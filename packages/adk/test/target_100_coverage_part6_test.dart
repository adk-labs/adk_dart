import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:adk/adk.dart';
import 'package:adk/src/dev/cli.dart';
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

class _Part6StubModel extends BaseLlm {
  _Part6StubModel() : super(model: 'part6-stub-model');

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    yield LlmResponse(content: Content.modelText('part6 stub response'));
  }
}

void main() {
  setUpAll(() {
    LLMRegistry.register(
      supportedModels: <RegExp>[
        RegExp(r'^part6-stub-model$'),
        RegExp(r'^gemini-2\.5-flash$'),
      ],
      factory: (String m) => _Part6StubModel(),
    );
  });

  group('Part 6 Coverage: CLI command parsing, validation & subcommands', () {
    test('test command with --rebuild, agent flag and extra runner args', () async {
      final Directory tempDir = Directory.systemTemp.createTempSync('cli_test_cmd_');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      await createDevProject(projectDirPath: tempDir.path);
      File('${tempDir.path}${Platform.pathSeparator}pubspec.yaml').writeAsStringSync('''
name: test_agent_pkg
environment:
  sdk: '>=3.0.0 <4.0.0'
''');

      final _CaptureSink out = _CaptureSink();
      final int code = await runAdkCli(
        <String>[
          'test',
          tempDir.path,
          '--rebuild',
          '--agent=root_agent',
          '--name',
          'nonexistent_pattern',
        ],
        outSink: out.sink,
      );
      final String text = await out.closeAndRead();
      expect(text, contains('Rebuilding agent project at'));
      expect(code, anyOf(0, 1, 65));
    });

    test('eval command flag variants, validations and errors', () async {
      final Directory tempDir = Directory.systemTemp.createTempSync('cli_eval_cmd_');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      await createDevProject(projectDirPath: tempDir.path);

      // 1. Unknown option -> CliUsageError (64)
      final _CaptureSink err1 = _CaptureSink();
      final int code1 = await runAdkCli(
        <String>['eval', tempDir.path, '--unknown_flag'],
        errSink: err1.sink,
      );
      expect(code1, 64);
      final String text1 = await err1.closeAndRead();
      expect(text1, contains('Unknown option for eval: --unknown_flag'));

      // 2. Empty eval selection -> error (64)
      final _CaptureSink err2 = _CaptureSink();
      final int code2 = await runAdkCli(
        <String>['eval', tempDir.path, ''],
        errSink: err2.sink,
      );
      expect(code2, 64);
      final String text2 = await err2.closeAndRead();
      expect(text2, contains('Empty eval set target is not allowed.'));

      // 3. Eval set not found -> StateError caught by eval handler (exit code 1)
      final _CaptureSink err3 = _CaptureSink();
      final int code3 = await runAdkCli(
        <String>['eval', tempDir.path, 'nonexistent_eval_set'],
        errSink: err3.sink,
      );
      expect(code3, 1);
      final String text3 = await err3.closeAndRead();
      expect(text3, contains('Runtime error: Bad state: Eval set `nonexistent_eval_set` not found.'));

      // 4. File-based eval target that does not exist -> FileSystemException/CliUsageError
      final _CaptureSink err4 = _CaptureSink();
      final int code4 = await runAdkCli(
        <String>['eval', tempDir.path, '${tempDir.path}${Platform.pathSeparator}missing_set.eval_set.json'],
        errSink: err4.sink,
      );
      expect(code4, anyOf(1, 64));
      await err4.closeAndRead();

      // 5. Config file path variants (--config_file_path <path>, --config_file_path=<path>)
      final File evalSetFile = File('${tempDir.path}${Platform.pathSeparator}valid_set.eval_set.json');
      evalSetFile.writeAsStringSync(jsonEncode(<String, Object?>{
        'eval_set_id': 'valid_set',
        'eval_cases': <Map<String, Object?>>[
          <String, Object?>{
            'eval_id': 'c1',
            'conversation': <Map<String, Object?>>[
              <String, Object?>{
                'user_content': <String, Object?>{
                  'parts': <Map<String, Object?>>[<String, Object?>{'text': 'hi'}]
                }
              }
            ]
          }
        ]
      }));

      final File dummyConfigFile = File('${tempDir.path}${Platform.pathSeparator}dummy_eval_config.json');
      dummyConfigFile.writeAsStringSync('{"invalid json": ');
      final _CaptureSink err5 = _CaptureSink();
      final int code5 = await runAdkCli(
        <String>[
          'eval',
          tempDir.path,
          evalSetFile.path,
          '--config_file_path',
          dummyConfigFile.path,
        ],
        errSink: err5.sink,
      );
      expect(code5, 1);
      final String text5 = await err5.closeAndRead();
      expect(text5, contains('Config parse error:'));

      // 6. Test flag variants with separated and inline syntax
      final _CaptureSink err6 = _CaptureSink();
      final int code6 = await runAdkCli(
        <String>[
          'eval',
          tempDir.path,
          '--config_file_path=${dummyConfigFile.path}',
          '--eval_storage_uri',
          'gs://my-bucket',
          '--eval_storage_uri=gs://my-bucket',
          '--log_level',
          'INFO',
          '--log_level=WARNING',
          '--enable_features',
          'JSON_SCHEMA_FOR_FUNC_DECL',
          '--enable_features=JSON_SCHEMA_FOR_FUNC_DECL',
          '--disable_features',
          'CLASSIFIER',
          '--disable_features=CLASSIFIER',
          evalSetFile.path,
        ],
        errSink: err6.sink,
      );
      expect(code6, 1);
      await err6.closeAndRead();
    });

    test('eval_set subcommand validations and execution', () async {
      final Directory tempDir = Directory.systemTemp.createTempSync('cli_eval_set_cmd_');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      await createDevProject(projectDirPath: tempDir.path);

      // 1. Unknown eval_set subcommand -> 64
      final _CaptureSink err1 = _CaptureSink();
      final int code1 = await runAdkCli(
        <String>['eval_set', 'unknown_sub', tempDir.path],
        errSink: err1.sink,
      );
      expect(code1, 64);
      final String text1 = await err1.closeAndRead();
      expect(text1, contains('Unknown eval_set subcommand: unknown_sub'));

      // 2. create: missing name -> 64
      final _CaptureSink err2 = _CaptureSink();
      final int code2 = await runAdkCli(
        <String>['eval_set', 'create', tempDir.path],
        errSink: err2.sink,
      );
      expect(code2, 64);
      final String text2 = await err2.closeAndRead();
      expect(text2, contains('eval_set create requires <project_dir> <eval_set_id>.'));

      // 3. create: unknown option -> 64
      final _CaptureSink err3 = _CaptureSink();
      final int code3 = await runAdkCli(
        <String>['eval_set', 'create', tempDir.path, 'set_1', '--bad_opt'],
        errSink: err3.sink,
      );
      expect(code3, 64);
      final String text3 = await err3.closeAndRead();
      expect(text3, contains('Unknown option for eval_set create: --bad_opt'));

      // 4. create: success with flag variants
      final int code4 = await runAdkCli(
        <String>[
          'eval_set',
          'create',
          tempDir.path,
          'set_alpha',
          '--log_level',
          'DEBUG',
          '--log_level=INFO',
        ],
      );
      expect(code4, 0);

      // 5. add_eval_case: unknown option -> 64
      final _CaptureSink err5 = _CaptureSink();
      final int code5 = await runAdkCli(
        <String>['eval_set', 'add_eval_case', tempDir.path, 'set_alpha', '--bad_flag'],
        errSink: err5.sink,
      );
      expect(code5, 64);
      final String text5 = await err5.closeAndRead();
      expect(text5, contains('Unknown option for eval_set add_eval_case: --bad_flag'));

      // 6. add_eval_case: missing eval set id -> 64
      final _CaptureSink err6 = _CaptureSink();
      final int code6 = await runAdkCli(
        <String>['eval_set', 'add_eval_case', tempDir.path],
        errSink: err6.sink,
      );
      expect(code6, 64);
      final String text6 = await err6.closeAndRead();
      expect(text6, contains('eval_set add_eval_case requires <project_dir> <eval_set_id>.'));

      // 7. add_eval_case: missing scenarios file -> 64
      final _CaptureSink err7 = _CaptureSink();
      final int code7 = await runAdkCli(
        <String>['eval_set', 'add_eval_case', tempDir.path, 'set_alpha'],
        errSink: err7.sink,
      );
      expect(code7, 64);
      final String text7 = await err7.closeAndRead();
      expect(text7, contains('eval_set add_eval_case requires --scenarios_file.'));

      // 8. generate_eval_cases: unknown option -> 64
      final _CaptureSink err8 = _CaptureSink();
      final int code8 = await runAdkCli(
        <String>['eval_set', 'generate_eval_cases', tempDir.path, 'set_alpha', '--unknown'],
        errSink: err8.sink,
      );
      expect(code8, 64);
      final String text8 = await err8.closeAndRead();
      expect(text8, contains('Unknown option for eval_set generate_eval_cases: --unknown'));

      // 9. generate_eval_cases: invalid repeat_num -> 64
      final _CaptureSink err9 = _CaptureSink();
      final int code9 = await runAdkCli(
        <String>[
          'eval_set',
          'generate_eval_cases',
          tempDir.path,
          'set_alpha',
          '--repeat_num',
          'not_a_number',
        ],
        errSink: err9.sink,
      );
      expect(code9, 64);
      final String text9 = await err9.closeAndRead();
      expect(text9, contains('Invalid value for --repeat_num: not_a_number'));

      // inline --repeat_num=0 -> 64
      final _CaptureSink err9b = _CaptureSink();
      final int code9b = await runAdkCli(
        <String>[
          'eval_set',
          'generate_eval_cases',
          tempDir.path,
          'set_alpha',
          '--repeat_num=0',
        ],
        errSink: err9b.sink,
      );
      expect(code9b, 64);
      final String text9b = await err9b.closeAndRead();
      expect(text9b, contains('Invalid value for --repeat_num: 0'));

      // 10. generate_eval_cases: missing prompt / conversation config -> 64
      final _CaptureSink err10 = _CaptureSink();
      final int code10 = await runAdkCli(
        <String>[
          'eval_set',
          'generate_eval_cases',
          tempDir.path,
          'set_alpha',
          '--eval_storage_uri',
          tempDir.path,
          '--eval_storage_uri=${tempDir.path}',
          '--log_level',
          'INFO',
        ],
        errSink: err10.sink,
      );
      expect(code10, 64);
      final String text10 = await err10.closeAndRead();
      expect(text10, contains('eval_set generate_eval_cases requires --conversation_generation_config_file.'));
    });

    test('migrate subcommand validations and session upgrade', () async {
      // 1. Unknown migrate subcommand -> 64
      final _CaptureSink err1 = _CaptureSink();
      final int code1 = await runAdkCli(
        <String>['migrate', 'unknown_migration'],
        errSink: err1.sink,
      );
      expect(code1, 64);
      final String text1 = await err1.closeAndRead();
      expect(text1, contains('Unknown migrate subcommand: unknown_migration'));

      // 2. migrate session: missing --source_db_url -> 64
      final _CaptureSink err2 = _CaptureSink();
      final int code2 = await runAdkCli(
        <String>['migrate', 'session'],
        errSink: err2.sink,
      );
      expect(code2, 64);
      final String text2 = await err2.closeAndRead();
      expect(text2, contains('Missing required option --source_db_url.'));

      // 3. migrate session: unknown option -> 64
      final _CaptureSink err3 = _CaptureSink();
      final int code3 = await runAdkCli(
        <String>['migrate', 'session', '--source_db_url=sqlite:///:memory:', '--bogus'],
        errSink: err3.sink,
      );
      expect(code3, 64);
      final String text3 = await err3.closeAndRead();
      expect(text3, contains('Unknown option for migrate session: --bogus'));

      // 4. migrate session: unexpected positional arg -> 64
      final _CaptureSink err4 = _CaptureSink();
      final int code4 = await runAdkCli(
        <String>['migrate', 'session', '--source_db_url=sqlite:///:memory:', 'extra_arg'],
        errSink: err4.sink,
      );
      expect(code4, 64);
      final String text4 = await err4.closeAndRead();
      expect(text4, contains('Unexpected positional argument for migrate session: extra_arg'));

      // 5. migrate session with flag variants and valid in-memory sqlite db url
      final Directory tempDir = Directory.systemTemp.createTempSync('migrate_db_');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      final String dbPath = '${tempDir.path}${Platform.pathSeparator}sessions.db';
      final String dbUri = 'sqlite://$dbPath';
      final String destDbPath = '${tempDir.path}${Platform.pathSeparator}dest_sessions.db';
      final String destDbUri = 'sqlite://$destDbPath';

      final _CaptureSink out5 = _CaptureSink();
      final int code5 = await runAdkCli(
        <String>[
          'migrate',
          'session',
          '--source_db_url',
          dbUri,
          '--source_db_url=$dbUri',
          '--dest_db_url',
          destDbUri,
          '--dest_db_url=$destDbUri',
          '--log_level',
          'INFO',
          '--log_level=WARNING',
          '--verbose',
          '-v',
          '--allow_unsafe_unpickling',
          '--allow-unsafe-unpickling',
        ],
        outSink: out5.sink,
      );
      expect(code5, 0);
      final String text5 = await out5.closeAndRead();
      expect(text5, contains('Migration check and upgrade process finished.'));
    });

    test('optimize subcommand validations and execution', () async {
      final Directory tempDir = Directory.systemTemp.createTempSync('cli_opt_cmd_');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      await createDevProject(projectDirPath: tempDir.path);

      // 1. Missing --sampler_config_file_path -> 64
      final _CaptureSink err1 = _CaptureSink();
      final int code1 = await runAdkCli(
        <String>['optimize', tempDir.path],
        errSink: err1.sink,
      );
      expect(code1, 64);
      final String text1 = await err1.closeAndRead();
      expect(text1, contains('Missing required option --sampler_config_file_path.'));

      // 2. Unknown option -> 64
      final _CaptureSink err2 = _CaptureSink();
      final int code2 = await runAdkCli(
        <String>[
          'optimize',
          tempDir.path,
          '--sampler_config_file_path=dummy.json',
          '--bad_opt',
        ],
        errSink: err2.sink,
      );
      expect(code2, 64);
      final String text2 = await err2.closeAndRead();
      expect(text2, contains('Unknown option for optimize: --bad_opt'));

      // 3. Multiple agent paths -> 64
      final _CaptureSink err3 = _CaptureSink();
      final int code3 = await runAdkCli(
        <String>[
          'optimize',
          tempDir.path,
          tempDir.path,
          '--sampler_config_file_path=dummy.json',
        ],
        errSink: err3.sink,
      );
      expect(code3, 64);
      final String text3 = await err3.closeAndRead();
      expect(text3, contains('optimize accepts only one agent directory path.'));

      // 4. App name mismatch -> 64
      final File samplerConfigFile = File('${tempDir.path}${Platform.pathSeparator}sampler_config.json');
      samplerConfigFile.writeAsStringSync(jsonEncode(<String, Object?>{
        'app_name': 'mismatched_app_name',
        'eval_dataset_file_path': 'dataset.json',
      }));

      final _CaptureSink err4 = _CaptureSink();
      final int code4 = await runAdkCli(
        <String>[
          'optimize',
          tempDir.path,
          '--sampler_config_file_path',
          samplerConfigFile.path,
          '--sampler_config_file_path=${samplerConfigFile.path}',
          '--optimizer_config_file_path',
          samplerConfigFile.path,
          '--optimizer_config_file_path=${samplerConfigFile.path}',
          '--log_level',
          'INFO',
          '--log_level=DEBUG',
          '--enable_features',
          'CLASSIFIER',
          '--enable_features=CLASSIFIER',
          '--disable_features',
          'CLASSIFIER',
          '--disable_features=CLASSIFIER',
        ],
        errSink: err4.sink,
      );
      expect(code4, 64);
      final String text4 = await err4.closeAndRead();
      expect(text4, contains('does not match the app name in the sampler config file'));
    });

    test('conformance subcommand validations, unsupported modes and mismatch formatting', () async {
      // 1. Unknown conformance subcommand -> 64
      final _CaptureSink err1 = _CaptureSink();
      final int code1 = await runAdkCli(
        <String>['conformance', 'invalid_sub'],
        errSink: err1.sink,
      );
      expect(code1, 64);
      final String text1 = await err1.closeAndRead();
      expect(text1, contains('Unknown conformance subcommand: invalid_sub'));

      // 2. Empty directory test -> 'No test specs found to process.'
      final Directory emptySpecsDir = Directory.systemTemp.createTempSync('conformance_empty_');
      addTearDown(() => emptySpecsDir.deleteSync(recursive: true));

      final _CaptureSink out2 = _CaptureSink();
      final int code2 = await runAdkCli(
        <String>['conformance', 'record', emptySpecsDir.path],
        outSink: out2.sink,
      );
      expect(code2, 0);
      final String text2 = await out2.closeAndRead();
      expect(text2, contains('No test specs found to process.'));

      // 3. Conformance test with unsupported mode -> FAIL
      final Directory testCaseDir = Directory('${emptySpecsDir.path}${Platform.pathSeparator}core${Platform.pathSeparator}dummy_case');
      testCaseDir.createSync(recursive: true);
      File('${testCaseDir.path}${Platform.pathSeparator}test-spec.yaml').writeAsStringSync('''
agent: test_agent
description: dummy test
user_messages:
  - content:
      parts:
        - text: hello
''');
      File('${testCaseDir.path}${Platform.pathSeparator}recorded-session.yaml').writeAsStringSync('''
events: []
''');

      final _CaptureSink err3 = _CaptureSink();
      final int code3 = await runAdkCli(
        <String>[
          'conformance',
          'test',
          emptySpecsDir.path,
          '--mode',
          'unsupported_mode',
          '--report_dir',
          emptySpecsDir.path,
        ],
        errSink: err3.sink,
      );
      expect(code3, 64);
      final String text3 = await err3.closeAndRead();
      expect(text3, contains('Invalid conformance mode: unsupported_mode'));
    });

    test('run command flag variations and validations', () async {
      final Directory tempDir = Directory.systemTemp.createTempSync('cli_run_edge_');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      await createDevProject(projectDirPath: tempDir.path);

      // 1. Missing replay file -> FileSystemException (exit code 1)
      final _CaptureSink err1 = _CaptureSink();
      final int code1 = await runAdkCli(
        <String>[
          'run',
          tempDir.path,
          '--replay',
          '${tempDir.path}${Platform.pathSeparator}nonexistent_replay.json',
        ],
        errSink: err1.sink,
      );
      expect(code1, 1);
      final String text1 = await err1.closeAndRead();
      expect(text1, contains('Replay file not found.'));

      // 2. Missing resume file -> FileSystemException (exit code 1)
      final _CaptureSink err2 = _CaptureSink();
      final int code2 = await runAdkCli(
        <String>[
          'run',
          tempDir.path,
          '--resume',
          '${tempDir.path}${Platform.pathSeparator}nonexistent_resume.json',
        ],
        errSink: err2.sink,
      );
      expect(code2, 1);
      final String text2 = await err2.closeAndRead();
      expect(text2, contains('Resume file not found.'));

      // 3. Flags: --timeout, --in_memory, --jsonl
      final _CaptureSink out3 = _CaptureSink();
      final int code3 = await runAdkCli(
        <String>[
          'run',
          tempDir.path,
          '--in_memory',
          '--timeout',
          '5s',
          '--jsonl',
          '--message',
          'ping',
        ],
        outSink: out3.sink,
      );
      expect(code3, 0);
      final String text3 = await out3.closeAndRead();
      expect(text3, contains('"author"'));

      // 4. Interactive exit / quit
      final _CaptureSink out4 = _CaptureSink();
      final int code4 = await runAdkCli(
        <String>['run', tempDir.path],
        readLine: () => 'exit',
        outSink: out4.sink,
      );
      expect(code4, 0);

      final _CaptureSink out5 = _CaptureSink();
      final int code5 = await runAdkCli(
        <String>['run', tempDir.path],
        readLine: () => 'quit',
        outSink: out5.sink,
      );
      expect(code5, 0);
    });

    test('web and api_server option parsing and validation errors', () async {
      final Directory tempDir = Directory.systemTemp.createTempSync('cli_web_opts_');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      await createDevProject(projectDirPath: tempDir.path);

      // 1. Unknown option for web -> 64
      final _CaptureSink err1 = _CaptureSink();
      final int code1 = await runAdkCli(
        <String>['web', tempDir.path, '--bogus_option'],
        errSink: err1.sink,
      );
      expect(code1, 64);
      final String text1 = await err1.closeAndRead();
      expect(text1, contains('Unknown option for web: --bogus_option'));

      // 2. Multiple project directories for web -> 64
      final _CaptureSink err2 = _CaptureSink();
      final int code2 = await runAdkCli(
        <String>['web', tempDir.path, tempDir.path],
        errSink: err2.sink,
      );
      expect(code2, 64);
      final String text2 = await err2.closeAndRead();
      expect(text2, contains('web accepts only one project directory.'));

      // 3. Invalid host -> 64
      final _CaptureSink err3 = _CaptureSink();
      final int code3 = await runAdkCli(
        <String>['web', tempDir.path, '--host', '999.999.999.999'],
        errSink: err3.sink,
      );
      expect(code3, 64);
      final String text3 = await err3.closeAndRead();
      expect(text3, contains('Invalid host: 999.999.999.999'));

      // 4. Invalid url_prefix -> 64
      final _CaptureSink err4 = _CaptureSink();
      final int code4 = await runAdkCli(
        <String>['web', tempDir.path, '--url_prefix', 'no_leading_slash'],
        errSink: err4.sink,
      );
      expect(code4, 64);
      final String text4 = await err4.closeAndRead();
      expect(text4, contains('url_prefix must start with "/": no_leading_slash'));

      // 5. Invalid max_llm_calls -> 64
      final _CaptureSink err5 = _CaptureSink();
      final int code5 = await runAdkCli(
        <String>['web', tempDir.path, '--max_llm_calls', 'not_a_number'],
        errSink: err5.sink,
      );
      expect(code5, 64);
      final String text5 = await err5.closeAndRead();
      expect(text5, contains('Invalid value for --max_llm_calls: not_a_number'));

      // 6. Invalid trigger source -> 64
      final _CaptureSink err6 = _CaptureSink();
      final int code6 = await runAdkCli(
        <String>['web', tempDir.path, '--trigger_sources', 'invalid_source'],
        errSink: err6.sink,
      );
      expect(code6, 64);
      final String text6 = await err6.closeAndRead();
      expect(text6, contains('Invalid trigger source "invalid_source". Supported: pubsub, eventarc.'));

      // 7. Invalid avatar_config entry -> 64
      final _CaptureSink err7 = _CaptureSink();
      final int code7 = await runAdkCli(
        <String>['web', tempDir.path, '--avatar_config', 'invalid_entry_without_colon'],
        errSink: err7.sink,
      );
      expect(code7, 64);
      final String text7 = await err7.closeAndRead();
      expect(text7, contains('Invalid --avatar_config entry: invalid_entry_without_colon'));

      // 8. Missing value for option -> 64
      final _CaptureSink err8 = _CaptureSink();
      final int code8 = await runAdkCli(
        <String>['web', tempDir.path, '--port'],
        errSink: err8.sink,
      );
      expect(code8, 64);
      final String text8 = await err8.closeAndRead();
      expect(text8, contains('Missing value for --port'));

      // 9. Deprecated flags warnings: --session_db_url and --artifact_storage_uri
      final _CaptureSink err9 = _CaptureSink();
      final _CaptureSink out9 = _CaptureSink();
      final int code9 = await runAdkCli(
        <String>[
          'web',
          tempDir.path,
          '--port',
          '0',
          '--session_db_url',
          'sqlite:///:memory:',
          '--artifact_storage_uri',
          'memory://',
        ],
        outSink: out9.sink,
        errSink: err9.sink,
        stopSignal: Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      expect(code9, 0);
      final String text9 = await err9.closeAndRead();
      expect(text9, contains('WARNING: Deprecated option --session_db_url is used.'));
      expect(text9, contains('WARNING: Deprecated option --artifact_storage_uri is used.'));
    });

    test('top-level CLI commands: missing command, telemetry, doctor, and test passthrough', () async {
      // 1. Missing command in parseAdkCliArgs -> throws CliUsageError
      expect(() => parseAdkCliArgs(<String>[]), throwsA(isA<CliUsageError>()));
      expect(CliUsageError('test msg').toString(), 'test msg');

      // Empty args to runAdkCli prints usage and returns 0
      final _CaptureSink outEmpty = _CaptureSink();
      final int codeEmpty = await runAdkCli(<String>[], outSink: outEmpty.sink);
      expect(codeEmpty, 0);
      expect(await outEmpty.closeAndRead(), contains('Agent Development Kit CLI tools.'));

      // 2. Telemetry status, enable, disable, and unknown
      final _CaptureSink outTelem1 = _CaptureSink();
      final int codeTelem1 = await runAdkCli(
        <String>['telemetry'],
        outSink: outTelem1.sink,
      );
      expect(codeTelem1, 0);

      final _CaptureSink outTelem2 = _CaptureSink();
      final int codeTelem2 = await runAdkCli(
        <String>['telemetry', 'enable'],
        outSink: outTelem2.sink,
      );
      expect(codeTelem2, 0);
      expect(await outTelem2.closeAndRead(), contains('Telemetry collection has been enabled.'));

      final _CaptureSink outTelem3 = _CaptureSink();
      final int codeTelem3 = await runAdkCli(
        <String>['telemetry', 'status'],
        outSink: outTelem3.sink,
      );
      expect(codeTelem3, 0);
      expect(await outTelem3.closeAndRead(), contains('Telemetry collection is enabled.'));

      final _CaptureSink outTelem4 = _CaptureSink();
      final int codeTelem4 = await runAdkCli(
        <String>['telemetry', 'disable'],
        outSink: outTelem4.sink,
      );
      expect(codeTelem4, 0);
      expect(await outTelem4.closeAndRead(), contains('Telemetry collection has been disabled.'));

      final _CaptureSink outTelem5 = _CaptureSink();
      final int codeTelem5 = await runAdkCli(
        <String>['telemetry', 'status'],
        outSink: outTelem5.sink,
      );
      expect(codeTelem5, 0);
      expect(await outTelem5.closeAndRead(), contains('Telemetry collection is disabled.'));

      final _CaptureSink errTelem6 = _CaptureSink();
      final int codeTelem6 = await runAdkCli(
        <String>['telemetry', 'bogus'],
        errSink: errTelem6.sink,
      );
      expect(codeTelem6, 64);
      expect(await errTelem6.closeAndRead(), contains('Unknown telemetry command: bogus'));

      // 3. Doctor command
      final _CaptureSink outDoctor = _CaptureSink();
      final int codeDoctor = await runAdkCli(
        <String>['doctor'],
        outSink: outDoctor.sink,
      );
      expect(codeDoctor, 0);
      expect(await outDoctor.closeAndRead(), contains('ADK Dart CLI Environment Diagnostics'));

      // 4. Test passthrough arguments with --
      final Directory tempDir = Directory.systemTemp.createTempSync('cli_test_pass_');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      await createDevProject(projectDirPath: tempDir.path);
      File('${tempDir.path}${Platform.pathSeparator}pubspec.yaml').writeAsStringSync('''
name: test_pass_pkg
environment:
  sdk: '>=3.0.0 <4.0.0'
''');
      final _CaptureSink outTest = _CaptureSink();
      final int codeTest = await runAdkCli(
        <String>['test', tempDir.path, '--', '--name', 'dummy_test'],
        outSink: outTest.sink,
      );
      expect(codeTest, anyOf(1, 65));
    });

    test('eval and eval_set edge cases and case ID selection', () async {
      final Directory tempDir = Directory.systemTemp.createTempSync('cli_eval_cases_');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      await createDevProject(projectDirPath: tempDir.path);

      // Create an eval set file
      final File evalSetFile = File('${tempDir.path}${Platform.pathSeparator}my_eval_set.json');
      evalSetFile.writeAsStringSync(jsonEncode(<String, dynamic>{
        'eval_set_id': 'set_1',
        'eval_cases': <dynamic>[
          <String, dynamic>{
            'eval_id': 'case_1',
            'conversation': <dynamic>[
              <String, dynamic>{
                'user_content': <String, dynamic>{
                  'parts': <dynamic>[
                    <String, dynamic>{'text': 'hello'}
                  ]
                }
              }
            ]
          },
          <String, dynamic>{
            'eval_id': 'case_2',
            'conversation': <dynamic>[
              <String, dynamic>{
                'user_content': <String, dynamic>{
                  'parts': <dynamic>[
                    <String, dynamic>{'text': 'world'}
                  ]
                }
              }
            ]
          }
        ]
      }));

      // 1. Eval with specific case selection and --print_detailed_results
      final _CaptureSink outEval = _CaptureSink();
      final _CaptureSink errEval = _CaptureSink();
      final int codeEval = await runAdkCli(
        <String>[
          'eval',
          tempDir.path,
          '${evalSetFile.path}:case_1',
          '--print_detailed_results',
        ],
        outSink: outEval.sink,
        errSink: errEval.sink,
      );
      await errEval.closeAndRead();
      final String textEval = await outEval.closeAndRead();
      expect(codeEval, 1);
      expect(textEval, contains('Eval Run Summary'));
      expect(textEval, contains('EvalCase: case_1'));

      // 2. Eval with non-existent case ID -> StateError
      final _CaptureSink errEvalNoMatch = _CaptureSink();
      final int codeEvalNoMatch = await runAdkCli(
        <String>[
          'eval',
          tempDir.path,
          '${evalSetFile.path}:nonexistent_case',
        ],
        errSink: errEvalNoMatch.sink,
      );
      expect(codeEvalNoMatch, 1);
      final String textEvalNoMatch = await errEvalNoMatch.closeAndRead();
      expect(textEvalNoMatch, contains('No matching eval IDs found in'));

      // 3. Eval mixing file path and eval ID -> 64
      final _CaptureSink errEvalMix = _CaptureSink();
      final int codeEvalMix = await runAdkCli(
        <String>[
          'eval',
          tempDir.path,
          evalSetFile.path,
          'uncreated_eval_id_target',
        ],
        errSink: errEvalMix.sink,
      );
      expect(codeEvalMix, 64);
      final String textEvalMix = await errEvalMix.closeAndRead();
      expect(textEvalMix, contains('Mixing eval set file paths with eval set ids is not supported.'));

      // 4. Eval target is a directory -> 64
      final _CaptureSink errEvalDir = _CaptureSink();
      final int codeEvalDir = await runAdkCli(
        <String>['eval', tempDir.path, tempDir.path],
        errSink: errEvalDir.sink,
      );
      expect(codeEvalDir, 64);
      final String textEvalDir = await errEvalDir.closeAndRead();
      expect(textEvalDir, contains('must be a file path.'));

      // 5. Eval set file with invalid JSON -> 64
      final File badEvalFile = File('${tempDir.path}${Platform.pathSeparator}bad_eval.json');
      badEvalFile.writeAsStringSync('not json');
      final _CaptureSink errEvalBad = _CaptureSink();
      final int codeEvalBad = await runAdkCli(
        <String>['eval', tempDir.path, badEvalFile.path],
        errSink: errEvalBad.sink,
      );
      expect(codeEvalBad, 64);
      final String textEvalBad = await errEvalBad.closeAndRead();
      expect(textEvalBad, contains('should be a valid eval set file.'));

      // 6. eval_set generate_eval_cases with config file containing list of string & map scenarios
      final File configFile = File('${tempDir.path}${Platform.pathSeparator}gen_config.json');
      configFile.writeAsStringSync(jsonEncode(<String, dynamic>{
        'count': 1,
        'scenarios': <dynamic>[
          'scenario alpha',
          <String, dynamic>{'conversation_plan': 'scenario beta'}
        ],
        'starting_prompt': 'start conversation',
      }));

      final File sessionInput = File('${tempDir.path}${Platform.pathSeparator}session_input.json');
      sessionInput.writeAsStringSync(jsonEncode(<String, dynamic>{
        'scenarios': <String>['scenario gamma'],
      }));

      final _CaptureSink outGen = _CaptureSink();
      final int codeGen = await runAdkCli(
        <String>[
          'eval_set',
          'generate_eval_cases',
          tempDir.path,
          'set_gen',
          '--conversation_generation_config_file',
          configFile.path,
          '--session_input_file',
          sessionInput.path,
          '--repeat_num',
          '1',
        ],
        outSink: outGen.sink,
      );
      expect(codeGen, 0);

      // 7. eval_set generate_eval_cases missing config file -> FileSystemException
      final _CaptureSink errGenMissing = _CaptureSink();
      final int codeGenMissing = await runAdkCli(
        <String>[
          'eval_set',
          'generate_eval_cases',
          tempDir.path,
          'set_gen',
          '--conversation_generation_config_file',
          '${tempDir.path}${Platform.pathSeparator}missing_gen_config.json',
          '--session_input_file',
          sessionInput.path,
        ],
        errSink: errGenMissing.sink,
      );
      expect(codeGenMissing, 1);
      expect(await errGenMissing.closeAndRead(), contains('Filesystem error:'));
    });

    test('optimize command config file and score comparison', () async {
      final Directory tempDir = Directory.systemTemp.createTempSync('cli_opt_');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      await createDevProject(projectDirPath: tempDir.path);

      final String appName = projectDirName(tempDir.path);
      final LocalEvalSetsManager evalMgr = LocalEvalSetsManager(tempDir.parent.path);
      await evalMgr.createEvalSet(appName, 'default_set');
      await evalMgr.addEvalCase(
        appName,
        'default_set',
        EvalCase(
          evalId: 'eval_case_1',
          conversationScenario: ConversationScenario(
            startingPrompt: 'hello',
            conversationPlan: 'test plan',
          ),
        ),
      );

      final File samplerConfig = File('${tempDir.path}${Platform.pathSeparator}sampler_config.json');
      samplerConfig.writeAsStringSync(jsonEncode(<String, dynamic>{
        'app_name': appName,
        'eval_config': <String, dynamic>{},
        'train_eval_set': 'default_set',
      }));

      final File optConfig = File('${tempDir.path}${Platform.pathSeparator}opt_config.json');
      optConfig.writeAsStringSync(jsonEncode(<String, dynamic>{
        'max_iterations': 1,
      }));

      // Optimize with config file and local eval set
      final _CaptureSink outOpt = _CaptureSink();
      final int codeOpt = await runAdkCli(
        <String>[
          'optimize',
          tempDir.path,
          '--sampler_config_file_path',
          samplerConfig.path,
          '--optimizer_config_file_path',
          optConfig.path,
        ],
        outSink: outOpt.sink,
      );
      expect(codeOpt, 0);
    });

    test('conformance command test execution, mismatches and report writing', () async {
      final Directory specsDir = Directory.systemTemp.createTempSync('conformance_full_');
      addTearDown(() => specsDir.deleteSync(recursive: true));

      final Directory testCaseDir = Directory('${specsDir.path}${Platform.pathSeparator}core${Platform.pathSeparator}dummy_case');
      testCaseDir.createSync(recursive: true);
      File('${testCaseDir.path}${Platform.pathSeparator}spec.yaml').writeAsStringSync('''
agent: test_agent
description: Conformance test mismatch verification
user_messages:
  - content:
      parts:
        - text: hello
''');
      File('${testCaseDir.path}${Platform.pathSeparator}generated-recordings.yaml').writeAsStringSync('''
recordings: []
''');
      File('${testCaseDir.path}${Platform.pathSeparator}generated-session.yaml').writeAsStringSync('''
events:
  - id: evt_recorded_1
    author: root_agent
    content:
      role: model
      parts:
        - text: recorded different text
''');
      File('${testCaseDir.path}${Platform.pathSeparator}generated-recordings-sse.yaml').writeAsStringSync('''
recordings: []
''');
      File('${testCaseDir.path}${Platform.pathSeparator}generated-session-sse.yaml').writeAsStringSync('''
events:
  - id: evt_recorded_1
    author: root_agent
    content:
      role: model
      parts:
        - text: recorded different text
''');

      final Directory reportDir = Directory('${specsDir.path}${Platform.pathSeparator}reports');
      final _CaptureSink outConf = _CaptureSink();
      final int codeConf = await runAdkCli(
        <String>[
          'conformance',
          'test',
          specsDir.path,
          '--mode',
          'replay',
          '--streaming_mode',
          'none',
          '--generate_report',
          '--report_dir',
          reportDir.path,
        ],
        outSink: outConf.sink,
      );
      expect(codeConf, 1);
      final String textConf = await outConf.closeAndRead();
      expect(textConf, contains('FAIL'));
      expect(textConf, contains('Conformance report written to'));
      expect(reportDir.existsSync(), isTrue);

      // Conformance test with --streaming_mode=sse
      final _CaptureSink outConfBoth = _CaptureSink();
      final int codeConfBoth = await runAdkCli(
        <String>[
          'conformance',
          'test',
          specsDir.path,
          '--mode=replay',
          '--streaming_mode=sse',
          '--report_dir=${reportDir.path}',
        ],
        outSink: outConfBoth.sink,
      );
      expect(codeConfBoth, 1);

      // Conformance parse with bidi streaming mode
      final _CaptureSink errBidi = _CaptureSink();
      final int codeBidi = await runAdkCli(
        <String>[
          'conformance',
          'test',
          specsDir.path,
          '--mode=replay',
          '--streaming_mode=bidi',
        ],
        errSink: errBidi.sink,
      );
      expect(codeBidi, 64);
      expect(await errBidi.closeAndRead(), contains('Invalid conformance streaming mode: bidi'));
    });

    test('create command flag variations and validations', () async {
      final Directory tempDir = Directory.systemTemp.createTempSync('cli_create_edge_');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      // 1. Missing project directory -> 64
      final _CaptureSink err1 = _CaptureSink();
      final int code1 = await runAdkCli(<String>['create'], errSink: err1.sink);
      expect(code1, 64);
      expect(await err1.closeAndRead(), contains('Missing project directory for create.'));

      // 2. Multiple project directories -> 64
      final _CaptureSink err2 = _CaptureSink();
      final int code2 = await runAdkCli(
        <String>['create', tempDir.path, tempDir.path],
        errSink: err2.sink,
      );
      expect(code2, 64);
      expect(await err2.closeAndRead(), contains('create accepts only one project directory.'));

      // 3. Invalid --type -> 64
      final _CaptureSink err3 = _CaptureSink();
      final int code3 = await runAdkCli(
        <String>['create', tempDir.path, '--type', 'BOGUS_TYPE'],
        errSink: err3.sink,
      );
      expect(code3, 64);
      expect(await err3.closeAndRead(), contains('Invalid value for --type: BOGUS_TYPE.'));

      // 4. Unknown option for create -> 64
      final _CaptureSink err4 = _CaptureSink();
      final int code4 = await runAdkCli(
        <String>['create', tempDir.path, '--unknown_flag'],
        errSink: err4.sink,
      );
      expect(code4, 64);
      expect(await err4.closeAndRead(), contains('Unknown option for create: --unknown_flag'));

      // 5. Success with --app-name=, --model=, --api_key=, --project=, --region=, --type=
      final String appSubdir = '${tempDir.path}${Platform.pathSeparator}my_app';
      final int code5 = await runAdkCli(
        <String>[
          'create',
          appSubdir,
          '--app-name=custom_name',
          '--model=gemini-2.5-flash',
          '--api_key=fake_key',
          '--project=fake_proj',
          '--region=us-central1',
          '--type=CODE',
        ],
      );
      expect(code5, 0);
      expect(Directory(appSubdir).existsSync(), isTrue);
    });

    test('run command initial state, state file, and interactive prompts', () async {
      final Directory tempDir = Directory.systemTemp.createTempSync('cli_run_state_');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      await createDevProject(projectDirPath: tempDir.path);

      // 1. Invalid JSON for --state -> 64
      final _CaptureSink err1 = _CaptureSink();
      final int code1 = await runAdkCli(
        <String>['run', tempDir.path, '--state', 'not_json'],
        errSink: err1.sink,
      );
      expect(code1, 64);
      expect(await err1.closeAndRead(), contains('Invalid JSON for --state'));

      // 2. Non-object JSON for --state -> 64
      final _CaptureSink err2 = _CaptureSink();
      final int code2 = await runAdkCli(
        <String>['run', tempDir.path, '--state', '[1, 2, 3]'],
        errSink: err2.sink,
      );
      expect(code2, 64);
      expect(await err2.closeAndRead(), contains('expected a JSON object.'));

      // 3. Missing state file -> 64
      final _CaptureSink err3 = _CaptureSink();
      final int code3 = await runAdkCli(
        <String>['run', tempDir.path, '--state_file', '${tempDir.path}/missing.json'],
        errSink: err3.sink,
      );
      expect(code3, 64);
      expect(await err3.closeAndRead(), contains('Failed to read --state_file'));

      // 4. Valid state file
      final File stateFile = File('${tempDir.path}${Platform.pathSeparator}initial_state.json');
      stateFile.writeAsStringSync(jsonEncode(<String, dynamic>{'counter': 42}));

      // 5. Interactive input then exit, with save_session prompting for session ID
      final List<String> inputs = <String>['hello agent', '', 'exit'];
      int inputIdx = 0;
      final _CaptureSink out5 = _CaptureSink();
      final int code5 = await runAdkCli(
        <String>[
          'run',
          tempDir.path,
          '--state_file',
          stateFile.path,
          '--save_session',
          '--default_llm_model',
          'part6-stub-model',
          '--enable_features',
          'unknown_feature_xyz',
        ],
        readLine: () => inputIdx < inputs.length ? inputs[inputIdx++] : 'exit',
        outSink: out5.sink,
      );
      expect(code5, 0);
      final String text5 = await out5.closeAndRead();
      expect(text5, contains('Session ID to save:'));

      // 6. Unknown option for run -> 64
      final _CaptureSink err6 = _CaptureSink();
      final int code6 = await runAdkCli(
        <String>['run', tempDir.path, '--bogus_run_flag'],
        errSink: err6.sink,
      );
      expect(code6, 64);
      expect(await err6.closeAndRead(), contains('Unknown option for run: --bogus_run_flag'));

      // 7. Invalid timeout -> 64
      final _CaptureSink err7 = _CaptureSink();
      final int code7 = await runAdkCli(
        <String>['run', tempDir.path, '--timeout', 'invalid_timeout'],
        errSink: err7.sink,
      );
      expect(code7, 64);
      expect(await err7.closeAndRead(), contains('Invalid value for --timeout: invalid_timeout'));
    });

    test('web options avatar config file and logging levels', () async {
      final Directory tempDir = Directory.systemTemp.createTempSync('cli_web_avatar_');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      await createDevProject(projectDirPath: tempDir.path);

      final File avatarFile = File('${tempDir.path}${Platform.pathSeparator}avatars.json');
      avatarFile.writeAsStringSync(jsonEncode(<String, dynamic>{
        'root_agent': 'https://example.com/avatar.png',
      }));

      final _CaptureSink outWeb = _CaptureSink();
      final _CaptureSink errWeb = _CaptureSink();
      final int codeWeb = await runAdkCli(
        <String>[
          'web',
          tempDir.path,
          '--port',
          '0',
          '--avatar_config',
          avatarFile.path,
          '--log_level',
          'ERROR',
          '--default_llm_model',
          'part6-stub-model',
          '--enable_features',
          'unknown_feature_abc',
        ],
        outSink: outWeb.sink,
        errSink: errWeb.sink,
        stopSignal: Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      expect(codeWeb, 0);
      final String textWebErr = await errWeb.closeAndRead();
      expect(textWebErr, contains("WARNING: Unknown feature name 'unknown_feature_abc'"));
    });
  });
}


