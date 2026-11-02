/// Dev-UI deployment endpoints, request models, command builders, and output parsers.
///
/// Mirrors `google.adk.cli._dev_deploy` for deploying agents to Vertex AI Agent
/// Engine, Cloud Run, and Google Kubernetes Engine (GKE) from the local Dev UI.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'cli_deploy.dart';

/// Marker line emitted at the end of a streaming deploy response before the
/// final JSON result object.
const String resultMarker = '__ADK_DEPLOY_RESULT__';

/// Alias matching the Python constant name `RESULT_MARKER`.
// ignore: constant_identifier_names
const String RESULT_MARKER = resultMarker;

/// Testing override for running `gcloud` commands during default detection.
Future<String?> Function(List<String> args)?
devDeployGcloudRunnerTestingOverride;

/// Testing override for spawning the `adk deploy` subprocess during streaming.
Future<Process> Function(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
})?
devDeployProcessStarterTestingOverride;

final RegExp _controlCharPattern = RegExp(r'[\x00-\x1f\x7f]');
final RegExp _regionPattern = RegExp(r'^[a-z]+-[a-z]+[0-9]+$');
final RegExp _projectPattern = RegExp(r'^[a-z][a-z0-9.:-]{4,61}[a-z0-9]$');
final RegExp _k8sServiceNamePattern = RegExp(
  r'^[a-z]([a-z0-9-]{0,61}[a-z0-9])?$',
);
final RegExp _clusterNamePattern = RegExp(
  r'^[a-z0-9]([a-z0-9-]{0,38}[a-z0-9])?$',
);
final RegExp _agentEngineIdPattern = RegExp(r'^[0-9]+$');
final RegExp _ansiEscapePattern = RegExp(
  r'\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])',
);

const Set<String> _validLogLevels = <String>{
  'DEBUG',
  'INFO',
  'WARNING',
  'ERROR',
  'CRITICAL',
};

const Set<String> _validGkeServiceTypes = <String>{
  'ClusterIP',
  'LoadBalancer',
  'NodePort',
};

String _basename(String filePath) {
  final String cleaned = filePath.replaceAll(RegExp(r'[/\\]+$'), '');
  if (cleaned.isEmpty) {
    return '';
  }
  return cleaned.split(RegExp(r'[/\\]')).last;
}

bool _isAbsolutePath(String filePath) {
  if (filePath.startsWith('/') || filePath.startsWith(r'\')) {
    return true;
  }
  return RegExp(r'^[A-Za-z]:[/\\]').hasMatch(filePath);
}

bool _isWithinDirectory(String parentCanonical, String childCanonical) {
  final String sep = Platform.pathSeparator;
  final String normalizedParent = parentCanonical.endsWith(sep)
      ? parentCanonical
      : '$parentCanonical$sep';
  return childCanonical.startsWith(normalizedParent);
}

String _rejectFlagAndControlChars(String value, {required String fieldName}) {
  if (_controlCharPattern.hasMatch(value)) {
    throw ArgumentError.value(
      value,
      fieldName,
      '$fieldName must not contain control characters or newlines.',
    );
  }
  if (value.startsWith('-')) {
    throw ArgumentError.value(
      value,
      fieldName,
      '$fieldName must not start with "-".',
    );
  }
  return value;
}

String _validateProject(String project) {
  final String trimmed = project.trim();
  if (trimmed.isEmpty) {
    throw ArgumentError.value(project, 'project', 'project is required.');
  }
  _rejectFlagAndControlChars(trimmed, fieldName: 'project');
  if (!_projectPattern.hasMatch(trimmed)) {
    throw ArgumentError.value(
      project,
      'project',
      'Invalid Google Cloud project ID format.',
    );
  }
  return trimmed;
}

String _validateRegion(String region) {
  final String trimmed = region.trim();
  if (trimmed.isEmpty) {
    throw ArgumentError.value(region, 'region', 'region is required.');
  }
  _rejectFlagAndControlChars(trimmed, fieldName: 'region');
  if (!_regionPattern.hasMatch(trimmed)) {
    throw ArgumentError.value(
      region,
      'region',
      'Invalid Google Cloud region format (expected e.g. us-central1).',
    );
  }
  return trimmed;
}

/// Alias for [DeployDefaultsResponse].
typedef DeployDefaults = DeployDefaultsResponse;

/// Default deployment parameters pre-populated for an agent in the Dev UI.
class DeployDefaultsResponse {
  /// Creates a [DeployDefaultsResponse].
  const DeployDefaultsResponse({
    this.project = '',
    this.projectSource = 'none',
    this.region = 'us-central1',
    this.regionSource = 'default',
    this.displayName = '',
    this.description = '',
    this.serviceName = '',
    this.envFile = '',
  });

  /// Detected Google Cloud project ID, or empty string if none.
  final String project;

  /// Source of [project]: `'env'`, `'dotenv'`, `'gcloud'`, or `'none'`.
  final String projectSource;

  /// Detected Google Cloud region (defaults to `'us-central1'`).
  final String region;

  /// Source of [region]: `'env'`, `'dotenv'`, `'gcloud'`, or `'default'`.
  final String regionSource;

  /// Default display name derived from the root agent or app name.
  final String displayName;

  /// Default description derived from the root agent.
  final String description;

  /// Sanitized Cloud Run / GKE service name derived from the app name.
  final String serviceName;

  /// Relative `.env` path (`'.env'`) if present in the agent directory, else `''`.
  final String envFile;

  /// Creates a [DeployDefaultsResponse] from a JSON map.
  factory DeployDefaultsResponse.fromJson(Map<String, Object?> json) {
    return DeployDefaultsResponse(
      project: '${json['project'] ?? ''}',
      projectSource:
          '${json['projectSource'] ?? json['project_source'] ?? 'none'}',
      region: '${json['region'] ?? 'us-central1'}',
      regionSource:
          '${json['regionSource'] ?? json['region_source'] ?? 'default'}',
      displayName: '${json['displayName'] ?? json['display_name'] ?? ''}',
      description: '${json['description'] ?? ''}',
      serviceName: '${json['serviceName'] ?? json['service_name'] ?? ''}',
      envFile: '${json['envFile'] ?? json['env_file'] ?? ''}',
    );
  }

  /// Serializes this response to a JSON map with camelCase keys matching the Dev UI.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'project': project,
      'projectSource': projectSource,
      'region': region,
      'regionSource': regionSource,
      'displayName': displayName,
      'description': description,
      'serviceName': serviceName,
      'envFile': envFile,
    };
  }
}

