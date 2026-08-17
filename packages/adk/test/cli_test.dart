import 'package:adk/cli.dart';
import 'package:test/test.dart';

void main() {
  group('adk CLI entrypoint & AdkCliRunner', () {
    test('AdkCliRunner returns package version', () {
      expect(AdkCliRunner.version, adkPackageVersion);
      expect(adkPackageVersion, isNotEmpty);
      expect(adkSpecVersion, '2.0');
    });

    test('AdkSystemInfo collects environment diagnostics', () {
      final Map<String, dynamic> info = AdkSystemInfo.collect();
      expect(info['adk_package_version'], adkPackageVersion);
      expect(info['dart_version'], isNotEmpty);
      expect(info['operating_system'], isNotEmpty);

      final String summary = AdkSystemInfo.formatSummary();
      expect(summary, contains('ADK Dart CLI Environment Diagnostics:'));
      expect(summary, contains(adkPackageVersion));
    });

    test('AdkCliRunner handles --version flag', () async {
      final int exitCode = await AdkCliRunner.run(<String>['--version']);
      expect(exitCode, 0);
    });

    test('AdkCliRunner handles doctor / diag command', () async {
      final int exitCode = await AdkCliRunner.run(<String>['doctor']);
      expect(exitCode, 0);
    });

    test('AdkCliRunner handles telemetry commands', () async {
      final int statusCode = await AdkCliRunner.run(<String>['telemetry', 'status']);
      expect(statusCode, 0);

      final int enableCode = await AdkCliRunner.run(<String>['telemetry', 'enable']);
      expect(enableCode, 0);

      final int disableCode = await AdkCliRunner.run(<String>['telemetry', 'disable']);
      expect(disableCode, 0);
    });

    test('AdkCliRunner returns exit code for help flag', () async {
      final int exitCode = await AdkCliRunner.run(<String>['--help']);
      expect(exitCode, 0);
    });

    test('AdkCliRunner returns non-zero exit code for unknown command', () async {
      final int exitCode = await AdkCliRunner.run(<String>['unknown_subcommand_test']);
      expect(exitCode, isNot(0));
    });
  });
}
