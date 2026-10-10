/// Deployment command parsing and execution for `adk deploy`.
library;

import 'dart:io';

/// Resolved deployment configuration used to build `gcloud` or `docker` commands.
///
/// ```dart
/// final command = DeployCommand(
///   service: 'my-agent-service',
///   project: 'my-gcp-project',
///   region: 'us-central1',
///   image: 'gcr.io/my-gcp-project/my-agent-service:latest',
/// );
/// final args = toCloudRun(command);
/// ```
class DeployCommand {
  /// Creates a deployment command payload.
  DeployCommand({
    required this.service,
    required this.project,
    required this.region,
    required this.image,
    this.serviceAccount,
    this.agentFolder,
    this.appName,
    this.tempFolder,
    this.port = 8000,
    this.traceToCloud = false,
    this.otelToCloud = false,
    this.withUi = false,
    this.adkVersion,
    this.logLevel = 'INFO',
    this.allowOrigins = const <String>[],
    this.sessionServiceUri,
    this.artifactServiceUri,
    this.memoryServiceUri,
    this.useLocalStorage = false,
    this.a2a = false,
    this.triggerSources,
    this.triggerOidcAudience,
    this.triggerOidcServiceAccounts,
    this.withCloudRunSandbox = false,
    this.extraPackages = const <String>[],
    this.providerArgs = const <String>[],
    this.envVars = const <String>[],
    this.apiKey,
    this.agentEngineId,
    this.displayName = '',
    this.description = '',
    this.agentEngineConfigFile = '',
    this.workerPool,
    this.clusterName,
    this.serviceType = 'ClusterIP',
    this.extraArgs = const <String>[],
  });

  /// The service or cluster name to deploy.
  final String service;

  /// The Google Cloud project identifier.
  final String project;

  /// The deployment region.
  final String region;

  /// The container image reference.
  final String image;

  /// Optional Google Cloud service account email used as the runtime identity.
  final String? serviceAccount;

  /// Optional path to the agent source folder.
  final String? agentFolder;

  /// Optional app name of the ADK API server.
  final String? appName;

  /// Optional temp folder for generated deployment source files.
  final String? tempFolder;

  /// Port of the ADK API server.
  final int port;

  /// Whether to enable Cloud Trace.
  final bool traceToCloud;

  /// Whether to enable OpenTelemetry export to GCP.
  final bool otelToCloud;

  /// Whether to deploy the ADK Web UI alongside the API server.
  final bool withUi;

  /// Optional ADK version used in deployment.
  final String? adkVersion;

  /// Logging level (`DEBUG`, `INFO`, `WARNING`, `ERROR`, `CRITICAL`).
  final String logLevel;

  /// Allowed CORS origins.
  final List<String> allowOrigins;

  /// Optional session service URI.
  final String? sessionServiceUri;

  /// Optional artifact service URI.
  final String? artifactServiceUri;

  /// Optional memory service URI.
  final String? memoryServiceUri;

  /// Whether local `.adk` storage is enabled.
  final bool useLocalStorage;

  /// Whether A2A protocol endpoint is enabled.
  final bool a2a;

  /// Comma-separated list of trigger sources (`pubsub`, `eventarc`).
  final String? triggerSources;

  /// Expected audience for Google-signed OIDC bearer tokens on `/trigger/*`.
  final String? triggerOidcAudience;

  /// Comma-separated list of allowed service account emails on `/trigger/*`.
  final String? triggerOidcServiceAccounts;

  /// Whether to enable the Cloud Run sandbox for code execution.
  final bool withCloudRunSandbox;

  /// Additional local package paths staged into `/app/<basename>`.
  final List<String> extraPackages;

  /// Provider-specific `KEY=VALUE` arguments (`-a` / `--provider-args`).
  final List<String> providerArgs;

  /// Environment variables (`-e` / `--env`) set on the deployed service.
  final List<String> envVars;

  /// Optional Express Mode API key for Agent Engine deployments.
  final String? apiKey;

  /// Optional Agent Engine instance ID to update.
  final String? agentEngineId;

  /// Display name of the agent in Agent Engine.
  final String displayName;

  /// Description of the agent in Agent Engine.
  final String description;

  /// Optional `.agent_engine_config.json` path.
  final String agentEngineConfigFile;

  /// Optional Cloud Build private worker pool resource name.
  final String? workerPool;

  /// Optional GKE cluster name.
  final String? clusterName;

  /// Kubernetes Service type for GKE deployments (`ClusterIP` or `LoadBalancer`).
  final String serviceType;

  /// Additional raw arguments forwarded to `gcloud`.
  final List<String> extraArgs;
}

/// Deploy targets supported by the CLI.
enum DeployTarget {
  /// Google Cloud Run serverless container deployment target.
  cloudRun,

  /// Local Docker container deployment target.
  docker,

  /// Vertex AI Agent Engine reasoning engine deployment target.
  agentEngine,

  /// Google Kubernetes Engine cluster deployment target.
  gke,
}

