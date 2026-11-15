/// FastAPI-style server adapter used by ADK CLI tooling.
library;

import 'dart:io';

import 'adk_web_server.dart';
import 'utils/base_agent_loader.dart';
export 'api_server.dart'
    show
        AgentsFileObserver,
        AgentsFileObserverFactory,
        SetupObserverCallback,
        TearDownObserverCallback,
        W3cTraceContext,
        agentsFileObserverFactoryTestingOverride,
        extractW3cTraceContext;

/// Allowed Vertex AI Agent Engine / Reasoning Engine adapter `class_method`
/// names mapped to whether the method uses the streaming endpoint
/// (`/api/stream_reasoning_engine` when `true`, `/api/reasoning_engine` when
/// `false`), mirroring `_ALLOWED_AGENT_ENGINE_CLASS_METHODS` in `fast_api.py`.
const Map<String, bool> allowedAgentEngineClassMethods = <String, bool>{
  'create_session': false,
  'async_create_session': false,
  'list_sessions': false,
  'async_list_sessions': false,
  'get_session': false,
  'async_get_session': false,
  'delete_session': false,
  'async_delete_session': false,
  'query': false,
  'async_query': false,
  'async_add_session_to_memory': false,
  'async_search_memory': false,
  'async_save_artifact': false,
  'async_load_artifact': false,
  'async_list_artifact_keys': false,
  'async_delete_artifact': false,
  'async_list_versions': false,
  'async_list_artifact_versions': false,
  'async_get_artifact_version': false,
  'stream_query': true,
  'async_stream_query': true,
  'streaming_agent_run_with_events': true,
};

/// Request payload for `/api/reasoning_engine` and `/api/stream_reasoning_engine`.
class ReasoningEngineQueryRequest {
  /// Creates a [ReasoningEngineQueryRequest].
  const ReasoningEngineQueryRequest({
    required this.classMethod,
    this.input = const <String, Object?>{},
  });

  /// Method name on the Vertex AI Reasoning Engine / `AdkApp` adapter.
  final String classMethod;

  /// Keyword arguments forwarded to [classMethod].
  final Map<String, Object?> input;

  /// Parses and validates a [ReasoningEngineQueryRequest] from decoded JSON.
  factory ReasoningEngineQueryRequest.fromJson(Map<String, Object?> json) {
    final Object? rawMethod = json['class_method'];
    if (rawMethod == null) {
      throw const FormatException('class_method cannot be None');
    }
    if (rawMethod is! String || rawMethod.trim().isEmpty) {
      throw const FormatException('class_method must be a non-empty string');
    }
    final Object? rawInput = json['input'];
    if (rawInput != null && rawInput is! Map) {
      throw const FormatException('input must be a JSON object');
    }
    final Map<String, Object?> inputMap = rawInput == null
        ? const <String, Object?>{}
        : Map<String, Object?>.from(rawInput as Map);
    return ReasoningEngineQueryRequest(
      classMethod: rawMethod.trim(),
      input: inputMap,
    );
  }

  /// Serializes this request to JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'class_method': classMethod,
    'input': input,
  };
}

/// Thin wrapper around [AdkWebServer] for web and API server modes.
class FastApiApp {
  /// Creates a FastAPI-compatible app wrapper.
  FastApiApp({
    required this.agentsDir,
    this.appName = '',
    this.port = 8000,
    this.host = '127.0.0.1',
    this.allowOrigins = const <String>[],
    this.sessionServiceUri,
    this.artifactServiceUri,
    this.memoryServiceUri,
    this.evalStorageUri,
    this.useLocalStorage = true,
    this.urlPrefix,
    this.autoCreateSession = false,
    this.enableWebUi = true,
    bool? withUi,
    this.logoText,
    this.logoImageUrl,
    this.avatarConfig,
    this.maxLlmCalls,
    this.defaultLlmModel,
    this.reload = false,
    this.reloadAgents = false,
    this.traceToCloud = false,
    this.otelToCloud = false,
    this.a2a = false,
    this.extraPlugins = const <String>[],
    this.triggerSources = const <String>[],
    this.triggerOidcAudience,
    this.triggerOidcServiceAccounts = const <String>[],
    this.geminiEnterpriseAppName,
    this.expressMode = false,
    this.agentLoader,
    this.environment,
    this.setupObserver,
    this.tearDownObserver,
  }) : withUi = withUi ?? enableWebUi {
    if (reloadAgents || setupObserver != null) {
      _server = _buildServer()
        ..getFastApiApp(
          allowOrigins: allowOrigins,
          setupObserver: setupObserver,
          tearDownObserver: tearDownObserver,
          withUi: this.withUi,
        );
    }
  }

