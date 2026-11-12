/// Development web/API server implementation used by ADK CLI commands.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:adk_dart/src/a2a/executor/a2a_agent_executor.dart';
import 'package:meta/meta.dart';
import 'package:adk_dart/src/a2a/protocol.dart';
import 'package:adk_dart/src/a2a/utils/agent_card_builder.dart';
import 'package:adk_dart/src/agents/abort_signal.dart';
import 'package:adk_dart/src/agents/base_agent.dart';
import 'package:adk_dart/src/agents/live_request_queue.dart';
import 'package:adk_dart/src/agents/llm_agent.dart';
import 'package:adk_dart/src/agents/run_config.dart';
import 'package:adk_dart/src/apps/app.dart';
import 'package:adk_dart/src/artifacts/base_artifact_service.dart';
import '../cli/_dev_deploy.dart' as dev_deploy;
import '../cli/agent_graph.dart' as agent_graph;
import '../cli/api_server.dart'
    show
        AgentIdentityApiException,
        AgentIdentityInvalidArgumentException,
        AgentIdentityMissingDependencyException,
        FinalizeAgentIdentityCredentialsRequest,
        W3cTraceContext,
        extractW3cTraceContext,
        finalizeAgentIdentityCredentials;
import '../cli/trigger_routes.dart';
import '../cli/utils/agent_loader.dart';
import '../cli/utils/base_agent_loader.dart'
    as base_loader
    show BaseAgentLoader, asBaseAgent, isStandaloneWorkflowNode;
import 'package:adk_dart/src/errors/invocation_not_found_error.dart';
import 'package:adk_dart/src/errors/session_not_found_error.dart';
import 'package:adk_dart/src/events/event.dart';
import 'package:adk_dart/src/events/internal_metadata.dart';
import '../cli/utils/evals.dart' as cli_evals;
import '../cli/utils/graph_serialization.dart' as graph_serialization;
import '../cli/service_registry.dart';
import '../cli/plugins/conformance_recordings_plugin.dart';
import '../cli/plugins/conformance_replay_plugin.dart';
import '../cli/utils/service_factory.dart';
import 'package:adk_dart/src/evaluation/base_eval_service.dart';
import 'package:adk_dart/src/evaluation/eval_case.dart';
import 'package:adk_dart/src/evaluation/eval_metric.dart';
import 'package:adk_dart/src/evaluation/eval_metrics.dart';
import 'package:adk_dart/src/evaluation/eval_result.dart';
import 'package:adk_dart/src/evaluation/eval_set.dart';
import 'package:adk_dart/src/evaluation/eval_set_results_manager.dart';
import 'package:adk_dart/src/evaluation/eval_sets_manager.dart';
import 'package:adk_dart/src/evaluation/in_memory_eval_set_results_manager.dart';
import 'package:adk_dart/src/evaluation/in_memory_eval_sets_manager.dart';
import 'package:adk_dart/src/evaluation/local_eval_service.dart';
import 'package:adk_dart/src/evaluation/local_eval_set_results_manager.dart';
import 'package:adk_dart/src/evaluation/local_eval_sets_manager.dart';
import 'package:adk_dart/src/evaluation/metric_evaluator_registry.dart';
import 'package:adk_dart/src/errors/not_found_error.dart';
import '../version.dart';
import 'package:adk_dart/src/events/event_actions.dart';
import 'package:adk_dart/src/memory/base_memory_service.dart';
import 'package:adk_dart/src/models/llm_request.dart';
import 'package:adk_dart/src/plugins/base_plugin.dart';
import 'package:adk_dart/src/plugins/context_filter_plugin.dart';
import 'package:adk_dart/src/plugins/debug_logging_plugin.dart';
import 'package:adk_dart/src/plugins/global_instruction_plugin.dart';
import 'package:adk_dart/src/plugins/logging_plugin.dart';
import 'package:adk_dart/src/plugins/multimodal_tool_results_plugin.dart';
import 'package:adk_dart/src/plugins/reflect_retry_tool_plugin.dart';
import 'package:adk_dart/src/utils/telemetry_config.dart';
import 'package:adk_dart/src/plugins/save_files_as_artifacts_plugin.dart';
import 'package:adk_dart/src/runners/runner.dart';
import 'package:adk_dart/src/sessions/base_session_service.dart';
import 'package:adk_dart/src/sessions/session.dart';
import 'package:adk_dart/src/sessions/schemas/v0.dart';
import 'package:adk_dart/src/telemetry/google_cloud.dart';
import 'package:adk_dart/src/telemetry/setup.dart';
import 'package:adk_dart/src/telemetry/sqlite_span_exporter.dart';
import 'package:adk_dart/src/types/content.dart';
import 'package:adk_dart/src/tools/_automatic_function_calling_util.dart';
import 'package:adk_dart/src/tools/base_tool.dart';
import 'package:adk_dart/src/tools/base_toolset.dart';
import 'package:adk_dart/src/tools/computer_use/computer_use_toolset.dart';
import 'package:adk_dart/src/workflow/workflow.dart';
import 'a2a_push_delivery_queue.dart';
import 'project.dart';
import 'runtime.dart';


part 'web_server_session_and_run_routes.dart';
part 'web_server_eval_and_a2a_routes.dart';
part 'web_server_assets_and_helpers.dart';
/// Sentinel indicating that default evaluation managers should be created from options.
const Object defaultEvalManagerSentinel = Object();

/// Decodes a `data:...;base64,...` URL into a UTF-8 text string, matching
/// `ContentBubbleComponent.getTextContent` in ADK Web.
String decodeDataUrlTextContentUtf8(String? dataUrl) {
  if (dataUrl == null || dataUrl.isEmpty) {
    return '';
  }
  final int commaIndex = dataUrl.indexOf(',');
  if (commaIndex == -1) {
    return '';
  }
  final String base64Part = dataUrl.substring(commaIndex + 1);
  try {
    final List<int> bytes = base64Decode(base64Part);
    return utf8.decode(bytes);
  } catch (_) {
    return 'Failed to decode text content';
  }
}