/// Base class for Dev UI deployment request payloads.
abstract class BaseDeployRequest {
  /// Creates a [BaseDeployRequest] and validates common fields.
  BaseDeployRequest({
    required String project,
    required String region,
    this.adkVersion,
    this.tempFolder,
  }) : project = _validateProject(project),
       region = _validateRegion(region) {
    if (adkVersion != null && adkVersion!.isNotEmpty) {
      _rejectFlagAndControlChars(adkVersion!, fieldName: 'adkVersion');
    }
    if (tempFolder != null && tempFolder!.isNotEmpty) {
      _rejectFlagAndControlChars(tempFolder!, fieldName: 'tempFolder');
    }
  }

  /// Target Google Cloud project ID.
  final String project;

  /// Target Google Cloud region.
  final String region;

  /// Optional ADK version override for the container build.
  final String? adkVersion;

  /// Optional temporary folder path for staging deployment artifacts.
  final String? tempFolder;

  /// Target `adk deploy` subcommand name (`'agent_engine'`, `'cloud_run'`, or `'gke'`).
  String get subcommand;

  /// Builds the common CLI flags (`--project`, `--region`, etc.).
  List<String> commonFlags() {
    return <String>[
      '--project=$project',
      '--region=$region',
      if (adkVersion != null && adkVersion!.isNotEmpty)
        '--adk_version=$adkVersion',
      if (tempFolder != null && tempFolder!.isNotEmpty)
        '--temp_folder=$tempFolder',
    ];
  }

  /// Builds target-specific CLI flags.
  List<String> targetFlags();
}

/// Request payload for `POST /dev/apps/{app_name}/deploy/agent_engine`.
class AgentEngineDeployRequest extends BaseDeployRequest {
  /// Creates and validates an [AgentEngineDeployRequest].
  AgentEngineDeployRequest({
    required super.project,
    required super.region,
    super.adkVersion,
    super.tempFolder,
    this.displayName = '',
    this.description = '',
    this.agentEngineId = '',
    this.traceToCloud = true,
    this.envFile = '',
    this.requirementsFile = '',
    this.extraPackages = const <String>[],
    this.agentEngineConfigFile = '',
  }) {
    if (displayName.isNotEmpty) {
      if (displayName.length > 128) {
        throw ArgumentError.value(
          displayName,
          'displayName',
          'displayName must be at most 128 characters.',
        );
      }
      _rejectFlagAndControlChars(displayName, fieldName: 'displayName');
    }
    if (description.isNotEmpty) {
      if (description.length > 512) {
        throw ArgumentError.value(
          description,
          'description',
          'description must be at most 512 characters.',
        );
      }
      _rejectFlagAndControlChars(description, fieldName: 'description');
    }
    if (agentEngineId.isNotEmpty) {
      _rejectFlagAndControlChars(agentEngineId, fieldName: 'agentEngineId');
      if (!_agentEngineIdPattern.hasMatch(agentEngineId)) {
        throw ArgumentError.value(
          agentEngineId,
          'agentEngineId',
          'agentEngineId must be a numeric ID.',
        );
      }
    }
    if (envFile.isNotEmpty) {
      _rejectFlagAndControlChars(envFile, fieldName: 'envFile');
    }
    if (requirementsFile.isNotEmpty) {
      _rejectFlagAndControlChars(
        requirementsFile,
        fieldName: 'requirementsFile',
      );
    }
    if (agentEngineConfigFile.isNotEmpty) {
      _rejectFlagAndControlChars(
        agentEngineConfigFile,
        fieldName: 'agentEngineConfigFile',
      );
    }
    for (final String pkg in extraPackages) {
      _rejectFlagAndControlChars(pkg, fieldName: 'extraPackages');
    }
  }

  /// Human-readable display name for the Agent Engine resource.
  final String displayName;

  /// Description for the Agent Engine resource.
  final String description;

  /// Optional existing Agent Engine numeric ID to update in place.
  final String agentEngineId;

  /// Whether to enable Cloud Trace telemetry export.
  final bool traceToCloud;

  /// Optional relative path to a `.env` file inside the agent directory.
  final String envFile;

  /// Optional relative path to a `requirements.txt` file inside the agent directory.
  final String requirementsFile;

  /// Extra paths or packages to bundle with the Agent Engine deployment.
  final List<String> extraPackages;

  /// Optional relative path to `.agent_engine_config.json`.
  final String agentEngineConfigFile;

  /// Parses an [AgentEngineDeployRequest] from a JSON map.
  factory AgentEngineDeployRequest.fromJson(Map<String, Object?> json) {
    final List<String> extraPackages =
        ((json['extraPackages'] ?? json['extra_packages']) as List?)
            ?.map((Object? e) => '$e')
            .toList() ??
        const <String>[];
    return AgentEngineDeployRequest(
      project: '${json['project'] ?? ''}',
      region: '${json['region'] ?? ''}',
      adkVersion: (json['adkVersion'] ?? json['adk_version']) as String?,
      tempFolder: (json['tempFolder'] ?? json['temp_folder']) as String?,
      displayName: '${json['displayName'] ?? json['display_name'] ?? ''}',
      description: '${json['description'] ?? ''}',
      agentEngineId: '${json['agentEngineId'] ?? json['agent_engine_id'] ?? ''}',
      traceToCloud:
          (json['traceToCloud'] ?? json['trace_to_cloud']) as bool? ?? true,
      envFile: '${json['envFile'] ?? json['env_file'] ?? ''}',
      requirementsFile:
          '${json['requirementsFile'] ?? json['requirements_file'] ?? ''}',
      extraPackages: extraPackages,
      agentEngineConfigFile:
          '${json['agentEngineConfigFile'] ?? json['agent_engine_config_file'] ?? ''}',
    );
  }

  @override
  String get subcommand => 'agent_engine';

  @override
  List<String> targetFlags({String? agentDir}) {
    final String resolvedEnvFile =
        (envFile.isNotEmpty && agentDir != null && agentDir.isNotEmpty)
        ? resolveOptionalAgentFile(agentDir, envFile, fieldName: 'envFile')
        : envFile;
    final String resolvedReqFile =
        (requirementsFile.isNotEmpty && agentDir != null && agentDir.isNotEmpty)
        ? resolveOptionalAgentFile(
            agentDir,
            requirementsFile,
            fieldName: 'requirementsFile',
          )
        : requirementsFile;
    final String resolvedConfigFile =
        (agentEngineConfigFile.isNotEmpty &&
            agentDir != null &&
            agentDir.isNotEmpty)
        ? resolveOptionalAgentFile(
            agentDir,
            agentEngineConfigFile,
            fieldName: 'agentEngineConfigFile',
          )
        : agentEngineConfigFile;

    return <String>[
      if (displayName.isNotEmpty) '--display_name=$displayName',
      if (description.isNotEmpty) '--description=$description',
      if (agentEngineId.isNotEmpty) '--agent_engine_id=$agentEngineId',
      traceToCloud ? '--trace_to_cloud' : '--no-trace_to_cloud',
      if (resolvedEnvFile.isNotEmpty) '--env_file=$resolvedEnvFile',
      if (resolvedReqFile.isNotEmpty) '--requirements_file=$resolvedReqFile',
      if (resolvedConfigFile.isNotEmpty)
        '--agent_engine_config_file=$resolvedConfigFile',
      for (final String pkg in extraPackages)
        if (pkg.isNotEmpty) '--extra_packages=$pkg',
    ];
  }
}

