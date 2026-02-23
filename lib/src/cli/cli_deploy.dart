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