  /// Creates a [FastApiApp] bound to an existing [AdkWebServer] instance.
  FastApiApp.bound({
    required AdkWebServer server,
    List<String>? allowOrigins,
    bool? withUi,
  }) : agentsDir = server.agentsDir,
       appName = server.appName,
       port = server.port,
       host = server.host,
       allowOrigins = allowOrigins ?? server.allowOrigins,
       sessionServiceUri = server.sessionServiceUri,
       artifactServiceUri = server.artifactServiceUri,
       memoryServiceUri = server.memoryServiceUri,
       evalStorageUri = server.evalStorageUri,
       useLocalStorage = server.useLocalStorage,
       urlPrefix = server.urlPrefix,
       autoCreateSession = server.autoCreateSession,
       enableWebUi = withUi ?? server.enableWebUi,
       withUi = withUi ?? server.enableWebUi,
       logoText = server.logoText,
       logoImageUrl = server.logoImageUrl,
       avatarConfig = server.avatarConfig,
       maxLlmCalls = server.maxLlmCalls,
       defaultLlmModel = server.defaultLlmModel,
       reload = server.reload,
       reloadAgents = server.reloadAgents,
       traceToCloud = server.traceToCloud,
       otelToCloud = server.otelToCloud,
       a2a = server.a2a,
       extraPlugins = server.extraPlugins,
       triggerSources = server.triggerSources,
       triggerOidcAudience = server.triggerOidcAudience,
       triggerOidcServiceAccounts = server.triggerOidcServiceAccounts,
       geminiEnterpriseAppName = server.geminiEnterpriseAppName,
       expressMode = server.expressMode,
       agentLoader = server.agentLoader,
       environment = server.environment,
       setupObserver = server.setupObserver,
       tearDownObserver = server.tearDownObserver,
       _server = server;

  /// Root directory that contains ADK agent projects.
  final String agentsDir;

  /// Optional application name override.
  final String appName;

  /// HTTP port to bind.
  final int port;

  /// Host interface to bind.
  final String host;

  /// Allowed CORS origins.
  final List<String> allowOrigins;

  /// External session service URI override.
  final String? sessionServiceUri;

  /// External artifact service URI override.
  final String? artifactServiceUri;

  /// External memory service URI override.
  final String? memoryServiceUri;

  /// Optional eval storage URI override.
  final String? evalStorageUri;

  /// Whether local storage-backed services are enabled.
  final bool useLocalStorage;

  /// Optional URL prefix used for mounted deployments.
  final String? urlPrefix;

  /// Whether missing sessions are created automatically.
  final bool autoCreateSession;

  /// Whether the browser UI is served alongside API endpoints.
  final bool enableWebUi;

  /// Alias for [enableWebUi] matching `adk api_server --with_ui`.
  final bool withUi;

  /// Optional text shown in the web UI logo area.
  final String? logoText;

  /// Optional image URL shown in the web UI logo area.
  final String? logoImageUrl;

  /// Optional mapping of agent names to avatar URLs for the Dev UI.
  final Map<String, String>? avatarConfig;

  /// Optional maximum number of LLM calls per invocation.
  final int? maxLlmCalls;

  /// Optional default LLM model name for agents that do not specify one.
  final String? defaultLlmModel;

  /// Whether server auto-reload is enabled.
  final bool reload;

  /// Whether local agent definitions are reloaded on change.
  final bool reloadAgents;

  /// Whether Cloud Trace export is enabled.
  final bool traceToCloud;

  /// Whether OpenTelemetry Google Cloud export is enabled.
  final bool otelToCloud;

  /// Whether A2A protocol endpoints are enabled.
  final bool a2a;

  /// Extra plugin specifications loaded at startup.
  final List<String> extraPlugins;

  /// Event trigger sources to enable (`pubsub`, `eventarc`).
  final List<String> triggerSources;