/// Request payload for `POST /dev/apps/{app_name}/deploy/cloud_run`.
class CloudRunDeployRequest extends BaseDeployRequest {
  /// Creates and validates a [CloudRunDeployRequest].
  CloudRunDeployRequest({
    required super.project,
    required super.region,
    super.adkVersion,
    super.tempFolder,
    this.serviceName = '',
    this.appName = '',
    this.port = 8000,
    this.traceToCloud = false,
    this.withUi = false,
    this.logLevel,
    this.allowOrigins = const <String>[],
    this.sessionServiceUri = '',
    this.artifactServiceUri = '',
    this.memoryServiceUri = '',
    this.useLocalStorage = true,
    this.extraGcloudArgs = const <String>[],
  }) {
    if (serviceName.isNotEmpty) {
      _rejectFlagAndControlChars(serviceName, fieldName: 'serviceName');
      if (!_k8sServiceNamePattern.hasMatch(serviceName)) {
        throw ArgumentError.value(
          serviceName,
          'serviceName',
          'serviceName must be a valid DNS-1035 label (lowercase alphanumeric and hyphens).',
        );
      }
    }
    if (appName.isNotEmpty) {
      _rejectFlagAndControlChars(appName, fieldName: 'appName');
    }
    if (port < 1 || port > 65535) {
      throw ArgumentError.value(port, 'port', 'port must be between 1 and 65535.');
    }
    if (logLevel != null && logLevel!.isNotEmpty) {
      if (!_validLogLevels.contains(logLevel!.toUpperCase())) {
        throw ArgumentError.value(
          logLevel,
          'logLevel',
          'logLevel must be one of ${_validLogLevels.join(', ')}.',
        );
      }
    }
    for (final String origin in allowOrigins) {
      _rejectFlagAndControlChars(origin, fieldName: 'allowOrigins');
    }
    if (sessionServiceUri.isNotEmpty) {
      _rejectFlagAndControlChars(
        sessionServiceUri,
        fieldName: 'sessionServiceUri',
      );
    }
    if (artifactServiceUri.isNotEmpty) {
      _rejectFlagAndControlChars(
        artifactServiceUri,
        fieldName: 'artifactServiceUri',
      );
    }
    if (memoryServiceUri.isNotEmpty) {
      _rejectFlagAndControlChars(
        memoryServiceUri,
        fieldName: 'memoryServiceUri',
      );
    }
    for (final String arg in extraGcloudArgs) {
      if (_controlCharPattern.hasMatch(arg)) {
        throw ArgumentError.value(
          arg,
          'extraGcloudArgs',
          'extraGcloudArgs must not contain control characters.',
        );
      }
    }
  }

  /// Cloud Run service name.
  final String serviceName;

  /// Optional application name override.
  final String appName;

  /// Container listening port (1..65535).
  final int port;

  /// Whether to enable Cloud Trace export.
  final bool traceToCloud;

  /// Whether to deploy with the ADK Dev UI enabled.
  final bool withUi;

  /// Optional server log level (`DEBUG`, `INFO`, `WARNING`, `ERROR`, `CRITICAL`).
  final String? logLevel;

  /// Allowed CORS origins.
  final List<String> allowOrigins;

  /// Custom session service URI.
  final String sessionServiceUri;

  /// Custom artifact service URI.
  final String artifactServiceUri;

  /// Custom memory service URI.
  final String memoryServiceUri;

  /// Whether local storage is allowed when service URIs are not provided.
  final bool useLocalStorage;

  /// Additional pass-through arguments for `gcloud run deploy`.
  final List<String> extraGcloudArgs;

  /// Parses a [CloudRunDeployRequest] from a JSON map.
  factory CloudRunDeployRequest.fromJson(Map<String, Object?> json) {
    final List<String> allowOrigins =
        ((json['allowOrigins'] ?? json['allow_origins']) as List?)
            ?.map((Object? e) => '$e')
            .toList() ??
        const <String>[];
    final List<String> extraGcloudArgs =
        ((json['extraGcloudArgs'] ?? json['extra_gcloud_args']) as List?)
            ?.map((Object? e) => '$e')
            .toList() ??
        const <String>[];
    final Object? rawPort = json['port'];
    final int port = rawPort is int
        ? rawPort
        : (rawPort is num ? rawPort.toInt() : int.tryParse('$rawPort') ?? 8000);
    return CloudRunDeployRequest(
      project: '${json['project'] ?? ''}',
      region: '${json['region'] ?? ''}',
      adkVersion: (json['adkVersion'] ?? json['adk_version']) as String?,
      tempFolder: (json['tempFolder'] ?? json['temp_folder']) as String?,
      serviceName: '${json['serviceName'] ?? json['service_name'] ?? ''}',
      appName: '${json['appName'] ?? json['app_name'] ?? ''}',
      port: port,
      traceToCloud:
          (json['traceToCloud'] ?? json['trace_to_cloud']) as bool? ?? false,
      withUi: (json['withUi'] ?? json['with_ui']) as bool? ?? false,
      logLevel: (json['logLevel'] ?? json['log_level']) as String?,
      allowOrigins: allowOrigins,
      sessionServiceUri:
          '${json['sessionServiceUri'] ?? json['session_service_uri'] ?? ''}',
      artifactServiceUri:
          '${json['artifactServiceUri'] ?? json['artifact_service_uri'] ?? ''}',
      memoryServiceUri:
          '${json['memoryServiceUri'] ?? json['memory_service_uri'] ?? ''}',
      useLocalStorage:
          (json['useLocalStorage'] ?? json['use_local_storage']) as bool? ??
          true,
      extraGcloudArgs: extraGcloudArgs,
    );
  }

  @override
  String get subcommand => 'cloud_run';

  @override
  List<String> targetFlags() {
    return <String>[
      if (serviceName.isNotEmpty) '--service_name=$serviceName',
      if (appName.isNotEmpty) '--app_name=$appName',
      '--port=$port',
      if (traceToCloud) '--trace_to_cloud',
      if (withUi) '--with_ui',
      if (logLevel != null && logLevel!.isNotEmpty)
        '--log_level=${logLevel!.toUpperCase()}',
      for (final String origin in allowOrigins)
        if (origin.isNotEmpty) '--allow_origins=$origin',
      if (sessionServiceUri.isNotEmpty)
        '--session_service_uri=$sessionServiceUri',
      if (artifactServiceUri.isNotEmpty)
        '--artifact_service_uri=$artifactServiceUri',
      if (memoryServiceUri.isNotEmpty) '--memory_service_uri=$memoryServiceUri',
      useLocalStorage ? '--use_local_storage' : '--no-use_local_storage',
    ];
  }
}