/// Starts the ADK development web server and returns the bound [HttpServer].
///
/// The server exposes API routes and optionally serves the bundled web UI.
///
/// ```dart
/// final project = DevProjectConfig(
///   appName: 'my_agent',
///   agentName: 'assistant',
///   userId: 'user',
/// );
/// final runtime = DevAgentRuntime(config: project);
/// final server = await startAdkDevWebServer(
///   runtime: runtime,
///   project: project,
///   port: 8000,
/// );
/// await server.close(force: true);
/// await runtime.runner.close();
/// ```
Future<HttpServer> startAdkDevWebServer({
  required DevAgentRuntime runtime,
  required DevProjectConfig project,
  String agentsDir = '.',
  int port = 8000,
  InternetAddress? host,
  List<String> allowOrigins = const <String>[],
  String? sessionServiceUri,
  String? artifactServiceUri,
  String? memoryServiceUri,
  String? evalStorageUri,
  bool useLocalStorage = true,
  String? urlPrefix,
  bool autoCreateSession = false,
  bool enableWebUi = true,
  String? logoText,
  String? logoImageUrl,
  Map<String, String>? avatarConfig,
  int? maxLlmCalls,
  String? defaultLlmModel,
  bool reload = true,
  bool reloadAgents = false,
  bool traceToCloud = false,
  bool otelToCloud = false,
  bool a2a = false,
  List<String> extraPlugins = const <String>[],
  List<String> triggerSources = const <String>[],
  String? triggerOidcAudience,
  List<String> triggerOidcServiceAccounts = const <String>[],
  TriggerAuthVerifier? triggerAuthVerifier,
  String? geminiEnterpriseAppName,
  bool expressMode = false,
  base_loader.BaseAgentLoader? agentLoader,
  Map<String, String>? environment,
  int maxLiveMessageBytes = 16 * 1024 * 1024,
  Duration liveKeepaliveTimeout = const Duration(seconds: 40),
  int maxLiveSessions = 0,
  Object? evalSetsManager = defaultEvalManagerSentinel,
  Object? evalSetResultsManager = defaultEvalManagerSentinel,
}) async {
  if (port < 0 || port > 65535) {
    throw ArgumentError.value(port, 'port', 'Port must be between 0 and 65535');
  }

  if (expressMode &&
      (geminiEnterpriseAppName == null ||
          geminiEnterpriseAppName.trim().isEmpty)) {
    throw ArgumentError(
      '--express_mode is only supported when --gemini_enterprise_app_name is set.',
    );
  }

  if (defaultLlmModel != null && defaultLlmModel.trim().isNotEmpty) {
    LlmAgent.setDefaultModel(defaultLlmModel.trim());
  }

  final bool hasLogoText = logoText != null && logoText.isNotEmpty;
  final bool hasLogoImage = logoImageUrl != null && logoImageUrl.isNotEmpty;
  if (hasLogoText != hasLogoImage) {
    throw ArgumentError(
      'Both --logo-text and --logo-image-url must be defined when using logo config.',
    );
  }

  final InternetAddress resolvedHost = host ?? InternetAddress.loopbackIPv4;
  final Map<String, String> resolvedEnv = environment ?? Platform.environment;
  final List<String> normalizedTriggers = triggerSources
      .map((String s) => s.trim().toLowerCase())
      .where((String s) => s.isNotEmpty)
      .toList(growable: false);
  final bool isLoopback =
      resolvedHost.isLoopback ||
      resolvedHost.address == '127.0.0.1' ||
      resolvedHost.address == '::1' ||
      resolvedHost.address.toLowerCase() == 'localhost';
  final String allowUnauthEnv =
      (resolvedEnv['ADK_ALLOW_UNAUTHENTICATED_TRIGGERS'] ?? '')
          .trim()
          .toLowerCase();
  final bool allowUnauthenticatedTriggers =
      allowUnauthEnv == '1' ||
      allowUnauthEnv == 'true' ||
      allowUnauthEnv == 'yes';
  if (normalizedTriggers.isNotEmpty &&
      !isLoopback &&
      triggerAuthVerifier == null &&
      (triggerOidcAudience == null || triggerOidcAudience.trim().isEmpty) &&
      !allowUnauthenticatedTriggers) {
    throw ArgumentError(
      '--trigger_sources requires --trigger_oidc_audience when --host is not loopback. '
      'Pass --trigger_oidc_audience=<expected-audience> (or set '
      'ADK_ALLOW_UNAUTHENTICATED_TRIGGERS=1 to bypass).',
    );
  }

  final _AdkDevWebContext context = await _AdkDevWebContext.create(
    runtime: runtime,
    project: project,
    agentsDir: agentsDir,
    allowOrigins: allowOrigins,
    sessionServiceUri: sessionServiceUri,
    artifactServiceUri: artifactServiceUri,
    memoryServiceUri: memoryServiceUri,
    evalStorageUri: evalStorageUri,
    useLocalStorage: useLocalStorage,
    urlPrefix: _normalizeUrlPrefix(urlPrefix),
    autoCreateSession: autoCreateSession,
    enableWebUi: enableWebUi,
    logoText: logoText,
    logoImageUrl: logoImageUrl,
    avatarConfig: avatarConfig,
    maxLlmCalls: maxLlmCalls,
    defaultLlmModel: defaultLlmModel,
    reload: reload,
    reloadAgents: reloadAgents,
    traceToCloud: traceToCloud,
    otelToCloud: otelToCloud,
    a2a: a2a,
    extraPlugins: extraPlugins,
    triggerSources: triggerSources,
    triggerOidcAudience: triggerOidcAudience,
    triggerOidcServiceAccounts: triggerOidcServiceAccounts,
    triggerAuthVerifier: triggerAuthVerifier,
    geminiEnterpriseAppName: geminiEnterpriseAppName,
    expressMode: expressMode,
    agentLoader: agentLoader,
    environment: environment,
    maxLiveMessageBytes: maxLiveMessageBytes,
    liveKeepaliveTimeout: liveKeepaliveTimeout,
    maxLiveSessions: maxLiveSessions,
    evalSetsManager: evalSetsManager,
    evalSetResultsManager: evalSetResultsManager,
  );

  final HttpServer server = await HttpServer.bind(resolvedHost, port);
  context.serverHost = resolvedHost.address;
  unawaited(_handleRequests(server, context));
  return server;
}

/// Thrown when an internal special agent (an app name starting with `__`)
/// is requested while the server is not configured to allow it.
///
/// Special agents (such as a built-in agent-builder assistant) may only be
/// loaded when the Dev UI is enabled; API-server-only deployments must
/// reject them to avoid exposing privileged internal tooling.
class SpecialAgentAccessDeniedException implements Exception {
  /// Creates a special-agent access-denied exception.
  const SpecialAgentAccessDeniedException([
    this.message =
        'Access to internal special agents is disabled in API server mode.',
  ]);

  /// Human-readable error message, matching upstream's HTTP detail text.
  final String message;

  @override
  String toString() => 'SpecialAgentAccessDeniedException: $message';
}

// Parsed extra plugin spec from CLI input.
class _ExtraPluginSpec {
  // Creates an extra plugin spec.
  _ExtraPluginSpec({required this.raw, required this.normalizedName});

  // Raw plugin string from CLI.
  final String raw;

  // Normalized plugin key used for built-in matching.
  final String normalizedName;
}

// Eval manager dependencies used by web server endpoints.
class _EvalManagers {
  // Creates eval manager dependencies.
  _EvalManagers({
    required this.evalSetsManager,
    required this.evalSetResultsManager,
  });

  // Eval set CRUD manager.
  final EvalSetsManager evalSetsManager;

  // Eval result persistence manager.
  final EvalSetResultsManager evalSetResultsManager;
}

_EvalManagers _createEvalManagersFromOptions({
  required String baseDir,
  required String? evalStorageUri,
  Map<String, String>? environment,
}) {
  String? normalized = evalStorageUri?.trim();
  if (normalized == null || normalized.isEmpty) {
    final String? envUri =
        (environment ?? Platform.environment)['ADK_EVAL_STORAGE_URI']?.trim();
    if (envUri != null && envUri.isNotEmpty) {
      normalized = envUri;
    }
  }
  if (normalized == null || normalized.isEmpty) {
    return _EvalManagers(
      evalSetsManager: LocalEvalSetsManager(baseDir),
      evalSetResultsManager: LocalEvalSetResultsManager(baseDir),
    );
  }

  if (normalized.startsWith('gs://')) {
    final cli_evals.GcsEvalManagers gcsManagers = cli_evals
        .createGcsEvalManagersFromUri(normalized);
    return _EvalManagers(
      evalSetsManager: gcsManagers.evalSetsManager,
      evalSetResultsManager: gcsManagers.evalSetResultsManager,
    );
  }

  if (normalized == 'memory' ||
      normalized == 'memory://' ||
      normalized.startsWith('memory://')) {
    return _EvalManagers(
      evalSetsManager: InMemoryEvalSetsManager(),
      evalSetResultsManager: InMemoryEvalSetResultsManager(),
    );
  }

  final String localBaseDir = _resolveEvalLocalBaseDir(
    baseDir: baseDir,
    evalStorageUri: normalized,
  );
  if (normalized.startsWith('file:')) {
    try {
      Directory(localBaseDir).createSync(recursive: true);
    } on FileSystemException catch (error) {
      throw ArgumentError(
        "Failed to create eval storage directory '$localBaseDir' for "
        "'$normalized' (configured via --eval_storage_uri or "
        'ADK_EVAL_STORAGE_URI): $error',
      );
    }
  }
  return _EvalManagers(
    evalSetsManager: LocalEvalSetsManager(localBaseDir),
    evalSetResultsManager: LocalEvalSetResultsManager(localBaseDir),
  );
}

String _resolveEvalLocalBaseDir({
  required String baseDir,
  required String evalStorageUri,
}) {
  if (evalStorageUri.startsWith('file:')) {
    final Uri parsed = Uri.parse(evalStorageUri);
    final String authority = parsed.authority.toLowerCase();
    if (authority.isNotEmpty && authority != 'localhost') {
      throw ArgumentError(
        'file:// eval storage URIs must reference the local filesystem.',
      );
    }
    final String afterScheme = evalStorageUri.substring('file:'.length);
    if (!afterScheme.startsWith('/') ||
        !parsed.path.startsWith('/') ||
        parsed.path.isEmpty ||
        parsed.path == '/') {
      throw ArgumentError(
        'file:// eval storage URIs must include an absolute path component.',
      );
    }
    return Uri.decodeFull(parsed.path);
  }

  if (evalStorageUri.contains('://')) {
    throw ArgumentError(
      'Unsupported eval storage URI: $evalStorageUri. '
      'Supported schemes: gs://, memory://, file:// or local directory path.',
    );
  }

  final String candidate = evalStorageUri.trim();
  if (candidate.isEmpty) {
    return baseDir;
  }
  return candidate;
}

class _EvalManagerNotConfiguredException implements Exception {
  const _EvalManagerNotConfiguredException(this.message);

  final String message;

  @override
  String toString() => message;
}

