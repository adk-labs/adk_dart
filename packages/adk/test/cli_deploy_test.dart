import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:adk/src/cli/cli_deploy.dart';
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

void main() {
  group('runDeployCommand', () {
    test('executes command runner in non-dry-run mode', () async {
      List<String>? captured;
      final _CapturedSink outCapture = _CapturedSink();
      final _CapturedSink errCapture = _CapturedSink();

      final int exitCode = await runDeployCommand(
        const <String>[],
        outSink: outCapture.sink,
        errSink: errCapture.sink,
        environment: <String, String>{'GOOGLE_CLOUD_PROJECT': 'proj-123'},
        commandRunner:
            (
              List<String> command, {
              required IOSink out,
              required IOSink err,
              required Map<String, String> environment,
            }) async {
              captured = command;
              expect(environment['GOOGLE_CLOUD_PROJECT'], 'proj-123');
              return 7;
            },
      );

      final String stdoutText = await outCapture.closeAndRead();
      final String stderrText = await errCapture.closeAndRead();

      expect(exitCode, 7);
      expect(captured, isNotNull);
      expect(captured!.take(4), <String>[
        'gcloud',
        'run',
        'deploy',
        'adk-service',
      ]);
      expect(captured, contains('gcr.io/proj-123/adk-service:latest'));
      expect(stdoutText, isEmpty);
      expect(stderrText, isEmpty);
    });

    test('prints command in dry-run mode and skips runner', () async {
      bool runnerCalled = false;
      final _CapturedSink outCapture = _CapturedSink();
      final _CapturedSink errCapture = _CapturedSink();

      final int exitCode = await runDeployCommand(
        const <String>['--dry-run', '--region=asia-northeast3'],
        outSink: outCapture.sink,
        errSink: errCapture.sink,
        environment: <String, String>{'GOOGLE_CLOUD_PROJECT': 'proj-123'},
        commandRunner:
            (
              List<String> command, {
              required IOSink out,
              required IOSink err,
              required Map<String, String> environment,
            }) async {
              runnerCalled = true;
              return 0;
            },
      );

      final String stdoutText = await outCapture.closeAndRead();
      final String stderrText = await errCapture.closeAndRead();

      expect(exitCode, 0);
      expect(runnerCalled, isFalse);
      expect(stdoutText, contains('gcloud run deploy adk-service'));
      expect(stdoutText, contains('--region asia-northeast3'));
      expect(stderrText, isEmpty);
    });

    test('supports agent_engine target and forwarded extra args', () async {
      final _CapturedSink outCapture = _CapturedSink();
      final _CapturedSink errCapture = _CapturedSink();

      final int exitCode = await runDeployCommand(
        const <String>[
          '--target',
          'agent_engine',
          '--dry-run',
          '--project=proj-abc',
          '--',
          '--verbosity=debug',
        ],
        outSink: outCapture.sink,
        errSink: errCapture.sink,
        environment: <String, String>{},
      );

      final String stdoutText = await outCapture.closeAndRead();
      final String stderrText = await errCapture.closeAndRead();

      expect(exitCode, 0);
      expect(stdoutText, contains('gcloud alpha ai reasoning-engines deploy'));
      expect(stdoutText, contains('--verbosity=debug'));
      expect(stderrText, isEmpty);
    });

    test('supports python-style positional deploy target', () async {
      final _CapturedSink outCapture = _CapturedSink();
      final _CapturedSink errCapture = _CapturedSink();

      final int exitCode = await runDeployCommand(
        const <String>[
          'agent_engine',
          '--dry-run',
          '--project=proj-abc',
          '--',
          '--verbosity=debug',
        ],
        outSink: outCapture.sink,
        errSink: errCapture.sink,
        environment: <String, String>{},
      );

      final String stdoutText = await outCapture.closeAndRead();
      final String stderrText = await errCapture.closeAndRead();

      expect(exitCode, 0);
      expect(stdoutText, contains('gcloud alpha ai reasoning-engines deploy'));
      expect(stdoutText, contains('--verbosity=debug'));
      expect(stderrText, isEmpty);
    });

    test('returns usage error for invalid target', () async {
      final _CapturedSink outCapture = _CapturedSink();
      final _CapturedSink errCapture = _CapturedSink();

      final int exitCode = await runDeployCommand(
        const <String>['--target=unknown-target'],
        outSink: outCapture.sink,
        errSink: errCapture.sink,
        environment: <String, String>{'GOOGLE_CLOUD_PROJECT': 'proj-123'},
      );

      final String stdoutText = await outCapture.closeAndRead();
      final String stderrText = await errCapture.closeAndRead();

      expect(exitCode, 64);
      expect(stdoutText, isEmpty);
      expect(stderrText, contains('Unknown deploy target'));
      expect(stderrText, contains('Usage: adk deploy'));
    });

    test('returns error when project cannot be resolved', () async {
      final _CapturedSink outCapture = _CapturedSink();
      final _CapturedSink errCapture = _CapturedSink();

      final int exitCode = await runDeployCommand(
        const <String>['--dry-run'],
        outSink: outCapture.sink,
        errSink: errCapture.sink,
        environment: <String, String>{},
      );

      final String stdoutText = await outCapture.closeAndRead();
      final String stderrText = await errCapture.closeAndRead();

      expect(exitCode, 1);
      expect(stdoutText, isEmpty);
      expect(stderrText, contains('GOOGLE_CLOUD_PROJECT is not set.'));
    });

    test('supports docker target with dry-run and options', () async {
      final _CapturedSink outCapture = _CapturedSink();
      final _CapturedSink errCapture = _CapturedSink();
      final int exitCode = await runDeployCommand(
        const <String>[
          'docker',
          '--project=proj-docker',
          '--service_name=my-docker-svc',
          '--port=8080',
          '--with_ui',
          '--a2a',
          '--trace_to_cloud',
          '--allow_origins=https://example.com',
          '--adk_version=1.2.0',
          '--no-use_local_storage',
          '--log_level=DEBUG',
          '--env=FOO=BAR',
          '--dry-run',
        ],
        outSink: outCapture.sink,
        errSink: errCapture.sink,
      );

      final String stdoutText = await outCapture.closeAndRead();
      final String stderrText = await errCapture.closeAndRead();
      expect(exitCode, 0);
      expect(stderrText, contains('WARNING: --with_ui is enabled'));
      expect(stdoutText, contains('docker run --rm -p 8080:8080 --name my-docker-svc'));
      expect(stdoutText, contains('-e FOO=BAR'));
    });

    test('supports gke target with dry-run and cluster options', () async {
      final _CapturedSink outCapture = _CapturedSink();
      final _CapturedSink errCapture = _CapturedSink();
      final int exitCode = await runDeployCommand(
        const <String>[
          'gke',
          '--project=proj-gke',
          '--region=us-central1',
          '--cluster_name=my-cluster',
          '--service_name=my-gke-svc',
          '--port=8080',
          '--with_ui',
          '--a2a',
          '--trace_to_cloud',
          '--otel_to_cloud',
          '--trigger_sources=pubsub',
          '--dry-run',
        ],
        outSink: outCapture.sink,
        errSink: errCapture.sink,
      );

      final String stdoutText = await outCapture.closeAndRead();
      final String stderrText = await errCapture.closeAndRead();
      expect(exitCode, 0);
      expect(stderrText, contains('WARNING: --with_ui is enabled'));
      expect(
        stdoutText,
        contains(
          'gcloud container clusters get-credentials my-cluster --project proj-gke --region us-central1',
        ),
      );
    });

    test('validates mutually exclusive --use_local_storage and service URIs in deploy', () async {
      final _CapturedSink outCapture = _CapturedSink();
      final _CapturedSink errCapture = _CapturedSink();
      final int exitCode = await runDeployCommand(
        const <String>[
          'cloud_run',
          '--project=proj-123',
          '--no-use_local_storage',
          '--session_service_uri=memory://',
          '--dry-run',
        ],
        outSink: outCapture.sink,
        errSink: errCapture.sink,
      );
      await outCapture.closeAndRead();
      final String stderrText = await errCapture.closeAndRead();
      expect(exitCode, 64);
      expect(stderrText, contains('--use_local_storage'));
    });
  });
}