/// Request payload for `POST /dev/apps/{app_name}/deploy/gke`.
class GkeDeployRequest extends BaseDeployRequest {
  /// Creates and validates a [GkeDeployRequest].
  GkeDeployRequest({
    required super.project,
    required super.region,
    required String clusterName,
    super.adkVersion,
    super.tempFolder,
    this.serviceName = '',
    this.serviceType = 'ClusterIP',
    this.appName = '',
    this.port = 8000,
    this.traceToCloud = false,
    this.withUi = false,
    this.logLevel,
    this.allowOrigins = const <String>[],
    this.sessionServiceUri = '',
    this.artifactServiceUri = '',
    this.memoryServiceUri = '',
  }) : clusterName = _validateClusterName(clusterName) {
    if (serviceName.isNotEmpty) {
      _rejectFlagAndControlChars(serviceName, fieldName: 'serviceName');
      if (!_k8sServiceNamePattern.hasMatch(serviceName)) {
        throw ArgumentError.value(
          serviceName,
          'serviceName',
          'serviceName must be a valid Kubernetes DNS-1035 service name.',
        );
      }
    }
    if (!_validGkeServiceTypes.contains(serviceType)) {
      throw ArgumentError.value(
        serviceType,
        'serviceType',
        'serviceType must be one of ${_validGkeServiceTypes.join(', ')}.',
      );
    }
    if (appName.isNotEmpty) {
      _rejectFlagAndControlChars(appName, fieldName: 'appName');
    }
    if (port < 1 || port > 65535) {
      throw ArgumentError.value(port, 'port', 'port must be between 1 and 65535.');
    }
    if (logLevel != null && logLevel!.isNotEmpty) {
      if (!_validLogLevels.contains(logLevel!.toUpperCase())) {
        throw ArgumentError.value(
          logLevel,
          'logLevel',
          'logLevel must be one of ${_validLogLevels.join(', ')}.',
        );
      }
    }
    for (final String origin in allowOrigins) {
      _rejectFlagAndControlChars(origin, fieldName: 'allowOrigins');
    }
    if (sessionServiceUri.isNotEmpty) {
      _rejectFlagAndControlChars(
        sessionServiceUri,
        fieldName: 'sessionServiceUri',
      );
    }
    if (artifactServiceUri.isNotEmpty) {
      _rejectFlagAndControlChars(
        artifactServiceUri,
        fieldName: 'artifactServiceUri',
      );
    }
    if (memoryServiceUri.isNotEmpty) {
      _rejectFlagAndControlChars(
        memoryServiceUri,
        fieldName: 'memoryServiceUri',
      );
    }
  }

  static String _validateClusterName(String clusterName) {
    final String trimmed = clusterName.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(
        clusterName,
        'clusterName',
        'clusterName is required.',
      );
    }
    _rejectFlagAndControlChars(trimmed, fieldName: 'clusterName');
    if (!_clusterNamePattern.hasMatch(trimmed)) {
      throw ArgumentError.value(
        clusterName,
        'clusterName',
        'Invalid GKE cluster name format.',
      );
    }
    return trimmed;
  }

  /// Target GKE cluster name.
  final String clusterName;

  /// Kubernetes service name.
  final String serviceName;

  /// Kubernetes Service type (`'ClusterIP'`, `'LoadBalancer'`, or `'NodePort'`).
  final String serviceType;

  /// Optional application name override.
  final String appName;

  /// Container listening port (1..65535).
  final int port;

  /// Whether to enable Cloud Trace export.
  final bool traceToCloud;

  /// Whether to deploy with the ADK Dev UI enabled.
  final bool withUi;

  /// Optional server log level (`DEBUG`, `INFO`, `WARNING`, `ERROR`, `CRITICAL`).
  final String? logLevel;

  /// Allowed CORS origins.
  final List<String> allowOrigins;

  /// Custom session service URI.
  final String sessionServiceUri;

  /// Custom artifact service URI.
  final String artifactServiceUri;

  /// Custom memory service URI.
  final String memoryServiceUri;

  /// Parses a [GkeDeployRequest] from a JSON map.
  factory GkeDeployRequest.fromJson(Map<String, Object?> json) {
    final List<String> allowOrigins =
        ((json['allowOrigins'] ?? json['allow_origins']) as List?)
            ?.map((Object? e) => '$e')
            .toList() ??
        const <String>[];
    final Object? rawPort = json['port'];
    final int port = rawPort is int
        ? rawPort
        : (rawPort is num ? rawPort.toInt() : int.tryParse('$rawPort') ?? 8000);
    return GkeDeployRequest(
      project: '${json['project'] ?? ''}',
      region: '${json['region'] ?? ''}',
      clusterName: '${json['clusterName'] ?? json['cluster_name'] ?? ''}',
      adkVersion: (json['adkVersion'] ?? json['adk_version']) as String?,
      tempFolder: (json['tempFolder'] ?? json['temp_folder']) as String?,
      serviceName: '${json['serviceName'] ?? json['service_name'] ?? ''}',
      serviceType:
          '${json['serviceType'] ?? json['service_type'] ?? 'ClusterIP'}',
      appName: '${json['appName'] ?? json['app_name'] ?? ''}',
      port: port,
      traceToCloud:
          (json['traceToCloud'] ?? json['trace_to_cloud']) as bool? ?? false,
      withUi: (json['withUi'] ?? json['with_ui']) as bool? ?? false,
      logLevel: (json['logLevel'] ?? json['log_level']) as String?,
      allowOrigins: allowOrigins,
      sessionServiceUri:
          '${json['sessionServiceUri'] ?? json['session_service_uri'] ?? ''}',
      artifactServiceUri:
          '${json['artifactServiceUri'] ?? json['artifact_service_uri'] ?? ''}',
      memoryServiceUri:
          '${json['memoryServiceUri'] ?? json['memory_service_uri'] ?? ''}',
    );
  }

  @override
  String get subcommand => 'gke';

  @override
  List<String> targetFlags() {
    return <String>[
      '--cluster_name=$clusterName',
      if (serviceName.isNotEmpty) '--service_name=$serviceName',
      '--port=$port',
      if (traceToCloud) '--trace_to_cloud',
      if (withUi) '--with_ui',
      if (logLevel != null && logLevel!.isNotEmpty)
        '--log_level=${logLevel!.toUpperCase()}',
      for (final String origin in allowOrigins)
        if (origin.isNotEmpty) '--allow_origins=$origin',
      if (sessionServiceUri.isNotEmpty)
        '--session_service_uri=$sessionServiceUri',
      if (artifactServiceUri.isNotEmpty)
        '--artifact_service_uri=$artifactServiceUri',
      if (memoryServiceUri.isNotEmpty) '--memory_service_uri=$memoryServiceUri',
    ];
  }
}

