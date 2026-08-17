/// Programmatic CLI runner and dispatcher for the `adk` command-line executable.
library;

import 'dart:io';

import 'package:adk_dart/cli.dart' as upstream_cli;

import 'system_info.dart';
import 'version.dart';

/// Programmatic interface for dispatching ADK CLI commands.
class AdkCliRunner {
  /// The active package version of the CLI runner.
  static String get version => adkPackageVersion;

  /// Dispatches CLI [args] to the underlying ADK command router.
  ///
  /// Intercepts `--version` / `-V` to display the package version and diagnostics.
  static Future<int> run(
    List<String> args, {
    IOSink? outSink,
    IOSink? errSink,
    Map<String, String>? environment,
  }) async {
    final IOSink out = outSink ?? stdout;

    if (args.length == 1 && (args.first == '--version' || args.first == '-v' || args.first == 'version')) {
      out.writeln('adk version $adkPackageVersion (spec $adkSpecVersion)');
      return 0;
    }

    if (args.length == 1 && (args.first == 'doctor' || args.first == 'diag')) {
      out.write(AdkSystemInfo.formatSummary());
      return 0;
    }

    return upstream_cli.main(
      args,
      outSink: outSink,
      errSink: errSink,
      environment: environment,
    );
  }
}