  /// Expected OIDC audience for authenticating `/apps/{app_name}/trigger/*` requests.
  final String? triggerOidcAudience;

  /// Optional allowlist of service account emails permitted as OIDC token subjects.
  final List<String> triggerOidcServiceAccounts;

  /// Resource name of the Gemini Enterprise App to read settings from.
  final String? geminiEnterpriseAppName;

  /// Whether Gemini Enterprise Express Mode is enabled.
  final bool expressMode;

  /// Optional custom [BaseAgentLoader] used for agent reloading.
  final BaseAgentLoader? agentLoader;

  /// Optional environment map override forwarded to [AdkWebServer].
  final Map<String, String>? environment;

  /// Optional callback for setting up the agents file watcher.
  final SetupObserverCallback? setupObserver;

  /// Optional callback for tearing down the agents file watcher.
  final TearDownObserverCallback? tearDownObserver;

  AdkWebServer? _server;

  /// Underlying [AdkWebServer] when initialized, or `null`.
  AdkWebServer? get server => _server;

  AdkWebServer _buildServer() {
    return AdkWebServer(
      agentsDir: agentsDir,
      appName: appName,
      port: port,
      host: host,
      allowOrigins: allowOrigins,
      sessionServiceUri: sessionServiceUri,
      artifactServiceUri: artifactServiceUri,
      memoryServiceUri: memoryServiceUri,
      evalStorageUri: evalStorageUri,
      useLocalStorage: useLocalStorage,
      urlPrefix: urlPrefix,
      autoCreateSession: autoCreateSession,
      enableWebUi: withUi,
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
      geminiEnterpriseAppName: geminiEnterpriseAppName,
      expressMode: expressMode,
      agentLoader: agentLoader,
      environment: environment,
      setupObserver: setupObserver,
      tearDownObserver: tearDownObserver,
    );
  }

  /// Starts the wrapped [AdkWebServer] instance.
  Future<HttpServer> start() async {
    final AdkWebServer server = _server ?? _buildServer();
    _server = server;
    return server.start();
  }

  /// Stops the running server instance and tears down any active file observer.
  Future<void> stop() async {
    await _server?.stop();
    _server = null;
  }
}

/// Creates a [FastApiApp] with the provided server options.
FastApiApp getFastApiApp({
  required String agentsDir,
  String appName = '',
  int port = 8000,
  String host = '127.0.0.1',
  List<String> allowOrigins = const <String>[],
  String? sessionServiceUri,
  String? artifactServiceUri,
  String? memoryServiceUri,
  String? evalStorageUri,
  bool useLocalStorage = true,
  String? urlPrefix,
  bool autoCreateSession = false,
  bool enableWebUi = true,
  bool? withUi,
  String? logoText,
  String? logoImageUrl,
  Map<String, String>? avatarConfig,
  int? maxLlmCalls,
  String? defaultLlmModel,
  bool reload = false,
  bool reloadAgents = false,
  bool traceToCloud = false,
  bool otelToCloud = false,
  bool a2a = false,
  List<String> extraPlugins = const <String>[],
  List<String> triggerSources = const <String>[],
  String? triggerOidcAudience,
  List<String> triggerOidcServiceAccounts = const <String>[],
  String? geminiEnterpriseAppName,
  bool expressMode = false,
  BaseAgentLoader? agentLoader,
  Map<String, String>? environment,
  SetupObserverCallback? setupObserver,
  TearDownObserverCallback? tearDownObserver,
}) {
  return FastApiApp(
    agentsDir: agentsDir,
    appName: appName,
    port: port,
    host: host,
    allowOrigins: allowOrigins,
    sessionServiceUri: sessionServiceUri,
    artifactServiceUri: artifactServiceUri,
    memoryServiceUri: memoryServiceUri,
    evalStorageUri: evalStorageUri,
    useLocalStorage: useLocalStorage,
    urlPrefix: urlPrefix,
    autoCreateSession: autoCreateSession,
    enableWebUi: withUi ?? enableWebUi,
    withUi: withUi,
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
    geminiEnterpriseAppName: geminiEnterpriseAppName,
    expressMode: expressMode,
    agentLoader: agentLoader,
    environment: environment,
    setupObserver: setupObserver,
    tearDownObserver: tearDownObserver,
  );
}