/// Parsed options for a single `adk deploy` invocation.
class DeployCliOptions {
  /// Creates parsed deploy CLI options.
  DeployCliOptions({
    required this.target,
    required this.service,
    required this.project,
    required this.region,
    required this.image,
    this.serviceAccount,
    this.agentFolder,
    this.appName,
    this.tempFolder,
    this.port = 8000,
    this.traceToCloud = false,
    this.otelToCloud = false,
    this.withUi = false,
    this.adkVersion,
    this.logLevel = 'INFO',
    this.allowOrigins = const <String>[],
    this.sessionServiceUri,
    this.artifactServiceUri,
    this.memoryServiceUri,
    this.useLocalStorage = false,
    this.a2a = false,
    this.triggerSources,
    this.triggerOidcAudience,
    this.triggerOidcServiceAccounts,
    this.withCloudRunSandbox = false,
    this.extraPackages = const <String>[],
    this.providerArgs = const <String>[],
    this.envVars = const <String>[],
    this.apiKey,
    this.agentEngineId,
    this.displayName = '',
    this.description = '',
    this.agentEngineConfigFile = '',
    this.workerPool,
    this.clusterName,
    this.serviceType = 'ClusterIP',
    this.warnings = const <String>[],
    required this.extraArgs,
    required this.dryRun,
  });

  /// The selected deployment backend.
  final DeployTarget target;

  /// The service or cluster name to deploy.
  final String service;

  /// The Google Cloud project identifier.
  final String project;

  /// The deployment region.
  final String region;

  /// The container image reference.
  final String image;

  /// Optional Google Cloud service account email used as the runtime identity.
  final String? serviceAccount;

  /// Optional path to the agent source folder.
  final String? agentFolder;

  /// Optional app name of the ADK API server.
  final String? appName;

  /// Optional temp folder for generated deployment source files.
  final String? tempFolder;

  /// Port of the ADK API server.
  final int port;

  /// Whether to enable Cloud Trace.
  final bool traceToCloud;

  /// Whether to enable OpenTelemetry export to GCP.
  final bool otelToCloud;

  /// Whether to deploy the ADK Web UI alongside the API server.
  final bool withUi;

  /// Optional ADK version used in deployment.
  final String? adkVersion;

  /// Logging level (`DEBUG`, `INFO`, `WARNING`, `ERROR`, `CRITICAL`).
  final String logLevel;

  /// Allowed CORS origins.
  final List<String> allowOrigins;

  /// Optional session service URI.
  final String? sessionServiceUri;

  /// Optional artifact service URI.
  final String? artifactServiceUri;

  /// Optional memory service URI.
  final String? memoryServiceUri;

  /// Whether local `.adk` storage is enabled.
  final bool useLocalStorage;

  /// Whether A2A protocol endpoint is enabled.
  final bool a2a;

  /// Comma-separated list of trigger sources (`pubsub`, `eventarc`).
  final String? triggerSources;

  /// Expected audience for Google-signed OIDC bearer tokens on `/trigger/*`.
  final String? triggerOidcAudience;

  /// Comma-separated list of allowed service account emails on `/trigger/*`.
  final String? triggerOidcServiceAccounts;

  /// Whether to enable the Cloud Run sandbox for code execution.
  final bool withCloudRunSandbox;

  /// Additional local package paths staged into `/app/<basename>`.
  final List<String> extraPackages;

  /// Provider-specific `KEY=VALUE` arguments (`-a` / `--provider-args`).
  final List<String> providerArgs;

  /// Environment variables (`-e` / `--env`) set on the deployed service.
  final List<String> envVars;

  /// Optional Express Mode API key for Agent Engine deployments.
  final String? apiKey;

  /// Optional Agent Engine instance ID to update.
  final String? agentEngineId;

  /// Display name of the agent in Agent Engine.
  final String displayName;

  /// Description of the agent in Agent Engine.
  final String description;

  /// Optional `.agent_engine_config.json` path.
  final String agentEngineConfigFile;

  /// Optional Cloud Build private worker pool resource name.
  final String? workerPool;

  /// Optional GKE cluster name.
  final String? clusterName;

  /// Kubernetes Service type for GKE deployments (`ClusterIP` or `LoadBalancer`).
  final String serviceType;

  /// Non-fatal warnings generated while parsing options.
  final List<String> warnings;

  /// Extra arguments forwarded to `gcloud`.
  final List<String> extraArgs;

  /// Whether command execution is skipped and only printed.
  final bool dryRun;
}

/// Signature for pluggable command execution in deploy workflows.
typedef DeployCommandRunner =
    Future<int> Function(
      List<String> command, {
      required IOSink out,
      required IOSink err,
      required Map<String, String> environment,
    });