/// Sanitizes [appName] into a valid DNS-1035 service name (`a-z0-9-`).
String sanitizeServiceName(String appName) {
  String cleaned = appName
      .trim()
      .toLowerCase()
      .replaceAll('_', '-')
      .replaceAll(RegExp(r'[^a-z0-9-]'), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  if (cleaned.isEmpty) {
    return 'adk-agent';
  }
  if (!RegExp(r'^[a-z]').hasMatch(cleaned)) {
    cleaned = 'adk-$cleaned';
  }
  if (cleaned.length > 63) {
    cleaned = cleaned.substring(0, 63).replaceAll(RegExp(r'-+$'), '');
  }
  return cleaned;
}

/// Resolves and validates that [appName] is a direct, existing agent directory
/// inside [agentsRoot], throwing an [ArgumentError] on path traversal or
/// [FileSystemException] if the directory does not exist.
String resolveAgentDir(String agentsRoot, String appName) {
  final String trimmed = appName.trim();
  if (trimmed.isEmpty ||
      trimmed == '.' ||
      trimmed == '..' ||
      trimmed.contains('/') ||
      trimmed.contains(r'\') ||
      trimmed.startsWith('-')) {
    throw ArgumentError.value(
      appName,
      'appName',
      'Invalid application name.',
    );
  }
  final Directory rootDir = Directory(agentsRoot);
  if (!rootDir.existsSync()) {
    throw FileSystemException('Agents root directory not found', agentsRoot);
  }
  final String canonicalRoot = rootDir.resolveSymbolicLinksSync();
  final Directory candidate = Directory(
    '$canonicalRoot${Platform.pathSeparator}$trimmed',
  );
  if (!candidate.existsSync()) {
    throw FileSystemException(
      'Agent directory "$trimmed" not found',
      candidate.path,
    );
  }
  final String canonicalCandidate = candidate.resolveSymbolicLinksSync();
  if (!_isWithinDirectory(canonicalRoot, canonicalCandidate)) {
    throw ArgumentError.value(
      appName,
      'appName',
      'Agent path escapes agents root directory.',
    );
  }
  return canonicalCandidate;
}

/// Resolves an optional relative file path inside [agentDir], ensuring it stays
/// within [agentDir] and exists on disk.
String resolveOptionalAgentFile(
  String agentDir,
  String relativePath, {
  required String fieldName,
}) {
  final String trimmed = relativePath.trim();
  if (trimmed.isEmpty) {
    return '';
  }
  _rejectFlagAndControlChars(trimmed, fieldName: fieldName);
  if (_isAbsolutePath(trimmed) ||
      trimmed.split(RegExp(r'[/\\]')).contains('..')) {
    throw ArgumentError.value(
      relativePath,
      fieldName,
      '$fieldName must be a safe path relative to the agent directory.',
    );
  }
  final String canonicalAgentDir = Directory(
    agentDir,
  ).resolveSymbolicLinksSync();
  final File file = File('$canonicalAgentDir${Platform.pathSeparator}$trimmed');
  if (!file.existsSync()) {
    throw ArgumentError.value(
      relativePath,
      fieldName,
      '$fieldName does not exist in the agent directory.',
    );
  }
  final String canonicalFile = file.resolveSymbolicLinksSync();
  if (!_isWithinDirectory(canonicalAgentDir, canonicalFile)) {
    throw ArgumentError.value(
      relativePath,
      fieldName,
      '$fieldName symlink escapes the agent directory.',
    );
  }
  return canonicalFile;
}

/// Builds the full `adk deploy <subcommand> ...` argv list for [req] and [agentDir].
List<String> buildDeployArgv(
  BaseDeployRequest req,
  String agentDir, {
  String executable = 'adk',
}) {
  if (agentDir.startsWith('-')) {
    throw ArgumentError.value(
      agentDir,
      'agentDir',
      'agentDir must not start with "-".',
    );
  }
  final List<String> targetFlags = req is AgentEngineDeployRequest
      ? req.targetFlags(agentDir: agentDir)
      : req.targetFlags();
  final List<String> argv = <String>[
    executable,
    'deploy',
    req.subcommand,
    ...req.commonFlags(),
    ...targetFlags,
    agentDir,
  ];
  if (req is CloudRunDeployRequest && req.extraGcloudArgs.isNotEmpty) {
    argv.add('--');
    argv.addAll(req.extraGcloudArgs);
  }
  return argv;
}

/// Strips ANSI escape sequences from [text].
String stripAnsi(String text) {
  return text.replaceAll(_ansiEscapePattern, '');
}

final RegExp _agentEngineResourcePattern = RegExp(
  r'''(projects/[^\s"'`]+/locations/([a-z0-9-]+)/reasoningEngines/([0-9]+))''',
);
final RegExp _cloudRunUrlPattern = RegExp(
  r'Service URL:\s*(https://[^\s]+)|(https://[a-z0-9-]+-[a-z0-9]+-[a-z]{2}\.a\.run\.app\b|https://[a-z0-9-]+-[0-9]+\.[a-z0-9-]+\.run\.app\b)',
  caseSensitive: false,
);

/// Parses `adk deploy agent_engine` output into a structured result dictionary.
Map<String, Object?> parseAgentEngineOutput(
  String log, {
  required int exitCode,
}) {
  final String clean = stripAnsi(log);
  final RegExpMatch? match = _agentEngineResourcePattern.firstMatch(clean);
  if (exitCode == 0 && match != null) {
    final String resourceName = match.group(1)!;
    final String location = match.group(2)!;
    final String engineId = match.group(3)!;
    final List<String> parts = resourceName.split('/');
    final String project = parts.length > 1 ? parts[1] : '';
    final String playgroundUrl =
        'https://console.cloud.google.com/vertex-ai/agents/locations/$location/agent-engines/$engineId/playground?project=$project';
    final String consoleUrl =
        'https://console.cloud.google.com/vertex-ai/agents/locations/$location/agent-engines/$engineId?project=$project';
    return <String, Object?>{
      'target': 'agent_engine',
      'status': 'succeeded',
      'resourceName': resourceName,
      'agentEngineId': engineId,
      'playgroundUrl': playgroundUrl,
      'consoleUrl': consoleUrl,
    };
  }
  if (exitCode == 0) {
    return <String, Object?>{
      'target': 'agent_engine',
      'status': 'succeeded',
      'resourceName': null,
      'agentEngineId': null,
      'playgroundUrl': null,
      'consoleUrl': null,
    };
  }
  return <String, Object?>{
    'target': 'agent_engine',
    'status': 'failed',
    'error': _extractLastNonEmptyLine(clean) ??
        'Agent Engine deployment failed with exit code $exitCode.',
  };
}

/// Parses `adk deploy cloud_run` output into a structured result dictionary.
Map<String, Object?> parseCloudRunOutput(
  String log, {
  required int exitCode,
  required String serviceName,
  required String region,
  String? project,
}) {
  final String clean = stripAnsi(log);
  if (exitCode == 0) {
    final RegExpMatch? match = _cloudRunUrlPattern.firstMatch(clean);
    final String? serviceUrl = match != null
        ? (match.group(1) ?? match.group(2))
        : null;
    final String consoleUrl = (project != null && project.isNotEmpty)
        ? 'https://console.cloud.google.com/run/detail/$region/$serviceName/metrics?project=$project'
        : 'https://console.cloud.google.com/run/detail/$region/$serviceName/metrics';
    return <String, Object?>{
      'target': 'cloud_run',
      'status': 'succeeded',
      'serviceName': serviceName,
      'region': region,
      'project': ?project,
      'serviceUrl': serviceUrl,
      'consoleUrl': consoleUrl,
    };
  }
  return <String, Object?>{
    'target': 'cloud_run',
    'status': 'failed',
    'serviceName': serviceName,
    'region': region,
    'project': ?project,
    'error': _extractLastNonEmptyLine(clean) ??
        'Cloud Run deployment failed with exit code $exitCode.',
  };
}

/// Parses `adk deploy gke` output into a structured result dictionary.
Map<String, Object?> parseGkeOutput(
  String log, {
  required int exitCode,
  required String serviceName,
  String serviceType = 'ClusterIP',
  int port = 8000,
}) {
  final String clean = stripAnsi(log);
  if (exitCode == 0) {
    final String portForwardCommand =
        'kubectl port-forward svc/$serviceName $port:$port';
    return <String, Object?>{
      'target': 'gke',
      'status': 'succeeded',
      'serviceName': serviceName,
      'serviceType': serviceType,
      'externalEndpoint': null,
      'portForwardCommand': portForwardCommand,
    };
  }
  return <String, Object?>{
    'target': 'gke',
    'status': 'failed',
    'serviceName': serviceName,
    'serviceType': serviceType,
    'error': _extractLastNonEmptyLine(clean) ??
        'GKE deployment failed with exit code $exitCode.',
  };
}

String? _extractLastNonEmptyLine(String text) {
  final List<String> lines = text
      .split('\n')
      .map((String l) => l.trim())
      .where((String l) => l.isNotEmpty)
      .toList();
  return lines.isEmpty ? null : lines.last;
}

Map<String, String> _readDotEnvFile(File envFile) {
  if (!envFile.existsSync()) {
    return const <String, String>{};
  }
  final Map<String, String> values = <String, String>{};
  try {
    for (final String rawLine in envFile.readAsLinesSync()) {
      String line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) {
        continue;
      }
      if (line.startsWith('export ')) {
        line = line.substring('export '.length).trim();
      }
      final int eqIdx = line.indexOf('=');
      if (eqIdx <= 0) {
        continue;
      }
      final String key = line.substring(0, eqIdx).trim();
      String value = line.substring(eqIdx + 1).trim();
      if (value.length >= 2 &&
          ((value.startsWith('"') && value.endsWith('"')) ||
              (value.startsWith("'") && value.endsWith("'")))) {
        value = value.substring(1, value.length - 1);
      }
      if (key.isNotEmpty) {
        values[key] = value;
      }
    }
  } catch (_) {}
  return values;
}

Future<String?> _defaultGcloudRunner(List<String> args) async {
  try {
    final ProcessResult result = await Process.run('gcloud', args).timeout(
      const Duration(seconds: 5),
    );
    if (result.exitCode != 0) {
      return null;
    }
    final String value = '${result.stdout}'.trim();
    if (value.isEmpty || value == '(unset)') {
      return null;
    }
    return value;
  } catch (_) {
    return null;
  }
}

/// Detects default deployment settings for [appName] inside [agentsRoot].
Future<DeployDefaultsResponse> detectDeployDefaults({
  required String agentsRoot,
  required String appName,
  Map<String, String>? environment,
  Future<String?> Function(List<String> args)? gcloudRunner,
  Object? rootAgent,
}) async {
  final String agentDir = resolveAgentDir(agentsRoot, appName);
  final Map<String, String> env = environment ?? Platform.environment;
  final File dotEnvFile = File('$agentDir${Platform.pathSeparator}.env');
  final bool hasDotEnv = dotEnvFile.existsSync();
  final Map<String, String> dotEnv = _readDotEnvFile(dotEnvFile);
  final Future<String?> Function(List<String> args) runGcloud =
      gcloudRunner ??
      devDeployGcloudRunnerTestingOverride ??
      _defaultGcloudRunner;

  String project = '';
  String projectSource = 'none';
  final String? envProject =
      env['GOOGLE_CLOUD_PROJECT'] ?? env['GCLOUD_PROJECT'];
  final String? dotEnvProject =
      dotEnv['GOOGLE_CLOUD_PROJECT'] ?? dotEnv['GCLOUD_PROJECT'];
  if (envProject != null && envProject.trim().isNotEmpty) {
    project = envProject.trim();
    projectSource = 'env';
  } else if (dotEnvProject != null && dotEnvProject.trim().isNotEmpty) {
    project = dotEnvProject.trim();
    projectSource = 'dotenv';
  } else {
    final String? gcloudProject = await runGcloud(const <String>[
      'config',
      'get-value',
      'project',
    ]);
    if (gcloudProject != null && gcloudProject.isNotEmpty) {
      project = gcloudProject;
      projectSource = 'gcloud';
    }
  }

  String region = 'us-central1';
  String regionSource = 'default';
  final String? envRegion =
      env['GOOGLE_CLOUD_LOCATION'] ?? env['CLOUDSDK_COMPUTE_REGION'];
  final String? dotEnvRegion =
      dotEnv['GOOGLE_CLOUD_LOCATION'] ?? dotEnv['CLOUDSDK_COMPUTE_REGION'];
  if (envRegion != null && envRegion.trim().isNotEmpty) {
    region = envRegion.trim();
    regionSource = 'env';
  } else if (dotEnvRegion != null && dotEnvRegion.trim().isNotEmpty) {
    region = dotEnvRegion.trim();
    regionSource = 'dotenv';
  } else {
    final String? gcloudRegion =
        await runGcloud(const <String>['config', 'get-value', 'run/region']) ??
        await runGcloud(const <String>[
          'config',
          'get-value',
          'compute/region',
        ]);
    if (gcloudRegion != null && gcloudRegion.isNotEmpty) {
      region = gcloudRegion;
      regionSource = 'gcloud';
    }
  }

  String displayName = appName;
  String description = '';
  if (rootAgent != null) {
    try {
      final dynamic dynAgent = rootAgent;
      final Object? nameVal = dynAgent.name;
      if (nameVal is String && nameVal.trim().isNotEmpty) {
        displayName = nameVal.trim();
      }
      final Object? descVal = dynAgent.description;
      if (descVal is String && descVal.trim().isNotEmpty) {
        description = descVal.trim();
      }
    } catch (_) {}
  }

  return DeployDefaultsResponse(
    project: project,
    projectSource: projectSource,
    region: region,
    regionSource: regionSource,
    displayName: displayName,
    description: description,
    serviceName: sanitizeServiceName(appName),
    envFile: hasDotEnv ? '.env' : '',
  );
}

/// Streams a deployment execution over [response] as `text/plain; charset=utf-8`
/// and appends `[resultMarker]\n<json>\n` at completion.
Future<void> streamDeploySubprocess({
  required HttpResponse response,
  required BaseDeployRequest request,
  required String agentDir,
  required Map<String, Object?> Function(String log, int exitCode) parseOutput,
  Future<Process> Function(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  })?
  processStarter,
}) async {
  response.statusCode = HttpStatus.ok;
  response.headers.contentType = ContentType('text', 'plain', charset: 'utf-8');
  response.headers.set('Cache-Control', 'no-cache');
  response.headers.set('X-Accel-Buffering', 'no');
  response.bufferOutput = false;

  final List<String> argv = buildDeployArgv(request, agentDir);
  final StringBuffer logBuffer = StringBuffer();

  void emitLine(String line) {
    logBuffer.writeln(line);
    response.writeln(line);
  }

  emitLine('\$ ${argv.join(' ')}');
  await response.flush();

  final Future<Process> Function(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  })?
  effectiveStarter = processStarter ?? devDeployProcessStarterTestingOverride;

  int exitCode = 0;
  if (effectiveStarter != null) {
    try {
      final Process proc = await effectiveStarter(
        argv.first,
        argv.sublist(1),
        workingDirectory: agentDir,
      );
      final Future<void> stdoutDone = proc.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .forEach((String line) {
            if (!line.contains(resultMarker)) {
              emitLine(line);
            }
          });
      final Future<void> stderrDone = proc.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .forEach((String line) {
            if (!line.contains(resultMarker)) {
              emitLine(line);
            }
          });
      await Future.wait(<Future<void>>[stdoutDone, stderrDone]);
      exitCode = await proc.exitCode;
    } catch (error) {
      exitCode = 1;
      emitLine('Error launching deploy process: $error');
    }
  } else {
    try {
      await _runDeployInProcess(request, agentDir, emitLine);
      exitCode = 0;
    } catch (error) {
      exitCode = 1;
      emitLine('Deployment failed: $error');
    }
  }

  final Map<String, Object?> resultPayload = parseOutput(
    logBuffer.toString(),
    exitCode,
  );
  response.writeln(resultMarker);
  response.writeln(jsonEncode(resultPayload));
  await response.flush();
  await response.close();
}