// Per-server runtime context for request handling.
class _AdkDevWebContext {
  // Creates a web server runtime context.
  _AdkDevWebContext({
    required this.runtime,
    required this.project,
    required this.agentsDir,
    required this.agentLoader,
    this.hasExplicitAgentLoader = false,
    required this.environment,
    required this.sessionService,
    required this.artifactService,
    required this.memoryService,
    required this.evalSetsManager,
    required this.evalSetResultsManager,
    required this.evalStorageUri,
    required this.spanExporter,
    required this.allowOrigins,
    required this.urlPrefix,
    required this.autoCreateSession,
    required this.enableWebUi,
    required this.logoText,
    required this.logoImageUrl,
    this.avatarConfig,
    this.maxLlmCalls,
    this.defaultLlmModel,
    this.triggerOidcAudience,
    this.triggerOidcServiceAccounts = const <String>[],
    this.geminiEnterpriseAppName,
    this.expressMode = false,
    required this.reload,
    required this.reloadAgents,
    required this.traceToCloud,
    required this.otelToCloud,
    required this.a2a,
    required this.extraPluginSpecs,
    required this.triggerSources,
    required this.triggerRouter,
    required this.a2aPushQueue,
    required this.webAssetsDir,
    this.maxLiveMessageBytes = 16 * 1024 * 1024,
    this.liveKeepaliveTimeout = const Duration(seconds: 40),
    this.maxLiveSessions = 0,
  });

  final DevAgentRuntime runtime;
  final DevProjectConfig project;
  final String agentsDir;
  final base_loader.BaseAgentLoader agentLoader;
  final bool hasExplicitAgentLoader;
  final Map<String, String> environment;
  final BaseSessionService sessionService;
  final BaseArtifactService artifactService;
  final BaseMemoryService memoryService;
  final EvalSetsManager? evalSetsManager;
  final EvalSetResultsManager? evalSetResultsManager;
  final String? evalStorageUri;
  final SqliteSpanExporter spanExporter;
  final List<String> allowOrigins;
  final String? urlPrefix;
  final bool autoCreateSession;
  final bool enableWebUi;
  final String? logoText;
  final String? logoImageUrl;
  final Map<String, String>? avatarConfig;
  final int? maxLlmCalls;
  final String? defaultLlmModel;
  final String? triggerOidcAudience;
  final List<String> triggerOidcServiceAccounts;
  final String? geminiEnterpriseAppName;
  final bool expressMode;
  final bool reload;
  final bool reloadAgents;
  final bool traceToCloud;
  final bool otelToCloud;
  final bool a2a;
  final List<_ExtraPluginSpec> extraPluginSpecs;
  final List<String> triggerSources;
  final TriggerRouter? triggerRouter;
  final A2aPushDeliveryQueue? a2aPushQueue;
  final Directory? webAssetsDir;
  final int maxLiveMessageBytes;
  final Duration liveKeepaliveTimeout;
  final int maxLiveSessions;
  int activeLiveSessions = 0;

  // Address the server is bound to, set once [HttpServer.bind] resolves.
  //
  // Used for DNS-rebinding protection: when the server is on loopback and
  // no explicit [allowOrigins] are configured, request origins must also
  // resolve to loopback.
  String? serverHost;

  final Map<String, Runner> _runners = <String, Runner>{};
  final Map<(String, String, String), List<AdkAbortController>>
  _activeSessionAbortControllers =
      <(String, String, String), List<AdkAbortController>>{};
  final Map<(String, String, String), List<Future<void>>>
  _activeSessionRunFutures = <(String, String, String), List<Future<void>>>{};
  final Map<String, Map<String, Map<String, Object?>>> _a2aTasksByApp =
      <String, Map<String, Map<String, Object?>>>{};
  final Map<String, Map<String, List<Map<String, Object?>>>>
  _a2aTaskUpdatesByApp = <String, Map<String, List<Map<String, Object?>>>>{};
  final Map<String, Map<String, Map<String, Object?>>> _a2aPushConfigsByApp =
      <String, Map<String, Map<String, Object?>>>{};
  final Map<String, Map<String, Object?>> _traceByEventId =
      <String, Map<String, Object?>>{};
  final Map<String, List<Map<String, Object?>>> _traceBySessionId =
      <String, List<Map<String, Object?>>>{};
  Timer? _a2aPushDeliveryTimer;
  bool _a2aPushDrainInProgress = false;
  static const int _a2aPushDrainBatchSize = 64;

  // Creates and wires context dependencies from CLI/runtime options.
  static Future<_AdkDevWebContext> create({
    required DevAgentRuntime runtime,
    required DevProjectConfig project,
    required String agentsDir,
    required List<String> allowOrigins,
    required String? sessionServiceUri,
    required String? artifactServiceUri,
    required String? memoryServiceUri,
    required String? evalStorageUri,
    required bool useLocalStorage,
    required String? urlPrefix,
    required bool autoCreateSession,
    required bool enableWebUi,
    required String? logoText,
    required String? logoImageUrl,
    Map<String, String>? avatarConfig,
    int? maxLlmCalls,
    String? defaultLlmModel,
    String? triggerOidcAudience,
    List<String> triggerOidcServiceAccounts = const <String>[],
    String? geminiEnterpriseAppName,
    bool expressMode = false,
    required bool reload,
    required bool reloadAgents,
    required bool traceToCloud,
    required bool otelToCloud,
    required bool a2a,
    required List<String> extraPlugins,
    List<String> triggerSources = const <String>[],
    TriggerAuthVerifier? triggerAuthVerifier,
    TriggerRouter? customTriggerRouter,
    base_loader.BaseAgentLoader? agentLoader,
    Map<String, String>? environment,
    int maxLiveMessageBytes = 16 * 1024 * 1024,
    Duration liveKeepaliveTimeout = const Duration(seconds: 40),
    int maxLiveSessions = 0,
    Object? evalSetsManager = defaultEvalManagerSentinel,
    Object? evalSetResultsManager = defaultEvalManagerSentinel,
  }) async {
    final bool hasLogoText = logoText != null && logoText.isNotEmpty;
    final bool hasLogoImage = logoImageUrl != null && logoImageUrl.isNotEmpty;
    if (hasLogoText != hasLogoImage) {
      throw ArgumentError(
        'Both --logo-text and --logo-image-url must be defined when using logo config.',
      );
    }

    if (defaultLlmModel != null && defaultLlmModel.trim().isNotEmpty) {
      LlmAgent.setDefaultModel(defaultLlmModel.trim());
    }

    final Directory agentsRoot = Directory(agentsDir).absolute;
    loadServicesModule(agentsRoot.path);
    final Map<String, String> appNameToDir = _buildAppNameToDir(
      agentsRoot,
      fallbackAppName: project.appName,
    );

    final BaseSessionService sessionService =
        webServerSessionServiceTestingOverride ??
        createSessionServiceFromOptions(
          baseDir: agentsRoot.path,
          sessionServiceUri: sessionServiceUri,
          appNameToDir: appNameToDir,
          useLocalStorage: useLocalStorage,
        );

    final BaseArtifactService artifactService =
        webServerArtifactServiceTestingOverride ??
        createArtifactServiceFromOptions(
          baseDir: agentsRoot.path,
          artifactServiceUri: artifactServiceUri,
          strictUri: true,
          useLocalStorage: useLocalStorage,
        );

    final BaseMemoryService memoryService = createMemoryServiceFromOptions(
      baseDir: agentsRoot.path,
      memoryServiceUri: memoryServiceUri,
    );
    final bool useDefaultEvalSets = identical(
      evalSetsManager,
      defaultEvalManagerSentinel,
    );
    final bool useDefaultEvalResults = identical(
      evalSetResultsManager,
      defaultEvalManagerSentinel,
    );
    final _EvalManagers? evalManagers =
        (useDefaultEvalSets || useDefaultEvalResults)
        ? _createEvalManagersFromOptions(
            baseDir: agentsRoot.path,
            evalStorageUri: evalStorageUri,
            environment: environment,
          )
        : null;
    final EvalSetsManager? resolvedEvalSetsManager = useDefaultEvalSets
        ? evalManagers!.evalSetsManager
        : evalSetsManager as EvalSetsManager?;
    final EvalSetResultsManager? resolvedEvalSetResultsManager =
        useDefaultEvalResults
        ? evalManagers!.evalSetResultsManager
        : evalSetResultsManager as EvalSetResultsManager?;

    final Directory? webAssetsDir = enableWebUi
        ? await _resolveWebAssetsDir()
        : null;
    final List<_ExtraPluginSpec> parsedExtraPlugins = _parseExtraPluginSpecs(
      extraPlugins,
    );
    _configureCloudTelemetry(
      traceToCloud: traceToCloud,
      otelToCloud: otelToCloud,
      environment: environment ?? Platform.environment,
    );
    final A2aPushDeliveryQueue? a2aPushQueue = a2a
        ? A2aPushDeliveryQueue.open(
            dbPath:
                '${agentsRoot.path}${Platform.pathSeparator}.adk${Platform.pathSeparator}a2a_push_delivery.db',
          )
        : null;
    final List<String> normalizedTriggerSources = triggerSources
        .map((String s) => s.trim().toLowerCase())
        .where((String s) => s.isNotEmpty)
        .toList(growable: false);
    late final _AdkDevWebContext context;
    final TriggerRouter? triggerRouter = customTriggerRouter ??
        (normalizedTriggerSources.isEmpty
            ? null
            : TriggerRouter(
                getRunnerAsync: (String appName) => context.getRunner(appName),
                sessionService: sessionService,
                triggerSources: normalizedTriggerSources,
                verifyAuth: triggerAuthVerifier,
              ));
    final Map<String, String> resolvedEnvironment =
        environment ?? Platform.environment;
    context = _AdkDevWebContext(
      runtime: runtime,
      project: project,
      agentsDir: agentsRoot.path,
      agentLoader:
          agentLoader ??
          webServerAgentLoaderTestingOverride?.call(agentsRoot.path) ??
          AgentLoader(agentsRoot.path),
      hasExplicitAgentLoader: agentLoader != null,
      environment: resolvedEnvironment,
      sessionService: sessionService,
      artifactService: artifactService,
      memoryService: memoryService,
      evalSetsManager: resolvedEvalSetsManager,
      evalSetResultsManager: resolvedEvalSetResultsManager,
      evalStorageUri: evalStorageUri,
      spanExporter: SqliteSpanExporter(
        dbPath:
            '${agentsRoot.path}${Platform.pathSeparator}.adk${Platform.pathSeparator}debug_spans.db',
      ),
      allowOrigins: allowOrigins,
      urlPrefix: urlPrefix,
      autoCreateSession: autoCreateSession,
      enableWebUi: enableWebUi,
      logoText: logoText,
      logoImageUrl: logoImageUrl,
      avatarConfig: avatarConfig == null
          ? null
          : Map<String, String>.unmodifiable(avatarConfig),
      maxLlmCalls: maxLlmCalls,
      defaultLlmModel: defaultLlmModel,
      triggerOidcAudience: triggerOidcAudience,
      triggerOidcServiceAccounts: List<String>.unmodifiable(
        triggerOidcServiceAccounts,
      ),
      geminiEnterpriseAppName: geminiEnterpriseAppName,
      expressMode: expressMode,
      reload: reload,
      reloadAgents: reloadAgents,
      traceToCloud: traceToCloud,
      otelToCloud: otelToCloud,
      a2a: a2a,
      extraPluginSpecs: parsedExtraPlugins,
      triggerSources: normalizedTriggerSources,
      triggerRouter: triggerRouter,
      a2aPushQueue: a2aPushQueue,
      webAssetsDir: webAssetsDir,
      maxLiveMessageBytes: maxLiveMessageBytes,
      liveKeepaliveTimeout: liveKeepaliveTimeout,
      maxLiveSessions: maxLiveSessions,
    );
    context._startA2aPushDeliveryLoop();
    return context;
  }