/// Usage text printed by `adk deploy --help`.
const String deployUsage = '''
Usage: adk deploy [target] [options] [agent] [-- <gcloud args...>]

Commands / Targets:
  cloud_run      Deploys an agent to Cloud Run.
  docker         Deploys an agent to a local Docker container.
  agent_engine   Deploys an agent to Agent Engine.
  gke            Deploys an agent to GKE.

Options:
      --target                           Deploy target: cloud_run | docker | agent_engine | gke (default: cloud_run)
      --service, --service_name          Service/cluster name (default: adk-service)
      --app_name                         App name of the ADK API server
      --project                          Google Cloud project id (default: GOOGLE_CLOUD_PROJECT)
      --region                           Google Cloud region (default: us-central1)
      --image                            Container image (default: gcr.io/<project>/adk-service:latest)
      --port, -p                         Port of the ADK API server (default: 8000)
      --temp_folder                      Temp folder for generated deployment source files
      --trace_to_cloud / --no-trace_to_cloud
                                         Enable Cloud Trace
      --otel_to_cloud                    Enable OpenTelemetry export to GCP
      --with_ui                          Deploy ADK Web UI (development/testing only)
      --adk_version                      ADK version used in deployment
      --log_level, --verbosity           Logging level: DEBUG | INFO | WARNING | ERROR | CRITICAL
      --allow_origins                    Allowed CORS origins (repeatable or comma-separated)
      --a2a                              Enable A2A protocol endpoint
      --session_service_uri              URI of the session service
      --artifact_service_uri             URI of the artifact service
      --memory_service_uri               URI of the memory service
      --use_local_storage / --no_use_local_storage
                                         Enable or disable local .adk storage
      --trigger_sources                  Comma-separated trigger sources (pubsub,eventarc)
      --trigger_oidc_audience            Expected OIDC audience for /trigger/* endpoints
      --trigger_oidc_service_accounts    Allowed service account emails for /trigger/* endpoints
      --with_cloud_run_sandbox           Enable Cloud Run sandbox for code execution
      --extra_packages                   Additional local package paths to stage (repeatable)
  -a, --provider-args                    Provider-specific KEY=VALUE arguments (repeatable)
  -e, --env                              Environment variable KEY=VALUE (repeatable)
      --api_key                          API key for Agent Engine Express Mode
      --agent_engine_id                  Agent Engine instance ID to update
      --display_name                     Display name of the agent in Agent Engine
      --description                      Description of the agent in Agent Engine
      --agent_engine_config_file         Filepath to .agent_engine_config.json
      --worker_pool                      Cloud Build private worker pool resource name
      --service_account                  Service account email for the deployed runtime
      --cluster_name                     GKE cluster name
      --service_type                     Kubernetes Service type: ClusterIP | LoadBalancer (default: ClusterIP)
      --dry-run                          Print deploy command only, do not execute
  -h, --help                             Show this help message
''';

const Set<String> _reservedExtraPackageNames = <String>{
  'agent',
  'agents',
  'src',
  'lib',
  'bin',
  'include',
  'share',
  'pyvenv.cfg',
};

final RegExp _serviceAccountEmailPattern = RegExp(
  r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
);

/// Validates that [serviceAccount] is a well-formed email address.
///
/// Throws an [ArgumentError] when [serviceAccount] is non-null and invalid.
void validateServiceAccountEmail(String? serviceAccount) {
  if (serviceAccount == null) {
    return;
  }
  if (!_serviceAccountEmailPattern.hasMatch(serviceAccount)) {
    throw ArgumentError(
      'Invalid service account email format: $serviceAccount',
    );
  }
}

/// Validates `--extra_packages` paths against traversal, reserved names, and collisions.
///
/// Throws an [ArgumentError] when any entry is invalid or collides.
void validateExtraPackages(List<String> extraPackages) {
  final Set<String> seenBasenames = <String>{};
  for (final String rawPath in extraPackages) {
    final String trimmed = rawPath.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('--extra_packages entry cannot be empty.');
    }
    final List<String> segments = trimmed
        .replaceAll('\\', '/')
        .split('/')
        .where((String s) => s.isNotEmpty)
        .toList(growable: false);
    if (segments.contains('..') || segments.isEmpty) {
      throw ArgumentError(
        "Invalid --extra_packages path '$rawPath': parent directory traversal ('..') is not allowed.",
      );
    }
    final String basename = segments.last;
    if (basename == '.' || basename == '..') {
      throw ArgumentError("Invalid --extra_packages path '$rawPath'.");
    }
    if (_reservedExtraPackageNames.contains(basename)) {
      throw ArgumentError(
        "Invalid --extra_packages name '$basename': reserved staging name.",
      );
    }
    if (!seenBasenames.add(basename)) {
      throw ArgumentError(
        "Duplicate --extra_packages basename '$basename': each staged package must have a distinct top-level name.",
      );
    }
  }
}

