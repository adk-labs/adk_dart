import 'dart:io';

import '../dev/cli.dart' as dev_cli;
import 'cli_deploy.dart';
import 'cli_create.dart';

Future<int> runAdkCli(List<String> args, {IOSink? outSink, IOSink? errSink}) {
  return dev_cli.runAdkCli(args, outSink: outSink, errSink: errSink);
}

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

Future<int> cliCreateCmd({required String projectDir, String? appName}) {
  return runCreateCommand(projectDir: projectDir, appName: appName);
}
