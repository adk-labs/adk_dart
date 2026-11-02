/// Docker container deployer for ADK applications.
library;

import 'dart:io';

import '../../version.dart';
import '_base_deployer.dart';
import '_dockerfile_template.dart';

String _basename(String filePath) {
  final String cleaned = filePath.replaceAll(
    RegExp(r'[/\\]+$'),
    '',
  );
  if (cleaned.isEmpty) {
    return '';
  }
  final List<String> parts = cleaned.split(RegExp(r'[/\\]'));
  return parts.last;
}

/// Builds a Docker deployment context and optionally builds a container image.
class DockerDeployer extends Deployer {
  /// Creates a [DockerDeployer].
  DockerDeployer({
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

  /// Builds CLI arguments representing configured runtime service URIs and flags.
  List<String> getCliEnvArgs({
    int port = 8000,
    bool traceToCloud = false,
    bool withUi = false,
    String? logLevel,
    String? sessionServiceUri,
    String? artifactServiceUri,
    String? memoryServiceUri,
    bool useLocalStorage = true,
    String? origins,
  }) {
    final List<String> args = <String>[
      'adk',
      withUi ? 'web' : 'api_server',
      '--port=$port',
      '--host=0.0.0.0',
    ];
    if (logLevel != null && logLevel.isNotEmpty) {
      args.add('--log_level=$logLevel');
    }
    if (traceToCloud) {
      args.add('--trace_to_cloud');
    }
    if (sessionServiceUri != null && sessionServiceUri.isNotEmpty) {
      args.add('--session_service_uri=$sessionServiceUri');
    }
    if (artifactServiceUri != null && artifactServiceUri.isNotEmpty) {
      args.add('--artifact_service_uri=$artifactServiceUri');
    }
    if (memoryServiceUri != null && memoryServiceUri.isNotEmpty) {
      args.add('--memory_service_uri=$memoryServiceUri');
    }
    if (!useLocalStorage) {
      args.add('--no-use_local_storage');
    }
    if (origins != null && origins.isNotEmpty) {
      args.add('--allow_origins=$origins');
    }
    return args;
  }

  /// Returns Docker `--env-file` arguments if a `.env` file exists in [agentFolder].
  List<String> getEnvFileArg(String agentFolder) {
    final File envFile = File('$agentFolder${Platform.pathSeparator}.env');
    if (envFile.existsSync()) {
      return <String>['--env-file', envFile.path];
    }
    return const <String>[];
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
    bool buildImage = false,
  }) async {
    final Directory srcDir = Directory(agentFolder);
    if (!srcDir.existsSync()) {
      throw ArgumentError.value(
        agentFolder,
        'agentFolder',
        'Agent folder does not exist.',
      );
    }

    final String effectiveAppName = validateAppName(
      (appName == null || appName.trim().isEmpty)
          ? _basename(srcDir.absolute.path)
          : appName.trim(),
    );
    final Directory targetTempDir = tempFolder != null && tempFolder.isNotEmpty
        ? Directory(tempFolder)
        : Directory.systemTemp.createTempSync('adk_docker_deploy_');
    targetTempDir.createSync(recursive: true);

    final String sep = Platform.pathSeparator;
    final Directory destAgentDir = Directory(
      '${targetTempDir.path}${sep}agents$sep$effectiveAppName',
    );
    destAgentDir.createSync(recursive: true);
    _copyDirectorySync(srcDir, destAgentDir);

    final bool hasRequirementsTxt = File(
      '${destAgentDir.path}${sep}requirements.txt',
    ).existsSync();

    final List<String> cmdArgs = <String>[
      ...getCliEnvArgs(
        port: port,
        traceToCloud: traceToCloud,
        withUi: withUi,
        logLevel: logLevel,
        sessionServiceUri: sessionServiceUri,
        artifactServiceUri: artifactServiceUri,
        memoryServiceUri: memoryServiceUri,
        useLocalStorage: useLocalStorage,
        origins: origins,
      ),
      '/app/agents',
    ];

    final String gcpEnvVars = <String>[
      if (project != null && project.isNotEmpty)
        'ENV GOOGLE_CLOUD_PROJECT=${validateDockerfileLiteral(project, fieldName: 'project')}',
      if (region != null && region.isNotEmpty)
        'ENV GOOGLE_CLOUD_LOCATION=${validateDockerfileLiteral(region, fieldName: 'region')}',
    ].join('\n');

    final String dockerfileContent = renderDockerfile(
      appName: effectiveAppName,
      port: port,
      cmdArgs: cmdArgs,
      adkVersion: adkVersion ?? adkPackageVersion,
      gcpEnvVars: gcpEnvVars,
      hasRequirementsTxt: hasRequirementsTxt,
    );

    File('${targetTempDir.path}${sep}Dockerfile').writeAsStringSync(
      dockerfileContent,
    );

    if (buildImage) {
      final String imageTag = (serviceName != null && serviceName.isNotEmpty)
          ? serviceName
          : effectiveAppName.toLowerCase();
      final ProcessResult result = await _processRunner('docker', <String>[
        'build',
        '-t',
        imageTag,
        targetTempDir.path,
      ]);
      if (result.exitCode != 0) {
        throw ProcessException(
          'docker',
          <String>['build', '-t', imageTag, targetTempDir.path],
          '${result.stderr}'.trim(),
          result.exitCode,
        );
      }
    }
  }
}

void _copyDirectorySync(Directory source, Directory destination) {
  final String sep = Platform.pathSeparator;
  for (final FileSystemEntity entity in source.listSync(followLinks: false)) {
    final String name = _basename(entity.path);
    if (entity is Directory) {
      final Directory nextDir = Directory('${destination.path}$sep$name');
      nextDir.createSync(recursive: true);
      _copyDirectorySync(entity, nextDir);
    } else if (entity is File) {
      entity.copySync('${destination.path}$sep$name');
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