  String get defaultAppName => project.appName;
  String get defaultUserId => project.userId;

  EvalSetsManager _getEvalSetsManager() {
    final EvalSetsManager? manager = evalSetsManager;
    if (manager == null) {
      throw const _EvalManagerNotConfiguredException(
        'Eval sets manager is not configured',
      );
    }
    return manager;
  }

  EvalSetResultsManager _getEvalSetResultsManager() {
    final EvalSetResultsManager? manager = evalSetResultsManager;
    if (manager == null) {
      throw const _EvalManagerNotConfiguredException(
        'Eval set results manager is not configured',
      );
    }
    return manager;
  }

  // Whether internal special agents (app names starting with `__`, such as
  // a built-in agent-builder assistant) may be loaded and executed.
  //
  // Mirrors Python's `_allow_special_agents`: it is only enabled when the
  // Dev UI is served ([enableWebUi]) and the server is bound to a loopback
  // address; API-server-only or non-loopback deployments must not expose
  // these privileged internal agents.
  bool get allowSpecialAgents =>
      enableWebUi && (serverHost == null || _isLoopbackAddress(serverHost!));

  void registerActiveSessionRun(
    String appName,
    String userId,
    String sessionId,
    AdkAbortController abortController,
    Future<void> runFuture,
  ) {
    final (String, String, String) key = (appName, userId, sessionId);
    _activeSessionAbortControllers
        .putIfAbsent(key, () => <AdkAbortController>[])
        .add(abortController);
    _activeSessionRunFutures
        .putIfAbsent(key, () => <Future<void>>[])
        .add(runFuture);
  }

  void unregisterActiveSessionRun(
    String appName,
    String userId,
    String sessionId,
    AdkAbortController abortController,
    Future<void> runFuture,
  ) {
    final (String, String, String) key = (appName, userId, sessionId);
    final List<AdkAbortController>? controllers =
        _activeSessionAbortControllers[key];
    if (controllers != null) {
      controllers.remove(abortController);
      if (controllers.isEmpty) {
        _activeSessionAbortControllers.remove(key);
      }
    }
    final List<Future<void>>? futures = _activeSessionRunFutures[key];
    if (futures != null) {
      futures.remove(runFuture);
      if (futures.isEmpty) {
        _activeSessionRunFutures.remove(key);
      }
    }
  }

  Future<void> cancelActiveSessionRuns(
    String appName,
    String userId,
    String sessionId,
  ) async {
    final (String, String, String) key = (appName, userId, sessionId);
    final List<AdkAbortController> controllers = List<AdkAbortController>.from(
      _activeSessionAbortControllers[key] ?? const <AdkAbortController>[],
    );
    for (final AdkAbortController controller in controllers) {
      controller.abort('Session rewind requested');
    }
    final List<Future<void>> futures = List<Future<void>>.from(
      _activeSessionRunFutures[key] ?? const <Future<void>>[],
    );
    if (futures.isNotEmpty) {
      await Future.wait(
        futures.map((Future<void> f) => f.catchError((Object _) {})),
      );
    }
  }

  // Resolves the filesystem directory for [appName].
  String? getAgentDir(String appName) {
    final Directory candidate = Directory('$agentsDir${Platform.pathSeparator}$appName');
    if (candidate.existsSync()) {
      return candidate.path;
    }
    if (appName == defaultAppName) {
      return agentsDir;
    }
    return null;
  }

  // Throws a [SpecialAgentAccessDeniedException] when [appName] is an
  // internal special agent and [allowSpecialAgents] is false, or when a
  // browser sends the request from a foreign origin.
  void _guardSpecialAgentAccess(String appName, {HttpRequest? request}) {
    if (!appName.startsWith('__')) {
      return;
    }
    if (!allowSpecialAgents) {
      throw const SpecialAgentAccessDeniedException();
    }
    if (request != null && _requestHasForeignBrowserOrigin(request, this)) {
      throw const SpecialAgentAccessDeniedException(
        "This endpoint writes agent files or starts runs, so it accepts "
        "browser requests only from this server's own origin or an origin "
        "listed literally in allow_origins.",
      );
    }
  }

  Future<Runner> getRunner(String? appName, {HttpRequest? request}) async {
    final String resolvedAppName = (appName == null || appName.trim().isEmpty)
        ? defaultAppName
        : appName.trim();
    _guardSpecialAgentAccess(resolvedAppName, request: request);

    final bool shouldReload = reload || reloadAgents;
    if (!shouldReload) {
      final Runner? cached = _runners[resolvedAppName];
      if (cached != null) {
        return cached;
      }
    } else {
      final Runner? stale = _runners.remove(resolvedAppName);
      if (stale != null) {
        await stale.close();
      }
    }

    final Runner runner = await _createRunner(resolvedAppName);
    _runners[resolvedAppName] = runner;
    return runner;
  }

  BaseAgent? asBaseAgent(Object? value) {
    if (value == null) {
      return null;
    }
    try {
      return base_loader.asBaseAgent(value);
    } on ArgumentError {
      return null;
    }
  }

  bool shouldReturnEmptyDevGraph(
    String appName, {
    required bool isDevGraphRoute,
  }) {
    final String resolvedAppName = appName.trim().isEmpty
        ? defaultAppName
        : appName.trim();
    try {
      final Object loaded = agentLoader.loadAgent(resolvedAppName);
      if (base_loader.isStandaloneWorkflowNode(loaded)) {
        return true;
      }
      if (isDevGraphRoute) {
        final Object root = loaded is App ? loaded.rootAgent : loaded;
        if (root is Workflow || base_loader.isStandaloneWorkflowNode(root)) {
          return true;
        }
      }
    } on Object {
      // Fallback handled by caller.
    }
    return false;
  }

