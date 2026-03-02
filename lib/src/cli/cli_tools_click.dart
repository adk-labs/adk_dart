/// Click-compatible CLI wrappers for ADK command entrypoints.
library;

import 'dart:io';

import '../dev/cli.dart' as dev_cli;
import 'cli_deploy.dart';
import 'cli_create.dart';

/// Runs the primary ADK CLI command router.
Future<int> runAdkCli(List<String> args, {IOSink? outSink, IOSink? errSink}) {
  return dev_cli.runAdkCli(args, outSink: outSink, errSink: errSink);
}

/// Dispatches Click-style command invocations.
Future<int> main(
  List<String> args, {
  IOSink? outSink,
  IOSink? errSink,
  Map<String, String>? environment,
}) async {
  if (args.isEmpty) {
    return runAdkCli(args, outSink: outSink, errSink: errSink);
  }

  final String command = args.first;
  switch (command) {
    case 'create':
    case 'run':
    case 'web':
    case 'api_server':
      return runAdkCli(args, outSink: outSink, errSink: errSink);
    case 'deploy':
      return runDeployCommand(
        args.skip(1).toList(growable: false),
        outSink: outSink,
        errSink: errSink,
        environment: environment,
      );
    default:
      return runAdkCli(args, outSink: outSink, errSink: errSink);
  }
}

/// Executes `adk create` behavior for compatibility wrappers.
Future<int> cliCreateCmd({required String projectDir, String? appName}) {
  return runCreateCommand(projectDir: projectDir, appName: appName);
}
