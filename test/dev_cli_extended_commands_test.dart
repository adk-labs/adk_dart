import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:adk_dart/src/dev/cli.dart';
import 'package:adk_dart/src/dev/project.dart';
import 'package:adk_dart/src/dev/runtime.dart';
import 'package:adk_dart/src/dev/web_server.dart';
import 'package:adk_dart/src/models/base_llm.dart';
import 'package:adk_dart/src/models/llm_request.dart';
import 'package:adk_dart/src/models/llm_response.dart';
import 'package:adk_dart/src/models/registry.dart';
import 'package:adk_dart/src/types/content.dart';
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

class _StubGeminiModel extends BaseLlm {
  _StubGeminiModel({required super.model});

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    yield LlmResponse(content: Content.modelText('stub response'));
  }
}

void main() {
  setUpAll(() {
    LLMRegistry.clear();
    LLMRegistry.register(
      supportedModels: <RegExp>[RegExp(r'gemini-2\.5-flash')],
      factory: (String model) => _StubGeminiModel(model: model),
    );
  });

  tearDownAll(LLMRegistry.clear);

  group('extended CLI commands', () {
    test('eval_set create and add_eval_case write eval set file', () async {
      final Directory tempDir = await Directory.systemTemp.createTemp(
        'adk_cli_eval_set_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      await createDevProject(projectDirPath: tempDir.path);

      final int createExitCode = await runAdkCli(<String>[
        'eval_set',
        'create',
        tempDir.path,
        'smoke_set',
      ]);
      expect(createExitCode, 0);

      final File scenarios = File(
        '${tempDir.path}${Platform.pathSeparator}scenarios.json',
      );
      await scenarios.writeAsString('''
{
  "scenarios": [
    {
      "starting_prompt": "hello",
      "conversation_plan": "One turn conversation."
    }
  ]
}
''');
      final File sessionInput = File(
        '${tempDir.path}${Platform.pathSeparator}session_input.json',
      );
      await sessionInput.writeAsString('''
{
  "app_name": "app",
  "user_id": "test_user",
  "state": {}
}
''');

      final int addExitCode = await runAdkCli(<String>[
        'eval_set',
        'add_eval_case',
        tempDir.path,
        'smoke_set',
        '--scenarios_file',
        scenarios.path,
        '--session_input_file',
        sessionInput.path,
      ]);
      expect(addExitCode, 0);

      final File evalSetFile = File(
        '${tempDir.path}${Platform.pathSeparator}smoke_set.evalset.json',
      );
      expect(await evalSetFile.exists(), isTrue);
      final Map<String, Object?> json =
          (jsonDecode(await evalSetFile.readAsString()) as Map).map(
            (Object? key, Object? value) => MapEntry('$key', value),
          );
      final List<dynamic> evalCases =
          (json['eval_cases'] as List?) ?? <dynamic>[];
      expect(evalCases, isNotEmpty);
    });

    test('eval command runs with local eval set id', () async {
      final Directory tempDir = await Directory.systemTemp.createTemp(
        'adk_cli_eval_local_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      await createDevProject(projectDirPath: tempDir.path);

      final File evalSetFile = File(
        '${tempDir.path}${Platform.pathSeparator}smoke_set.evalset.json',
      );
      await evalSetFile.writeAsString('''
{
  "eval_set_id": "smoke_set",
  "eval_cases": [
    {
      "eval_id": "eval_1",
      "input": "hello",
      "expected_output": "stub response"
    }
  ]
}
''');

      final _CapturedSink outCapture = _CapturedSink();
      final _CapturedSink errCapture = _CapturedSink();
      final int exitCode = await runAdkCli(
        <String>['eval', tempDir.path, 'smoke_set'],
        outSink: outCapture.sink,
        errSink: errCapture.sink,
      );
      final String stdoutText = await outCapture.closeAndRead();
      final String stderrText = await errCapture.closeAndRead();

      expect(exitCode, 0);
      expect(stdoutText, contains('Eval Run Summary'));
      expect(stdoutText, contains('smoke_set'));
      expect(stderrText, isEmpty);
    });

    test('eval command runs with eval set file path', () async {
      final Directory tempDir = await Directory.systemTemp.createTemp(
        'adk_cli_eval_file_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      await createDevProject(projectDirPath: tempDir.path);

      final File evalSetFile = File(
        '${tempDir.path}${Platform.pathSeparator}sample.evalset.json',
      );
      await evalSetFile.writeAsString('''
{
  "eval_set_id": "sample_set",
  "eval_cases": [
    {
      "eval_id": "case1",
      "input": "hello",
      "expected_output": "stub response"
    }
  ]
}
''');

      final int exitCode = await runAdkCli(<String>[
        'eval',
        tempDir.path,
        evalSetFile.path,
      ]);
      expect(exitCode, 0);
    });

    test('optimize command runs GEPA optimizer with local eval sampler', () async {
      final Directory tempDir = await Directory.systemTemp.createTemp(
        'adk_cli_optimize_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      await createDevProject(projectDirPath: tempDir.path);

      final String appName = projectDirName(tempDir.path);
      final File evalSetFile = File(
        '${tempDir.path}${Platform.pathSeparator}optimize_set.evalset.json',
      );
      await evalSetFile.writeAsString('''
{
  "eval_set_id": "optimize_set",
  "eval_cases": [
    {
      "eval_id": "case1",
      "input": "hello",
      "expected_output": "stub response"
    }
  ]
}
''');

      final File samplerConfigFile = File(
        '${tempDir.path}${Platform.pathSeparator}sampler_config.json',
      );
      await samplerConfigFile.writeAsString(jsonEncode(<String, Object?>{
        'app_name': appName,
        'train_eval_set': 'optimize_set',
        'eval_config': <String, Object?>{
          'criteria': <String, Object?>{
            'final_response_match_v2': 1.0,
          },
        },
      }));

      final _CapturedSink outCapture = _CapturedSink();
      final _CapturedSink errCapture = _CapturedSink();
      final int exitCode = await runAdkCli(
        <String>[
          'optimize',
          tempDir.path,
          '--sampler_config_file_path',
          samplerConfigFile.path,
          '--print_detailed_results',
        ],
        outSink: outCapture.sink,
        errSink: errCapture.sink,
      );
      final String stdoutText = await outCapture.closeAndRead();
      final String stderrText = await errCapture.closeAndRead();

      expect(exitCode, 0);
      expect(stdoutText, contains('Optimized root agent instructions'));
      expect(stdoutText, contains('Detailed GEPA optimization metrics'));
      expect(stderrText, isEmpty);
    });

    test('migrate session validates required options', () async {
      final _CapturedSink outCapture = _CapturedSink();
      final _CapturedSink errCapture = _CapturedSink();

      final int exitCode = await runAdkCli(
        <String>[
          'migrate',
          'session',
          '--source_db_url',
          'sqlite:///source.db',
        ],
        outSink: outCapture.sink,
        errSink: errCapture.sink,
      );

      final String stdoutText = await outCapture.closeAndRead();
      final String stderrText = await errCapture.closeAndRead();

      expect(exitCode, 64);
      expect(stdoutText, isEmpty);
      expect(stderrText, contains('Missing required option --dest_db_url.'));
    });

    test('conformance test accepts live mode flag', () async {
      final _CapturedSink outCapture = _CapturedSink();
      final _CapturedSink errCapture = _CapturedSink();

      final int exitCode = await runAdkCli(
        <String>['conformance', 'test', '--mode', 'live'],
        outSink: outCapture.sink,
        errSink: errCapture.sink,
      );

      final String stdoutText = await outCapture.closeAndRead();
      final String stderrText = await errCapture.closeAndRead();

      expect(exitCode, 0);
      expect(
        stdoutText,
        contains('Running ADK conformance tests in live mode'),
      );
      expect(stdoutText, contains('No test cases found!'));
      expect(stdoutText, contains('No tests were run.'));
      expect(stderrText, isEmpty);
    });

    test('conformance test live mode executes discovered spec', () async {
      final Directory tempDir = await Directory.systemTemp.createTemp(
        'adk_cli_conformance_live_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final Directory caseDir = Directory(
        '${tempDir.path}${Platform.pathSeparator}core${Platform.pathSeparator}smoke_case',
      );
      await caseDir.create(recursive: true);
      final File specFile = File(
        '${caseDir.path}${Platform.pathSeparator}spec.yaml',
      );
      await specFile.writeAsString('''
description: smoke live case
agent: test_app
initial_state: {}
user_messages:
  - text: hello
''');

      final DevProjectConfig config = const DevProjectConfig(
        appName: 'test_app',
        agentName: 'root_agent',
        description: 'test',
      );
      final DevAgentRuntime runtime = DevAgentRuntime(config: config);
      final HttpServer server = await startAdkDevWebServer(
        runtime: runtime,
        project: config,
        port: 0,
        autoCreateSession: true,
      );
      addTearDown(() async {
        await server.close(force: true);
        await runtime.runner.close();
      });

      final _CapturedSink outCapture = _CapturedSink();
      final _CapturedSink errCapture = _CapturedSink();
      final int exitCode = await runAdkCli(
        <String>[
          'conformance',
          'test',
          tempDir.path,
          '--mode',
          'live',
          '--base_url',
          'http://127.0.0.1:${server.port}',
          '--user_id',
          'u1',
        ],
        outSink: outCapture.sink,
        errSink: errCapture.sink,
      );

      final String stdoutText = await outCapture.closeAndRead();
      final String stderrText = await errCapture.closeAndRead();

      expect(exitCode, 0);
      expect(stdoutText, contains('Found 1 test cases to run in live mode'));
      expect(stdoutText, contains('Running core/smoke_case... PASS'));
      expect(stderrText, isEmpty);
    });
  });
}