  Future<Runner> _createRunner(String appName) async {
    final List<BasePlugin> extraPlugins = await _instantiateExtraPlugins(
      extraPluginSpecs,
      baseDir: agentsDir,
    );
    _appendBuiltinConformancePlugins(extraPlugins);
    final Object loaded;
    try {
      loaded = agentLoader.loadAgent(appName);
    } on StateError {
      if (appName != defaultAppName) {
        rethrow;
      }
      return _createRuntimeFallbackRunner(appName, extraPlugins);
    } on ArgumentError {
      if (appName != defaultAppName) {
        rethrow;
      }
      return _createRuntimeFallbackRunner(appName, extraPlugins);
    }

    if (loaded is App) {
      return Runner(
        app: loaded,
        appName: appName,
        sessionService: sessionService,
        artifactService: artifactService,
        memoryService: memoryService,
        plugins: extraPlugins,
        autoCreateSession: autoCreateSession,
      );
    }

    return Runner(
      appName: appName,
      agent: asBaseAgent(loaded),
      sessionService: sessionService,
      artifactService: artifactService,
      memoryService: memoryService,
      plugins: extraPlugins,
      autoCreateSession: autoCreateSession,
    );
  }

  Runner _createRuntimeFallbackRunner(
    String appName,
    List<BasePlugin> extraPlugins,
  ) {
    return Runner(
      appName: appName,
      agent: runtime.runner.agent,
      sessionService: sessionService,
      artifactService: artifactService,
      memoryService: memoryService,
      plugins: extraPlugins,
      autoCreateSession: autoCreateSession,
    );
  }

  void _appendBuiltinConformancePlugins(List<BasePlugin> plugins) {
    final Set<String> existing = plugins
        .map((BasePlugin plugin) => plugin.name)
        .toSet();
    if (!existing.contains('adk_conformance_recordings')) {
      plugins.add(ConformanceRecordingsPlugin());
    }
    if (!existing.contains('adk_conformance_replay')) {
      plugins.add(ConformanceReplayPlugin());
    }
  }

  List<String> listAppNames() {
    final Set<String> names = agentLoader.listAgents().toSet();
    if (!hasExplicitAgentLoader) {
      names.add(defaultAppName);
    }
    final List<String> sorted = names.toList()..sort();
    return sorted;
  }

  List<Map<String, Object?>> listAppDetails() {
    final List<Map<String, Object?>> details = agentLoader
        .listAgentsDetailed()
        .map((Map<String, Object?> value) {
          return Map<String, Object?>.from(value);
        })
        .toList(growable: true);

    final Set<String> knownNames = details
        .map((Map<String, Object?> value) => '${value['name'] ?? ''}')
        .where((String value) => value.isNotEmpty)
        .toSet();

    if (!hasExplicitAgentLoader && !knownNames.contains(defaultAppName)) {
      final BaseAgent defaultRootAgent = runtime.runner.agent;
      details.add(<String, Object?>{
        'name': defaultAppName,
        'root_agent_name': defaultRootAgent.name,
        'description': defaultRootAgent.description,
        'language': 'dart',
        'is_computer_use': _isComputerUseAgent(defaultRootAgent),
      });
    }

    details.sort((Map<String, Object?> a, Map<String, Object?> b) {
      final String left = '${a['name'] ?? ''}';
      final String right = '${b['name'] ?? ''}';
      return left.compareTo(right);
    });
    return details;
  }

  Future<void> close() async {
    _a2aPushDeliveryTimer?.cancel();
    _a2aPushDeliveryTimer = null;
    while (_a2aPushDrainInProgress) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    for (final Runner runner in _runners.values) {
      await runner.close();
    }
    _runners.clear();
    _a2aTasksByApp.clear();
    _a2aTaskUpdatesByApp.clear();
    _a2aPushConfigsByApp.clear();
    a2aPushQueue?.close();
    spanExporter.shutdown();
  }

  void upsertA2aTask(String appName, Map<String, Object?> task) {
    final String taskId = '${task['id'] ?? ''}'.trim();
    if (taskId.isEmpty) {
      return;
    }
    final Map<String, Map<String, Object?>> byTask = _a2aTasksByApp.putIfAbsent(
      appName,
      () => <String, Map<String, Object?>>{},
    );
    byTask[taskId] = Map<String, Object?>.from(task);
  }

  Map<String, Object?>? readA2aTask(String appName, String taskId) {
    final Map<String, Map<String, Object?>>? byTask = _a2aTasksByApp[appName];
    final Map<String, Object?>? found = byTask?[taskId];
    if (found == null) {
      return null;
    }
    return Map<String, Object?>.from(found);
  }

  void upsertA2aTaskUpdates(
    String appName,
    String taskId,
    List<Map<String, Object?>> updates,
  ) {
    final String normalizedTaskId = taskId.trim();
    if (normalizedTaskId.isEmpty) {
      return;
    }
    final Map<String, List<Map<String, Object?>>> byTask = _a2aTaskUpdatesByApp
        .putIfAbsent(appName, () => <String, List<Map<String, Object?>>>{});
    byTask[normalizedTaskId] = updates
        .map((Map<String, Object?> value) => Map<String, Object?>.from(value))
        .toList(growable: false);
  }

  List<Map<String, Object?>> readA2aTaskUpdates(String appName, String taskId) {
    final Map<String, List<Map<String, Object?>>>? byTask =
        _a2aTaskUpdatesByApp[appName];
    final List<Map<String, Object?>>? found = byTask?[taskId];
    if (found == null) {
      return const <Map<String, Object?>>[];
    }
    return found
        .map((Map<String, Object?> value) => Map<String, Object?>.from(value))
        .toList(growable: false);
  }

  void upsertA2aPushConfig(
    String appName,
    String taskId,
    Map<String, Object?> config,
  ) {
    final String normalizedTaskId = taskId.trim();
    if (normalizedTaskId.isEmpty) {
      return;
    }
    final Map<String, Map<String, Object?>> byTask = _a2aPushConfigsByApp
        .putIfAbsent(appName, () => <String, Map<String, Object?>>{});
    byTask[normalizedTaskId] = Map<String, Object?>.from(config);
  }

  Map<String, Object?>? readA2aPushConfig(String appName, String taskId) {
    final Map<String, Map<String, Object?>>? byTask =
        _a2aPushConfigsByApp[appName];
    final Map<String, Object?>? found = byTask?[taskId];
    if (found == null) {
      return null;
    }
    return Map<String, Object?>.from(found);
  }

