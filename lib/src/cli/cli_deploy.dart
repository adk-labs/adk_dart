import 'dart:io';

class DeployCommand {
  DeployCommand({
    required this.service,
    required this.project,
    required this.region,
    required this.image,
    this.extraArgs = const <String>[],
  });

  final String service;
  final String project;
  final String region;
  final String image;
  final List<String> extraArgs;
}

enum DeployTarget { cloudRun, agentEngine, gke }

class DeployCliOptions {
  DeployCliOptions({
    required this.target,
    required this.service,
    required this.project,
    required this.region,
    required this.image,
    required this.extraArgs,
    required this.dryRun,
  });

  final DeployTarget target;
  final String service;
  final String project;
  final String region;
  final String image;
  final List<String> extraArgs;
  final bool dryRun;
}

typedef DeployCommandRunner =
    Future<int> Function(
      List<String> command, {
      required IOSink out,
      required IOSink err,
      required Map<String, String> environment,
    });

const String deployUsage = '''
Usage: adk deploy [options] [-- <gcloud args...>]

Options:
      --target             Deploy target: cloud_run | agent_engine | gke (default: cloud_run)
      --service            Service/cluster name (default: adk-service)
      --project            Google Cloud project id (default: GOOGLE_CLOUD_PROJECT)
      --region             Region (default: us-central1)
      --image              Container image (default: gcr.io/<project>/adk-service:latest)
      --dry-run            Print gcloud command only, do not execute
  -h, --help               Show this help message
''';

Future<int> runDeployCommand(
  List<String> args, {
  IOSink? outSink,
  IOSink? errSink,
  Map<String, String>? environment,
  DeployCommandRunner? commandRunner,
}) async {
  final IOSink out = outSink ?? stdout;
  final IOSink err = errSink ?? stderr;
  final Map<String, String> env = environment ?? Platform.environment;

  if (args.any((String arg) => arg == '--help' || arg == '-h')) {
    out.writeln(deployUsage);
    return 0;
  }

  final DeployCliOptions options;
  try {
    options = _parseDeployOptions(args, env: env);
  } on StateError catch (error) {
    err.writeln(error.message);
    return 1;
  } on ArgumentError catch (error) {
    err.writeln('${error.message}');
    err.writeln(deployUsage);
    return 64;
  }

  final DeployCommand command = DeployCommand(
    service: options.service,
    project: options.project,
    region: options.region,
    image: options.image,
    extraArgs: options.extraArgs,
  );
  final List<String> gcloudCommand = switch (options.target) {
    DeployTarget.cloudRun => toCloudRun(command),
    DeployTarget.agentEngine => toAgentEngine(command),
    DeployTarget.gke => toGke(command),
  };

  if (options.dryRun) {
    out.writeln(gcloudCommand.join(' '));
    return 0;
  }

  final DeployCommandRunner runner = commandRunner ?? _defaultDeployRunner;
  return runner(gcloudCommand, out: out, err: err, environment: env);
}

DeployCliOptions _parseDeployOptions(
  List<String> args, {
  required Map<String, String> env,
}) {
  String targetRaw = 'cloud_run';
  String service = 'adk-service';
  String? project;
  String region = 'us-central1';
  String? image;
  bool dryRun = false;
  final List<String> extraArgs = <String>[];
  bool forwardingOnly = false;

  for (int i = 0; i < args.length; i += 1) {
    final String arg = args[i];
    if (forwardingOnly) {
      extraArgs.add(arg);
      continue;
    }
    if (arg == '--') {
      forwardingOnly = true;
      continue;
    }
    if (arg == '--target') {
      targetRaw = _nextArg(args, i, '--target');
      i += 1;
      continue;
    }
    if (arg.startsWith('--target=')) {
      targetRaw = arg.substring('--target='.length);
      continue;
    }
    if (arg == '--service') {
      service = _nextArg(args, i, '--service');
      i += 1;
      continue;
    }
    if (arg.startsWith('--service=')) {
      service = arg.substring('--service='.length);
      continue;
    }
    if (arg == '--project') {
      project = _nextArg(args, i, '--project');
      i += 1;
      continue;
    }
    if (arg.startsWith('--project=')) {
      project = arg.substring('--project='.length);
      continue;
    }
    if (arg == '--region') {
      region = _nextArg(args, i, '--region');
      i += 1;
      continue;
    }
    if (arg.startsWith('--region=')) {
      region = arg.substring('--region='.length);
      continue;
    }
    if (arg == '--image') {
      image = _nextArg(args, i, '--image');
      i += 1;
      continue;
    }
    if (arg.startsWith('--image=')) {
      image = arg.substring('--image='.length);
      continue;
    }
    if (arg == '--dry-run') {
      dryRun = true;
      continue;
    }
    extraArgs.add(arg);
  }

  final String resolvedProject = resolveProject(project, env: env);
  final String resolvedService = service.trim().isEmpty
      ? 'adk-service'
      : service.trim();
  final String resolvedRegion = region.trim().isEmpty
      ? 'us-central1'
      : region.trim();
  final String resolvedImage = image == null || image.trim().isEmpty
      ? 'gcr.io/$resolvedProject/adk-service:latest'
      : image.trim();

  return DeployCliOptions(
    target: _parseDeployTarget(targetRaw),
    service: resolvedService,
    project: resolvedProject,
    region: resolvedRegion,
    image: resolvedImage,
    extraArgs: extraArgs,
    dryRun: dryRun,
  );
}

