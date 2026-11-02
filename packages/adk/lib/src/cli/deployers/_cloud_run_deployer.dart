/// Google Cloud Run deployer for ADK applications.
library;

import 'dart:io';

import '_base_deployer.dart';
import '_docker_deployer.dart';

String _basename(String filePath) {
  final String cleaned = filePath.replaceAll(RegExp(r'[/\\]+$'), '');
  if (cleaned.isEmpty) {
    return '';
  }
  return cleaned.split(RegExp(r'[/\\]')).last;
}

/// Reserved `gcloud run deploy` flags that cannot be overridden via extra args.
const Set<String> disallowedGcloudFlags = <String>{
  '--source',
  '--project',
  '--region',
  '--port',
  '--set-env-vars',
};

/// Deploys an ADK application to Google Cloud Run.
class CloudRunDeployer extends Deployer {
  /// Creates a [CloudRunDeployer].
  CloudRunDeployer({
    Future<ProcessResult> Function(
      String executable,
      List<String> arguments, {
      String? workingDirectory,
    })?
    processRunner,
  }) : _processRunner = processRunner ?? _defaultProcessRunner;

  final Future<ProcessResult> Function(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  })
  _processRunner;

  /// Parses key-value environment variables from a `.env` file at [envFilePath].
  Map<String, String> loadEnvFile(String envFilePath) {
    final File file = File(envFilePath);
    if (!file.existsSync()) {
      return <String, String>{};
    }
    final Map<String, String> env = <String, String>{};
    for (final String rawLine in file.readAsLinesSync()) {
      String line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) {
        continue;
      }
      if (line.startsWith('export ')) {
        line = line.substring('export '.length).trim();
      }
      final int eqIndex = line.indexOf('=');
      if (eqIndex <= 0) {
        continue;
      }
      final String key = line.substring(0, eqIndex).trim();
      String value = line.substring(eqIndex + 1).trim();
      if (value.length >= 2 &&
          ((value.startsWith('"') && value.endsWith('"')) ||
              (value.startsWith("'") && value.endsWith("'")))) {
        value = value.substring(1, value.length - 1);
      }
      if (key.isNotEmpty) {
        env[key] = value;
      }
    }
    return env;
  }

  /// Resolves the Google Cloud project ID from [project], environment, or `gcloud config`.
  Future<String> resolveProject(String? project) async {
    if (project != null && project.trim().isNotEmpty) {
      return project.trim();
    }
    final String? envProject =
        Platform.environment['GOOGLE_CLOUD_PROJECT'] ??
        Platform.environment['GCLOUD_PROJECT'];
    if (envProject != null && envProject.trim().isNotEmpty) {
      return envProject.trim();
    }
    final ProcessResult result = await _processRunner('gcloud', const <String>[
      'config',
      'get-value',
      'project',
    ]);
    final String resolved = '${result.stdout}'.trim();
    if (result.exitCode != 0 || resolved.isEmpty || resolved == '(unset)') {
      throw StateError(
        'Failed to resolve Google Cloud project. Pass --project or set gcloud config project.',
      );
    }
    return resolved;
  }

  /// Validates that [extraGcloudArgs] does not contain reserved flags.
  List<String> validateGcloudExtraArgs(List<String>? extraGcloudArgs) {
    if (extraGcloudArgs == null || extraGcloudArgs.isEmpty) {
      return const <String>[];
    }
    for (final String arg in extraGcloudArgs) {
      final String flagName = arg.split('=').first.trim();
      if (disallowedGcloudFlags.contains(flagName)) {
        throw ArgumentError.value(
          arg,
          'extraGcloudArgs',
          'Flag $flagName is managed by CloudRunDeployer and cannot be passed in extraGcloudArgs.',
        );
      }
    }
    return List<String>.from(extraGcloudArgs);
  }

  /// Serializes [envVars] into a `gcloud --set-env-vars` compatible string.
  String buildEnvVarsString(Map<String, String> envVars) {
    if (envVars.isEmpty) {
      return '';
    }
    return envVars.entries
        .map((MapEntry<String, String> entry) => '${entry.key}=${entry.value}')
        .join(',');
  }

  /// Adds `GOOGLE_CLOUD_PROJECT` and `GOOGLE_CLOUD_LOCATION` to [envVars].
  Map<String, String> addGcpEnvVars(
    Map<String, String> envVars, {
    required String project,
    String? region,
  }) {
    final Map<String, String> merged = Map<String, String>.from(envVars);
    merged.putIfAbsent('GOOGLE_CLOUD_PROJECT', () => project);
    if (region != null && region.isNotEmpty) {
      merged.putIfAbsent('GOOGLE_CLOUD_LOCATION', () => region);
    }
    return merged;
  }

  @override
  Future<void> deploy({
    required String agentFolder,
    String? project,
    String? region,
    String? serviceName,
    String? appName,
    String? tempFolder,
    int port = 8000,
    bool traceToCloud = false,
    bool withUi = false,
    String? adkVersion,
    String? logLevel,
    String? sessionServiceUri,
    String? artifactServiceUri,
    String? memoryServiceUri,
    bool useLocalStorage = true,
    String? origins,
    List<String>? extraGcloudArgs,
  }) async {
    final String resolvedProject = await resolveProject(project);
    final List<String> validatedExtraArgs = validateGcloudExtraArgs(
      extraGcloudArgs,
    );
    final Directory targetTempDir = tempFolder != null && tempFolder.isNotEmpty
        ? Directory(tempFolder)
        : Directory.systemTemp.createTempSync('adk_cloud_run_deploy_');
    final bool createdTemp = tempFolder == null || tempFolder.isEmpty;

    try {
      final DockerDeployer dockerDeployer = DockerDeployer(
        processRunner: _processRunner,
      );
      await dockerDeployer.deploy(
        agentFolder: agentFolder,
        project: resolvedProject,
        region: region,
        serviceName: serviceName,
        appName: appName,
        tempFolder: targetTempDir.path,
        port: port,
        traceToCloud: traceToCloud,
        withUi: withUi,
        adkVersion: adkVersion,
        logLevel: logLevel,
        sessionServiceUri: sessionServiceUri,
        artifactServiceUri: artifactServiceUri,
        memoryServiceUri: memoryServiceUri,
        useLocalStorage: useLocalStorage,
        origins: origins,
      );

      final String resolvedServiceName =
          (serviceName != null && serviceName.trim().isNotEmpty)
          ? serviceName.trim()
          : (appName != null && appName.trim().isNotEmpty)
          ? appName.trim().toLowerCase().replaceAll('_', '-')
          : _basename(agentFolder).toLowerCase().replaceAll('_', '-');

      final Map<String, String> envFromFile = loadEnvFile(
        '$agentFolder${Platform.pathSeparator}.env',
      );
      final Map<String, String> effectiveEnv = addGcpEnvVars(
        envFromFile,
        project: resolvedProject,
        region: region,
      );
      final String envVarsArg = buildEnvVarsString(effectiveEnv);

      final List<String> gcloudArgs = <String>[
        'run',
        'deploy',
        resolvedServiceName,
        '--source',
        targetTempDir.path,
        '--project',
        resolvedProject,
        if (region != null && region.trim().isNotEmpty) ...<String>[
          '--region',
          region.trim(),
        ],
        '--port',
        '$port',
        if (envVarsArg.isNotEmpty) ...<String>['--set-env-vars', envVarsArg],
        ...validatedExtraArgs,
      ];

      final ProcessResult result = await _processRunner('gcloud', gcloudArgs);
      if (result.exitCode != 0) {
        throw ProcessException(
          'gcloud',
          gcloudArgs,
          '${result.stderr}'.trim(),
          result.exitCode,
        );
      }
    } finally {
      if (createdTemp && targetTempDir.existsSync()) {
        try {
          targetTempDir.deleteSync(recursive: true);
        } catch (_) {}
      }
    }
  }
}

Future<ProcessResult> _defaultProcessRunner(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
}) {
  return Process.run(
    executable,
    arguments,
    workingDirectory: workingDirectory,
  );
}