  void _startA2aPushDeliveryLoop() {
    if (a2aPushQueue == null) {
      return;
    }
    _a2aPushDeliveryTimer?.cancel();
    _a2aPushDeliveryTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      unawaited(_drainA2aPushDeliveryQueue());
    });
    unawaited(_drainA2aPushDeliveryQueue());
  }

  Future<void> enqueueA2aPushNotifications({
    required String appName,
    required String taskId,
    required Map<String, Object?> pushConfig,
    required Map<String, Object?> task,
    required List<Map<String, Object?>> updates,
  }) async {
    if (updates.isEmpty) {
      return;
    }
    final _A2aPushTarget? target = _resolveA2aPushTarget(pushConfig);
    if (target == null) {
      return;
    }

    final A2aPushDeliveryQueue? queue = a2aPushQueue;
    if (queue == null) {
      for (final Map<String, Object?> update in updates) {
        try {
          await _postA2aPushNotification(
            uri: target.uri,
            headers: target.headers,
            authHeader: target.authHeader,
            task: task,
            update: update,
            requestTimeoutMs: target.policy.requestTimeoutMs,
          );
        } catch (_) {
          // Best-effort fallback path when the queue is not configured.
        }
      }
      return;
    }

    for (final Map<String, Object?> update in updates) {
      queue.enqueue(
        appName: appName,
        taskId: taskId,
        targetUrl: target.uri.toString(),
        headers: target.headers,
        authHeader: target.authHeader,
        task: task,
        update: update,
        policy: target.policy,
      );
    }
    unawaited(_drainA2aPushDeliveryQueue());
  }

  Future<void> _drainA2aPushDeliveryQueue() async {
    final A2aPushDeliveryQueue? queue = a2aPushQueue;
    if (queue == null || _a2aPushDrainInProgress) {
      return;
    }

    _a2aPushDrainInProgress = true;
    try {
      while (true) {
        List<A2aPushDeliveryEntry> dueEntries;
        try {
          dueEntries = queue.readDue(limit: _a2aPushDrainBatchSize);
        } catch (_) {
          return;
        }
        if (dueEntries.isEmpty) {
          return;
        }

        for (final A2aPushDeliveryEntry entry in dueEntries) {
          try {
            await _postA2aPushNotification(
              uri: Uri.parse(entry.targetUrl),
              headers: entry.headers,
              authHeader: entry.authHeader,
              task: entry.task,
              update: entry.update,
              requestTimeoutMs: entry.policy.requestTimeoutMs,
            );
            try {
              queue.markDelivered(entry.id);
            } catch (_) {
              // Queue persistence failure should not crash the server.
            }
          } catch (error) {
            try {
              queue.markFailed(entry, error: '$error');
            } catch (_) {
              // Queue persistence failure should not crash the server.
            }
          }
        }

        if (dueEntries.length < _a2aPushDrainBatchSize) {
          return;
        }
      }
    } finally {
      _a2aPushDrainInProgress = false;
    }
  }

  void recordTraceEvent({
    required String appName,
    required String userId,
    required String sessionId,
    required Event event,
    W3cTraceContext? traceContext,
  }) {
    final Map<String, Object?> trace = _traceFromEvent(
      appName: appName,
      userId: userId,
      sessionId: sessionId,
      event: event,
      traceContext: traceContext,
    );
    _traceByEventId[event.id] = trace;

    final List<Map<String, Object?>> bySession = _traceBySessionId.putIfAbsent(
      sessionId,
      () => <Map<String, Object?>>[],
    );
    final int existingIndex = bySession.indexWhere(
      (Map<String, Object?> value) => '${value['event_id'] ?? ''}' == event.id,
    );
    if (existingIndex >= 0) {
      bySession[existingIndex] = trace;
    } else {
      bySession.add(trace);
    }
    bySession.sort((Map<String, Object?> a, Map<String, Object?> b) {
      final double left = _asDouble(a['start_time']);
      final double right = _asDouble(b['start_time']);
      return left.compareTo(right);
    });

    final int resolvedTraceInt = (traceContext?.traceId != null)
        ? (int.tryParse(
                traceContext!.traceId!.substring(
                  traceContext.traceId!.length - 15,
                ),
                radix: 16,
              ) ??
              _stablePositiveInt(traceContext.traceId!))
        : _stablePositiveInt(event.invocationId);
    final SpanContext contextSpan = SpanContext(
      traceId: resolvedTraceInt,
      spanId: _stablePositiveInt(event.id),
      isRemote: traceContext?.hasTraceContext ?? false,
      traceFlags: TraceFlags.sampled,
      traceState: const TraceState(),
    );
    SpanContext? parent;
    final String? parentHex = trace['parent_span_id']?.toString();
    if (parentHex != null && parentHex.isNotEmpty) {
      parent = SpanContext(
        traceId: contextSpan.traceId,
        spanId: int.tryParse(parentHex, radix: 16) ?? 0,
        isRemote: traceContext?.hasTraceContext ?? false,
        traceFlags: TraceFlags.sampled,
        traceState: const TraceState(),
      );
    }

    final Map<String, Object?> attributes = Map<String, Object?>.from(
      trace['attributes'] as Map<String, Object?>? ?? const <String, Object?>{},
    );
    spanExporter.export(<ReadableSpan>[
      ReadableSpan(
        name: '${trace['name'] ?? 'event'}',
        context: contextSpan,
        parent: parent,
        attributes: attributes,
        startTimeUnixNano: _toUnixNano(event.timestamp),
        endTimeUnixNano: _toUnixNano(event.timestamp),
      ),
    ]);
  }

  Map<String, Object?>? readTraceByEventId(String eventId) {
    final Map<String, Object?>? persisted = spanExporter.getTraceByEventId(
      eventId,
    );
    if (persisted != null) {
      final Map<String, Object?> copy = Map<String, Object?>.from(persisted);
      final Object? rawAttrs = copy['attributes'];
      if (rawAttrs is Map) {
        final Object? w3cTraceId = rawAttrs['w3c.trace_id'];
        if (w3cTraceId is String && w3cTraceId.isNotEmpty) {
          copy['trace_id'] = w3cTraceId;
        }
        final Object? w3cParentSpanId = rawAttrs['w3c.parent_span_id'];
        if (w3cParentSpanId is String && w3cParentSpanId.isNotEmpty) {
          copy['parent_span_id'] = w3cParentSpanId;
        }
      }
      return copy;
    }
    final Map<String, Object?>? trace = _traceByEventId[eventId];
    return trace == null ? null : Map<String, Object?>.from(trace);
  }

  List<Map<String, Object?>> readTraceBySessionId(String sessionId) {
    final List<ReadableSpan> persisted = spanExporter.getAllSpansForSession(
      sessionId,
    );
    if (persisted.isNotEmpty) {
      return persisted
          .map<Map<String, Object?>>((ReadableSpan span) {
            final Map<String, Object?> attrs = Map<String, Object?>.from(
              span.attributes,
            );
            final Object? w3cTraceId = attrs['w3c.trace_id'];
            final Object? w3cParentSpanId = attrs['w3c.parent_span_id'];
            return <String, Object?>{
              'name': span.name,
              'span_id': span.context.spanIdHex,
              'trace_id': (w3cTraceId is String && w3cTraceId.isNotEmpty)
                  ? w3cTraceId
                  : span.context.traceIdHex,
              'start_time': span.startTimeUnixNano,
              'end_time': span.endTimeUnixNano,
              'attributes': attrs,
              'parent_span_id':
                  (w3cParentSpanId is String && w3cParentSpanId.isNotEmpty)
                  ? w3cParentSpanId
                  : span.parent?.spanIdHex,
            };
          })
          .toList(growable: false);
    }
    final List<Map<String, Object?>> values =
        _traceBySessionId[sessionId] ?? const <Map<String, Object?>>[];
    return values
        .map((Map<String, Object?> value) => Map<String, Object?>.from(value))
        .toList(growable: false);
  }

  /// Internal testing access to in-memory traces by event id.
  @visibleForTesting
  Map<String, Map<String, Object?>> get inMemoryTracesByEventIdForTesting =>
      _traceByEventId;

  Future<Event?> readSessionEvent({
    required String appName,
    required String userId,
    required String sessionId,
    required String eventId,
  }) async {
    final Session? session = await sessionService.getSession(
      appName: appName,
      userId: userId,
      sessionId: sessionId,
    );
    final List<Event> events = session?.events ?? const <Event>[];
    for (final Event event in events) {
      if (event.id == eventId) {
        return event;
      }
    }
    return null;
  }

  double _asDouble(Object? value) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse('$value') ?? 0.0;
  }

  int _stablePositiveInt(String value) {
    int hash = 0;
    for (final int unit in value.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    if (hash == 0) {
      return 1;
    }
    return hash;
  }

  int _toUnixNano(double seconds) {
    return (seconds * 1000000000).round();
  }

  BaseAgent getRootAgent(String appName) {
    final String resolvedAppName = appName.trim().isEmpty
        ? defaultAppName
        : appName.trim();

    try {
      final Object loaded = agentLoader.loadAgent(resolvedAppName);
      if (loaded is App) {
        return loaded.rootAgent;
      }
      return asBaseAgent(loaded) ?? runtime.runner.agent;
    } on StateError {
      if (resolvedAppName != defaultAppName) {
        rethrow;
      }
      return runtime.runner.agent;
    } on ArgumentError {
      if (resolvedAppName != defaultAppName) {
        rethrow;
      }
      return runtime.runner.agent;
    }
  }
}