String _nextArg(List<String> args, int index, String option) {
  if (index + 1 >= args.length) {
    throw ArgumentError('Missing value for $option.');
  }
  return args[index + 1];
}

DeployTarget _parseDeployTarget(String value) {
  final String normalized = value.trim().toLowerCase();
  switch (normalized) {
    case 'cloud_run':
    case 'cloud-run':
    case 'cloudrun':
      return DeployTarget.cloudRun;
    case 'agent_engine':
    case 'agent-engine':
    case 'agentengine':
      return DeployTarget.agentEngine;
    case 'gke':
      return DeployTarget.gke;
    default:
      throw ArgumentError(
        'Unknown deploy target: $value. '
        'Allowed values: cloud_run, agent_engine, gke.',
      );
  }
}

Future<int> _defaultDeployRunner(
  List<String> command, {
  required IOSink out,
  required IOSink err,
  required Map<String, String> environment,
}) async {
  final Process process = await Process.start(
    command.first,
    command.skip(1).toList(growable: false),
    runInShell: Platform.isWindows,
    environment: environment,
  );

  final Future<void> stdoutPump = process.stdout
      .transform(systemEncoding.decoder)
      .forEach(out.write);
  final Future<void> stderrPump = process.stderr
      .transform(systemEncoding.decoder)
      .forEach(err.write);

  final int exitCode = await process.exitCode;
  await stdoutPump;
  await stderrPump;
  return exitCode;
}

String resolveProject(String? projectInOption, {Map<String, String>? env}) {
  final String? fromOption = projectInOption?.trim();
  if (fromOption != null && fromOption.isNotEmpty) {
    return fromOption;
  }
  final String? fromEnv = (env ?? Platform.environment)['GOOGLE_CLOUD_PROJECT']
      ?.trim();
  if (fromEnv == null || fromEnv.isEmpty) {
    throw StateError('GOOGLE_CLOUD_PROJECT is not set.');
  }
  return fromEnv;
}

void validateGcloudExtraArgs(List<String> args) {
  for (final String arg in args) {
    if (arg.contains('\n') || arg.contains('\r')) {
      throw ArgumentError('Invalid gcloud extra arg: $arg');
    }
  }
}

List<String> toCloudRun(DeployCommand command) {
  validateGcloudExtraArgs(command.extraArgs);
  return <String>[
    'gcloud',
    'run',
    'deploy',
    command.service,
    '--project',
    command.project,
    '--region',
    command.region,
    '--image',
    command.image,
    ...command.extraArgs,
  ];
}

List<String> toAgentEngine(DeployCommand command) {
  validateGcloudExtraArgs(command.extraArgs);
  return <String>[
    'gcloud',
    'alpha',
    'ai',
    'reasoning-engines',
    'deploy',
    '--project',
    command.project,
    '--region',
    command.region,
    '--image',
    command.image,
    ...command.extraArgs,
  ];
}

List<String> toGke(DeployCommand command) {
  validateGcloudExtraArgs(command.extraArgs);
  return <String>[
    'gcloud',
    'container',
    'clusters',
    'get-credentials',
    command.service,
    '--project',
    command.project,
    '--region',
    command.region,
    ...command.extraArgs,
  ];
}