Future<void> _runDeployInProcess(
  BaseDeployRequest request,
  String agentDir,
  void Function(String line) emitLine,
) async {
  final String defaultService = sanitizeServiceName(_basename(agentDir));
  List<String> commandArgs;
  if (request is AgentEngineDeployRequest) {
    final String resolvedConfigFile = request.agentEngineConfigFile.isNotEmpty
        ? resolveOptionalAgentFile(
            agentDir,
            request.agentEngineConfigFile,
            fieldName: 'agentEngineConfigFile',
          )
        : '';
    commandArgs = toAgentEngine(
      DeployCommand(
        service: defaultService,
        project: request.project,
        region: request.region,
        image: 'gcr.io/${request.project}/$defaultService:latest',
        agentFolder: agentDir,
        adkVersion: request.adkVersion,
        tempFolder: request.tempFolder,
        displayName: request.displayName,
        description: request.description,
        agentEngineId: request.agentEngineId.isEmpty
            ? null
            : request.agentEngineId,
        traceToCloud: request.traceToCloud,
        extraPackages: request.extraPackages,
        agentEngineConfigFile: resolvedConfigFile,
      ),
    );
  } else if (request is CloudRunDeployRequest) {
    final String effectiveService = request.serviceName.isNotEmpty
        ? request.serviceName
        : defaultService;
    commandArgs = toCloudRun(
      DeployCommand(
        service: effectiveService,
        project: request.project,
        region: request.region,
        image: 'gcr.io/${request.project}/$effectiveService:latest',
        agentFolder: agentDir,
        appName: request.appName.isEmpty ? null : request.appName,
        tempFolder: request.tempFolder,
        port: request.port,
        traceToCloud: request.traceToCloud,
        withUi: request.withUi,
        adkVersion: request.adkVersion,
        logLevel: request.logLevel ?? 'INFO',
        allowOrigins: request.allowOrigins,
        sessionServiceUri: request.sessionServiceUri.isEmpty
            ? null
            : request.sessionServiceUri,
        artifactServiceUri: request.artifactServiceUri.isEmpty
            ? null
            : request.artifactServiceUri,
        memoryServiceUri: request.memoryServiceUri.isEmpty
            ? null
            : request.memoryServiceUri,
        useLocalStorage: request.useLocalStorage,
        extraArgs: request.extraGcloudArgs,
      ),
    );
  } else if (request is GkeDeployRequest) {
    final String effectiveService = request.serviceName.isNotEmpty
        ? request.serviceName
        : defaultService;
    commandArgs = toGke(
      DeployCommand(
        service: effectiveService,
        project: request.project,
        region: request.region,
        image: 'gcr.io/${request.project}/$effectiveService:latest',
        clusterName: request.clusterName,
        serviceType: request.serviceType,
        agentFolder: agentDir,
        appName: request.appName.isEmpty ? null : request.appName,
        tempFolder: request.tempFolder,
        port: request.port,
        traceToCloud: request.traceToCloud,
        withUi: request.withUi,
        adkVersion: request.adkVersion,
        logLevel: request.logLevel ?? 'INFO',
        allowOrigins: request.allowOrigins,
        sessionServiceUri: request.sessionServiceUri.isEmpty
            ? null
            : request.sessionServiceUri,
        artifactServiceUri: request.artifactServiceUri.isEmpty
            ? null
            : request.artifactServiceUri,
        memoryServiceUri: request.memoryServiceUri.isEmpty
            ? null
            : request.memoryServiceUri,
      ),
    );
  } else {
    throw UnsupportedError('Unsupported deploy request: ${request.runtimeType}');
  }

  emitLine('Executing: ${commandArgs.join(' ')}');
  final ProcessResult res = await Process.run(
    commandArgs.first,
    commandArgs.sublist(1),
    workingDirectory: agentDir,
  );
  final String out = '${res.stdout}'.trim();
  final String err = '${res.stderr}'.trim();
  if (out.isNotEmpty) {
    emitLine(out);
  }
  if (err.isNotEmpty) {
    emitLine(err);
  }
  if (res.exitCode != 0) {
    throw ProcessException(
      commandArgs.first,
      commandArgs.sublist(1),
      err,
      res.exitCode,
    );
  }
}

