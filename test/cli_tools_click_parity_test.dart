import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:adk_dart/cli.dart' as cli;
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
  group('cli tools click shim', () {
    test('returns success when no args', () async {
      final int exitCode = await cli.runAdkCli(const <String>[]);
      expect(exitCode, 0);
    });

    test('deploy preview uses GOOGLE_CLOUD_PROJECT from environment', () async {
      final _CapturedSink outCapture = _CapturedSink();
      final _CapturedSink errCapture = _CapturedSink();

      final int exitCode = await cli.main(
        const <String>['deploy'],
        outSink: outCapture.sink,
        errSink: errCapture.sink,
        environment: <String, String>{'GOOGLE_CLOUD_PROJECT': 'proj-test-123'},
      );

      final String stdoutText = await outCapture.closeAndRead();
      final String stderrText = await errCapture.closeAndRead();

      expect(exitCode, 0);
      expect(stdoutText, contains('--project proj-test-123'));
      expect(stdoutText, contains('gcr.io/proj-test-123/adk-service:latest'));
      expect(stderrText, isEmpty);
    });

    test('deploy preview fails when GOOGLE_CLOUD_PROJECT is missing', () async {
      final _CapturedSink outCapture = _CapturedSink();
      final _CapturedSink errCapture = _CapturedSink();

      final int exitCode = await cli.main(
        const <String>['deploy'],
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
  });
}
