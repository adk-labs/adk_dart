import 'package:adk_dart/cli.dart' as cli;
import 'package:test/test.dart';

void main() {
  group('cli tools click shim', () {
    test('returns success when no args', () async {
      final int exitCode = await cli.runAdkCli(const <String>[]);
      expect(exitCode, 0);
    });
  });
}