final RegExp _devDeployRoutePattern = RegExp(
  r'^/dev/apps/([^/]+)/deploy/(defaults|agent_engine|cloud_run|gke)$',
);

/// Handles `/dev/apps/{app_name}/deploy/{defaults|agent_engine|cloud_run|gke}`
/// HTTP requests, returning `true` if the path matched a deploy endpoint.
Future<bool> handleDevDeployRoute({
  required HttpRequest request,
  required String agentsRoot,
  required bool enableWebUi,
  required bool isLocalClient,
  String? routedPath,
  Object? Function(String appName)? agentLookup,
  Future<String?> Function(List<String> args)? gcloudRunner,
  Future<Process> Function(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  })?
  processStarter,
}) async {
  final RegExpMatch? match = _devDeployRoutePattern.firstMatch(
    routedPath ?? request.uri.path,
  );
  if (match == null) {
    return false;
  }

  if (!enableWebUi) {
    await _writeJsonResponse(
      request.response,
      HttpStatus.notFound,
      <String, Object?>{'detail': 'Not Found'},
    );
    return true;
  }

  if (!isLocalClient) {
    await _writeJsonResponse(
      request.response,
      HttpStatus.forbidden,
      <String, Object?>{
        'detail':
            'Deploy endpoints are restricted to local loopback clients unless '
            'ADK_ALLOW_REMOTE_AGENT_BUILDER=1 is set.',
      },
    );
    return true;
  }

  final String appName = Uri.decodeComponent(match.group(1)!);
  final String action = match.group(2)!;

  final String agentDir;
  try {
    agentDir = resolveAgentDir(agentsRoot, appName);
  } on ArgumentError catch (error) {
    await _writeJsonResponse(
      request.response,
      HttpStatus.badRequest,
      <String, Object?>{'detail': error.message ?? '$error'},
    );
    return true;
  } on FileSystemException catch (error) {
    await _writeJsonResponse(
      request.response,
      HttpStatus.notFound,
      <String, Object?>{'detail': error.message},
    );
    return true;
  }

  if (action == 'defaults') {
    if (request.method.toUpperCase() != 'GET') {
      await _writeJsonResponse(
        request.response,
        HttpStatus.methodNotAllowed,
        <String, Object?>{'detail': 'Method Not Allowed'},
      );
      return true;
    }
    final DeployDefaultsResponse defaults = await detectDeployDefaults(
      agentsRoot: agentsRoot,
      appName: appName,
      gcloudRunner: gcloudRunner,
      rootAgent: agentLookup?.call(appName),
    );
    await _writeJsonResponse(
      request.response,
      HttpStatus.ok,
      defaults.toJson(),
    );
    return true;
  }

  if (request.method.toUpperCase() != 'POST') {
    await _writeJsonResponse(
      request.response,
      HttpStatus.methodNotAllowed,
      <String, Object?>{'detail': 'Method Not Allowed'},
    );
    return true;
  }

  final Map<String, Object?> body;
  try {
    final String rawBody = await utf8.decoder.bind(request).join();
    final Object? decoded = rawBody.trim().isEmpty
        ? <String, Object?>{}
        : jsonDecode(rawBody);
    if (decoded is! Map) {
      throw const FormatException('Request body must be a JSON object.');
    }
    body = Map<String, Object?>.from(decoded);
  } catch (error) {
    await _writeJsonResponse(
      request.response,
      HttpStatus.unprocessableEntity,
      <String, Object?>{'detail': 'Invalid JSON payload: $error'},
    );
    return true;
  }

  try {
    if (action == 'agent_engine') {
      final AgentEngineDeployRequest deployReq =
          AgentEngineDeployRequest.fromJson(body);
      // Validate optional files upfront so invalid paths return 422 before streaming.
      deployReq.targetFlags(agentDir: agentDir);
      await streamDeploySubprocess(
        response: request.response,
        request: deployReq,
        agentDir: agentDir,
        processStarter: processStarter,
        parseOutput: (String log, int exitCode) =>
            parseAgentEngineOutput(log, exitCode: exitCode),
      );
      return true;
    }

    if (action == 'cloud_run') {
      final CloudRunDeployRequest deployReq = CloudRunDeployRequest.fromJson(
        body,
      );
      final String effectiveServiceName = deployReq.serviceName.isNotEmpty
          ? deployReq.serviceName
          : sanitizeServiceName(
              deployReq.appName.isNotEmpty ? deployReq.appName : appName,
            );
      await streamDeploySubprocess(
        response: request.response,
        request: deployReq,
        agentDir: agentDir,
        processStarter: processStarter,
        parseOutput: (String log, int exitCode) => parseCloudRunOutput(
          log,
          exitCode: exitCode,
          serviceName: effectiveServiceName,
          region: deployReq.region,
          project: deployReq.project,
        ),
      );
      return true;
    }

    if (action == 'gke') {
      final GkeDeployRequest deployReq = GkeDeployRequest.fromJson(body);
      final String effectiveServiceName = deployReq.serviceName.isNotEmpty
          ? deployReq.serviceName
          : sanitizeServiceName(
              deployReq.appName.isNotEmpty ? deployReq.appName : appName,
            );
      await streamDeploySubprocess(
        response: request.response,
        request: deployReq,
        agentDir: agentDir,
        processStarter: processStarter,
        parseOutput: (String log, int exitCode) => parseGkeOutput(
          log,
          exitCode: exitCode,
          serviceName: effectiveServiceName,
          serviceType: deployReq.serviceType,
          port: deployReq.port,
        ),
      );
      return true;
    }
  } on ArgumentError catch (error) {
    await _writeJsonResponse(
      request.response,
      HttpStatus.unprocessableEntity,
      <String, Object?>{'detail': error.message ?? '$error'},
    );
    return true;
  }

  return false;
}

Future<void> _writeJsonResponse(
  HttpResponse response,
  int statusCode,
  Map<String, Object?> payload,
) async {
  response.statusCode = statusCode;
  response.headers.contentType = ContentType.json;
  response.write(jsonEncode(payload));
  await response.close();
}