Map<String, Object?> _traceFromEvent({
  required String appName,
  required String userId,
  required String sessionId,
  required Event event,
  W3cTraceContext? traceContext,
}) {
  final String traceId = traceContext?.traceId ?? event.invocationId;
  final String spanId = event.id;
  final List<FunctionCall> functionCalls = event.getFunctionCalls();
  final List<FunctionResponse> functionResponses = event.getFunctionResponses();
  final Map<String, Object?> attributes = <String, Object?>{
    'gcp.vertex.agent.app_name': appName,
    'gcp.vertex.agent.user_id': userId,
    'gcp.vertex.agent.session_id': sessionId,
    'gcp.vertex.agent.event_id': event.id,
    'gcp.vertex.agent.invocation_id': event.invocationId,
    'event.author': event.author,
    'event.partial': event.partial ?? false,
    'event.turn_complete': event.turnComplete ?? false,
    'event.function_calls': functionCalls
        .map((FunctionCall call) => call.name)
        .toList(growable: false),
    'event.function_responses': functionResponses
        .map((FunctionResponse response) => response.name)
        .toList(growable: false),
    'event.artifact_delta': Map<String, int>.from(event.actions.artifactDelta),
    if (event.errorMessage != null) 'event.error_message': event.errorMessage,
    if (event.finishReason != null) 'event.finish_reason': event.finishReason,
    if (traceContext?.traceparent != null)
      'w3c.traceparent': traceContext!.traceparent,
    if (traceContext?.traceId != null) 'w3c.trace_id': traceContext!.traceId,
    if (traceContext?.parentSpanId != null)
      'w3c.parent_span_id': traceContext!.parentSpanId,
    if (traceContext?.tracestate != null)
      'w3c.tracestate': traceContext!.tracestate,
    if (traceContext != null && traceContext.hasBaggage) ...<String, Object?>{
      'w3c.baggage': Map<String, String>.from(traceContext.baggage),
      for (final MapEntry<String, String> entry in traceContext.baggage.entries)
        'baggage.${entry.key}': entry.value,
    },
  };
  return <String, Object?>{
    'name': _spanNameFromEvent(event),
    'span_id': spanId,
    'trace_id': traceId,
    'start_time': event.timestamp,
    'end_time': event.timestamp,
    'attributes': attributes,
    'parent_span_id':
        event.customMetadata?['parent_span_id'] ?? traceContext?.parentSpanId,
    'event_id': event.id,
  };
}

String _spanNameFromEvent(Event event) {
  if (event.getFunctionCalls().isNotEmpty) {
    return 'execute_tool';
  }
  if (event.getFunctionResponses().isNotEmpty) {
    return 'tool_response';
  }
  if ((event.content?.parts.length ?? 0) > 0) {
    return 'call_llm';
  }
  return 'event';
}

/// Optional override for testing request handling and error catches.
@visibleForTesting
Future<void> Function(HttpRequest request, dynamic context)?
handleRequestTestingOverride;

Future<void> _handleRequests(
  HttpServer server,
  _AdkDevWebContext context,
) async {
  try {
    await for (final HttpRequest request in server) {
      unawaited(() async {
        try {
          if (handleRequestTestingOverride != null) {
            await handleRequestTestingOverride!(request, context);
            return;
          }
          await _handleRequest(request, context);
        } on FormatException catch (error) {
          await _writeError(
            request,
            context,
            statusCode: HttpStatus.badRequest,
            message: error.message,
          );
        } on InvocationNotFoundError catch (error) {
          await _writeError(
            request,
            context,
            statusCode: HttpStatus.notFound,
            message: error.message,
          );
        } on ArgumentError catch (error) {
          await _writeError(
            request,
            context,
            statusCode: HttpStatus.badRequest,
            message: '${error.message}',
          );
        } on StateError catch (error) {
          await _writeError(
            request,
            context,
            statusCode: HttpStatus.notFound,
            message: error.message,
          );
        } on SessionNotFoundError catch (error) {
          await _writeError(
            request,
            context,
            statusCode: HttpStatus.notFound,
            message: error.message,
          );
        } on SpecialAgentAccessDeniedException catch (error) {
          await _writeError(
            request,
            context,
            statusCode: HttpStatus.forbidden,
            message: error.message,
          );
        } catch (_) {
          await _writeError(
            request,
            context,
            statusCode: HttpStatus.internalServerError,
            message: 'Internal server error.',
          );
        }
      }());
    }
  } finally {
    await context.close();
  }
}

Future<void> _handleRequest(
  HttpRequest request,
  _AdkDevWebContext context,
) async {
  final String? routedPath = _stripPrefix(request.uri.path, context.urlPrefix);
  if (routedPath == null) {
    await _writeError(
      request,
      context,
      statusCode: HttpStatus.notFound,
      message: 'Not found.',
    );
    return;
  }

  if (request.method == 'OPTIONS') {
    await _writeJson(request, context, payload: const <String, Object?>{});
    return;
  }

  if (_shouldBlockCrossOriginRequest(request, context)) {
    await _writeText(
      request,
      context,
      statusCode: HttpStatus.forbidden,
      text: 'Forbidden: origin not allowed',
      includeCorsHeaders: false,
    );
    return;
  }

  if (context.a2a &&
      request.method == 'GET' &&
      (routedPath == '/.well-known/agent.json' ||
          routedPath == '/a2a/agent-card')) {
    await _handleA2aAgentCard(request, context);
    return;
  }

  if (context.a2a && request.method == 'GET') {
    final String? scopedAppName = _extractA2aScopedAppName(routedPath);
    if (scopedAppName != null) {
      await _handleA2aAgentCard(
        request,
        context,
        appNameFromPath: scopedAppName,
      );
      return;
    }
  }

  if (context.a2a && (request.method == 'POST' || request.method == 'GET')) {
    final _A2aRpcRoute? rpcRoute = _parseA2aRpcRoute(
      routedPath,
      request.method,
    );
    if (rpcRoute != null) {
      await _handleA2aRpc(request, context, route: rpcRoute);
      return;
    }
  }

  if (await _handleWebUi(request, context, routedPath)) {
    return;
  }

  if (routedPath == '/health' && request.method == 'GET') {
    await _writeJson(
      request,
      context,
      payload: <String, Object?>{
        'status': 'ok',
        'service': 'adk_dart_web',
        'appName': context.defaultAppName,
      },
    );
    return;
  }

  if (routedPath == '/version' && request.method == 'GET') {
    await _writeJson(
      request,
      context,
      payload: <String, Object?>{
        'version': adkPackageVersion,
        'language': 'dart',
        'language_version': Platform.version.split(' ').first,
      },
    );
    return;
  }

  if (routedPath == '/config/telemetry') {
    if (request.method == 'GET') {
      await _writeJson(
        request,
        context,
        payload: <String, Object?>{
          'telemetry': readTelemetryConsent(),
        },
      );
      return;
    }
    if (request.method == 'POST') {
      final String? headerVal =
          request.headers.value('x-adk-telemetry-request');
      if (headerVal != 'true') {
        await _writeText(
          request,
          context,
          statusCode: HttpStatus.forbidden,
          text: 'Forbidden: missing x-adk-telemetry-request header',
        );
        return;
      }
      final Map<String, dynamic> body = await _readJsonBody(request);
      final Object? telemetryVal = body['telemetry'];
      if (telemetryVal is! bool) {
        await _writeText(
          request,
          context,
          statusCode: HttpStatus.badRequest,
          text: "Bad Request: 'telemetry' boolean field is required",
        );
        return;
      }
      writeTelemetryConsent(telemetryVal);
      await _writeJson(
        request,
        context,
        payload: <String, Object?>{'telemetry': telemetryVal},
      );
      return;
    }
  }

  if (request.method == 'GET' && routedPath.startsWith('/debug/trace/')) {
    final List<String> traceSegments = Uri(
      path: routedPath,
    ).pathSegments.where((String s) => s.isNotEmpty).toList(growable: false);
    if (traceSegments.length == 3 &&
        traceSegments[0] == 'debug' &&
        traceSegments[1] == 'trace') {
      if (traceSegments[2] == 'session') {
        // Session trace endpoint requires /debug/trace/session/{session_id}.
      } else {
        await _handleGetTraceByEventId(
          request,
          context,
          eventId: traceSegments[2],
        );
        return;
      }
    }
    if (traceSegments.length == 4 &&
        traceSegments[0] == 'debug' &&
        traceSegments[1] == 'trace' &&
        traceSegments[2] == 'session') {
      await _handleGetTraceBySessionId(
        request,
        context,
        sessionId: traceSegments[3],
      );
      return;
    }
  }

  if (routedPath == '/agent-identity/finalize' && request.method == 'POST') {
    await _handleFinalizeAgentIdentityCredentials(request, context);
    return;
  }

  if (routedPath == '/list-apps' && request.method == 'GET') {
    final bool detailed = _isTruthy(request.uri.queryParameters['detailed']);
    if (detailed) {
      await _writeJson(
        request,
        context,
        payload: <String, Object?>{
          'apps': context.listAppDetails().map(_serializeAppSummary).toList(),
        },
      );
    } else {
      await _writeJson(request, context, payload: context.listAppNames());
    }
    return;
  }

  if (routedPath == '/api/info' && request.method == 'GET') {
    await _writeJson(
      request,
      context,
      payload: <String, Object?>{
        'name': 'adk_dart',
        'ui': context.enableWebUi ? 'development' : 'disabled',
        'appName': context.defaultAppName,
        'agentName': context.project.agentName,
        'description': context.project.description,
        'a2a': context.a2a,
        'extra_plugins': context.extraPluginSpecs
            .map((_ExtraPluginSpec spec) => spec.raw)
            .toList(growable: false),
        'trigger_sources': context.triggerSources,
        'eval_storage_uri': context.evalStorageUri,
        'trace_to_cloud': context.traceToCloud,
        'otel_to_cloud': context.otelToCloud,
      },
    );
    return;
  }

  if (routedPath == '/api/sessions' && request.method == 'POST') {
    await _handleLegacyCreateSession(request, context);
    return;
  }

  if (routedPath == '/api/sessions' && request.method == 'GET') {
    await _handleLegacyListSessions(request, context);
    return;
  }

  if (routedPath == '/run' && request.method == 'POST') {
    await _handleRun(request, context);
    return;
  }

  if (routedPath == '/run_sse' && request.method == 'POST') {
    await _handleRunSse(request, context);
    return;
  }

  if (routedPath == '/run_live' && request.method == 'GET') {
    await _handleRunLive(request, context);
    return;
  }

  final List<String> segments = routedPath
      .split('/')
      .where((String s) => s.isNotEmpty)
      .map(_decodePathSegment)
      .toList();

  if (segments.length == 4 &&
      segments[0] == 'api' &&
      segments[1] == 'sessions' &&
      segments[3] == 'messages' &&
      request.method == 'POST') {
    await _handleLegacyPostMessage(request, context, sessionId: segments[2]);
    return;
  }

  if (segments.length == 4 &&
      segments[0] == 'api' &&
      segments[1] == 'sessions' &&
      segments[3] == 'events' &&
      request.method == 'GET') {
    await _handleLegacyGetEvents(request, context, sessionId: segments[2]);
    return;
  }

  if (segments.length == 3 &&
      segments[0] == 'dev' &&
      segments[1] == 'build_graph' &&
      request.method == 'GET') {
    await _handleGetAppGraph(request, context, appName: segments[2]);
    return;
  }

  if (segments.length == 3 &&
      segments[0] == 'dev' &&
      segments[1] == 'build_graph_image' &&
      request.method == 'GET') {
    await _handleGetAppGraphImage(request, context, appName: segments[2]);
    return;
  }

  if (segments.length == 5 &&
      segments[0] == 'dev' &&
      segments[1] == 'apps' &&
      segments[3] == 'deploy') {
    final bool handled = await dev_deploy.handleDevDeployRoute(
      request: request,
      routedPath: routedPath,
      agentsRoot: context.agentsDir,
      enableWebUi: context.enableWebUi,
      isLocalClient: _isLocalDevDeployClient(request, context),
      agentLookup: (String appName) {
        try {
          return context.getRootAgent(appName);
        } catch (_) {
          return null;
        }
      },
    );
    if (handled) {
      return;
    }
  }

  if (await _handlePythonStyleRoutes(request, context, segments)) {
    return;
  }

  await _writeError(
    request,
    context,
    statusCode: HttpStatus.notFound,
    message: 'Not found.',
  );
}

