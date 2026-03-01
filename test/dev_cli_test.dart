import 'dart:io';

import 'package:adk_dart/src/dev/cli.dart';
import 'package:adk_dart/src/dev/project.dart';
import 'package:test/test.dart';

void main() {
  group('parseAdkCliArgs', () {
    test('parses create command', () {
      final ParsedAdkCommand command = parseAdkCliArgs(<String>[
        'create',
        'my_agent',
      ]);

      expect(command.type, AdkCommandType.create);
      expect(command.projectDir, 'my_agent');
    });

    test('parses run command with project dir and message', () {
      final ParsedAdkCommand command = parseAdkCliArgs(<String>[
        'run',
        'my_agent',
        '--message',
        'hello',
      ]);

      expect(command.type, AdkCommandType.run);
      expect(command.projectDir, 'my_agent');
      expect(command.message, 'hello');
      expect(command.saveSession, isFalse);
      expect(command.resumeFilePath, isNull);
    });

    test('parses run command save_session and resume options', () {
      final ParsedAdkCommand command = parseAdkCliArgs(<String>[
        'run',
        '--save_session',
        '--resume',
        './saved.session.json',
      ]);

      expect(command.type, AdkCommandType.run);
      expect(command.projectDir, '.');
      expect(command.saveSession, isTrue);
      expect(command.resumeFilePath, './saved.session.json');
    });

    test('parses run command replay option', () {
      final ParsedAdkCommand command = parseAdkCliArgs(<String>[
        'run',
        '--replay',
        './input.json',
      ]);

      expect(command.type, AdkCommandType.run);
      expect(command.replayFilePath, './input.json');
      expect(command.resumeFilePath, isNull);
    });

    test('throws when --resume and --replay are used together', () {
      expect(
        () => parseAdkCliArgs(<String>[
          'run',
          '--resume',
          './saved.session.json',
          '--replay',
          './input.json',
        ]),
        throwsA(isA<CliUsageError>()),
      );
    });

    test('throws when --message and --replay are used together', () {
      expect(
        () => parseAdkCliArgs(<String>[
          'run',
          '--message',
          'hello',
          '--replay',
          './input.json',
        ]),
        throwsA(isA<CliUsageError>()),
      );
    });

    test('parses web command with default options', () {
      final ParsedAdkCommand command = parseAdkCliArgs(<String>['web']);

      expect(command.type, AdkCommandType.web);
      expect(command.port, 8000);
      expect(command.host?.address, InternetAddress.loopbackIPv4.address);
    });

    test('parses api_server command as web alias', () {
      final ParsedAdkCommand command = parseAdkCliArgs(<String>[
        'api_server',
        '--port',
        '8100',
      ]);

      expect(command.type, AdkCommandType.web);
      expect(command.port, 8100);
      expect(command.enableWebUi, isFalse);
    });

    test('parses parity web options', () {
      final ParsedAdkCommand command = parseAdkCliArgs(<String>[
        'web',
        '--allow_origins',
        'https://example.com,regex:https://.*\\.example\\.org',
        '--url_prefix',
        '/adk',
        '--session_service_uri',
        'memory://',
        '--artifact_service_uri',
        'memory://',
        '--memory_service_uri',
        'memory://',
        '--eval_storage_uri',
        'memory://',
        '--no-use_local_storage',
        '--auto_create_session',
      ]);

      expect(command.allowOrigins, <String>[
        'https://example.com',
        'regex:https://.*\\.example\\.org',
      ]);
      expect(command.urlPrefix, '/adk');
      expect(command.sessionServiceUri, 'memory://');
      expect(command.artifactServiceUri, 'memory://');
      expect(command.memoryServiceUri, 'memory://');
      expect(command.evalStorageUri, 'memory://');
      expect(command.useLocalStorage, isFalse);
      expect(command.autoCreateSession, isTrue);
      expect(command.enableWebUi, isTrue);
    });

    test('parses web trace/a2a/reload/extra plugin options', () {
      final ParsedAdkCommand command = parseAdkCliArgs(<String>[
        'web',
        '--trace_to_cloud',
        '--otel_to_cloud',
        '--no-reload',
        '--reload_agents',
        '--a2a',
        '--extra_plugins',
        'logging_plugin,debug_logging_plugin',
        '--extra_plugins=reflect_retry_tool_plugin',
      ]);

      expect(command.traceToCloud, isTrue);
      expect(command.otelToCloud, isTrue);
      expect(command.reload, isFalse);
      expect(command.reloadAgents, isTrue);
      expect(command.a2a, isTrue);
      expect(command.extraPlugins, <String>[
        'logging_plugin',
        'debug_logging_plugin',
        'reflect_retry_tool_plugin',
      ]);
    });

    test('parses web command with explicit port', () {
      final ParsedAdkCommand command = parseAdkCliArgs(<String>[
        'web',
        '--port',
        '9000',
      ]);

      expect(command.port, 9000);
      expect(command.projectDir, '.');
    });

    test('parses web command with --port=value syntax', () {
      final ParsedAdkCommand command = parseAdkCliArgs(<String>[
        'web',
        '--port=9100',
      ]);

      expect(command.port, 9100);
    });

    test('throws usage error for invalid port', () {
      expect(
        () => parseAdkCliArgs(<String>['web', '--port', 'bad']),
        throwsA(isA<CliUsageError>()),
      );
    });

    test('throws usage error for unknown command', () {
      expect(
        () => parseAdkCliArgs(<String>['unknown']),
        throwsA(isA<CliUsageError>()),
      );
    });

    test(
      'run command saves and resumes session snapshot in message mode',
      () async {
        final Directory tempDir = await Directory.systemTemp.createTemp(
          'adk_cli_snapshot_test_',
        );
        addTearDown(() async {
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
          }
        });

        await createDevProject(projectDirPath: tempDir.path);

        final int saveExitCode = await runAdkCli(<String>[
          'run',
          tempDir.path,
          '--message',
          'hello',
          '--session-id',
          'snapshot_session',
          '--save_session',
        ]);
        expect(saveExitCode, 0);

        final File snapshot = File(
          '${tempDir.path}${Platform.pathSeparator}snapshot_session.session.json',
        );
        expect(await snapshot.exists(), isTrue);

        final int resumeExitCode = await runAdkCli(<String>[
          'run',
          tempDir.path,
          '--message',
          'resume hello',
          '--resume',
          snapshot.path,
        ]);
        expect(resumeExitCode, 0);
      },
    );

    test('run command replays state and queries from input file', () async {
      final Directory tempDir = await Directory.systemTemp.createTemp(
        'adk_cli_replay_test_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      await createDevProject(projectDirPath: tempDir.path);
      final File replay = File(
        '${tempDir.path}${Platform.pathSeparator}replay_input.json',
      );
      await replay.writeAsString('''
{
  "state": {"foo": "bar"},
  "queries": ["hello", "What time is it in Seoul?"]
}
''');

      final int exitCode = await runAdkCli(<String>[
        'run',
        tempDir.path,
        '--replay',
        replay.path,
      ]);
      expect(exitCode, 0);
    });
  });
}
