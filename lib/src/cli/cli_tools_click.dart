import 'dart:io';

import '../dev/cli.dart' as dev_cli;
import 'cli_create.dart';
import 'cli_deploy.dart';

Future<int> runAdkCli(List<String> args, {IOSink? outSink, IOSink? errSink}) {
  return dev_cli.runAdkCli(args, outSink: outSink, errSink: errSink);
}

Future<int> main(List<String> args, {IOSink? outSink, IOSink? errSink}) async {
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
      final IOSink out = outSink ?? stdout;
      final String project = resolveProject(
        null,
        env: <String, String>{'GOOGLE_CLOUD_PROJECT': 'demo-project'},
      );
      final List<String> preview = toCloudRun(
        DeployCommand(
          service: 'adk-service',
          project: project,
          region: 'us-central1',
          image: 'gcr.io/$project/adk-service:latest',
        ),
      );
      out.writeln(preview.join(' '));
      return 0;
    default:
      return runAdkCli(args, outSink: outSink, errSink: errSink);
  }
}

Future<int> cliCreateCmd({required String projectDir, String? appName}) {
  return runCreateCommand(projectDir: projectDir, appName: appName);
}