Future<bool> _handlePythonStyleRoutes(
  HttpRequest request,
  _AdkDevWebContext context,
  List<String> rawSegments,
) async {
  if (rawSegments.isNotEmpty &&
      rawSegments[0] == 'dev' &&
      !_safeHttpMethods.contains(request.method.toUpperCase()) &&
      _requestHasForeignBrowserOrigin(request, context)) {
    throw const SpecialAgentAccessDeniedException(
      "This endpoint writes agent files or starts runs, so it accepts "
      "browser requests only from this server's own origin or an origin "
      "listed literally in allow_origins.",
    );
  }
  final List<String> segments =
      (rawSegments.length >= 3 &&
          rawSegments[0] == 'dev' &&
          rawSegments[1] == 'apps')
      ? rawSegments.sublist(1)
      : rawSegments;
  if (segments.length < 2 || segments[0] != 'apps') {
    return false;
  }

  final String appName = segments[1];
  context._guardSpecialAgentAccess(appName, request: request);
  if (segments.length == 4 &&
      segments[2] == 'trigger' &&
      request.method == 'POST') {
    final String triggerSource = segments[3].toLowerCase();
    final TriggerRouter? triggerRouter = context.triggerRouter;
    if (triggerRouter == null) {
      return false;
    }
    if (!triggerRouter.isSourceEnabled(triggerSource)) {
      await _writeError(
        request,
        context,
        statusCode: HttpStatus.notFound,
        message: 'Unknown trigger source: $triggerSource',
      );
      return true;
    }
    await _handleTriggerRoute(
      request,
      context,
      triggerRouter: triggerRouter,
      appName: appName,
      triggerSource: triggerSource,
    );
    return true;
  }
  if (segments.length == 3 &&
      segments[2] == 'app-info' &&
      request.method == 'GET') {
    await _handleGetAppInfo(request, context, appName: appName);
    return true;
  }
  if (segments.length == 3 &&
      segments[2] == 'screencast' &&
      request.method == 'GET') {
    await _handleScreencast(request, context, appName: appName);
    return true;
  }
  if (segments.length == 3 &&
      (segments[2] == 'graph' || segments[2] == 'build_graph') &&
      request.method == 'GET') {
    await _handleGetAppGraph(
      request,
      context,
      appName: appName,
      isDevGraphRoute: rawSegments.first == 'dev' && segments[2] == 'graph',
    );
    return true;
  }
  if (segments.length == 3 &&
      segments[2] == 'build_graph_image' &&
      request.method == 'GET') {
    await _handleGetAppGraphImage(request, context, appName: appName);
    return true;
  }
  if (segments.length == 5 &&
      segments[2] == 'debug' &&
      segments[3] == 'trace' &&
      segments[4] != 'session' &&
      request.method == 'GET') {
    context._guardSpecialAgentAccess(appName, request: request);
    await _handleGetTraceDict(request, context, eventId: segments[4]);
    return true;
  }
  if (segments.length == 6 &&
      segments[2] == 'debug' &&
      segments[3] == 'trace' &&
      segments[4] == 'session' &&
      request.method == 'GET') {
    context._guardSpecialAgentAccess(appName, request: request);
    await _handleGetSessionTrace(request, context, sessionId: segments[5]);
    return true;
  }
  if (await _handleEvalRoutes(request, context, segments, appName: appName)) {
    return true;
  }

  if (segments.length < 5 || segments[2] != 'users') {
    return false;
  }

  final String userId = _validatePathIdentifier(segments[3], 'user_id');

  if (segments[4] == 'memory' &&
      segments.length == 5 &&
      request.method == 'PATCH') {
    await _handlePatchMemory(
      request,
      context,
      appName: appName,
      userId: userId,
    );
    return true;
  }

  if (segments[4] != 'sessions') {
    return false;
  }

  if (segments.length == 5) {
    if (request.method == 'GET') {
      await _handleListSessions(
        request,
        context,
        appName: appName,
        userId: userId,
      );
      return true;
    }
    if (request.method == 'POST') {
      await _handleCreateSession(
        request,
        context,
        appName: appName,
        userId: userId,
      );
      return true;
    }
    return false;
  }

  final String sessionId = _validatePathIdentifier(segments[5], 'session_id');
  if (segments.length == 6) {
    if (request.method == 'GET') {
      await _handleGetSession(
        request,
        context,
        appName: appName,
        userId: userId,
        sessionId: sessionId,
      );
      return true;
    }
    if (request.method == 'DELETE') {
      await _handleDeleteSession(
        request,
        context,
        appName: appName,
        userId: userId,
        sessionId: sessionId,
      );
      return true;
    }
    if (request.method == 'POST') {
      await _handleCreateSessionWithId(
        request,
        context,
        appName: appName,
        userId: userId,
        sessionId: sessionId,
      );
      return true;
    }
    if (request.method == 'PATCH') {
      await _handleUpdateSession(
        request,
        context,
        appName: appName,
        userId: userId,
        sessionId: sessionId,
      );
      return true;
    }
    return false;
  }

  if (segments.length == 7 &&
      segments[6] == 'rewind' &&
      request.method == 'POST') {
    await _handleRewindSession(
      request,
      context,
      appName: appName,
      userId: userId,
      sessionId: sessionId,
    );
    return true;
  }

  if (segments.length >= 7 && segments[6] == 'artifacts') {
    await _handleArtifactsRoute(
      request,
      context,
      segments,
      appName: appName,
      userId: userId,
      sessionId: sessionId,
    );
    return true;
  }

  if (segments.length == 9 &&
      segments[6] == 'events' &&
      segments[8] == 'graph' &&
      request.method == 'GET') {
    await _handleGetEventGraph(
      request,
      context,
      appName: appName,
      userId: userId,
      sessionId: sessionId,
      eventId: segments[7],
      isDevGraphRoute: rawSegments.first == 'dev',
    );
    return true;
  }

  return false;
}