/// Runs the deploy CLI command and returns a process-compatible exit code.
///
/// Returns `0` for help and successful dry-runs, `64` for invalid arguments,
/// and `1` for runtime failures while resolving options.
///
/// ```dart
/// final exitCode = await runDeployCommand([
///   'cloud_run',
///   '--project=my-gcp-project',
///   '--service=my-agent',
///   '--dry-run',
/// ]);
/// ```
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

  final int separatorIndex = args.indexOf('--');
  final List<String> adkArgs = separatorIndex == -1
      ? args
      : args.sublist(0, separatorIndex);
  if (adkArgs.any((String arg) => arg == '--help' || arg == '-h')) {
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

  for (final String warning in options.warnings) {
    err.writeln(warning);
  }

  final DeployCommand command = DeployCommand(
    service: options.service,
    project: options.project,
    region: options.region,
    image: options.image,
    serviceAccount: options.serviceAccount,
    agentFolder: options.agentFolder,
    appName: options.appName,
    tempFolder: options.tempFolder,
    port: options.port,
    traceToCloud: options.traceToCloud,
    otelToCloud: options.otelToCloud,
    withUi: options.withUi,
    adkVersion: options.adkVersion,
    logLevel: options.logLevel,
    allowOrigins: options.allowOrigins,
    sessionServiceUri: options.sessionServiceUri,
    artifactServiceUri: options.artifactServiceUri,
    memoryServiceUri: options.memoryServiceUri,
    useLocalStorage: options.useLocalStorage,
    a2a: options.a2a,
    triggerSources: options.triggerSources,
    triggerOidcAudience: options.triggerOidcAudience,
    triggerOidcServiceAccounts: options.triggerOidcServiceAccounts,
    withCloudRunSandbox: options.withCloudRunSandbox,
    extraPackages: options.extraPackages,
    providerArgs: options.providerArgs,
    envVars: options.envVars,
    apiKey: options.apiKey,
    agentEngineId: options.agentEngineId,
    displayName: options.displayName,
    description: options.description,
    agentEngineConfigFile: options.agentEngineConfigFile,
    workerPool: options.workerPool,
    clusterName: options.clusterName,
    serviceType: options.serviceType,
    extraArgs: options.extraArgs,
  );
  final List<String> gcloudCommand = switch (options.target) {
    DeployTarget.cloudRun => toCloudRun(command),
    DeployTarget.docker => toDocker(command),
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

/// Parses [args] into a typed [DeployCliOptions] instance.
DeployCliOptions parseDeployCliOptions(
  List<String> args, {
  Map<String, String>? env,
}) {
  return _parseDeployOptions(args, env: env ?? Platform.environment);
}

DeployCliOptions _parseDeployOptions(
  List<String> args, {
  required Map<String, String> env,
}) {
  String targetRaw = 'cloud_run';
  bool targetExplicitlySet = false;
  bool positionalTargetConsumed = false;
  String service = 'adk-service';
  String? project;
  String region = 'us-central1';
  String? image;
  String? serviceAccount;
  String? agentFolder;
  String? appName;
  String? tempFolder;
  int port = 8000;
  bool traceToCloud = false;
  bool otelToCloud = false;
  bool withUi = false;
  String? adkVersion;
  String logLevel = 'INFO';
  final List<String> allowOrigins = <String>[];
  String? sessionServiceUri;
  String? artifactServiceUri;
  String? memoryServiceUri;
  String? deprecatedSessionDbUrl;
  String? deprecatedArtifactStorageUri;
  bool? explicitUseLocalStorage;
  bool a2a = false;
  String? triggerSources;
  String? triggerOidcAudience;
  String? triggerOidcServiceAccounts;
  bool withCloudRunSandbox = false;
  final List<String> extraPackages = <String>[];
  final List<String> providerArgs = <String>[];
  final List<String> envVars = <String>[];
  String? apiKey;
  String? agentEngineId;
  String displayName = '';
  String description = '';
  String agentEngineConfigFile = '';
  String? workerPool;
  String? clusterName;
  String serviceType = 'ClusterIP';
  bool validateAgentImport = false;
  bool skipAgentImportValidation = false;
  bool dryRun = false;
  final List<String> warnings = <String>[];
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
      targetExplicitlySet = true;
      i += 1;
      continue;
    }
    if (arg.startsWith('--target=')) {
      targetRaw = arg.substring('--target='.length);
      targetExplicitlySet = true;
      continue;
    }
    if (arg == '--service' || arg == '--service_name' || arg == '--service-name') {
      service = _nextArg(args, i, arg);
      i += 1;
      continue;
    }
    if (arg.startsWith('--service=')) {
      service = arg.substring('--service='.length);
      continue;
    }
    if (arg.startsWith('--service_name=')) {
      service = arg.substring('--service_name='.length);
      continue;
    }
    if (arg.startsWith('--service-name=')) {
      service = arg.substring('--service-name='.length);
      continue;
    }
    if (arg == '--app_name' || arg == '--app-name') {
      appName = _nextArg(args, i, arg);
      i += 1;
      continue;
    }
    if (arg.startsWith('--app_name=')) {
      appName = arg.substring('--app_name='.length);
      continue;
    }
    if (arg.startsWith('--app-name=')) {
      appName = arg.substring('--app-name='.length);
      continue;
    }
    if (arg == '--temp_folder' || arg == '--temp-folder') {
      tempFolder = _nextArg(args, i, arg);
      i += 1;
      continue;
    }
    if (arg.startsWith('--temp_folder=')) {
      tempFolder = arg.substring('--temp_folder='.length);
      continue;
    }
    if (arg.startsWith('--temp-folder=')) {
      tempFolder = arg.substring('--temp-folder='.length);
      continue;
    }
    if (arg == '--port' || arg == '-p') {
      final int? parsedPort = int.tryParse(_nextArg(args, i, arg));
      if (parsedPort == null || parsedPort < 0 || parsedPort > 65535) {
        throw ArgumentError('Invalid port for deploy.');
      }
      port = parsedPort;
      i += 1;
      continue;
    }
    if (arg.startsWith('--port=')) {
      final int? parsedPort = int.tryParse(arg.substring('--port='.length));
      if (parsedPort == null || parsedPort < 0 || parsedPort > 65535) {
        throw ArgumentError('Invalid port for deploy.');
      }
      port = parsedPort;
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
    if (arg == '--service_account' || arg == '--service-account') {
      serviceAccount = _nextArg(args, i, arg);
      i += 1;
      continue;
    }
    if (arg.startsWith('--service_account=')) {
      serviceAccount = arg.substring('--service_account='.length);
      continue;
    }
    if (arg.startsWith('--service-account=')) {
      serviceAccount = arg.substring('--service-account='.length);
      continue;
    }
    if (arg == '--trace_to_cloud') {
      traceToCloud = true;
      continue;
    }
    if (arg == '--no-trace_to_cloud' || arg == '--no_trace_to_cloud') {
      traceToCloud = false;
      continue;
    }
    if (arg == '--otel_to_cloud') {
      otelToCloud = true;
      continue;
    }
    if (arg == '--with_ui' || arg == '--with-ui') {
      withUi = true;
      continue;
    }
    if (arg == '--adk_version' || arg == '--adk-version') {
      adkVersion = _nextArg(args, i, arg);
      i += 1;
      continue;
    }
    if (arg.startsWith('--adk_version=')) {
      adkVersion = arg.substring('--adk_version='.length);
      continue;
    }
    if (arg.startsWith('--adk-version=')) {
      adkVersion = arg.substring('--adk-version='.length);
      continue;
    }
    if (arg == '--log_level' || arg == '--verbosity') {
      if (arg == '--verbosity') {
        warnings.add(
          'WARNING: Deprecated option --verbosity is used. Please use --log_level instead.',
        );
      }
      logLevel = _validateDeployLogLevel(_nextArg(args, i, arg));
      i += 1;
      continue;
    }
    if (arg.startsWith('--log_level=')) {
      logLevel = _validateDeployLogLevel(arg.substring('--log_level='.length));
      continue;
    }
    if (arg.startsWith('--verbosity=')) {
      warnings.add(
        'WARNING: Deprecated option --verbosity is used. Please use --log_level instead.',
      );
      logLevel = _validateDeployLogLevel(arg.substring('--verbosity='.length));
      continue;
    }
    if (arg == '--allow_origins' || arg == '--allow-origins') {
      allowOrigins.add(_nextArg(args, i, arg));
      i += 1;
      continue;
    }
    if (arg.startsWith('--allow_origins=')) {
      allowOrigins.add(arg.substring('--allow_origins='.length));
      continue;
    }
    if (arg.startsWith('--allow-origins=')) {
      allowOrigins.add(arg.substring('--allow-origins='.length));
      continue;
    }
    if (arg == '--a2a') {
      a2a = true;
      continue;
    }
    if (arg == '--session_service_uri') {
      sessionServiceUri = _nextArg(args, i, arg);
      i += 1;
      continue;
    }
    if (arg.startsWith('--session_service_uri=')) {
      sessionServiceUri = arg.substring('--session_service_uri='.length);
      continue;
    }
    if (arg == '--artifact_service_uri') {
      artifactServiceUri = _nextArg(args, i, arg);
      i += 1;
      continue;
    }
    if (arg.startsWith('--artifact_service_uri=')) {
      artifactServiceUri = arg.substring('--artifact_service_uri='.length);
      continue;
    }
    if (arg == '--memory_service_uri') {
      memoryServiceUri = _nextArg(args, i, arg);
      i += 1;
      continue;
    }
    if (arg.startsWith('--memory_service_uri=')) {
      memoryServiceUri = arg.substring('--memory_service_uri='.length);
      continue;
    }
    if (arg == '--session_db_url') {
      warnings.add(
        'WARNING: Deprecated option --session_db_url is used. Please use --session_service_uri instead.',
      );
      deprecatedSessionDbUrl = _nextArg(args, i, arg);
      i += 1;
      continue;
    }
    if (arg.startsWith('--session_db_url=')) {
      warnings.add(
        'WARNING: Deprecated option --session_db_url is used. Please use --session_service_uri instead.',
      );
      deprecatedSessionDbUrl = arg.substring('--session_db_url='.length);
      continue;
    }
    if (arg == '--artifact_storage_uri') {
      warnings.add(
        'WARNING: Deprecated option --artifact_storage_uri is used. Please use --artifact_service_uri instead.',
      );
      deprecatedArtifactStorageUri = _nextArg(args, i, arg);
      i += 1;
      continue;
    }
    if (arg.startsWith('--artifact_storage_uri=')) {
      warnings.add(
        'WARNING: Deprecated option --artifact_storage_uri is used. Please use --artifact_service_uri instead.',
      );
      deprecatedArtifactStorageUri = arg.substring(
        '--artifact_storage_uri='.length,
      );
      continue;
    }
    if (arg == '--use_local_storage') {
      explicitUseLocalStorage = true;
      continue;
    }
    if (arg == '--no_use_local_storage' || arg == '--no-use_local_storage') {
      explicitUseLocalStorage = false;
      continue;
    }
    if (arg == '--trigger_sources' || arg == '--trigger-sources') {
      triggerSources = _nextArg(args, i, arg);
      i += 1;
      continue;
    }
    if (arg.startsWith('--trigger_sources=')) {
      triggerSources = arg.substring('--trigger_sources='.length);
      continue;
    }
    if (arg.startsWith('--trigger-sources=')) {
      triggerSources = arg.substring('--trigger-sources='.length);
      continue;
    }
    if (arg == '--trigger_oidc_audience' || arg == '--trigger-oidc-audience') {
      triggerOidcAudience = _nextArg(args, i, arg);
      i += 1;
      continue;
    }
    if (arg.startsWith('--trigger_oidc_audience=')) {
      triggerOidcAudience = arg.substring('--trigger_oidc_audience='.length);
      continue;
    }
    if (arg.startsWith('--trigger-oidc-audience=')) {
      triggerOidcAudience = arg.substring('--trigger-oidc-audience='.length);
      continue;
    }
    if (arg == '--trigger_oidc_service_accounts' ||
        arg == '--trigger-oidc-service-accounts') {
      triggerOidcServiceAccounts = _nextArg(args, i, arg);
      i += 1;
      continue;
    }
    if (arg.startsWith('--trigger_oidc_service_accounts=')) {
      triggerOidcServiceAccounts = arg.substring(
        '--trigger_oidc_service_accounts='.length,
      );
      continue;
    }
    if (arg.startsWith('--trigger-oidc-service-accounts=')) {
      triggerOidcServiceAccounts = arg.substring(
        '--trigger-oidc-service-accounts='.length,
      );
      continue;
    }
    if (arg == '--with_cloud_run_sandbox' || arg == '--with-cloud-run-sandbox') {
      withCloudRunSandbox = true;
      continue;
    }
    if (arg == '--extra_packages' || arg == '--extra-packages') {
      extraPackages.add(_nextArg(args, i, arg));
      i += 1;
      continue;
    }
    if (arg.startsWith('--extra_packages=')) {
      extraPackages.add(arg.substring('--extra_packages='.length));
      continue;
    }
    if (arg.startsWith('--extra-packages=')) {
      extraPackages.add(arg.substring('--extra-packages='.length));
      continue;
    }
    if (arg == '-a' || arg == '--provider-args' || arg == '--provider_args') {
      providerArgs.add(_validateKeyValueOption(_nextArg(args, i, arg), arg));
      i += 1;
      continue;
    }
    if (arg.startsWith('--provider-args=')) {
      providerArgs.add(
        _validateKeyValueOption(
          arg.substring('--provider-args='.length),
          '--provider-args',
        ),
      );
      continue;
    }
    if (arg.startsWith('--provider_args=')) {
      providerArgs.add(
        _validateKeyValueOption(
          arg.substring('--provider_args='.length),
          '--provider_args',
        ),
      );
      continue;
    }
    if (arg == '-e' || arg == '--env') {
      envVars.add(_validateKeyValueOption(_nextArg(args, i, arg), arg));
      i += 1;
      continue;
    }
    if (arg.startsWith('--env=')) {
      envVars.add(
        _validateKeyValueOption(arg.substring('--env='.length), '--env'),
      );
      continue;
    }
    if (arg == '--api_key' || arg == '--api-key') {
      apiKey = _nextArg(args, i, arg);
      i += 1;
      continue;
    }
    if (arg.startsWith('--api_key=')) {
      apiKey = arg.substring('--api_key='.length);
      continue;
    }
    if (arg.startsWith('--api-key=')) {
      apiKey = arg.substring('--api-key='.length);
      continue;
    }
    if (arg == '--staging_bucket' ||
        arg == '--adk_app' ||
        arg == '--adk_app_object' ||
        arg == '--env_file' ||
        arg == '--requirements_file') {
      warnings.add(
        'WARNING: Deprecated option $arg is used and will be removed in the future.',
      );
      _nextArg(args, i, arg);
      i += 1;
      continue;
    }
    if (arg.startsWith('--staging_bucket=') ||
        arg.startsWith('--adk_app=') ||
        arg.startsWith('--adk_app_object=') ||
        arg.startsWith('--env_file=') ||
        arg.startsWith('--requirements_file=')) {
      final String flagName = arg.substring(0, arg.indexOf('='));
      warnings.add(
        'WARNING: Deprecated option $flagName is used and will be removed in the future.',
      );
      continue;
    }
    if (arg == '--absolutize_imports' ||
        arg.startsWith('--absolutize_imports=')) {
      warnings.add(
        'WARNING: Deprecated option --absolutize_imports is used and will be removed in the future.',
      );
      if (arg == '--absolutize_imports' &&
          i + 1 < args.length &&
          (args[i + 1] == 'true' || args[i + 1] == 'false')) {
        i += 1;
      }
      continue;
    }
    if (arg == '--agent_engine_id' || arg == '--agent-engine-id') {
      agentEngineId = _nextArg(args, i, arg);
      i += 1;
      continue;
    }
    if (arg.startsWith('--agent_engine_id=')) {
      agentEngineId = arg.substring('--agent_engine_id='.length);
      continue;
    }
    if (arg.startsWith('--agent-engine-id=')) {
      agentEngineId = arg.substring('--agent-engine-id='.length);
      continue;
    }
    if (arg == '--display_name' || arg == '--display-name') {
      displayName = _nextArg(args, i, arg);
      i += 1;
      continue;
    }
    if (arg.startsWith('--display_name=')) {
      displayName = arg.substring('--display_name='.length);
      continue;
    }
    if (arg.startsWith('--display-name=')) {
      displayName = arg.substring('--display-name='.length);
      continue;
    }
    if (arg == '--description') {
      description = _nextArg(args, i, arg);
      i += 1;
      continue;
    }
    if (arg.startsWith('--description=')) {
      description = arg.substring('--description='.length);
      continue;
    }
    if (arg == '--agent_engine_config_file' ||
        arg == '--agent-engine-config-file') {
      agentEngineConfigFile = _nextArg(args, i, arg);
      i += 1;
      continue;
    }
    if (arg.startsWith('--agent_engine_config_file=')) {
      agentEngineConfigFile = arg.substring(
        '--agent_engine_config_file='.length,
      );
      continue;
    }
    if (arg.startsWith('--agent-engine-config-file=')) {
      agentEngineConfigFile = arg.substring(
        '--agent-engine-config-file='.length,
      );
      continue;
    }
    if (arg == '--validate-agent-import') {
      validateAgentImport = true;
      continue;
    }
    if (arg == '--no-validate-agent-import') {
      validateAgentImport = false;
      continue;
    }
    if (arg == '--skip-agent-import-validation') {
      skipAgentImportValidation = true;
      continue;
    }
    if (arg == '--worker_pool' || arg == '--worker-pool') {
      workerPool = _nextArg(args, i, arg);
      i += 1;
      continue;
    }
    if (arg.startsWith('--worker_pool=')) {
      workerPool = arg.substring('--worker_pool='.length);
      continue;
    }
    if (arg.startsWith('--worker-pool=')) {
      workerPool = arg.substring('--worker-pool='.length);
      continue;
    }
    if (arg == '--cluster_name' || arg == '--cluster-name') {
      clusterName = _nextArg(args, i, arg);
      i += 1;
      continue;
    }
    if (arg.startsWith('--cluster_name=')) {
      clusterName = arg.substring('--cluster_name='.length);
      continue;
    }
    if (arg.startsWith('--cluster-name=')) {
      clusterName = arg.substring('--cluster-name='.length);
      continue;
    }
    if (arg == '--service_type' || arg == '--service-type') {
      serviceType = _validateGkeServiceType(_nextArg(args, i, arg));
      i += 1;
      continue;
    }
    if (arg.startsWith('--service_type=')) {
      serviceType = _validateGkeServiceType(
        arg.substring('--service_type='.length),
      );
      continue;
    }
    if (arg.startsWith('--service-type=')) {
      serviceType = _validateGkeServiceType(
        arg.substring('--service-type='.length),
      );
      continue;
    }
    if (arg == '--dry-run') {
      dryRun = true;
      continue;
    }

    if (!arg.startsWith('-') &&
        !targetExplicitlySet &&
        !positionalTargetConsumed) {
      try {
        _parseDeployTarget(arg);
        targetRaw = arg;
        positionalTargetConsumed = true;
        continue;
      } on ArgumentError {
        // Not a target name; treat as agent folder or extra arg.
      }
    }
    if (!arg.startsWith('-') && agentFolder == null) {
      agentFolder = arg;
      continue;
    }
    extraArgs.add(arg);
  }

  if (validateAgentImport && skipAgentImportValidation) {
    throw ArgumentError(
      'Do not pass both --validate-agent-import and --skip-agent-import-validation.',
    );
  }

  sessionServiceUri ??= deprecatedSessionDbUrl;
  artifactServiceUri ??= deprecatedArtifactStorageUri;

  if (explicitUseLocalStorage != null &&
      ((sessionServiceUri != null && sessionServiceUri.trim().isNotEmpty) ||
          (artifactServiceUri != null &&
              artifactServiceUri.trim().isNotEmpty))) {
    throw ArgumentError(
      'Cannot specify both --use_local_storage/--no_use_local_storage and --session_service_uri or --artifact_service_uri.',
    );
  }

  if (withUi) {
    warnings.add(
      'WARNING: --with_ui is enabled. The ADK web UI is for development and testing only — do not use in production.',
    );
  }

  validateExtraPackages(extraPackages);

  final DeployTarget resolvedTarget = _parseDeployTarget(targetRaw);
  final String resolvedProject =
      resolvedTarget == DeployTarget.docker ||
          (resolvedTarget == DeployTarget.agentEngine &&
              apiKey != null &&
              apiKey.trim().isNotEmpty)
      ? (project?.trim().isNotEmpty == true
            ? project!.trim()
            : (env['GOOGLE_CLOUD_PROJECT']?.trim() ?? ''))
      : resolveProject(project, env: env);
  final String resolvedService =
      (clusterName != null &&
          clusterName.trim().isNotEmpty &&
          resolvedTarget == DeployTarget.gke &&
          service == 'adk-service')
      ? clusterName.trim()
      : (service.trim().isEmpty ? 'adk-service' : service.trim());
  final String resolvedRegion = region.trim().isEmpty
      ? 'us-central1'
      : region.trim();
  final String resolvedImage = image == null || image.trim().isEmpty
      ? (resolvedProject.isEmpty
            ? 'adk-service:latest'
            : 'gcr.io/$resolvedProject/adk-service:latest')
      : image.trim();
  final String? resolvedServiceAccount =
      serviceAccount == null || serviceAccount.trim().isEmpty
      ? null
      : serviceAccount.trim();
  validateServiceAccountEmail(resolvedServiceAccount);

  final bool defaultUseLocalStorage = resolvedTarget == DeployTarget.docker;

  return DeployCliOptions(
    target: resolvedTarget,
    service: resolvedService,
    project: resolvedProject,
    region: resolvedRegion,
    image: resolvedImage,
    serviceAccount: resolvedServiceAccount,
    agentFolder: agentFolder,
    appName: appName,
    tempFolder: tempFolder,
    port: port,
    traceToCloud: traceToCloud,
    otelToCloud: otelToCloud,
    withUi: withUi,
    adkVersion: adkVersion,
    logLevel: logLevel,
    allowOrigins: allowOrigins,
    sessionServiceUri: sessionServiceUri,
    artifactServiceUri: artifactServiceUri,
    memoryServiceUri: memoryServiceUri,
    useLocalStorage: explicitUseLocalStorage ?? defaultUseLocalStorage,
    a2a: a2a,
    triggerSources: triggerSources,
    triggerOidcAudience: triggerOidcAudience,
    triggerOidcServiceAccounts: triggerOidcServiceAccounts,
    withCloudRunSandbox: withCloudRunSandbox,
    extraPackages: extraPackages,
    providerArgs: providerArgs,
    envVars: envVars,
    apiKey: apiKey,
    agentEngineId: agentEngineId,
    displayName: displayName,
    description: description,
    agentEngineConfigFile: agentEngineConfigFile,
    workerPool: workerPool,
    clusterName: clusterName,
    serviceType: serviceType,
    warnings: warnings,
    extraArgs: extraArgs,
    dryRun: dryRun,
  );
}

String _validateDeployLogLevel(String raw) {
  final String upper = raw.trim().toUpperCase();
  const Set<String> allowed = <String>{
    'DEBUG',
    'INFO',
    'WARNING',
    'ERROR',
    'CRITICAL',
  };
  if (!allowed.contains(upper)) {
    throw ArgumentError(
      'Invalid log level: $raw. Allowed values: DEBUG, INFO, WARNING, ERROR, CRITICAL.',
    );
  }
  return upper;
}

String _validateGkeServiceType(String raw) {
  final String trimmed = raw.trim();
  if (trimmed != 'ClusterIP' && trimmed != 'LoadBalancer') {
    throw ArgumentError(
      "Invalid value for '--service_type': '$raw' is not one of 'ClusterIP', 'LoadBalancer'.",
    );
  }
  return trimmed;
}

String _validateKeyValueOption(String raw, String option) {
  if (!raw.contains('=')) {
    throw ArgumentError(
      "Invalid value for '$option': '$raw' must be in KEY=VALUE format.",
    );
  }
  final String key = raw.substring(0, raw.indexOf('=')).trim();
  if (key.isEmpty) {
    throw ArgumentError(
      "Invalid value for '$option': '$raw' must have a non-empty KEY.",
    );
  }
  return raw;
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
    case 'docker':
      return DeployTarget.docker;
    case 'agent_engine':
    case 'agent-engine':
    case 'agentengine':
      return DeployTarget.agentEngine;
    case 'gke':
      return DeployTarget.gke;
    default:
      throw ArgumentError(
        'Unknown deploy target: $value. '
        'Allowed values: cloud_run, docker, agent_engine, gke.',
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

/// The resolved Google Cloud project ID for deployment.
///
/// [projectInOption] takes precedence over `GOOGLE_CLOUD_PROJECT`.
/// Throws a [StateError] when neither source provides a value.
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

/// Validates raw `gcloud` passthrough [args].
///
/// Throws an [ArgumentError] when an argument contains newline characters.
void validateGcloudExtraArgs(List<String> args) {
  for (final String arg in args) {
    if (arg.contains('\n') || arg.contains('\r')) {
      throw ArgumentError('Invalid gcloud extra arg: $arg');
    }
  }
}

/// The `gcloud run deploy` command built from [command].
List<String> toCloudRun(DeployCommand command) {
  validateGcloudExtraArgs(command.extraArgs);
  validateServiceAccountEmail(command.serviceAccount);
  validateExtraPackages(command.extraPackages);
  return <String>[
    'gcloud',
    if (command.withCloudRunSandbox) 'beta',
    'run',
    'deploy',
    command.service,
    '--project',
    command.project,
    '--region',
    command.region,
    '--image',
    command.image,
    if (command.serviceAccount != null) ...<String>[
      '--service-account',
      command.serviceAccount!,
    ],
    if (command.withCloudRunSandbox) '--execution-environment=gen2',
    ...command.extraArgs,
  ];
}

/// The `docker run` command built from [command].
List<String> toDocker(DeployCommand command) {
  validateGcloudExtraArgs(command.extraArgs);
  return <String>[
    'docker',
    'run',
    '--rm',
    '-p',
    '${command.port}:${command.port}',
    '--name',
    command.service,
    for (final String envVar in command.envVars) ...<String>['-e', envVar],
    command.image,
    ...command.extraArgs,
  ];
}

/// The `gcloud alpha ai reasoning-engines deploy` command from [command].
List<String> toAgentEngine(DeployCommand command) {
  validateGcloudExtraArgs(command.extraArgs);
  validateServiceAccountEmail(command.serviceAccount);
  validateExtraPackages(command.extraPackages);
  return <String>[
    'gcloud',
    'alpha',
    'ai',
    'reasoning-engines',
    'deploy',
    if (command.project.isNotEmpty) ...<String>['--project', command.project],
    '--region',
    command.region,
    '--image',
    command.image,
    if (command.serviceAccount != null) ...<String>[
      '--service-account',
      command.serviceAccount!,
    ],
    if (command.workerPool != null && command.workerPool!.isNotEmpty) ...<String>[
      '--worker-pool',
      command.workerPool!,
    ],
    ...command.extraArgs,
  ];
}

/// The `gcloud container clusters get-credentials` command from [command].
List<String> toGke(DeployCommand command) {
  validateGcloudExtraArgs(command.extraArgs);
  validateExtraPackages(command.extraPackages);
  return <String>[
    'gcloud',
    'container',
    'clusters',
    'get-credentials',
    command.clusterName?.isNotEmpty == true
        ? command.clusterName!
        : command.service,
    '--project',
    command.project,
    '--region',
    command.region,
    ...command.extraArgs,
  ];
}
